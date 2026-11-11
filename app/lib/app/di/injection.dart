import 'package:get_it/get_it.dart';
import 'package:pawsense/app/di/data_module.dart';
import 'package:pawsense/app/di/ml_module.dart';
import 'package:pawsense/app/router.dart';
import 'package:pawsense/features/settings/presentation/settings_cubit.dart';

/// Composition root. Feature blocs are created in their pages with
/// `BlocProvider(create: (_) => XBloc(getIt()))`, not registered here.
void configureDependencies(GetIt getIt) {
  getIt.registerSingleton<PermissionsCheck>(cameraAndMicrophoneGranted);
  registerMlModule(getIt);
  registerDataModule(getIt);
  // App-wide: Live, Settings and Battery test share one settings state.
  getIt.registerLazySingleton<SettingsCubit>(SettingsCubit.new);
}
