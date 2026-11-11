import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:pawsense/ml/breed_classifier.dart';
import 'package:pawsense/ml/coreml_breed_classifier.dart';
import 'package:pawsense/ml/frame_scheduler.dart';
import 'package:pawsense/ml/pet_detector.dart';
import 'package:pawsense/ml/sound_classifier.dart';
import 'package:pawsense/ml/tflite_isolate.dart';

/// Registers the ML engine layer.
///
/// [TfliteIsolate] is the one shared, long-lived inference isolate. The
/// engines are factories: the bloc that gets one owns it and calls `load()`
/// on start and `dispose()` in `close()` (dispose frees the interpreter, the
/// isolate stays up).
///
/// Breed engine: `getIt<BreedClassifier>()` is TFLite;
/// `getIt<BreedClassifier>(param1: BreedEngine.coreml)` is Core ML on iOS
/// (falls back to TFLite elsewhere).
void registerMlModule(GetIt getIt) {
  getIt
    ..registerLazySingleton<TfliteIsolate>(
      TfliteIsolate.new,
      dispose: (isolate) => isolate.dispose(),
    )
    // Low floor: LiveDetectionBloc applies the user's Settings threshold
    // (0.1..0.95) on top, so the slider works below the 0.5 default.
    ..registerFactory<PetDetector>(
      () => TflitePetDetector(getIt(), scoreThreshold: 0.1),
    )
    ..registerFactoryParam<BreedClassifier, BreedEngine?, void>(
      (engine, _) => engine == BreedEngine.coreml && Platform.isIOS
          ? const CoreMLBreedClassifier()
          : TfliteBreedClassifier(getIt()),
    )
    ..registerFactory<SoundClassifier>(() => TfliteSoundClassifier(getIt()))
    ..registerFactory<FrameScheduler>(
      () => FrameScheduler(batteryLevel: () => Battery().batteryLevel),
    );
}
