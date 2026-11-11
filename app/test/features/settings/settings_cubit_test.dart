import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/features/settings/presentation/settings_cubit.dart';
import 'package:pawsense/ml/breed_classifier.dart';

void main() {
  test('defaults: TFLite, HUD on, 0.5 threshold, adaptive on', () {
    expect(SettingsCubit().state, const SettingsState());
    expect(SettingsCubit().state.scoreThreshold, 0.5);
  });

  blocTest<SettingsCubit, SettingsState>(
    'updates each setting',
    build: SettingsCubit.new,
    act: (c) => c
      ..setBreedEngine(BreedEngine.coreml)
      ..setShowHud(show: false)
      ..setScoreThreshold(0.7)
      ..setAdaptiveSkipping(enabled: false),
    expect: () => const [
      SettingsState(breedEngine: BreedEngine.coreml),
      SettingsState(breedEngine: BreedEngine.coreml, showHud: false),
      SettingsState(
        breedEngine: BreedEngine.coreml,
        showHud: false,
        scoreThreshold: 0.7,
      ),
      SettingsState(
        breedEngine: BreedEngine.coreml,
        showHud: false,
        scoreThreshold: 0.7,
        adaptiveSkipping: false,
      ),
    ],
  );

  blocTest<SettingsCubit, SettingsState>(
    'clamps the score threshold',
    build: SettingsCubit.new,
    act: (c) => c.setScoreThreshold(2),
    expect: () => const [SettingsState(scoreThreshold: 0.95)],
  );
}
