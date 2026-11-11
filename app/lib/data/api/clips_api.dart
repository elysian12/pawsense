import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';
import 'package:web_socket_channel/io.dart';

/// Thrown by [ClipsApi.uploadClip]. [retryable] is false when retrying the
/// same request cannot help (4xx other than 408/429).
class ApiException implements Exception {
  const new(this.message, {required this.retryable});

  final String message;
  final bool retryable;

  @override
  String toString() => 'ApiException($message, retryable: $retryable)';
}

/// No response (offline, timeout), 408, 429 and 5xx are worth retrying.
bool isRetryableStatus(int? statusCode) =>
    statusCode == null ||
    statusCode == 408 ||
    statusCode == 429 ||
    statusCode >= 500;

/// REST + WebSocket client for the clip-analysis backend
/// (docs/WS_PROTOCOL.md). Auth is the `API_TOKEN` bearer on both.
class ClipsApi {
  new({required String baseUrl, required String token})
    : _baseUrl = Uri.parse(baseUrl),
      _token = token,
      _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  final Uri _baseUrl;
  final String _token;
  final Dio _dio;

  /// `POST /v1/clips` with the keyframes; returns the jobId. Idempotent by
  /// `clip.id`, so retrying after a timeout cannot start a second analysis.
  Future<String> uploadClip(Clip clip) async {
    final form = FormData()
      ..fields.addAll([
        MapEntry('clipId', clip.id),
        MapEntry('petType', clip.petType.name),
        if (clip.breedHint case final hint?) MapEntry('breedHint', hint),
      ]);
    for (final path in clip.framePaths) {
      form.files.add(
        MapEntry(
          'frames[]',
          await MultipartFile.fromFile(
            path,
            contentType: DioMediaType('image', 'jpeg'),
          ),
        ),
      );
    }
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/clips',
        data: form,
      );
      return res.data!['jobId'] as String;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      throw ApiException(
        code == null ? '${e.type.name}: ${e.message}' : 'HTTP $code',
        retryable: isRetryableStatus(code),
      );
    }
  }

  /// `GET /v1/stream?jobId=…` as parsed events. Completes after
  /// [ClipAnalysisDone]; a stream that ends (or errors) before that means the
  /// socket dropped and the caller should reconnect.
  Stream<ClipAnalysisEvent> streamAnalysis(String jobId) async* {
    final uri = _baseUrl.replace(
      scheme: _baseUrl.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/stream',
      queryParameters: {'jobId': jobId},
    );
    final channel = IOWebSocketChannel.connect(
      uri,
      headers: {'Authorization': 'Bearer $_token'},
      connectTimeout: const Duration(seconds: 10),
    );
    try {
      await channel.ready;
      await for (final message in channel.stream) {
        final event = parseServerMessage(message as String);
        if (event == null) continue;
        yield event;
        if (event is ClipAnalysisDone) return;
      }
    } finally {
      await channel.sink.close();
    }
  }
}

/// Maps one server → client WS message to an event; null for unknown types
/// (the protocol says to ignore them).
ClipAnalysisEvent? parseServerMessage(String raw) {
  final json = (jsonDecode(raw) as Map).cast<String, Object?>();
  return switch (json['type']) {
    'status' =>
      ClipStatus.values
          .where((s) => s.wireName == json['status'])
          .map(ClipStatusChanged.new)
          .firstOrNull,
    'delta' => ClipDelta(json['text']! as String),
    'insight' => ClipInsightReady(
      ClipInsight.fromJson((json['insight']! as Map).cast<String, Object?>()),
    ),
    'error' => ClipAnalysisError(
      ClipErrorCode.fromWire(json['code']! as String),
      json['message'] as String? ?? '',
    ),
    'done' => const ClipAnalysisDone(),
    _ => null,
  };
}
