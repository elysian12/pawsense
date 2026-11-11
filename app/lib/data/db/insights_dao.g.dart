// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'insights_dao.dart';

// ignore_for_file: type=lint
mixin _$InsightsDaoMixin on DatabaseAccessor<AppDatabase> {
  $InsightsTable get insights => attachedDatabase.insights;
  InsightsDaoManager get managers => InsightsDaoManager(this);
}

class InsightsDaoManager {
  final _$InsightsDaoMixin _db;
  InsightsDaoManager(this._db);
  $$InsightsTableTableManager get insights =>
      $$InsightsTableTableManager(_db.attachedDatabase, _db.insights);
}
