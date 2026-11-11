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
  TextColumn get framePaths => text().map(const DocumentsPathsConverter())();
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
      DocumentsPathsConverter.documentsDir = dir.path;
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

/// Keyframe paths, stored relative to the app documents directory.
///
/// iOS moves the app's data container (a new UUID in the path) when the app
/// is updated or reinstalled, so absolute paths go stale and queued clips
/// fail with PathNotFoundException. Rows written before this converter hold
/// absolute paths; those are re-rooted after `/Documents/` on read.
class DocumentsPathsConverter extends TypeConverter<List<String>, String> {
  const new();

  /// Set by [AppDatabase.open] before the first query. Null for in-memory
  /// test databases, where paths pass through unchanged.
  static String? documentsDir;

  static const _marker = '/Documents/';

  @override
  List<String> fromSql(String fromDb) => [
    for (final s in (jsonDecode(fromDb) as List).cast<String>()) _absolute(s),
  ];

  @override
  String toSql(List<String> value) =>
      jsonEncode([for (final s in value) _relative(s)]);

  static String _absolute(String stored) {
    final docs = documentsDir;
    if (docs == null) return stored;
    if (p.isRelative(stored)) return p.join(docs, stored);
    final i = stored.lastIndexOf(_marker); // legacy absolute iOS path
    return i < 0 ? stored : p.join(docs, stored.substring(i + _marker.length));
  }

  static String _relative(String path) {
    final docs = documentsDir;
    return docs != null && p.isWithin(docs, path)
        ? p.relative(path, from: docs)
        : path;
  }
}

class ClipStatusConverter extends TypeConverter<ClipStatus, String> {
  const new();

  @override
  ClipStatus fromSql(String fromDb) =>
      ClipStatus.values.firstWhere((s) => s.wireName == fromDb);

  @override
  String toSql(ClipStatus value) => value.wireName;
}
