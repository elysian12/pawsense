import 'package:drift/drift.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/ml/ml_types.dart';

part 'insights_dao.g.dart';

@DriftAccessor(tables: [Insights])
class InsightsDao extends DatabaseAccessor<AppDatabase>
    with _$InsightsDaoMixin {
  new(super.attachedDatabase);

  /// Newest first; rowid breaks ties (createdAt has second precision).
  // ponytail: unbounded list, add paging (limit/offset) if feeds get long.
  Stream<List<InsightRow>> watchFeed({InsightType? type}) {
    final query = select(insights)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.rowId),
      ]);
    if (type != null) query.where((t) => t.type.equalsValue(type));
    return query.watch();
  }

  Future<DateTime?> latestDetectionAt(PetType petType) {
    final latest = insights.createdAt.max();
    final query = selectOnly(insights)
      ..addColumns([latest])
      ..where(
        insights.type.equalsValue(InsightType.detection) &
            insights.petType.equalsValue(petType),
      );
    return query.map((row) => row.read(latest)).getSingle();
  }

  Future<InsightRow?> byId(String id) =>
      (select(insights)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Ignores a row whose id already exists (idempotent clip insights).
  Future<void> insertOrIgnore(InsightsCompanion row) =>
      into(insights).insert(row, mode: InsertMode.insertOrIgnore);
}
