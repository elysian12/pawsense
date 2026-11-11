import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/ml/ml_types.dart';

import '../fakes.dart';

void main() {
  late AppDatabase db;
  final t0 = DateTime(2026, 11, 12, 10);

  ClipRow clip(String id, {int minute = 0}) => ClipRow(
    id: id,
    status: ClipStatus.pendingUpload,
    framePaths: const ['/a.jpg', '/b.jpg'],
    createdAt: t0.add(Duration(minutes: minute)),
    petType: PetType.dog,
  );

  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  test('insertPending saves the clip and queues it', () async {
    await db.clipsDao.insertPending(clip('a'), t0);
    await db.clipsDao.insertPending(clip('b', minute: 1), t0);

    final all = await db.clipsDao.watchAll().first;
    expect(all.map((c) => c.id), ['b', 'a']);
    expect(all.last.framePaths, ['/a.jpg', '/b.jpg']);
    expect(all.last.status, ClipStatus.pendingUpload);
    expect((await db.clipsDao.queue()).map((q) => q.clipId), {'a', 'b'});
  });

  test('status is stored as the wire name', () async {
    await db.clipsDao.insertPending(clip('a'), t0);
    final raw = await db.customSelect('SELECT status FROM clips').getSingle();
    expect(raw.read<String>('status'), 'pending_upload');
  });

  test('queue respects nextAttemptAt; makeAllDue resets it', () async {
    await db.clipsDao.insertPending(clip('a'), t0);
    await db.clipsDao.scheduleRetry(
      'a',
      attempts: 1,
      at: t0.add(const Duration(minutes: 5)),
    );
    expect(await db.clipsDao.queue(dueBy: t0), isEmpty);

    await db.clipsDao.makeAllDue(t0);
    expect((await db.clipsDao.queue(dueBy: t0)).single.attempts, 1);
  });

  test('markUploaded / markFailed leave the queue; requeue resets', () async {
    await db.clipsDao.insertPending(clip('a'), t0);
    await db.clipsDao.markUploaded('a', 'job-1');
    var row = (await db.clipsDao.getClip('a'))!;
    expect((row.status, row.jobId), (ClipStatus.analyzing, 'job-1'));
    expect(await db.clipsDao.queue(), isEmpty);

    await db.clipsDao.markFailed('a', 'refused');
    row = (await db.clipsDao.getClip('a'))!;
    expect((row.status, row.error), (ClipStatus.failed, 'refused'));

    await db.clipsDao.requeue('a', t0);
    row = (await db.clipsDao.getClip('a'))!;
    expect(
      (row.status, row.error, row.jobId),
      (ClipStatus.pendingUpload, null, null),
    );
    expect((await db.clipsDao.queue()).single.attempts, 0);
  });
}
