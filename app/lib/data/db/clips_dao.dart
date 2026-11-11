import 'package:drift/drift.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';

part 'clips_dao.g.dart';

/// Clips and their upload queue. Every status change goes through here, so
/// `watchClip` / `watchAll` are the single source of truth for the UI.
@DriftAccessor(tables: [Clips, PendingUploads])
class ClipsDao extends DatabaseAccessor<AppDatabase> with _$ClipsDaoMixin {
  new(super.attachedDatabase);

  /// Saves [clip] and enqueues it for upload, due at [now].
  Future<void> insertPending(ClipRow clip, DateTime now) =>
      transaction(() async {
        await into(clips).insert(clip);
        await into(pendingUploads).insert(
          PendingUploadsCompanion.insert(clipId: clip.id, nextAttemptAt: now),
        );
      });

  Stream<List<ClipRow>> watchAll() =>
      (select(clips)..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.rowId),
          ]))
          .watch();

  Stream<ClipRow?> watchClip(String id) =>
      (select(clips)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<ClipRow?> getClip(String id) =>
      (select(clips)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<ClipRow>> withStatus(ClipStatus status) =>
      (select(clips)..where((t) => t.status.equalsValue(status))).get();

  /// Queue entries in due order; only those due by [dueBy] when given.
  Future<List<PendingUploadRow>> queue({DateTime? dueBy}) {
    final query = select(pendingUploads)
      ..orderBy([(t) => OrderingTerm.asc(t.nextAttemptAt)]);
    if (dueBy != null) {
      query.where((t) => t.nextAttemptAt.isSmallerOrEqualValue(dueBy));
    }
    return query.get();
  }

  Future<void> setStatus(String id, ClipStatus status) =>
      (update(clips)..where((t) => t.id.equals(id))).write(
        ClipsCompanion(status: Value(status)),
      );

  /// Upload accepted: clip -> analyzing with [jobId], leaves the queue.
  Future<void> markUploaded(String id, String jobId) => transaction(() async {
    await (update(clips)..where((t) => t.id.equals(id))).write(
      ClipsCompanion(
        status: const Value(ClipStatus.analyzing),
        jobId: Value(jobId),
      ),
    );
    await _dequeue(id);
  });

  /// Retryable upload failure: back to "queued" until [at].
  Future<void> scheduleRetry(
    String id, {
    required int attempts,
    required DateTime at,
  }) => transaction(() async {
    await setStatus(id, ClipStatus.pendingUpload);
    await (update(pendingUploads)..where((t) => t.clipId.equals(id))).write(
      PendingUploadsCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(at),
      ),
    );
  });

  Future<void> markFailed(String id, String error) => transaction(() async {
    await (update(clips)..where((t) => t.id.equals(id))).write(
      ClipsCompanion(
        status: const Value(ClipStatus.failed),
        error: Value(error),
      ),
    );
    await _dequeue(id);
  });

  /// Puts a clip back in the queue with fresh backoff, due at [now]. Same
  /// clipId, so the backend deduplicates.
  Future<void> requeue(String id, DateTime now) => transaction(() async {
    await (update(clips)..where((t) => t.id.equals(id))).write(
      const ClipsCompanion(
        status: Value(ClipStatus.pendingUpload),
        error: Value(null),
        jobId: Value(null),
      ),
    );
    await into(pendingUploads).insertOnConflictUpdate(
      PendingUploadsCompanion.insert(clipId: id, nextAttemptAt: now),
    );
  });

  /// Network is back: everything in the queue is due now.
  Future<void> makeAllDue(DateTime now) =>
      update(pendingUploads)
          .write(PendingUploadsCompanion(nextAttemptAt: Value(now)));

  /// App was killed mid-upload: those clips are still queued.
  Future<void> resetInterruptedUploads() =>
      (update(clips)..where((t) => t.status.equalsValue(ClipStatus.uploading)))
          .write(const ClipsCompanion(status: Value(ClipStatus.pendingUpload)));

  Future<void> _dequeue(String id) =>
      (delete(pendingUploads)..where((t) => t.clipId.equals(id))).go();
}

extension ClipRowX on ClipRow {
  Clip toDomain() => Clip(
    id: id,
    status: status,
    framePaths: framePaths,
    createdAt: createdAt,
    petType: petType,
    jobId: jobId,
    error: error,
    breedHint: breedHint,
  );
}
