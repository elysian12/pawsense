import 'dart:async';

import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/data/db/clips_dao.dart';
import 'package:pawsense/data/sync/sync_service.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_repository.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:uuid/uuid.dart';

class DriftClipRepository implements ClipRepository {
  new(
    this._db,
    this._sync, {
    DateTime Function()? now,
    this._uuid = const Uuid(),
  }) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final SyncService _sync;
  final DateTime Function() _now;
  final Uuid _uuid;

  @override
  Future<Clip> createPendingClip({
    required List<String> framePaths,
    required PetType petType,
    String? breedHint,
  }) async {
    final now = _now();
    final row = ClipRow(
      id: _uuid.v4(),
      status: ClipStatus.pendingUpload,
      framePaths: framePaths,
      createdAt: now,
      petType: petType,
      breedHint: breedHint,
    );
    await _db.clipsDao.insertPending(row, now);
    unawaited(_sync.sync()); // no-op while offline
    return row.toDomain();
  }

  @override
  Stream<List<Clip>> watchClips() => _db.clipsDao.watchAll().map(
    (rows) => [for (final r in rows) r.toDomain()],
  );

  /// Status comes from Drift; deltas/insight/error/done from the sync
  /// service's live socket. An already-analyzed clip gets its stored insight.
  @override
  Stream<ClipAnalysisEvent> watchAnalysis(String clipId) {
    late final StreamController<ClipAnalysisEvent> out;
    StreamSubscription<Object?>? live;
    StreamSubscription<Object?>? status;

    void emit(ClipAnalysisEvent event) {
      if (out.isClosed) return;
      out.add(event);
      if (event is ClipAnalysisDone) unawaited(out.close());
    }

    out = StreamController(
      onListen: () {
        live = _sync.events(clipId).listen(emit);
        ClipStatus? last;
        status = _db.clipsDao.watchClip(clipId).listen((row) async {
          if (row == null || row.status == last) return;
          last = row.status;
          emit(ClipStatusChanged(row.status));
          if (row.status == ClipStatus.analyzed) {
            final stored = await _db.insightsDao.byId(clipId);
            if (stored != null) {
              emit(
                ClipInsightReady(
                  ClipInsight.fromJson(
                    (stored.payload['insight']! as Map).cast<String, Object?>(),
                  ),
                ),
              );
            }
            emit(const ClipAnalysisDone());
          }
        });
      },
      onCancel: () async {
        await live?.cancel();
        await status?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<void> retry(String clipId) async {
    await _db.clipsDao.requeue(clipId, _now());
    unawaited(_sync.sync());
  }
}
