part of 'clip_analysis_bloc.dart';

sealed class ClipsEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Start watching the clip list.
final class ClipsStarted extends ClipsEvent {
  const new();
}

/// Record a 10 s clip, extract keyframes, queue it.
final class ClipRecordPressed extends ClipsEvent {
  const new();
}

final class ClipSelected extends ClipsEvent {
  const new(this.clipId);

  final String clipId;

  @override
  List<Object?> get props => [clipId];
}

final class ClipRetryPressed extends ClipsEvent {
  const new(this.clipId);

  final String clipId;

  @override
  List<Object?> get props => [clipId];
}

final class _AnalysisEventReceived extends ClipsEvent {
  const new(this.clipId, this.event);

  final String clipId;
  final ClipAnalysisEvent event;

  @override
  List<Object?> get props => [clipId, event];
}
