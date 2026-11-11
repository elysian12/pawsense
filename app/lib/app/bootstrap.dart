import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:pawsense/app/app.dart';
import 'package:pawsense/app/di/injection.dart';
import 'package:pawsense/app/router.dart';
import 'package:pawsense/core/env.dart';
import 'package:pawsense/core/log.dart';
import 'package:pawsense/data/sync/sync_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Shared entry point for every flavor.
///
/// Flavors are Dart entrypoints only (`main_development.dart`,
/// `main_production.dart`), not native Android productFlavors / iOS schemes:
/// the only per-flavor difference is configuration, which comes from
/// `--dart-define-from-file`.
///
/// [overrides] runs after [configureDependencies] with reassignment allowed,
/// so tests (E2E) can swap any registration for a fake, e.g.
/// `overrides: (g) => g.registerSingleton<PetDetector>(FakePetDetector())`.
Future<void> bootstrap({
  required String flavor,
  void Function(GetIt getIt)? overrides,
}) async {
  Future<void> run() async {
    WidgetsFlutterBinding.ensureInitialized();
    final getIt = GetIt.instance;
    await getIt.reset();
    configureDependencies(getIt);
    if (overrides != null) {
      getIt.allowReassignment = true;
      overrides(getIt);
      getIt.allowReassignment = false;
    }
    // Start the upload queue now, so clips left uploading/analyzing by a
    // killed app resume at launch, not when the Clips tab first opens.
    getIt<SyncService>();
    LicenseRegistry.addLicense(_modelLicenses);
    Bloc.observer = const SentryBlocObserver();
    log('Starting PawSense ($flavor)');

    final app = PawSenseApp(
      router: createRouter(hasPermissions: getIt<PermissionsCheck>()),
    );
    runApp(Env.sentryDsn.isEmpty ? app : SentryWidget(child: app));
  }

  if (Env.sentryDsn.isEmpty) {
    await run();
    return;
  }

  await SentryFlutter.init(
    (options) => options
      ..dsn = Env.sentryDsn
      ..environment = flavor
      ..tracesSampleRate = Env.sentryTracesSampleRate,
    appRunner: run,
  );
}

/// The bundled pretrained models are Apache-2.0 and need their notice shown
/// in the app (Settings → About → View licenses). Sources: ml/README.md.
Stream<LicenseEntry> _modelLicenses() => Stream.value(
  const LicenseEntryWithLineBreaks(
    ['EfficientDet-Lite0 (TensorFlow)', 'YAMNet (Google)'],
    'Copyright Google LLC / The TensorFlow Authors.\n\n'
    'Licensed under the Apache License, Version 2.0 (the "License"); you may '
    'not use these files except in compliance with the License. You may '
    'obtain a copy of the License at\n\n'
    'http://www.apache.org/licenses/LICENSE-2.0\n\n'
    'Unless required by applicable law or agreed to in writing, software '
    'distributed under the License is distributed on an "AS IS" BASIS, '
    'WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. '
    'See the License for the specific language governing permissions and '
    'limitations under the License.',
  ),
);

/// Turns every bloc/cubit state change into a Sentry breadcrumb and reports
/// bloc errors. Breadcrumbs are no-ops when Sentry is not initialised.
class SentryBlocObserver extends BlocObserver {
  const new();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'bloc',
          message:
              '${bloc.runtimeType}: ${change.currentState.runtimeType} -> '
              '${change.nextState.runtimeType}',
        ),
      ),
    );
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    log('${bloc.runtimeType} error', error: error, stackTrace: stackTrace);
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }
}
