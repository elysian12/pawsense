import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:pawsense/features/sound/presentation/sound_bloc.dart';
import 'package:pawsense/ml/ml_types.dart' show SoundEvent;

class SoundPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SoundBloc(GetIt.I(), GetIt.I()),
    child: const SoundView(),
  );
}

class SoundView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sound')),
      body: BlocBuilder<SoundBloc, SoundState>(
        builder: (context, state) {
          final listening = state.status == SoundStatus.listening;
          final scores = listening ? state.scores : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Level', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: levelFromRms(scores?.rms ?? 0),
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      scores == null
                          ? (listening ? 'Listening…' : 'Not listening')
                          : '${scores.topLabel} '
                                '${(scores.topScore * 100).round()}%',
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (scores != null)
                      Text(
                        'dog ${(scores.dogScore * 100).round()}%  ·  '
                        'cat ${(scores.catScore * 100).round()}%',
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (state.status == SoundStatus.failure)
                      Text(
                        'Could not start: ${state.error}',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: state.status == SoundStatus.starting
                          ? null
                          : () => context.read<SoundBloc>().add(
                              listening
                                  ? const SoundListenStopped()
                                  : const SoundListenStarted(),
                            ),
                      icon: Icon(listening ? Icons.stop : Icons.mic),
                      label: Text(listening ? 'Stop' : 'Start listening'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: state.events.isEmpty
                    ? const Center(child: Text('No barks or meows yet'))
                    : ListView.builder(
                        itemCount: state.events.length,
                        itemBuilder: (_, i) => _EventTile(state.events[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Maps RMS to a 0..1 meter on a -60..0 dBFS scale (linear RMS barely moves
/// for normal room sound).
double levelFromRms(double rms) {
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 60) / 60).clamp(0, 1);
}

class _EventTile extends StatelessWidget {
  const new(this.event);

  final SoundEvent event;

  @override
  Widget build(BuildContext context) {
    final t = TimeOfDay.fromDateTime(event.timestamp).format(context);
    return ListTile(
      leading: const Icon(Icons.pets),
      title: Text('${event.label} (${event.kind.name})'),
      subtitle: Text(t),
      trailing: Text('${(event.score * 100).round()}%'),
    );
  }
}
