import 'package:pawsense/ml/ml_types.dart';

/// Turns per-window YAMNet scores into debounced bark/meow events.
///
/// A kind fires only when its score stays at or above its threshold for
/// [windowsRequired] consecutive windows (one loud transient is not a bark),
/// then stays quiet for [cooldown] so one barking fit is one event.
class SoundDebouncer {
  new({
    this.thresholds = const {SoundKind.dog: 0.3, SoundKind.cat: 0.3},
    this.windowsRequired = 2,
    this.cooldown = const Duration(seconds: 3),
  });

  final Map<SoundKind, double> thresholds;
  final int windowsRequired;
  final Duration cooldown;

  final _streak = <SoundKind, int>{};
  final _quietUntil = <SoundKind, DateTime>{};

  /// Feeds one window's best score for [kind]; returns an event when it fires.
  SoundEvent? add(SoundKind kind, String label, double score, DateTime at) {
    if (score < thresholds[kind]!) {
      _streak[kind] = 0;
      return null;
    }
    final streak = _streak[kind] = (_streak[kind] ?? 0) + 1;
    final quietUntil = _quietUntil[kind];
    if (streak < windowsRequired ||
        (quietUntil != null && at.isBefore(quietUntil))) {
      return null;
    }
    _streak[kind] = 0;
    _quietUntil[kind] = at.add(cooldown);
    return SoundEvent(kind: kind, label: label, score: score, timestamp: at);
  }

  void reset() {
    _streak.clear();
    _quietUntil.clear();
  }
}
