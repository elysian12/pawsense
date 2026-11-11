import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/ml/frame_scheduler.dart';
import 'package:pawsense/ml/ml_types.dart';

void main() {
  late DateTime now;
  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  setUp(() => now = DateTime(2026));

  FrameScheduler scheduler({
    Future<int> Function()? battery,
    int window = 50,
  }) => FrameScheduler(clock: () => now, batteryLevel: battery, window: window);

  /// Accepts a frame, "runs inference" for [ms], completes it.
  void process(FrameScheduler s, int ms, {bool pet = false}) {
    expect(s.shouldProcess(), isTrue);
    advance(ms);
    s.onProcessed(petDetected: pet);
  }

  test('drops frames while one is in flight, never queues', () {
    final s = scheduler();
    expect(s.shouldProcess(), isTrue);
    advance(100);
    expect(s.shouldProcess(), isFalse);
    expect(s.shouldProcess(), isFalse);
    s.onProcessed(petDetected: true);
    expect(s.stats.droppedFrames, 2);
    advance(50); // 150 ms interval since the last start
    expect(s.shouldProcess(), isTrue);
  });

  test('interval = max(minInterval, avgMs * k)', () {
    final s = scheduler();
    process(s, 100, pet: true);
    advance(50);
    process(s, 100, pet: true);
    // avg 100 ms * k 1.5 = 150 ms since the last start (100 ms ago).
    expect(s.interval, const Duration(milliseconds: 150));
    advance(49);
    expect(s.shouldProcess(), isFalse);
    advance(1);
    expect(s.shouldProcess(), isTrue);

    final fast = scheduler();
    process(fast, 10, pet: true);
    expect(fast.interval, const Duration(milliseconds: 33));
  });

  test('failed frames free the slot without counting a time', () {
    final s = scheduler();
    expect(s.shouldProcess(), isTrue);
    advance(500);
    s.onFailed();
    expect(s.busy, isFalse);
    expect(s.stats.avgInferenceMs, 0);
  });

  test('idles at ~2 fps without a pet, back to full on detection', () {
    final s = scheduler();
    process(s, 20);
    advance(5000);
    expect(s.mode, SchedulerMode.idle);
    expect(s.interval, const Duration(milliseconds: 500));
    expect(s.shouldProcess(), isTrue);
    advance(20);
    s.onProcessed(petDetected: true);
    expect(s.mode, SchedulerMode.full);
    expect(s.interval, const Duration(milliseconds: 33));
  });

  test('low battery and thermal lower the rate', () async {
    var level = 50;
    final s = scheduler(battery: () async => level);
    process(s, 20, pet: true);
    await Future<void>.delayed(Duration.zero);
    expect(s.mode, SchedulerMode.full);

    level = 15;
    advance(60000); // next battery poll is due
    s.shouldProcess();
    await Future<void>.delayed(Duration.zero);
    expect(s.mode, SchedulerMode.lowBattery);
    expect(s.interval, const Duration(milliseconds: 500));

    s.thermalThrottled = true;
    expect(s.mode, SchedulerMode.thermal);
    expect(s.interval, const Duration(seconds: 1));
  });

  test('stats: avg, p95 and processed fps', () {
    final s = scheduler(window: 100);
    for (var ms = 1; ms <= 100; ms++) {
      advance(1000); // past any interval
      process(s, ms, pet: true);
    }
    final stats = s.stats;
    expect(stats.avgInferenceMs, closeTo(50.5, 1e-9));
    expect(stats.p95InferenceMs, 95);
    expect(stats.processedFps, 1); // one completion in the last second
  });
}
