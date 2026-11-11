// Flow 2 (spec Phase 8 step 3): record a clip offline -> it is queued ->
// network restored -> the fake WebSocket streams an insight -> it shows up in
// the feed. No camera or backend needed, so it runs on CI emulators.

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:pawsense/app/bootstrap.dart';
import 'package:pawsense/app/router.dart';
import 'package:pawsense/data/api/clips_api.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_recorder.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_page.dart';

import '../test/data/fakes.dart';

class FakeClipRecorder implements ClipRecorder {
  new(this.frames);

  final List<String> frames;

  @override
  Future<void> initialize() async {}

  @override
  Future<String> recordClip(
    Duration length, {
    void Function(Duration remaining)? onTick,
  }) async => 'fake.mp4';

  @override
  Future<List<String>> extractKeyframes(
    String videoPath,
    List<Duration> at,
  ) async => frames;

  @override
  Future<void> dispose() async {}
}

/// Pumps frames until [finder] matches; pumpAndSettle would hang on the
/// Live tab's spinners.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late List<String> frames;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clip_flow');
    final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));
    frames = [
      for (var i = 0; i < 5; i++)
        (await File('${tmp.path}/frame_$i.jpg').writeAsBytes(jpeg)).path,
    ];
  });

  tearDown(() => tmp.delete(recursive: true));

  testWidgets('offline clip is queued, then analyzed and shown in the feed', (
    tester,
  ) async {
    final connectivity = FakeConnectivity(online: false);
    final api = FakeClipsApi()
      ..uploadResults.add('job-1')
      ..sockets.add([
        const ClipStatusChanged(ClipStatus.analyzing),
        const ClipDelta('{"mood":'),
        const ClipInsightReady(testInsight),
        const ClipAnalysisDone(),
      ]);

    await bootstrap(
      flavor: 'test',
      overrides: (getIt) => getIt
        ..registerSingleton<AppDatabase>(memoryDb())
        ..registerSingleton<Connectivity>(connectivity)
        ..registerSingleton<ClipsApi>(api)
        ..registerSingleton<ClipRecorder>(FakeClipRecorder(frames))
        // No real camera on the Live tab: its permission dialog blocks CI.
        ..registerSingleton<ListCameras>(() async => [])
        ..registerSingleton<PermissionsCheck>(() async => true),
    );
    // The router's permission redirect is async: wait for the shell.
    await pumpUntilFound(tester, tab('Clips'));
    await tester.tap(tab('Clips'));
    await pumpUntilFound(tester, find.text('Record 10 s clip'));
    await tester.tap(find.text('Record 10 s clip'));
    await pumpUntilFound(tester, find.text('Queued'));
    expect(api.uploaded, isEmpty);

    connectivity.set(online: true);
    await pumpUntilFound(tester, find.text('Analyzed'));
    expect(api.uploaded, hasLength(1));
    expect(api.connectedJobs, ['job-1']);
    expect(find.text('Queued'), findsNothing);

    await tester.tap(tab('Feed'));
    await pumpUntilFound(tester, find.text('Clip insight'));
  });
}
