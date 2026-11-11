part of 'clip_analysis_bloc.dart';

enum RecordPhase { idle, recording, extracting }

final class ClipsState extends Equatable {
  const new({
    this.clips = const [],
    this.phase = RecordPhase.idle,
    this.remaining = Duration.zero,
    this.recordError,
    this.selectedId,
    this.streamedText = '',
    this.insight,
    this.analysisError,
  });

  /// Newest first, live from Drift.
  final List<Clip> clips;
  final RecordPhase phase;

  /// Countdown while [phase] is [RecordPhase.recording].
  final Duration remaining;
  final String? recordError;

  /// Clip whose analysis is shown below the record button.
  final String? selectedId;

  /// Model text streamed so far, for the "typing" effect.
  final String streamedText;
  final ClipInsight? insight;
  final String? analysisError;

  Clip? get selected => clips.where((c) => c.id == selectedId).firstOrNull;

  /// Focus [clipId] with a fresh analysis view.
  ClipsState selecting(String clipId) => ClipsState(
    clips: clips,
    phase: phase,
    remaining: remaining,
    recordError: recordError,
    selectedId: clipId,
  );

  /// Nullable fields take a getter so they can be set back to null.
  ClipsState copyWith({
    List<Clip>? clips,
    RecordPhase? phase,
    Duration? remaining,
    String? Function()? recordError,
    String? streamedText,
    ClipInsight? Function()? insight,
    String? Function()? analysisError,
  }) => ClipsState(
    clips: clips ?? this.clips,
    phase: phase ?? this.phase,
    remaining: remaining ?? this.remaining,
    recordError: recordError != null ? recordError() : this.recordError,
    selectedId: selectedId,
    streamedText: streamedText ?? this.streamedText,
    insight: insight != null ? insight() : this.insight,
    analysisError: analysisError != null ? analysisError() : this.analysisError,
  );

  @override
  List<Object?> get props => [
    clips,
    phase,
    remaining,
    recordError,
    selectedId,
    streamedText,
    insight,
    analysisError,
  ];
}
