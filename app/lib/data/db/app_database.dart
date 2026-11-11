import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pawsense/data/db/clips_dao.dart';
import 'package:pawsense/data/db/insights_dao.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/ml/ml_types.dart';

part 'app_database.g.dart';

/// Offline-first feed: detections, sounds and clip insights.
@DataClassName('InsightRow')
class Insights extends Table {
  /// UUID v4; for `clip` rows it is the clipId, which makes replays idempotent.
  TextColumn get id => text()();
  TextColumn get type => textEnum<InsightType>()();
  TextColumn get petType => textEnum<PetType>()();
  TextColumn get breed => text().nullable()();
  TextColumn get payload => text().map(const JsonMapConverter())();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ClipRow')
class Clips extends Table {
  TextColumn get id => text()();

  /// Stored as [ClipStatus.wireName] (`pending_upload`, ...).
  TextColumn get status => text().map(const ClipStatusConverter())();
  TextColumn get framePaths => text().map(const StringListConverter())();
  TextColumn get jobId => text().nullable()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get petType => textEnum<PetType>()();
  TextColumn get breedHint => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Upload queue: one row per clip waiting for `POST /v1/clips`, with its
/// exponential-backoff state. Deleted once the upload returns a jobId.
@DataClassName('PendingUploadRow')
class PendingUploads extends Table {
  TextColumn get clipId => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clipId};
}

@DriftDatabase(
  tables: [Insights, Clips, PendingUploads],
  daos: [InsightsDao, ClipsDao],
)
class AppDatabase extends _$AppDatabase {
  new(super.e);

  /// The on-device database in the app documents directory, opened on a
  /// background isolate so queries never block the UI thread.
  factory open() => AppDatabase(
    LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(dir.path, 'pawsense.sqlite')),
      );
    }),
  );

  @override
  int get schemaVersion => 1;
}

class JsonMapConverter extends TypeConverter<Map<String, Object?>, String> {
  const new();

  @override
  Map<String, Object?> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as Map).cast<String, Object?>();

  @override
  String toSql(Map<String, Object?> value) => jsonEncode(value);
}

class StringListConverter extends TypeConverter<List<String>, String> {
  const new();

  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List).cast<String>();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

class ClipStatusConverter extends TypeConverter<ClipStatus, String> {
  const new();

  @override
  ClipStatus fromSql(String fromDb) =>
      ClipStatus.values.firstWhere((s) => s.wireName == fromDb);

  @override
  String toSql(ClipStatus value) => value.wireName;
}
