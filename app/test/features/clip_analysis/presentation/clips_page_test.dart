import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_recorder.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_repository.dart';
import 'package:pawsense/features/clip_analysis/presentation/clips_page.dart';
import 'package:pawsense/ml/ml_types.dart';

import '../../../data/fakes.dart';

class _MockRepository extends Mock implements ClipRepository;

class _MockRecorder extends Mock implements ClipRecorder;

void main() {
  final repo = _MockRepository();
  Clip clip(String id, ClipStatus status) => Clip(
    id: id,
    status: status,
    framePaths: const ['/missing.jpg'],
    createdAt: DateTime(2026, 11, 12, 10),
    petType: PetType.unknown,
  );

  setUp(() {
    when(repo.watchClips).thenAnswer(
      (_) => Stream.value([
        clip('q', ClipStatus.pendingUpload),
        clip('a', ClipStatus.analyzed),
        clip('f', ClipStatus.failed),
      ]),
    );
    when(() => repo.watchAnalysis('a')).thenAnswer(
      (_) => Stream.fromIterable(const [
        ClipDelta('Thinking'),
        ClipInsightReady(testInsight),
        ClipAnalysisDone(),
      ]),
    );
    GetIt.I
      ..registerSingleton<ClipRepository>(repo)
      ..registerSingleton<ClipRecorder>(_MockRecorder());
  });
  tearDown(GetIt.I.reset);

  testWidgets('shows status badges, retry, and the selected insight', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ClipsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Record 10 s clip'), findsOne);
    expect(find.text('Queued'), findsOne);
    expect(find.text('Analyzed'), findsOne);
    expect(find.text('Retry'), findsOne);

    await tester.tap(find.text('Analyzed'));
    await tester.pumpAndSettle();
    expect(find.text('Mood: playful'), findsOne);
    expect(find.text('limping (low)'), findsOne);
    expect(find.textContaining('Not a diagnosis'), findsOne);
  });
}
