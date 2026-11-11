import 'dart:async';
import 'dart:collection';

import 'package:pawsense/ml/ml_types.dart';

/// Adaptive frame skipping for the live camera stream.
///
/// The camera delivers ~30 fps; inference is slower and the battery matters,
/// so for every camera frame the caller asks [shouldProcess]:
///
/// - **Busy:** while a frame is in flight every new frame is dropped, never
///   queued (a queue only adds latency and memory).
/// - **Adaptive interval:** a moving average of processing time sets the
///   target interval `max(minInterval, avgMs * k)`, so a slow device spends
///   less time saturated.
/// - **Lower rate** when no pet was seen for [idleAfter] (idle, ~2 fps), when
///   the battery is below [lowBatteryPercent], or when [thermalThrottled] is
///   set by a thermal-state source. Battery and thermal win over a detected
///   pet: they protect the device.
/// - **Back to full rate** on the first frame that detects a pet.
///
/// Usage per camera frame:
/// ```dart
/// if (!scheduler.shouldProcess()) return; // dropped
/// try {
///   final r = await detector.detect(frame);
///   scheduler.onProcessed(petDetected: r.detections.isNotEmpty);
/// } catch (_) {
///   scheduler.onFailed();
/// }
/// ```
///
/// Time comes from `clock` and battery from `batteryLevel` (polled every
/// [batteryPollEvery]), both injectable for tests.
class FrameScheduler {
  new({
    DateTime Function()? clock,
    Future<int> Function()? batteryLevel,
    this.minInterval = const Duration(milliseconds: 33),
    this.k = 1.5,
    this.idleAfter = const Duration(seconds: 5),
    this.idleInterval = const Duration(milliseconds: 500),
    this.lowBatteryInterval = const Duration(milliseconds: 500),
    this.thermalInterval = const Duration(seconds: 1),
    this.lowBatteryPercent = 20,
    this.batteryPollEvery = const Duration(minutes: 1),
    this.window = 50,
  }) : _now = clock ?? DateTime.now,
       _readBattery = batteryLevel;

  final Duration minInterval;

  /// Multiplier on the average processing time.
  final double k;
  final Duration idleAfter;
  final Duration idleInterval;
  final Duration lowBatteryInterval;
  final Duration thermalInterval;
  final int lowBatteryPercent;
  final Duration batteryPollEvery;

  /// Number of recent processing times kept for the average and p95.
  final int window;

  /// Set from a thermal-state source (serious/critical) when one exists.
  bool thermalThrottled = false;

  final DateTime Function() _now;
  final Future<int> Function()? _readBattery;

  bool _busy = false;
  DateTime? _lastStart;
  DateTime? _lastPetAt;
  DateTime? _lastBatteryPoll;
  int? _battery;
  int _dropped = 0;
  final _durationsMs = ListQueue<double>();
  double _sumMs = 0;
  final _completions = ListQueue<DateTime>();

  bool get busy => _busy;

  /// True: process this frame and call [onProcessed] or [onFailed] after.
  /// False: drop it.
  bool shouldProcess() {
    final now = _now();
    _lastPetAt ??= now;
    _pollBattery(now);
    final last = _lastStart;
    if (_busy || (last != null && now.difference(last) < interval)) {
      _dropped++;
      return false;
    }
    _busy = true;
    _lastStart = now;
    return true;
  }

  void onProcessed({required bool petDetected}) {
    final now = _now();
    final ms = now.difference(_lastStart!).inMicroseconds / 1000;
    _durationsMs.add(ms);
    _sumMs += ms;
    if (_durationsMs.length > window) _sumMs -= _durationsMs.removeFirst();
    _completions.add(now);
    if (petDetected) _lastPetAt = now;
    _busy = false;
  }

  /// The in-flight frame failed; frees the slot without recording a time.
  void onFailed() => _busy = false;

  SchedulerMode get mode {
    if (thermalThrottled) return SchedulerMode.thermal;
    if ((_battery ?? 100) < lowBatteryPercent) return SchedulerMode.lowBattery;
    final lastPet = _lastPetAt;
    if (lastPet != null && _now().difference(lastPet) >= idleAfter) {
      return SchedulerMode.idle;
    }
    return SchedulerMode.full;
  }

  /// Minimum time between the starts of two processed frames.
  Duration get interval {
    final adaptive = Duration(microseconds: (_avgMs * k * 1000).round());
    final floor = switch (mode) {
      SchedulerMode.full => minInterval,
      SchedulerMode.idle => idleInterval,
      SchedulerMode.lowBattery => lowBatteryInterval,
      SchedulerMode.thermal => thermalInterval,
    };
    final base = adaptive > minInterval ? adaptive : minInterval;
    return base > floor ? base : floor;
  }

  SchedulerStats get stats {
    final now = _now();
    while (_completions.isNotEmpty &&
        now.difference(_completions.first) > const Duration(seconds: 1)) {
      _completions.removeFirst();
    }
    final sorted = _durationsMs.toList()..sort();
    return SchedulerStats(
      processedFps: _completions.length.toDouble(),
      droppedFrames: _dropped,
      avgInferenceMs: _avgMs,
      p95InferenceMs: sorted.isEmpty
          ? 0
          : sorted[(sorted.length * 0.95).ceil() - 1],
      mode: mode,
    );
  }

  double get _avgMs => _durationsMs.isEmpty ? 0 : _sumMs / _durationsMs.length;

  void _pollBattery(DateTime now) {
    final read = _readBattery;
    final lastPoll = _lastBatteryPoll;
    if (read == null ||
        (lastPoll != null && now.difference(lastPoll) < batteryPollEvery)) {
      return;
    }
    _lastBatteryPoll = now;
    unawaited(
      read().then((level) => _battery = level, onError: (Object _) => null),
    );
  }
}
