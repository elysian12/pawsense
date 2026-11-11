import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/data/api/clips_api.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/data/sync/sync_service.dart';
import 'package:pawsense/features/clip_analysis/data/drift_clip_repository.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/insights_feed/data/drift_insights_repository.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/ml/ml_types.dart';

import '../fakes.dart';

void main() {
  test('defaultBackoff doubles from 2 s and caps at 5 min', () {
    expect([1, 2, 3, 10, 30].map(defaultBackoff), const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(minutes: 5),
      Duration(minutes: 5),
    ]);
  });

  group('SyncService', () {
    late AppDatabase db;
    late FakeClipsApi api;
    late FakeConnectivity connectivity;
    late DateTime now;
    late SyncService sync;
    late DriftClipRepository repo;
    late DriftInsightsRepository insights;

    /// Minutes, so the retry timer never fires during a test.
    Duration slowBackoff(int attempt) => Duration(minutes: attempt);

    Future<void> build({
      bool online = true,
      Duration Function(int) backoff = defaultBackoff,
    }) async {
      db = memoryDb();
      api = FakeClipsApi();
      connectivity = FakeConnectivity(online: online);
      now = DateTime(2026, 11, 12, 10);
      insights = DriftInsightsRepository(db);
      sync = SyncService(
        clips: db.clipsDao,
        insights: insights,
        api: api,
        connectivity: connectivity,
        now: () => now,
        backoff: backoff,
      );
      repo = DriftClipRepository(db, sync, now: () => now);
      await sync.start();
    }

    tearDown(() async {
      await sync.dispose();
      await db.close();
    });

    Future<ClipRow> waitForStatus(String id, ClipStatus status) => db.clipsDao
        .watchClip(id)
        .where((r) => r?.status == status)
        .cast<ClipRow>()
        .first
        .timeout(const Duration(seconds: 5));

    Future<Clip> newClip() => repo.createPendingClip(
      framePaths: const ['/f.jpg'],
      petType: PetType.dog,
    );

    test('offline clip stays queued, then drains and analyzes when the '
        'network returns', () async {
      await build(online: false);
      api
        ..uploadResults.add('job-1')
        ..sockets.add([
          const ClipStatusChanged(ClipStatus.analyzing),
          const ClipDelta('Looks '),
          const ClipDelta('happy'),
          const ClipInsightReady(testInsight),
          const ClipAnalysisDone(),
        ]);

      final clip = await newClip();
      await pumpEventQueue();
      expect(api.uploaded, isEmpty);
      expect(
        (await db.clipsDao.getClip(clip.id))!.status,
        ClipStatus.pendingUpload,
      );

      final events = repo.watchAnalysis(clip.id).toList();
      connectivity.set(online: true);

      final row = await waitForStatus(clip.id, ClipStatus.analyzed);
      expect(row.jobId, 'job-1');
      expect(api.uploaded, [clip.id]);
      expect(await db.clipsDao.queue(), isEmpty);

      final feed = await insights.watchFeed(filter: InsightType.clip).first;
      expect(feed.single.id, clip.id);

      final received = await events.timeout(const Duration(seconds: 5));
      expect(received.first, const ClipStatusChanged(ClipStatus.pendingUpload));
      expect(
        received,
        containsAllInOrder(const [ClipDelta('Looks '), ClipDelta('happy')]),
      );
      expect(
        received.whereType<ClipInsightReady>().single.insight,
        testInsight,
      );
      expect(received.last, const ClipAnalysisDone());
    });

    test('retryable upload failures back off exponentially', () async {
      await build(backoff: slowBackoff);
      api.uploadResults.addAll([
        const ApiException('HTTP 503', retryable: true),
        const ApiException('timeout', retryable: true),
        'job-1',
      ]);

      final clip = await newClip();
      await pumpEventQueue();
      var queued = (await db.clipsDao.queue()).single;
      expect(queued.attempts, 1);
      expect(queued.nextAttemptAt, now.add(const Duration(minutes: 1)));
      expect(
        (await db.clipsDao.getClip(clip.id))!.status,
        ClipStatus.pendingUpload,
      );

      // Not due yet: no request.
      now = now.add(const Duration(seconds: 59));
      await sync.sync();
      expect(api.uploaded, hasLength(1));

      now = now.add(const Duration(seconds: 1));
      await sync.sync();
      queued = (await db.clipsDao.queue()).single;
      expect(queued.attempts, 2);
      expect(queued.nextAttemptAt, now.add(const Duration(minutes: 2)));

      // Network restored skips the remaining backoff.
      await sync.sync(networkRestored: true);
      expect(api.uploaded, hasLength(3));
      expect((await db.clipsDao.getClip(clip.id))!.jobId, 'job-1');
      expect(await db.clipsDao.queue(), isEmpty);
    });

    test('non-retryable upload failure marks the clip failed; retry re-posts '
        'the same clipId', () async {
      await build(backoff: slowBackoff);
      api.uploadResults.add(const ApiException('HTTP 413', retryable: false));

      final clip = await newClip();
      final failed = await waitForStatus(clip.id, ClipStatus.failed);
      expect(failed.error, 'HTTP 413');
      expect(await db.clipsDao.queue(), isEmpty);

      api
        ..uploadResults.add('job-2')
        ..sockets.add([
          const ClipInsightReady(testInsight),
          const ClipAnalysisDone(),
        ]);
      await repo.retry(clip.id);
      await waitForStatus(clip.id, ClipStatus.analyzed);
      expect(api.uploaded, [clip.id, clip.id]);
    });

    test('a dropped socket reconnects to the same jobId', () async {
      await build(backoff: (_) => Duration.zero);
      api
        ..uploadResults.add('job-1')
        ..sockets.addAll([
          [const ClipDelta('par')], // drops without done
          [const ClipInsightReady(testInsight), const ClipAnalysisDone()],
        ]);

      final clip = await newClip();
      await waitForStatus(clip.id, ClipStatus.analyzed);
      expect(api.connectedJobs, ['job-1', 'job-1']);
    });

    test('server error marks the clip failed', () async {
      await build();
      api
        ..uploadResults.add('job-1')
        ..sockets.add([
          const ClipAnalysisError(ClipErrorCode.refused, 'declined'),
          const ClipAnalysisDone(),
        ]);

      final clip = await newClip();
      final row = await waitForStatus(clip.id, ClipStatus.failed);
      expect(row.error, 'declined');
    });

    test(
      'watchAnalysis of an analyzed clip replays the stored insight',
      () async {
        await build();
        api
          ..uploadResults.add('job-1')
          ..sockets.add([
            const ClipInsightReady(testInsight),
            const ClipAnalysisDone(),
          ]);
        final clip = await newClip();
        await waitForStatus(clip.id, ClipStatus.analyzed);

        expect(await repo.watchAnalysis(clip.id).toList(), const [
          ClipStatusChanged(ClipStatus.analyzed),
          ClipInsightReady(testInsight),
          ClipAnalysisDone(),
        ]);
      },
    );

    test(
      'start resumes clips left analyzing and resets interrupted uploads',
      () async {
        db = memoryDb();
        final t0 = DateTime(2020); // in the past, so already due
        ClipRow row(String id) => ClipRow(
          id: id,
          status: ClipStatus.pendingUpload,
          framePaths: const ['/f.jpg'],
          createdAt: t0,
          petType: PetType.cat,
        );
        await db.clipsDao.insertPending(row('analyzing'), t0);
        await db.clipsDao.markUploaded('analyzing', 'job-9');
        await db.clipsDao.insertPending(row('interrupted'), t0);
        await db.clipsDao.setStatus('interrupted', ClipStatus.uploading);

        api = FakeClipsApi()
          ..uploadResults.add('job-10')
          ..sockets.addAll([
            [const ClipInsightReady(testInsight), const ClipAnalysisDone()],
            [const ClipInsightReady(testInsight), const ClipAnalysisDone()],
          ]);
        sync = SyncService(
          clips: db.clipsDao,
          insights: DriftInsightsRepository(db),
          api: api,
          connectivity: FakeConnectivity(),
        );
        await sync.start();

        await waitForStatus('analyzing', ClipStatus.analyzed);
        await waitForStatus('interrupted', ClipStatus.analyzed);
        expect(api.uploaded, ['interrupted']);
        expect(api.connectedJobs, containsAll(['job-9', 'job-10']));
      },
    );
  });
}
