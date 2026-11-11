import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/features/insights_feed/data/drift_insights_repository.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/ml/ml_types.dart';

import '../../../data/fakes.dart';

void main() {
  late AppDatabase db;
  late DriftInsightsRepository repo;
  final t0 = DateTime(2026, 11, 12, 10);

  setUp(() {
    db = memoryDb();
    repo = DriftInsightsRepository(db);
  });
  tearDown(() => db.close());

  Future<List<Insight>> feed({InsightType? filter}) =>
      repo.watchFeed(filter: filter).first;

  test('detections are saved at most once per minute per pet type', () async {
    await repo.addDetection(petType: PetType.dog, score: 0.9, at: t0);
    await repo.addDetection(
      petType: PetType.dog,
      score: 0.9,
      at: t0.add(const Duration(seconds: 59)),
    );
    await repo.addDetection(
      petType: PetType.cat,
      score: 0.7,
      at: t0.add(const Duration(seconds: 30)),
    );
    await repo.addDetection(
      petType: PetType.dog,
      score: 0.8,
      breed: 'beagle',
      at: t0.add(const Duration(minutes: 1)),
    );

    final items = await feed(filter: InsightType.detection);
    expect(items.map((i) => (i.petType, i.createdAt)), [
      (PetType.dog, t0.add(const Duration(minutes: 1))),
      (PetType.cat, t0.add(const Duration(seconds: 30))),
      (PetType.dog, t0),
    ]);
    expect(items.first.breed, 'beagle');
    expect(items.first.payload, {'score': 0.8});
  });

  test('concurrent detections in the same instant insert once', () async {
    await Future.wait([
      for (var i = 0; i < 5; i++)
        repo.addDetection(petType: PetType.dog, score: 0.9, at: t0),
    ]);
    expect(await feed(), hasLength(1));
  });

  test('feed is newest first and filters by type', () async {
    await repo.addDetection(petType: PetType.dog, score: 0.9, at: t0);
    await repo.addSound(
      SoundEvent(
        kind: SoundKind.cat,
        label: 'Meow',
        score: 0.6,
        timestamp: t0.add(const Duration(minutes: 5)),
      ),
    );

    expect((await feed()).map((i) => i.type), [
      InsightType.sound,
      InsightType.detection,
    ]);
    final sounds = await feed(filter: InsightType.sound);
    expect(sounds.single.petType, PetType.cat);
    expect(sounds.single.payload, {
      'kind': 'cat',
      'label': 'Meow',
      'score': 0.6,
    });
  });

  test('clip insight is idempotent per clipId', () async {
    for (var i = 0; i < 2; i++) {
      await repo.addClipInsight(
        clipId: 'clip-1',
        petType: PetType.dog,
        insight: testInsight,
      );
    }
    final clips = await feed(filter: InsightType.clip);
    expect(clips.single.id, 'clip-1');
    expect(clips.single.payload['insight'], testInsight.toJson());
  });
}
