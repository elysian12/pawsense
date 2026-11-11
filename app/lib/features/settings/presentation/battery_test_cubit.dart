import 'dart:async';
import 'dart:io' show Platform;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum BatteryTestStatus { idle, running, done }

class BatteryTestState extends Equatable {
  const new({
    this.status = BatteryTestStatus.idle,
    this.remaining = Duration.zero,
    this.startLevel,
    this.endLevel,
    this.avgProcessedFps = 0,
    this.adaptive = true,
    this.startedAt,
  });

  final BatteryTestStatus status;
  final Duration remaining;
  final int? startLevel;
  final int? endLevel;

  /// Mean of the per-second processed-fps samples.
  final double avgProcessedFps;

  /// Adaptive frame skipping setting the run was made with.
  final bool adaptive;
  final DateTime? startedAt;

  /// Line to paste into docs/METRICS.md.
  String get report {
    final drop = (startLevel ?? 0) - (endLevel ?? 0);
    final date = startedAt?.toIso8601String().substring(0, 10) ?? '';
    return '| $date | <device> (${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}) | adaptive skipping '
        '${adaptive ? 'ON' : 'OFF'} | $startLevel% → $endLevel% '
        '(−$drop%) over 10 min | avg processed '
        '${avgProcessedFps.toStringAsFixed(1)} fps |';
  }

  @override
  List<Object?> get props => [
    status,
    remaining,
    startLevel,
    endLevel,
    avgProcessedFps,
    adaptive,
    startedAt,
  ];
}

/// Runs live detection for [length] and records battery % at start/end and
/// the average processed fps (sampled every [tick] from `processedFps`).
class BatteryTestCubit extends Cubit<BatteryTestState> {
  new({
    required this._batteryLevel,
    required this._processedFps,
    this.length = const Duration(minutes: 10),
    this.tick = const Duration(seconds: 1),
  }) : super(const BatteryTestState());

  final Duration length;
  final Duration tick;
  final Future<int> Function() _batteryLevel;
  final double Function() _processedFps;
  Timer? _timer;
  double _fpsSum = 0;
  int _samples = 0;

  Future<void> start({required bool adaptive}) async {
    if (state.status == BatteryTestStatus.running) return;
    _fpsSum = 0;
    _samples = 0;
    final level = await _batteryLevel();
    emit(
      BatteryTestState(
        status: BatteryTestStatus.running,
        remaining: length,
        startLevel: level,
        adaptive: adaptive,
        startedAt: DateTime.now(),
      ),
    );
    final end = DateTime.now().add(length);
    _timer = Timer.periodic(tick, (_) => _onTick(end));
  }

  Future<void> _onTick(DateTime end) async {
    if (state.status != BatteryTestStatus.running) return;
    _fpsSum += _processedFps();
    _samples++;
    final remaining = end.difference(DateTime.now());
    if (remaining > Duration.zero) {
      emit(_copy(remaining: remaining));
      return;
    }
    _timer?.cancel();
    final level = await _batteryLevel();
    emit(
      _copy(
        status: BatteryTestStatus.done,
        remaining: Duration.zero,
        endLevel: level,
      ),
    );
  }

  void cancel() {
    _timer?.cancel();
    emit(const BatteryTestState());
  }

  BatteryTestState _copy({
    required Duration remaining,
    BatteryTestStatus? status,
    int? endLevel,
  }) => BatteryTestState(
    status: status ?? state.status,
    remaining: remaining,
    startLevel: state.startLevel,
    endLevel: endLevel,
    avgProcessedFps: _samples == 0 ? 0 : _fpsSum / _samples,
    adaptive: state.adaptive,
    startedAt: state.startedAt,
  );

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
