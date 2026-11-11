import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';
import 'package:pawsense/features/insights_feed/presentation/feed_page.dart';
import 'package:pawsense/ml/ml_types.dart';

import '../../../data/fakes.dart';

class _MockRepository extends Mock implements InsightsRepository;

void main() {
  final repo = _MockRepository();
  final at = DateTime(2026, 11, 12, 10);
  final items = [
    Insight(
      id: 'c',
      type: InsightType.clip,
      petType: PetType.dog,
      payload: {'clipId': 'c', 'insight': testInsight.toJson()},
      createdAt: at,
    ),
    Insight(
      id: 's',
      type: InsightType.sound,
      petType: PetType.dog,
      payload: const {'kind': 'dog', 'label': 'Bark', 'score': 0.91},
      createdAt: at,
    ),
    Insight(
      id: 'd',
      type: InsightType.detection,
      petType: PetType.cat,
      breed: 'Bengal',
      payload: const {'score': 0.8},
      createdAt: at,
    ),
  ];

  setUpAll(() => registerFallbackValue(InsightType.clip));
  setUp(() {
    when(() => repo.watchFeed(filter: any(named: 'filter'))).thenAnswer((inv) {
      final filter = inv.namedArguments[#filter] as InsightType?;
      return Stream.value([
        for (final i in items)
          if (filter == null || i.type == filter) i,
      ]);
    });
    GetIt.I.registerSingleton<InsightsRepository>(repo);
  });
  tearDown(GetIt.I.reset);

  testWidgets('renders each entry type and filters by chip', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FeedPage()));
    await tester.pumpAndSettle();

    expect(find.text('Cat spotted · Bengal'), findsOne);
    expect(find.text('Bark heard (Dog)'), findsOne);
    expect(find.text('Clip insight'), findsOne);

    await tester.tap(find.text('Clip insight'));
    await tester.pumpAndSettle();
    expect(find.text('A dog chasing a ball.'), findsOne);
    expect(find.textContaining('Not a diagnosis'), findsOne);

    await tester.tap(find.text('Sounds'));
    await tester.pumpAndSettle();
    expect(find.text('Bark heard (Dog)'), findsOne);
    expect(find.text('Clip insight'), findsNothing);
    expect(find.text('Cat spotted · Bengal'), findsNothing);
  });
}
