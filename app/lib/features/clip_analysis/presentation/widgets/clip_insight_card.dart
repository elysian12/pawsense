import 'package:flutter/material.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';

/// Final clip insight: mood, activity, health flags and the vet disclaimer.
/// Also used by the feed for `clip` entries.
class ClipInsightCard extends StatelessWidget {
  const new({required this.insight, super.key});

  static const disclaimer = 'Not a diagnosis — see a vet if concerned.';

  final ClipInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            Chip(label: Text('Mood: ${insight.mood.name}')),
            Chip(label: Text('Activity: ${insight.activity.name}')),
            Chip(
              label: Text('Confidence ${(insight.confidence * 100).round()}%'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(insight.summary),
        if (insight.healthFlags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Health observations', style: theme.textTheme.titleSmall),
          for (final flag in insight.healthFlags)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.health_and_safety_outlined,
                color: _severityColor(flag.severity, theme.colorScheme),
              ),
              title: Text('${flag.flag} (${flag.severity.name})'),
              subtitle: Text(flag.evidence),
            ),
          Text(
            disclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  static Color _severityColor(Severity s, ColorScheme scheme) => switch (s) {
    Severity.low => scheme.primary,
    Severity.medium => scheme.tertiary,
    Severity.high => scheme.error,
  };
}
