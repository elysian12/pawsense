import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pawsense/ml/breed_classifier.dart';

class SettingsState extends Equatable {
  const new({
    this.breedEngine = BreedEngine.tflite,
    this.showHud = true,
    this.scoreThreshold = 0.5,
    this.adaptiveSkipping = true,
  });

  /// Core ML is iOS-only; the toggle is hidden elsewhere.
  final BreedEngine breedEngine;
  final bool showHud;

  /// Minimum detector score a box needs to be shown/saved.
  final double scoreThreshold;

  /// Off = process every frame the isolate can take (the "before" battery
  /// baseline). On = idle / low-battery / thermal throttling.
  final bool adaptiveSkipping;

  SettingsState copyWith({
    BreedEngine? breedEngine,
    bool? showHud,
    double? scoreThreshold,
    bool? adaptiveSkipping,
  }) => SettingsState(
    breedEngine: breedEngine ?? this.breedEngine,
    showHud: showHud ?? this.showHud,
    scoreThreshold: scoreThreshold ?? this.scoreThreshold,
    adaptiveSkipping: adaptiveSkipping ?? this.adaptiveSkipping,
  );

  @override
  List<Object?> get props => [
    breedEngine,
    showHud,
    scoreThreshold,
    adaptiveSkipping,
  ];
}

/// App-wide settings, shared by the Settings and Live screens (one instance
/// registered in DI).
// ponytail: in-memory only, resets on app restart; persist to Drift or
// shared_preferences if the owner wants settings to survive restarts.
class SettingsCubit extends Cubit<SettingsState> {
  new() : super(const SettingsState());

  void setBreedEngine(BreedEngine engine) =>
      emit(state.copyWith(breedEngine: engine));

  void setShowHud({required bool show}) => emit(state.copyWith(showHud: show));

  void setScoreThreshold(double threshold) =>
      emit(state.copyWith(scoreThreshold: threshold.clamp(0.1, 0.95)));

  void setAdaptiveSkipping({required bool enabled}) =>
      emit(state.copyWith(adaptiveSkipping: enabled));
}
