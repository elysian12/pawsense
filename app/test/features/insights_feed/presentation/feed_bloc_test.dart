import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';
import 'package:pawsense/features/insights_feed/presentation/bloc/feed_bloc.dart';
import 'package:pawsense/ml/ml_types.dart';

class _MockRepository extends Mock implements InsightsRepository;

void main() {
  late _MockRepository repo;

  final sound = Insight(
    id: 's',
    type: InsightType.sound,
    petType: PetType.dog,
    payload: const {'kind': 'dog', 'label': 'Bark', 'score': 0.9},
    createdAt: DateTime(2026, 11, 12, 10, 5),
  );
  final detection = Insight(
    id: 'd',
    type: InsightType.detection,
    petType: PetType.dog,
    payload: const {'score': 0.8},
    createdAt: DateTime(2026, 11, 12, 10),
  );

  setUpAll(() => registerFallbackValue(InsightType.clip));

  setUp(() {
    repo = _MockRepository();
    when(() => repo.watchFeed(filter: any(named: 'filter')))
        .thenAnswer((_) => Stream.value([sound, detection]));
    when(() => repo.watchFeed(filter: InsightType.sound))
        .thenAnswer((_) => Stream.value([sound]));
  });

  blocTest<FeedBloc, FeedState>(
    'shows the whole feed, newest first, from the repository stream',
    build: () => FeedBloc(repo),
    act: (bloc) => bloc.add(const FeedFilterChanged(null)),
    expect: () => [
      const FeedState(),
      FeedState(insights: [sound, detection], loading: false),
    ],
  );

  blocTest<FeedBloc, FeedState>(
    'a filter chip re-subscribes with that filter',
    build: () => FeedBloc(repo),
    seed: () => FeedState(insights: [sound, detection], loading: false),
    act: (bloc) => bloc.add(const FeedFilterChanged(InsightType.sound)),
    expect: () => [
      FeedState(filter: InsightType.sound, insights: [sound, detection]),
      FeedState(filter: InsightType.sound, insights: [sound], loading: false),
    ],
    verify: (_) =>
        verify(() => repo.watchFeed(filter: InsightType.sound)).called(1),
  );
}
