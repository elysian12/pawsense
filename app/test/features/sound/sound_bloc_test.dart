import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';
import 'package:pawsense/features/sound/presentation/sound_bloc.dart';
import 'package:pawsense/features/sound/presentation/sound_page.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:pawsense/ml/sound_classifier.dart';

class _MockInsights extends Mock implements InsightsRepository;

class _FakeClassifier implements SoundClassifier {
  final scoresCtrl = StreamController<SoundScores>.broadcast();
  final eventsCtrl = StreamController<SoundEvent>.broadcast();
  int loads = 0;
  int starts = 0;
  int stops = 0;
  int disposes = 0;
  Exception? startError;

  @override
  Stream<SoundScores> get scores => scoresCtrl.stream;
  @override
  Stream<SoundEvent> get events => eventsCtrl.stream;
  @override
  Future<void> load() async => loads++;
  @override
  Future<void> start() async {
    if (startError != null) throw startError!;
    starts++;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async => disposes++;
}

void main() {
  late _FakeClassifier classifier;
  late _MockInsights insights;

  const scores = SoundScores(
    topLabel: 'Bark',
    topScore: 0.8,
    dogScore: 0.8,
    catScore: 0.01,
    rms: 0.1,
  );
  final bark = SoundEvent(
    kind: SoundKind.dog,
    label: 'Bark',
    score: 0.8,
    timestamp: DateTime(2026),
  );

  setUpAll(() => registerFallbackValue(bark));

  setUp(() {
    classifier = _FakeClassifier();
    insights = _MockInsights();
    when(() => insights.addSound(any())).thenAnswer((_) async {});
  });

  blocTest<SoundBloc, SoundState>(
    'start loads once, listens, shows scores and saves events',
    build: () => SoundBloc(classifier, insights),
    act: (b) async {
      b.add(const SoundListenStarted());
      await Future<void>.delayed(Duration.zero);
      classifier.scoresCtrl.add(scores);
      classifier.eventsCtrl.add(bark);
    },
    expect: () => [
      const SoundState(status: SoundStatus.starting),
      const SoundState(status: SoundStatus.listening),
      const SoundState(status: SoundStatus.listening, scores: scores),
      SoundState(status: SoundStatus.listening, scores: scores, events: [bark]),
    ],
    verify: (_) {
      expect(classifier.loads, 1);
      expect(classifier.starts, 1);
      verify(() => insights.addSound(bark)).called(1);
    },
  );

  blocTest<SoundBloc, SoundState>(
    'stop releases the mic and ignores late scores; restart skips load',
    build: () => SoundBloc(classifier, insights),
    act: (b) async {
      b.add(const SoundListenStarted());
      await Future<void>.delayed(Duration.zero);
      b.add(const SoundListenStopped());
      await Future<void>.delayed(Duration.zero);
      classifier.scoresCtrl.add(scores);
      await Future<void>.delayed(Duration.zero);
      b.add(const SoundListenStarted());
    },
    expect: () => const [
      SoundState(status: SoundStatus.starting),
      SoundState(status: SoundStatus.listening),
      SoundState(),
      SoundState(status: SoundStatus.starting),
      SoundState(status: SoundStatus.listening),
    ],
    verify: (_) {
      expect(classifier.loads, 1);
      expect(classifier.stops, 2); // the stop event + close() while listening
    },
  );

  blocTest<SoundBloc, SoundState>(
    'start failure is reported',
    build: () =>
        SoundBloc(classifier..startError = Exception('mic busy'), insights),
    act: (b) => b.add(const SoundListenStarted()),
    expect: () => const [
      SoundState(status: SoundStatus.starting),
      SoundState(status: SoundStatus.failure, error: 'Exception: mic busy'),
    ],
  );

  test('close stops the listener and disposes the classifier', () async {
    final bloc = SoundBloc(classifier, insights)
      ..add(const SoundListenStarted());
    await Future<void>.delayed(Duration.zero);
    await bloc.close();
    expect(classifier.stops, 1);
    expect(classifier.disposes, 1);
  });

  test('level meter maps RMS on a -60..0 dB scale', () {
    expect(levelFromRms(0), 0);
    expect(levelFromRms(1), 1);
    expect(levelFromRms(0.001), closeTo(0, 1e-9)); // -60 dB
    expect(levelFromRms(0.0316), closeTo(0.5, 0.01)); // -30 dB
  });
}
