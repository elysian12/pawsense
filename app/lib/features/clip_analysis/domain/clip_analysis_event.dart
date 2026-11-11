import 'package:equatable/equatable.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';

/// Events emitted by `ClipRepository.watchAnalysis` for one clip: local
/// status changes plus the server's WebSocket messages
/// (docs/WS_PROTOCOL.md), already parsed.
sealed class ClipAnalysisEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// The clip moved to [status] (pendingUpload -> uploading -> analyzing ...).
final class ClipStatusChanged extends ClipAnalysisEvent {
  const new(this.status);

  final ClipStatus status;

  @override
  List<Object?> get props => [status];
}

/// A chunk of streamed model text, for the "typing" effect. Append in order.
final class ClipDelta extends ClipAnalysisEvent {
  const new(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

/// The final structured insight. Already saved to Drift (clip marked
/// analyzed, feed entry added) when this is emitted.
final class ClipInsightReady extends ClipAnalysisEvent {
  const new(this.insight);

  final ClipInsight insight;

  @override
  List<Object?> get props => [insight];
}

/// Server-side `error` codes plus [network] for client-side failures that
/// exhausted retries.
enum ClipErrorCode {
  refused('refused'),
  timeout('timeout'),
  badInput('bad_input'),
  internal('internal'),
  network('network');

  new(this.wireName);

  final String wireName;

  static ClipErrorCode fromWire(String value) =>
      values.where((c) => c.wireName == value).firstOrNull ?? internal;
}

final class ClipAnalysisError extends ClipAnalysisEvent {
  const new(this.code, this.message);

  final ClipErrorCode code;
  final String message;

  @override
  List<Object?> get props => [code, message];
}

/// Last event for this analysis; the stream closes after it.
final class ClipAnalysisDone extends ClipAnalysisEvent {
  const new();
}
