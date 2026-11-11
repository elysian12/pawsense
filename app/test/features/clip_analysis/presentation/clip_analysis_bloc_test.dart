import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_recorder.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_repository.dart';
import 'package:pawsense/features/clip_analysis/presentation/bloc/clip_analysis_bloc.dart';
import 'package:pawsense/ml/ml_types.dart';

import '../../../data/fakes.dart';

class _MockRepository extends Mock implements ClipRepository;

class _MockRecorder extends Mock implements ClipRecorder;

void main() {
  late _MockRepository repo;
  late _MockRecorder recorder;

  final clip = Clip(
    id: 'clip-1',
    status: ClipStatus.pendingUpload,
    framePaths: const ['/k0.jpg'],
    createdAt: DateTime(2026, 11, 12),
    petType: PetType.unknown,
  );

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<Duration>[]);
    registerFallbackValue(PetType.unknown);
  });

  setUp(() {
    repo = _MockRepository();
    recorder = _MockRecorder();
    when(() => recorder.initialize()).thenAnswer((_) async {});
    when(() => recorder.dispose()).thenAnswer((_) async {});
    when(() => recorder.extractKeyframes(any(), any()))
        .thenAnswer((_) async => ['/k0.jpg']);
    when(
      () => repo.createPendingClip(
        framePaths: any(named: 'framePaths'),
        petType: any(named: 'petType'),
      ),
    ).thenAnswer((_) async => clip);
    when(() => repo.watchAnalysis(any())).thenAnswer(
      (_) => Stream.fromIterable(const [
        ClipStatusChanged(ClipStatus.analyzing),
        ClipDelta('Hap'),
        ClipDelta('py'),
        ClipInsightReady(testInsight),
        ClipAnalysisDone(),
      ]),
    );
  });

  ClipAnalysisBloc build() => ClipAnalysisBloc(repo, recorder);

  blocTest<ClipAnalysisBloc, ClipsState>(
    'ClipsStarted mirrors the clip list',
    setUp: () =>
        when(() => repo.watchClips()).thenAnswer((_) => Stream.value([clip])),
    build: build,
    act: (bloc) => bloc.add(const ClipsStarted()),
    expect: () => [
      ClipsState(clips: [clip]),
    ],
  );

  blocTest<ClipAnalysisBloc, ClipsState>(
    'record: countdown, keyframes at 1/3/5/7/9 s, queue, stream the insight',
    setUp: () =>
        when(() => recorder.recordClip(any(), onTick: any(named: 'onTick')))
            .thenAnswer((inv) async {
              final onTick =
                  inv.namedArguments[#onTick] as void Function(Duration)?;
              onTick?.call(const Duration(seconds: 3));
              return '/video.mp4';
            }),
    build: build,
    act: (bloc) => bloc.add(const ClipRecordPressed()),
    expect: () => const [
      ClipsState(
        phase: RecordPhase.recording,
        remaining: Duration(seconds: 10),
      ),
      ClipsState(phase: RecordPhase.recording, remaining: Duration(seconds: 3)),
      ClipsState(
        phase: RecordPhase.extracting,
        remaining: Duration(seconds: 3),
      ),
      ClipsState(remaining: Duration(seconds: 3)),
      ClipsState(remaining: Duration(seconds: 3), selectedId: 'clip-1'),
      ClipsState(
        remaining: Duration(seconds: 3),
        selectedId: 'clip-1',
        streamedText: 'Hap',
      ),
      ClipsState(
        remaining: Duration(seconds: 3),
        selectedId: 'clip-1',
        streamedText: 'Happy',
      ),
      ClipsState(
        remaining: Duration(seconds: 3),
        selectedId: 'clip-1',
        streamedText: 'Happy',
        insight: testInsight,
      ),
    ],
    verify: (_) {
      verify(
        () => recorder.recordClip(
          const Duration(seconds: 10),
          onTick: any(named: 'onTick'),
        ),
      ).called(1);
      verify(
        () => recorder.extractKeyframes(
          '/video.mp4',
          ClipAnalysisBloc.keyframeTimes,
        ),
      ).called(1);
      expect(ClipAnalysisBloc.keyframeTimes.map((d) => d.inSeconds), [
        1,
        3,
        5,
        7,
        9,
      ]);
      verify(
        () => repo.createPendingClip(
          framePaths: ['/k0.jpg'],
          petType: PetType.unknown,
        ),
      ).called(1);
      verify(() => recorder.dispose()).called(1);
    },
  );

  blocTest<ClipAnalysisBloc, ClipsState>(
    'record failure shows an error and still releases the camera',
    setUp: () =>
        when(() => recorder.initialize())
            .thenThrow(StateError('No camera available')),
    build: build,
    act: (bloc) => bloc.add(const ClipRecordPressed()),
    expect: () => [
      const ClipsState(
        phase: RecordPhase.recording,
        remaining: Duration(seconds: 10),
      ),
      isA<ClipsState>()
          .having((s) => s.phase, 'phase', RecordPhase.idle)
          .having((s) => s.recordError, 'recordError', contains('No camera')),
    ],
    errors: () => [isA<StateError>()],
    verify: (_) {
      verify(() => recorder.dispose()).called(1);
      verifyNever(
        () => repo.createPendingClip(
          framePaths: any(named: 'framePaths'),
          petType: any(named: 'petType'),
        ),
      );
    },
  );

  blocTest<ClipAnalysisBloc, ClipsState>(
    'retry re-queues and shows the analysis error stream',
    setUp: () {
      when(() => repo.retry(any())).thenAnswer((_) async {});
      when(() => repo.watchAnalysis(any())).thenAnswer(
        (_) => Stream.fromIterable(const [
          ClipAnalysisError(ClipErrorCode.refused, 'declined'),
          ClipAnalysisDone(),
        ]),
      );
    },
    build: build,
    act: (bloc) => bloc.add(const ClipRetryPressed('clip-1')),
    expect: () => const [
      ClipsState(selectedId: 'clip-1'),
      ClipsState(selectedId: 'clip-1', analysisError: 'declined'),
    ],
    verify: (_) => verify(() => repo.retry('clip-1')).called(1),
  );
}
