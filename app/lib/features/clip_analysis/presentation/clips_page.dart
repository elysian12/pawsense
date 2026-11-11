import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:pawsense/features/clip_analysis/data/camera_clip_recorder.dart';
import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_recorder.dart';
import 'package:pawsense/features/clip_analysis/presentation/bloc/clip_analysis_bloc.dart';
import 'package:pawsense/features/clip_analysis/presentation/widgets/clip_insight_card.dart';

class ClipsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        ClipAnalysisBloc(GetIt.I(), GetIt.I<ClipRecorder>())
          ..add(const ClipsStarted()),
    child: const ClipsView(),
  );
}

class ClipsView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ClipAnalysisBloc>().state;
    final selected = state.selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Clips')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _RecordSection(),
          if (selected != null) ...[
            const SizedBox(height: 16),
            _AnalysisSection(clip: selected, state: state),
          ],
          const SizedBox(height: 16),
          Text(
            'Recorded clips',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (state.clips.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No clips yet. Record one to analyze it.'),
            ),
          for (final clip in state.clips)
            _ClipTile(clip: clip, selected: clip.id == state.selectedId),
        ],
      ),
    );
  }
}

class _RecordSection extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ClipAnalysisBloc>().state;
    final label = switch (state.phase) {
      RecordPhase.idle => 'Record 10 s clip',
      RecordPhase.recording => 'Recording… ${state.remaining.inSeconds} s',
      RecordPhase.extracting => 'Extracting keyframes…',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.phase == RecordPhase.recording) const _RecordingPreview(),
        FilledButton.icon(
          onPressed: state.phase == RecordPhase.idle
              ? () => context.read<ClipAnalysisBloc>().add(
                  const ClipRecordPressed(),
                )
              : null,
          icon: Icon(
            state.phase == RecordPhase.idle
                ? Icons.fiber_manual_record
                : Icons.hourglass_top,
          ),
          label: Text(label),
        ),
        if (state.recordError case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// Live preview while recording (only for the real camera recorder; fakes in
/// tests have no preview).
class _RecordingPreview extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final recorder = GetIt.I<ClipRecorder>();
    if (recorder is! CameraClipRecorder) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: recorder.controller,
      builder: (_, controller, _) =>
          controller == null || !controller.value.isInitialized
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CameraPreview(controller),
              ),
            ),
    );
  }
}

class _AnalysisSection extends StatelessWidget {
  const new({required this.clip, required this.state});

  final Clip clip;
  final ClipsState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Analysis', style: theme.textTheme.titleMedium),
                ),
                StatusBadge(status: clip.status),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Keyframes (debug)'),
              children: [_KeyframeGallery(paths: clip.framePaths)],
            ),
            if (clip.status == ClipStatus.pendingUpload)
              const Text('Queued: uploads automatically when online.'),
            if (state.streamedText.isNotEmpty && state.insight == null)
              Text(
                '${state.streamedText}▍',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            if (state.insight case final insight?)
              ClipInsightCard(insight: insight),
            if (state.analysisError ?? clip.error case final error?)
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }
}

class _KeyframeGallery extends StatelessWidget {
  const new({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: paths.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(paths[i]),
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.square(
            dimension: 96,
            child: Icon(Icons.broken_image),
          ),
        ),
      ),
    ),
  );
}

class _ClipTile extends StatelessWidget {
  const new({required this.clip, required this.selected});

  final Clip clip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ClipAnalysisBloc>();
    final time = TimeOfDay.fromDateTime(clip.createdAt).format(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: selected,
      leading: const Icon(Icons.movie_outlined),
      title: Text(
        '${MaterialLocalizations.of(context).formatShortDate(clip.createdAt)}'
        ' $time',
      ),
      subtitle: Text('${clip.framePaths.length} keyframes'),
      trailing: clip.status == ClipStatus.failed
          ? TextButton(
              onPressed: () => bloc.add(ClipRetryPressed(clip.id)),
              child: const Text('Retry'),
            )
          : StatusBadge(status: clip.status),
      onTap: () => bloc.add(ClipSelected(clip.id)),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const new({required this.status, super.key});

  final ClipStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      ClipStatus.pendingUpload => ('Queued', scheme.outline),
      ClipStatus.uploading => ('Uploading', scheme.tertiary),
      ClipStatus.analyzing => ('Analyzing', scheme.tertiary),
      ClipStatus.analyzed => ('Analyzed', scheme.primary),
      ClipStatus.failed => ('Failed', scheme.error),
    };
    return Chip(
      label: Text(label),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}
