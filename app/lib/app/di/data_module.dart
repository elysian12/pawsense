import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:pawsense/core/env.dart';
import 'package:pawsense/data/api/clips_api.dart';
import 'package:pawsense/data/db/app_database.dart';
import 'package:pawsense/data/sync/sync_service.dart';
import 'package:pawsense/features/clip_analysis/data/camera_clip_recorder.dart';
import 'package:pawsense/features/clip_analysis/data/drift_clip_repository.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_recorder.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_repository.dart';
import 'package:pawsense/features/insights_feed/data/drift_insights_repository.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';

/// Registers the data layer. Everything is lazy, so `bootstrap`'s overrides
/// (E2E fakes for ClipsApi, Connectivity, ClipRecorder, ...) are in place
/// before anything is built. Resolving [SyncService] starts it.
void registerDataModule(GetIt getIt) {
  getIt
    ..registerLazySingleton<AppDatabase>(
      AppDatabase.open,
      dispose: (db) => db.close(),
    )
    ..registerLazySingleton<Connectivity>(Connectivity.new)
    ..registerLazySingleton<ClipsApi>(
      () => ClipsApi(baseUrl: Env.apiBaseUrl, token: Env.apiToken),
    )
    ..registerLazySingleton<InsightsRepository>(
      () => DriftInsightsRepository(getIt()),
    )
    ..registerLazySingleton<SyncService>(() {
      final sync = SyncService(
        clips: getIt<AppDatabase>().clipsDao,
        insights: getIt(),
        api: getIt(),
        connectivity: getIt(),
      );
      unawaited(sync.start());
      return sync;
    }, dispose: (s) => s.dispose())
    ..registerLazySingleton<ClipRepository>(
      () => DriftClipRepository(getIt(), getIt()),
    )
    ..registerLazySingleton<ClipRecorder>(CameraClipRecorder.new);
}
