import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_recorder.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_repository.dart';
import 'package:pawsense/ml/ml_types.dart';

part 'clips_event.dart';
part 'clips_state.dart';

/// Clips tab: records a clip, saves it locally (queued), and shows the
/// selected clip's streamed analysis.
class ClipAnalysisBloc extends Bloc<ClipsEvent, ClipsState> {
  new(this._repository, this._recorder) : super(const ClipsState()) {
    on<ClipsStarted>(_onStarted);
    on<ClipRecordPressed>(_onRecordPressed);
    on<ClipSelected>((e, emit) => _select(e.clipId, emit));
    on<ClipRetryPressed>(_onRetryPressed);
    on<_AnalysisEventReceived>(_onAnalysisEvent);
  }

  static const clipLength = Duration(seconds: 10);
  static const keyframeTimes = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 7),
    Duration(seconds: 9),
  ];

  final ClipRepository _repository;
  final ClipRecorder _recorder;
  StreamSubscription<ClipAnalysisEvent>? _analysis;

  Future<void> _onStarted(ClipsStarted event, Emitter<ClipsState> emit) =>
      emit.forEach(
        _repository.watchClips(),
        onData: (clips) => state.copyWith(clips: clips),
      );

  Future<void> _onRecordPressed(
    ClipRecordPressed event,
    Emitter<ClipsState> emit,
  ) async {
    if (state.phase != RecordPhase.idle) return;
    emit(
      state.copyWith(
        phase: RecordPhase.recording,
        remaining: clipLength,
        recordError: () => null,
      ),
    );
    try {
      await _recorder.initialize();
      final video = await _recorder.recordClip(
        clipLength,
        onTick: (left) {
          if (!emit.isDone) emit(state.copyWith(remaining: left));
        },
      );
      emit(state.copyWith(phase: RecordPhase.extracting));
      final frames = await _recorder.extractKeyframes(video, keyframeTimes);
      // ponytail: petType unknown, no breedHint. Pass the live tab's last
      // detection here if the backend prompt needs it.
      final clip = await _repository.createPendingClip(
        framePaths: frames,
        petType: PetType.unknown,
      );
      emit(state.copyWith(phase: RecordPhase.idle));
      _select(clip.id, emit);
    } on Object catch (e, st) {
      addError(e, st);
      emit(
        state.copyWith(
          phase: RecordPhase.idle,
          recordError: () => 'Recording failed: $e',
        ),
      );
    } finally {
      await _recorder.dispose();
    }
  }

  Future<void> _onRetryPressed(
    ClipRetryPressed event,
    Emitter<ClipsState> emit,
  ) async {
    await _repository.retry(event.clipId);
    _select(event.clipId, emit);
  }

  void _select(String clipId, Emitter<ClipsState> emit) {
    emit(state.selecting(clipId));
    unawaited(_analysis?.cancel());
    _analysis = _repository
        .watchAnalysis(clipId)
        .listen((e) => add(_AnalysisEventReceived(clipId, e)));
  }

  void _onAnalysisEvent(
    _AnalysisEventReceived event,
    Emitter<ClipsState> emit,
  ) {
    if (event.clipId != state.selectedId) return;
    switch (event.event) {
      case ClipDelta(:final text):
        emit(state.copyWith(streamedText: state.streamedText + text));
      case ClipInsightReady(:final insight):
        emit(state.copyWith(insight: () => insight));
      case ClipAnalysisError(:final message):
        emit(state.copyWith(analysisError: () => message));
      case ClipStatusChanged() || ClipAnalysisDone():
        break; // The clip list shows status.
    }
  }

  @override
  Future<void> close() async {
    await _analysis?.cancel();
    await super.close();
  }
}
