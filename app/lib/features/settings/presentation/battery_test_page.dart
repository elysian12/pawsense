import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_bloc.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_page.dart';
import 'package:pawsense/features/settings/presentation/battery_test_cubit.dart';
import 'package:pawsense/features/settings/presentation/settings_cubit.dart';

/// Runs live detection for 10 minutes and reports battery drain and the
/// average processed fps, for the before/after adaptive-skipping numbers in
/// docs/METRICS.md.
class BatteryTestPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: GetIt.I<SettingsCubit>()),
      BlocProvider(create: (_) => createLiveDetectionBloc()),
      BlocProvider(
        create: (context) => BatteryTestCubit(
          batteryLevel: () => Battery().batteryLevel,
          processedFps: () =>
              context.read<LiveDetectionBloc>().state.stats.processedFps,
        ),
      ),
    ],
    child: Scaffold(
      appBar: AppBar(title: const Text('Battery test')),
      body: const Column(
        children: [
          Expanded(child: LiveDetectionView()),
          _Panel(),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BatteryTestCubit>();
    final adaptive = context.select<SettingsCubit, bool>(
      (c) => c.state.adaptiveSkipping,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: BlocBuilder<BatteryTestCubit, BatteryTestState>(
          builder: (context, s) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: switch (s.status) {
              BatteryTestStatus.idle => [
                Text(
                  'Unplug the phone, set auto-lock to Never and keep the '
                  'screen on this page. Adaptive frame skipping is '
                  '${adaptive ? 'ON' : 'OFF'} (change it in Settings).',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => cubit.start(adaptive: adaptive),
                  child: const Text('Start 10-minute test'),
                ),
              ],
              BatteryTestStatus.running => [
                Text(
                  'Running · ${_mmss(s.remaining)} left · started at '
                  '${s.startLevel}% · avg '
                  '${s.avgProcessedFps.toStringAsFixed(1)} fps',
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: cubit.cancel,
                  child: const Text('Cancel'),
                ),
              ],
              BatteryTestStatus.done => [
                SelectableText(s.report),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy for METRICS.md'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: s.report));
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Copied')));
                    }
                  },
                ),
                TextButton(onPressed: cubit.cancel, child: const Text('Reset')),
              ],
            },
          ),
        ),
      ),
    );
  }

  static String _mmss(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
