import 'package:drift/drift.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:uuid/uuid.dart';

class DriftInsightsRepository implements InsightsRepository {
  new(this._db, {this._uuid = const Uuid()});

  /// One detection entry per pet type per this interval.
  static const detectionInterval = Duration(minutes: 1);

  final AppDatabase _db;
  final Uuid _uuid;

  @override
  Stream<List<Insight>> watchFeed({InsightType? filter}) => _db.insightsDao
      .watchFeed(type: filter)
      .map((rows) => [for (final r in rows) r.toDomain()]);

  @override
  Future<void> addDetection({
    required PetType petType,
    required double score,
    String? breed,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    // Transaction: the check and the insert are atomic (drift serializes
    // transactions), so two frames in the same instant cannot both insert.
    return _db.transaction(() async {
      final last = await _db.insightsDao.latestDetectionAt(petType);
      if (last != null && now.difference(last) < detectionInterval) return;
      await _db.insightsDao.insertOrIgnore(
        InsightsCompanion.insert(
          id: _uuid.v4(),
          type: InsightType.detection,
          petType: petType,
          breed: Value(breed),
          payload: {'score': score},
          createdAt: now,
        ),
      );
    });
  }

  @override
  Future<void> addSound(SoundEvent event) => _db.insightsDao.insertOrIgnore(
    InsightsCompanion.insert(
      id: _uuid.v4(),
      type: InsightType.sound,
      petType: switch (event.kind) {
        SoundKind.dog => PetType.dog,
        SoundKind.cat => PetType.cat,
      },
      payload: {
        'kind': event.kind.name,
        'label': event.label,
        'score': event.score,
      },
      createdAt: event.timestamp,
    ),
  );

  /// The row id is the clipId, so a replayed insight is ignored.
  @override
  Future<void> addClipInsight({
    required String clipId,
    required PetType petType,
    required ClipInsight insight,
    String? breed,
  }) => _db.insightsDao.insertOrIgnore(
    InsightsCompanion.insert(
      id: clipId,
      type: InsightType.clip,
      petType: petType,
      breed: Value(breed),
      payload: {'clipId': clipId, 'insight': insight.toJson()},
      createdAt: DateTime.now(),
    ),
  );
}

extension InsightRowX on InsightRow {
  Insight toDomain() => Insight(
    id: id,
    type: type,
    petType: petType,
    breed: breed,
    payload: payload,
    createdAt: createdAt,
  );
}
