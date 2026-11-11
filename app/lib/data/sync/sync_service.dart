import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:pawsense/core/log.dart';
import 'package:pawsense/data/api/clips_api.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/data/db/clips_dao.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 2 s, 4 s, 8 s … capped at 5 min.
Duration defaultBackoff(int attempt) => Duration(
  milliseconds: math.min(2000 * math.pow(2, attempt - 1).toInt(), 300000),
);

/// Drains the Drift upload queue and streams analyses.
///
/// - Uploads only while online; when connectivity returns, every queued clip
///   is due immediately (the "queue drains automatically" behaviour).
/// - Retryable failures back off exponentially without limit: a clip stays
///   "queued" until it uploads. Non-retryable ones (4xx) mark it failed.
/// - After upload it opens `WS /v1/stream?jobId=` and reconnects to the same
///   jobId on drops. The final insight is written to Drift (clip -> analyzed
///   + feed entry) BEFORE [ClipInsightReady] is emitted.
class SyncService {
  new({
    required this._clips,
    required this._insights,
    required this._api,
    required this._connectivity,
    DateTime Function()? now,
    this._backoff = defaultBackoff,
  }) : _now = now ?? DateTime.now;

  /// Socket drops tolerated per analysis before waiting for the next
  /// connectivity change / app start.
  static const maxReconnects = 5;

  final ClipsDao _clips;
  final InsightsRepository _insights;
  final ClipsApi _api;
  final Connectivity _connectivity;
  final DateTime Function() _now;
  final Duration Function(int attempt) _backoff;

  final _events =
      StreamController<({String clipId, ClipAnalysisEvent event})>.broadcast();
  final _analyzing = <String>{};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;
  var _draining = false;
  var _drainAgain = false;
  var _disposed = false;

  /// Live (non-status) analysis events for [clipId]. Status lives in Drift.
  Stream<ClipAnalysisEvent> events(String clipId) =>
      _events.stream.where((e) => e.clipId == clipId).map((e) => e.event);

  Future<void> start() async {
    await _clips.resetInterruptedUploads();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((result) {
      if (_isOnline(result)) unawaited(sync(networkRestored: true));
    });
    await sync();
  }

  /// Uploads due clips, then (re)opens the socket for every clip still
  /// analyzing. [networkRestored] skips the remaining backoff.
  Future<void> sync({bool networkRestored = false}) async {
    if (_disposed || !_isOnline(await _connectivity.checkConnectivity())) {
      return;
    }
    if (networkRestored) await _clips.makeAllDue(_now());
    await _drain();
    for (final clip in await _clips.withStatus(ClipStatus.analyzing)) {
      unawaited(_analyze(clip));
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _connectivitySub?.cancel();
    await _events.close();
  }

  Future<void> _drain() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        for (final item in await _clips.queue(dueBy: _now())) {
          if (_disposed) return;
          await _upload(item);
        }
      } while (_drainAgain);
    } finally {
      _draining = false;
      await _scheduleNextDrain();
    }
  }

  Future<void> _scheduleNextDrain() async {
    _retryTimer?.cancel();
    if (_disposed) return;
    final next = (await _clips.queue()).firstOrNull;
    if (next == null) return;
    final wait = next.nextAttemptAt.difference(_now());
    _retryTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      unawaited(sync());
    });
  }

  Future<void> _upload(PendingUploadRow item) async {
    final clip = await _clips.getClip(item.clipId);
    if (clip == null) return;
    await _clips.setStatus(clip.id, ClipStatus.uploading);
    final span = Sentry.startTransaction('clip.upload', 'http.client');
    try {
      final jobId = await _api.uploadClip(clip.toDomain());
      await _clips.markUploaded(clip.id, jobId);
      span.status = const SpanStatus.ok();
      unawaited(
        _analyze(
          clip.copyWith(status: ClipStatus.analyzing, jobId: Value(jobId)),
        ),
      );
    } on ApiException catch (e) {
      span
        ..throwable = e
        ..status = const SpanStatus.unavailable();
      if (e.retryable) {
        final attempts = item.attempts + 1;
        await _clips.scheduleRetry(
          clip.id,
          attempts: attempts,
          at: _now().add(_backoff(attempts)),
        );
      } else {
        await _fail(clip.id, ClipErrorCode.badInput, e.message);
      }
    } on Object catch (e, st) {
      // e.g. a keyframe file is gone: retrying cannot fix it.
      span
        ..throwable = e
        ..status = const SpanStatus.internalError();
      log('Clip upload failed', error: e, stackTrace: st);
      await _fail(clip.id, ClipErrorCode.internal, '$e');
    } finally {
      await span.finish();
    }
  }

  Future<void> _analyze(ClipRow clip) async {
    final jobId = clip.jobId;
    if (jobId == null || !_analyzing.add(clip.id)) return;
    try {
      for (var attempt = 0; attempt <= maxReconnects; attempt++) {
        if (attempt > 0) await Future<void>.delayed(_backoff(attempt));
        if (_disposed) return;
        final span = Sentry.startTransaction('clip.ws', 'websocket.client');
        final sinceConnect = Stopwatch()..start();
        var firstDelta = true;
        try {
          await for (final event in _api.streamAnalysis(jobId)) {
            if (event is ClipDelta && firstDelta) {
              // docs/METRICS.md "time to first insight token".
              firstDelta = false;
              final ms = sinceConnect.elapsedMilliseconds;
              log('Clip ${clip.id}: first delta ${ms}ms after socket open');
              span.setMeasurement(
                'time_to_first_delta',
                ms,
                unit: DurationSentryMeasurementUnit.milliSecond,
              );
            }
            await _handle(clip, event);
            if (event is ClipAnalysisDone) {
              span.status = const SpanStatus.ok();
              return;
            }
          }
          span.status = const SpanStatus.aborted();
        } on Object catch (e) {
          span
            ..throwable = e
            ..status = const SpanStatus.unavailable();
          log('Clip socket dropped (attempt $attempt)', error: e);
        } finally {
          await span.finish();
        }
      }
      // Still `analyzing` in Drift: resumed on the next sync().
    } finally {
      _analyzing.remove(clip.id);
    }
  }

  Future<void> _handle(ClipRow clip, ClipAnalysisEvent event) async {
    switch (event) {
      case ClipStatusChanged():
        return; // Drift is the source of truth for status.
      case ClipInsightReady(:final insight):
        await _clips.transaction(() async {
          await _insights.addClipInsight(
            clipId: clip.id,
            petType: clip.petType,
            insight: insight,
            breed: clip.breedHint,
          );
          await _clips.setStatus(clip.id, ClipStatus.analyzed);
        });
      case ClipAnalysisError(:final message):
        await _clips.markFailed(clip.id, message);
      case ClipDelta() || ClipAnalysisDone():
        break;
    }
    _emit(clip.id, event);
  }

  Future<void> _fail(String clipId, ClipErrorCode code, String message) async {
    await _clips.markFailed(clipId, message);
    _emit(clipId, ClipAnalysisError(code, message));
  }

  void _emit(String clipId, ClipAnalysisEvent event) {
    if (!_events.isClosed) _events.add((clipId: clipId, event: event));
  }

  static bool _isOnline(List<ConnectivityResult> result) =>
      result.any((r) => r != ConnectivityResult.none);
}
