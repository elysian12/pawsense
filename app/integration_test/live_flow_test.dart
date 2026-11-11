// Flow 1 (spec Phase 8): onboarding -> permissions -> the Live tab shows a
// detection from a fake detector. No camera, model or network: ML and data
// edges are replaced through `bootstrap(overrides:)`, and frames are fed to
// the LiveDetectionBloc directly (a simulator/emulator has no real pet).
//
// Run: flutter test integration_test/live_flow_test.dart -d <device>
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pawsense/app/bootstrap.dart';
import 'package:pawsense/app/router.dart';
import 'package:pawsense/data/api/clips_api.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_bloc.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_page.dart';
import 'package:pawsense/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:pawsense/ml/breed_classifier.dart';
import 'package:pawsense/ml/frame_scheduler.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:pawsense/ml/pet_detector.dart';
import 'package:permission_handler/permission_handler.dart';

const _dog = Detection(
  label: PetType.dog,
  score: 0.92,
  box: Rect.fromLTRB(0.2, 0.3, 0.8, 0.9),
);

class _FakeDetector implements PetDetector {
  @override
  Future<void> load() async {}

  @override
  Future<DetectionResult> detect(FrameData frame) async =>
      const DetectionResult(detections: [_dog], detectionMs: 5, engine: 'fake');

  @override
  Future<void> dispose() async {}
}

class _FakeClassifier implements BreedClassifier {
  @override
  String get engineName => 'Fake';

  @override
  Future<void> load() async {}

  @override
  Future<List<BreedPrediction>> classify(FrameData frame, Rect box) async =>
      const [BreedPrediction(label: 'beagle', confidence: 0.71)];

  @override
  Future<void> dispose() async {}
}

/// Offline backend: SyncService starts in bootstrap but never uploads.
class _OfflineApi implements ClipsApi {
  @override
  Future<String> uploadClip(Clip clip) => throw UnimplementedError();

  @override
  Stream<ClipAnalysisEvent> streamAnalysis(String jobId) =>
      const Stream.empty();
}

class _OfflineConnectivity implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.none,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

final _frame = FrameData(
  planes: [Uint8List(4)],
  bytesPerRow: const [4],
  bytesPerPixel: const [4],
  width: 1,
  height: 1,
  format: FrameFormat.bgra8888,
  sensorOrientation: 90,
  timestamp: DateTime(2026),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding -> Live tab shows a fake detection', (tester) async {
    final semantics = tester.ensureSemantics();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    var granted = false;

    await bootstrap(
      flavor: 'e2e',
      overrides: (g) => g
        ..registerSingleton<PermissionsCheck>(() async => granted)
        ..registerSingleton<ReadPermissions>(() async {
          granted = true;
          return [PermissionStatus.granted, PermissionStatus.granted];
        })
        // No real camera: its system permission dialog would block CI.
        ..registerSingleton<ListCameras>(() async => [])
        ..registerFactory<PetDetector>(_FakeDetector.new)
        ..registerFactoryParam<BreedClassifier, BreedEngine?, void>(
          (_, _) => _FakeClassifier(),
        )
        ..registerFactory<FrameScheduler>(FrameScheduler.new)
        ..registerLazySingleton<AppDatabase>(
          () => AppDatabase(NativeDatabase.memory()),
          dispose: (db) => db.close(),
        )
        ..registerLazySingleton<ClipsApi>(_OfflineApi.new)
        ..registerLazySingleton<Connectivity>(_OfflineConnectivity.new),
    );
    await tester.pumpAndSettle();

    // Not granted yet: the router sends us to onboarding.
    expect(find.text('Welcome'), findsOne);
    await tester.tap(find.text('Allow camera & microphone'));
    await tester.pumpAndSettle();

    // Live tab. The camera is absent or unauthorized here; the overlay still
    // paints whatever the bloc detects.
    expect(find.byType(LiveDetectionView), findsOne);
    final bloc = tester
        .element(find.byType(LiveDetectionView))
        .read<LiveDetectionBloc>();
    Future<void> until(bool Function(LiveDetectionState) test) async {
      if (!test(bloc.state)) await bloc.stream.firstWhere(test);
    }

    await until((s) => s.status == LiveStatus.ready);
    bloc.add(LiveFrameArrived(() => _frame));
    await until((s) => s.detections.isNotEmpty);
    await tester.pump();

    expect(find.bySemanticsLabel(RegExp('dog 92%')), findsOne);
    expect(find.textContaining('breed Fake'), findsOne); // HUD
    semantics.dispose();
  });
}
