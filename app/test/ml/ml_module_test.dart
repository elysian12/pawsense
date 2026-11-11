import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:pawsense/app/di/ml_module.dart';
import 'package:pawsense/ml/breed_classifier.dart';
import 'package:pawsense/ml/frame_scheduler.dart';
import 'package:pawsense/ml/pet_detector.dart';
import 'package:pawsense/ml/sound_classifier.dart';

void main() {
  test('ML module resolves every engine without spawning anything', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final getIt = GetIt.asNewInstance();
    registerMlModule(getIt);
    expect(getIt<PetDetector>(), isA<TflitePetDetector>());
    expect(getIt<BreedClassifier>(), isA<TfliteBreedClassifier>());
    // Core ML only on iOS; the test host falls back to TFLite.
    expect(
      getIt<BreedClassifier>(param1: BreedEngine.coreml),
      isA<TfliteBreedClassifier>(),
    );
    expect(getIt<SoundClassifier>(), isA<TfliteSoundClassifier>());
    expect(getIt<FrameScheduler>(), isNot(same(getIt<FrameScheduler>())));
  });
}
