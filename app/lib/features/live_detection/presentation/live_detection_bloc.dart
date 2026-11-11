import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';
import 'package:pawsense/features/settings/presentation/settings_cubit.dart';
import 'package:pawsense/ml/breed_classifier.dart';
import 'package:pawsense/ml/breed_smoother.dart';
import 'package:pawsense/ml/frame_scheduler.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:pawsense/ml/pet_detector.dart';

sealed class LiveDetectionEvent {
  const new();
}

/// Start and settings changes share one sequential handler, so an engine
/// swap never overlaps the initial model load.
sealed class LiveConfigEvent extends LiveDetectionEvent {
  const new(this.settings);
  final SettingsState settings;
}

/// Loads the models. [settings] is the current SettingsCubit state.
final class LiveStarted extends LiveConfigEvent {
  const new(super.settings);
}

final class LiveSettingsChanged extends LiveConfigEvent {
  const new(super.settings);
}

/// One camera frame. [read] copies the camera buffers into a [FrameData]; it
/// is only called for frames the scheduler accepts, so dropped frames cost
/// nothing.
final class LiveFrameArrived extends LiveDetectionEvent {
  const new(this.read);
  final FrameData Function() read;
}

enum LiveStatus { loading, ready, failure }

class LiveDetectionState extends Equatable {
  const new({
    this.status = LiveStatus.loading,
    this.detections = const [],
    this.breeds = const [],
    this.cameraFps = 0,
    this.stats = SchedulerStats.initial,
    this.adaptive = true,
    this.engine = '',
    this.detectionMs,
    this.classificationMs,
    this.error,
  });

  final LiveStatus status;

  /// Pets above the settings threshold in the last processed frame.
  final List<Detection> detections;

  /// Smoothed top-3 breeds of the primary detection.
  final List<BreedPrediction> breeds;
  final double cameraFps;
  final SchedulerStats stats;

  /// False when adaptive skipping is off (fixed rate, stats.mode ignored).
  final bool adaptive;

  /// Active breed engine name (`TFLite` / `Core ML`), empty while loading.
  final String engine;
  final double? detectionMs;

  /// Last breed-classifier inference time.
  final double? classificationMs;
  final String? error;

  LiveDetectionState copyWith({
    LiveStatus? status,
    List<Detection>? detections,
    List<BreedPrediction>? breeds,
    double? cameraFps,
    SchedulerStats? stats,
    bool? adaptive,
    String? engine,
    double? detectionMs,
    double? classificationMs,
    String? error,
  }) => LiveDetectionState(
    status: status ?? this.status,
    detections: detections ?? this.detections,
    breeds: breeds ?? this.breeds,
    cameraFps: cameraFps ?? this.cameraFps,
    stats: stats ?? this.stats,
    adaptive: adaptive ?? this.adaptive,
    engine: engine ?? this.engine,
    detectionMs: detectionMs ?? this.detectionMs,
    classificationMs: classificationMs ?? this.classificationMs,
    error: error ?? this.error,
  );

  @override
  List<Object?> get props => [
    status,
    detections,
    breeds,
    cameraFps,
    stats,
    adaptive,
    engine,
    detectionMs,
    classificationMs,
    error,
  ];
}

/// Owns the live pipeline: camera frame -> FrameScheduler -> PetDetector ->
/// (when [BreedSmoother.shouldClassify]) BreedClassifier -> smoothed label.
/// The widget only forwards camera frames and paints state.
class LiveDetectionBloc extends Bloc<LiveDetectionEvent, LiveDetectionState> {
  new({
    required this._detector,
    required this._classifierFor,
    required this._schedulerFor,
    required this._insights,
    DateTime Function()? clock,
    BreedSmoother? smoother,
  }) : _clock = clock ?? DateTime.now,
       _smoother = smoother ?? BreedSmoother(),
       super(const LiveDetectionState()) {
    // Frames run concurrently (the scheduler drops while one is in flight);
    // start/settings run one at a time so engine swaps never overlap.
    on<LiveFrameArrived>(_onFrame);
    on<LiveConfigEvent>(_onConfig, transformer: _sequential);
  }

  /// Frames without a pet before the breed label is cleared (~1 s at full
  /// rate, longer in idle mode).
  static const _missesBeforeReset = 10;

  final PetDetector _detector;
  final BreedClassifier Function(BreedEngine) _classifierFor;
  final FrameScheduler Function({required bool adaptive}) _schedulerFor;
  final InsightsRepository _insights;
  final DateTime Function() _clock;
  final BreedSmoother _smoother;

  FrameScheduler? _scheduler;
  bool? _adaptive;
  double _threshold = const SettingsState().scoreThreshold;
  BreedEngine? _engine;
  BreedClassifier? _classifier;
  Future<void>? _classifying;
  int _misses = 0;
  PetType? _lastPet;

  // Camera fps over ~1 s windows.
  DateTime? _windowStart;
  int _windowFrames = 0;
  double _cameraFps = 0;

  static Stream<E> _sequential<E>(Stream<E> events, EventMapper<E> mapper) =>
      events.asyncExpand(mapper);

  Future<void> _onConfig(
    LiveConfigEvent event,
    Emitter<LiveDetectionState> emit,
  ) async {
    switch (event) {
      case LiveStarted():
        try {
          await _detector.load();
          await _apply(event.settings, emit);
          emit(state.copyWith(status: LiveStatus.ready));
        } on Object catch (e) {
          emit(state.copyWith(status: LiveStatus.failure, error: '$e'));
        }
      case LiveSettingsChanged():
        if (state.status == LiveStatus.failure) return;
        try {
          await _apply(event.settings, emit);
        } on Object catch (e) {
          emit(state.copyWith(error: 'Breed engine failed: $e'));
        }
    }
  }

  Future<void> _apply(SettingsState s, Emitter<LiveDetectionState> emit) async {
    _threshold = s.scoreThreshold;
    if (s.adaptiveSkipping != _adaptive) {
      // Fresh scheduler: stats restart, so before/after numbers don't mix.
      _adaptive = s.adaptiveSkipping;
      _scheduler = _schedulerFor(adaptive: s.adaptiveSkipping);
    }
    if (s.breedEngine == _engine) return;
    _engine = s.breedEngine;
    final old = _classifier;
    _classifier = null; // new frames skip classification during the swap
    await _settled(_classifying);
    await old?.dispose();
    final next = _classifierFor(s.breedEngine);
    await next.load();
    _classifier = next;
    _smoother.reset();
    emit(
      state.copyWith(
        engine: next.engineName,
        breeds: const [],
        classificationMs: 0,
      ),
    );
  }

  Future<void> _onFrame(
    LiveFrameArrived event,
    Emitter<LiveDetectionState> emit,
  ) async {
    final now = _clock();
    _countCameraFrame(now);
    // Null until LiveStarted applied the settings: frames before are dropped.
    final scheduler = _scheduler;
    if (scheduler == null || !scheduler.shouldProcess()) return;

    final List<Detection> pets;
    var breeds = state.breeds;
    final DetectionResult result;
    double? classificationMs;
    try {
      final frame = event.read();
      result = await _detector.detect(frame);
      pets = [
        for (final d in result.detections)
          if (d.score >= _threshold) d,
      ];
      if (pets.isEmpty) {
        if (++_misses >= _missesBeforeReset) {
          _smoother.reset();
          breeds = const [];
        }
      } else {
        _misses = 0;
        final primary = pets.first;
        if (primary.label != _lastPet) {
          _lastPet = primary.label;
          _smoother.reset();
          breeds = const [];
        }
        final classifier = _classifier;
        if (classifier != null && _smoother.shouldClassify(primary.box)) {
          final t = _clock();
          final classifying = classifier.classify(frame, primary.box);
          _classifying = classifying;
          breeds = _smoother.update(await classifying);
          classificationMs = _clock().difference(t).inMicroseconds / 1000;
        }
      }
      scheduler.onProcessed(petDetected: pets.isNotEmpty);
    } on Object {
      scheduler.onFailed();
      rethrow; // reported by the bloc observer (Sentry)
    }

    emit(
      state.copyWith(
        detections: pets,
        breeds: breeds,
        cameraFps: _cameraFps,
        stats: scheduler.stats,
        adaptive: _adaptive,
        detectionMs: result.detectionMs,
        classificationMs: classificationMs,
      ),
    );
    if (pets.isNotEmpty) {
      // The repository keeps at most one entry per pet type per minute.
      await _insights.addDetection(
        petType: pets.first.label,
        score: pets.first.score,
        breed: breeds.firstOrNull?.label,
        at: now,
      );
    }
  }

  void _countCameraFrame(DateTime now) {
    final start = _windowStart ??= now;
    _windowFrames++;
    final elapsed = now.difference(start);
    if (elapsed >= const Duration(seconds: 1)) {
      _cameraFps = _windowFrames * 1e6 / elapsed.inMicroseconds;
      _windowStart = now;
      _windowFrames = 0;
    }
  }

  /// Waits for an in-flight classification; its error was already reported.
  static Future<void> _settled(Future<void>? f) =>
      f?.then((_) {}, onError: (_) {}) ?? Future.value();

  @override
  Future<void> close() async {
    await _settled(_classifying);
    // Detector and classifier are DI factories: this bloc owns both (the
    // shared TFLite isolate stays up).
    await _classifier?.dispose();
    await _detector.dispose();
    await super.close();
  }
}
