import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_bloc.dart';
import 'package:pawsense/features/settings/presentation/settings_cubit.dart';
import 'package:pawsense/ml/breed_classifier.dart';
import 'package:pawsense/ml/frame_scheduler.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:pawsense/ml/pet_detector.dart';

class _MockInsights extends Mock implements InsightsRepository;

class _FakeDetector implements PetDetector {
  List<Detection> next = const [];
  Completer<void>? gate; // when set, detect() waits for it
  int loads = 0;
  int disposes = 0;
  int calls = 0;

  @override
  Future<void> load() async => loads++;
  @override
  Future<DetectionResult> detect(FrameData frame) async {
    calls++;
    await gate?.future;
    return DetectionResult(detections: next, detectionMs: 12, engine: 'tflite');
  }

  @override
  Future<void> dispose() async => disposes++;
}

class _FakeClassifier implements BreedClassifier {
  new(this.engineName);

  @override
  final String engineName;
  int loads = 0;
  int disposes = 0;
  int calls = 0;

  @override
  Future<void> load() async => loads++;
  @override
  Future<List<BreedPrediction>> classify(FrameData frame, Rect box) async {
    calls++;
    return const [BreedPrediction(label: 'beagle', confidence: 0.9)];
  }

  @override
  Future<void> dispose() async => disposes++;
}

final _frame = FrameData(
  planes: [Uint8List(0)],
  bytesPerRow: const [0],
  bytesPerPixel: const [4],
  width: 0,
  height: 0,
  format: FrameFormat.bgra8888,
  sensorOrientation: 0,
  timestamp: DateTime(2026),
);

const _dog = Detection(
  label: PetType.dog,
  score: 0.9,
  box: Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
);
const _weakCat = Detection(
  label: PetType.cat,
  score: 0.3,
  box: Rect.fromLTRB(0, 0, 0.1, 0.1),
);

void main() {
  late DateTime now;
  late _FakeDetector detector;
  late Map<BreedEngine, _FakeClassifier> classifiers;
  late List<bool> schedulerRequests;
  late _MockInsights insights;

  setUpAll(() => registerFallbackValue(PetType.dog));

  setUp(() {
    now = DateTime(2026);
    detector = _FakeDetector();
    classifiers = {};
    schedulerRequests = [];
    insights = _MockInsights();
    when(
      () => insights.addDetection(
        petType: any(named: 'petType'),
        score: any(named: 'score'),
        breed: any(named: 'breed'),
        at: any(named: 'at'),
      ),
    ).thenAnswer((_) async {});
  });

  LiveDetectionBloc build() => LiveDetectionBloc(
    detector: detector,
    classifierFor: (e) => classifiers[e] = _FakeClassifier(e.name),
    schedulerFor: ({required adaptive}) {
      schedulerRequests.add(adaptive);
      return FrameScheduler(clock: () => now);
    },
    insights: insights,
    clock: () => now,
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Sends one frame 100 ms after the previous one; returns whether the
  /// bloc asked for the frame's bytes (i.e. the scheduler accepted it).
  Future<bool> sendFrame(LiveDetectionBloc bloc) async {
    now = now.add(const Duration(milliseconds: 100));
    var read = false;
    bloc.add(
      LiveFrameArrived(() {
        read = true;
        return _frame;
      }),
    );
    await settle();
    return read;
  }

  blocTest<LiveDetectionBloc, LiveDetectionState>(
    'start loads the detector and the TFLite classifier',
    build: build,
    act: (b) => b.add(const LiveStarted(SettingsState())),
    expect: () => const [
      LiveDetectionState(engine: 'tflite', classificationMs: 0),
      LiveDetectionState(
        status: LiveStatus.ready,
        engine: 'tflite',
        classificationMs: 0,
      ),
    ],
    verify: (_) {
      expect(detector.loads, 1);
      expect(classifiers[BreedEngine.tflite]!.loads, 1);
      expect(schedulerRequests, [true]);
    },
  );

  test('frames before start are ignored', () async {
    final bloc = build();
    expect(await sendFrame(bloc), isFalse);
    expect(detector.calls, 0);
    await bloc.close();
  });

  test('a pet frame filters by threshold, classifies, smooths and is '
      'saved', () async {
    final bloc = build()..add(const LiveStarted(SettingsState()));
    await settle();
    detector.next = const [_dog, _weakCat];

    expect(await sendFrame(bloc), isTrue);

    final s = bloc.state;
    expect(s.detections, [_dog]); // 0.3 cat is below the 0.5 threshold
    expect(s.breeds.first.label, 'beagle');
    expect(s.detectionMs, 12);
    expect(s.stats.mode, SchedulerMode.full);
    verify(
      () => insights.addDetection(
        petType: PetType.dog,
        score: 0.9,
        breed: 'beagle',
        at: now,
      ),
    ).called(1);
    await bloc.close();
  });

  test('classifies only every few frames for a steady box', () async {
    final bloc = build()..add(const LiveStarted(SettingsState()));
    await settle();
    detector.next = const [_dog];
    for (var i = 0; i < 5; i++) {
      await sendFrame(bloc);
    }
    // BreedSmoother default: first box, then every 5th processed frame.
    expect(classifiers[BreedEngine.tflite]!.calls, 1);
    await bloc.close();
  });

  test('drops frames while one is in flight, without copying them', () async {
    final bloc = build()..add(const LiveStarted(SettingsState()));
    await settle();
    detector.gate = Completer();

    expect(await sendFrame(bloc), isTrue); // in flight
    expect(await sendFrame(bloc), isFalse); // dropped, bytes never read
    expect(await sendFrame(bloc), isFalse);

    detector.gate!.complete();
    await settle();
    expect(detector.calls, 1);
    expect(bloc.state.stats.droppedFrames, 2);
    await bloc.close();
  });

  test('engine switch disposes the old classifier and loads the new one; '
      'adaptive off swaps the scheduler', () async {
    final bloc = build()..add(const LiveStarted(SettingsState()));
    await settle();

    bloc.add(
      const LiveSettingsChanged(
        SettingsState(breedEngine: BreedEngine.coreml, adaptiveSkipping: false),
      ),
    );
    await settle();

    expect(classifiers[BreedEngine.tflite]!.disposes, 1);
    expect(classifiers[BreedEngine.coreml]!.loads, 1);
    expect(bloc.state.engine, 'coreml');
    expect(schedulerRequests, [true, false]);

    await bloc.close();
    expect(classifiers[BreedEngine.coreml]!.disposes, 1);
    expect(detector.disposes, 1);
  });

  test('load failure is reported', () async {
    final bloc = LiveDetectionBloc(
      detector: detector,
      classifierFor: (_) => throw StateError('no model'),
      schedulerFor: ({required adaptive}) => FrameScheduler(),
      insights: insights,
    )..add(const LiveStarted(SettingsState()));
    await settle();
    expect(bloc.state.status, LiveStatus.failure);
    expect(bloc.state.error, contains('no model'));
  });
}
