import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:pawsense/features/settings/presentation/battery_test_page.dart';
import 'package:pawsense/features/settings/presentation/settings_cubit.dart';
import 'package:pawsense/ml/breed_classifier.dart';

class SettingsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: GetIt.I<SettingsCubit>(),
    child: const SettingsView(),
  );
}

class SettingsView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, s) => ListView(
          children: [
            if (defaultTargetPlatform == TargetPlatform.iOS)
              ListTile(
                title: const Text('Breed engine'),
                subtitle: const Text('Compare latency in the HUD'),
                trailing: SegmentedButton<BreedEngine>(
                  segments: const [
                    ButtonSegment(
                      value: BreedEngine.tflite,
                      label: Text('TFLite'),
                    ),
                    ButtonSegment(
                      value: BreedEngine.coreml,
                      label: Text('Core ML'),
                    ),
                  ],
                  selected: {s.breedEngine},
                  onSelectionChanged: (v) => cubit.setBreedEngine(v.single),
                ),
              ),
            SwitchListTile(
              title: const Text('Debug HUD'),
              subtitle: const Text('FPS, inference ms, scheduler mode'),
              value: s.showHud,
              onChanged: (v) => cubit.setShowHud(show: v),
            ),
            SwitchListTile(
              title: const Text('Adaptive frame skipping'),
              subtitle: const Text(
                'Slows down when no pet is in view, on low battery or when '
                'hot. Turn off for the "before" battery measurement.',
              ),
              value: s.adaptiveSkipping,
              onChanged: (v) => cubit.setAdaptiveSkipping(enabled: v),
            ),
            ListTile(
              title: const Text('Detection score threshold'),
              subtitle: Slider(
                value: s.scoreThreshold,
                min: 0.1,
                max: 0.95,
                divisions: 17,
                label: s.scoreThreshold.toStringAsFixed(2),
                onChanged: cubit.setScoreThreshold,
              ),
              trailing: Text(s.scoreThreshold.toStringAsFixed(2)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.battery_charging_full),
              title: const Text('Battery test'),
              subtitle: const Text('10 minutes of live detection'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BatteryTestPage(),
                ),
              ),
            ),
            // Opens the licenses page, which includes the bundled models.
            const AboutListTile(
              icon: Icon(Icons.info_outline),
              applicationName: 'PawSense',
            ),
          ],
        ),
      ),
    );
  }
}
