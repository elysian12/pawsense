import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/features/settings/presentation/battery_test_cubit.dart';

void main() {
  test('records start/end battery and the average processed fps', () async {
    final levels = [90, 87];
    final fps = [10.0, 20.0, 30.0, 30.0, 30.0];
    var i = 0;
    final cubit = BatteryTestCubit(
      batteryLevel: () async => levels.removeAt(0),
      processedFps: () => fps[i++ % fps.length],
      length: const Duration(milliseconds: 60),
      tick: const Duration(milliseconds: 20),
    );

    await cubit.start(adaptive: false);
    expect(cubit.state.status, BatteryTestStatus.running);
    expect(cubit.state.startLevel, 90);

    await cubit.stream.firstWhere((s) => s.status == BatteryTestStatus.done);
    final s = cubit.state;
    expect(s.endLevel, 87);
    expect(s.avgProcessedFps, greaterThan(0));
    expect(s.report, contains('adaptive skipping OFF'));
    expect(s.report, contains('90% → 87% (−3%)'));
    await cubit.close();
  });

  test('cancel resets', () async {
    final cubit = BatteryTestCubit(
      batteryLevel: () async => 50,
      processedFps: () => 1,
    );
    await cubit.start(adaptive: true);
    cubit.cancel();
    expect(cubit.state, const BatteryTestState());
    await cubit.close();
  });
}
