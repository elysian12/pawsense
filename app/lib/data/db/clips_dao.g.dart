// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clips_dao.dart';

// ignore_for_file: type=lint
mixin _$ClipsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ClipsTable get clips => attachedDatabase.clips;
  $PendingUploadsTable get pendingUploads => attachedDatabase.pendingUploads;
  ClipsDaoManager get managers => ClipsDaoManager(this);
}

class ClipsDaoManager {
  final _$ClipsDaoMixin _db;
  ClipsDaoManager(this._db);
  $$ClipsTableTableManager get clips =>
      $$ClipsTableTableManager(_db.attachedDatabase, _db.clips);
  $$PendingUploadsTableTableManager get pendingUploads =>
      $$PendingUploadsTableTableManager(
        _db.attachedDatabase,
        _db.pendingUploads,
      );
}
