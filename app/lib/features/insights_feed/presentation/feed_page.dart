import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';
import 'package:pawsense/features/clip_analysis/presentation/widgets/clip_insight_card.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/features/insights_feed/presentation/bloc/feed_bloc.dart';
import 'package:pawsense/ml/ml_types.dart';

class FeedPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => FeedBloc(GetIt.I())..add(const FeedFilterChanged(null)),
    child: const FeedView(),
  );
}

class FeedView extends StatelessWidget {
  const new({super.key});

  static const _filters = <(String, InsightType?)>[
    ('All', null),
    ('Detections', InsightType.detection),
    ('Sounds', InsightType.sound),
    ('Clips', InsightType.clip),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FeedBloc>().state;
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                for (final (label, type) in _filters)
                  ChoiceChip(
                    label: Text(label),
                    selected: state.filter == type,
                    onSelected: (_) =>
                        context.read<FeedBloc>().add(FeedFilterChanged(type)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: state.loading && state.insights.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.insights.isEmpty
                ? const Center(child: Text('Nothing here yet.'))
                : ListView.separated(
                    itemCount: state.insights.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) =>
                        _InsightTile(insight: state.insights[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const new({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final p = insight.payload;
    final pet = switch (insight.petType) {
      PetType.dog => 'Dog',
      PetType.cat => 'Cat',
      PetType.unknown => 'Pet',
    };
    final date = MaterialLocalizations.of(context)
        .formatShortDate(insight.createdAt);
    final when =
        '$date ${TimeOfDay.fromDateTime(insight.createdAt).format(context)}';
    final breed = insight.breed == null ? '' : ' · ${insight.breed}';

    return switch (insight.type) {
      InsightType.detection => ListTile(
        leading: const Icon(Icons.pets),
        title: Text('$pet spotted$breed'),
        subtitle: Text('${_percent(p['score'])} · $when'),
      ),
      InsightType.sound => ListTile(
        leading: const Icon(Icons.graphic_eq),
        title: Text('${p['label']} heard ($pet)'),
        subtitle: Text('${_percent(p['score'])} · $when'),
      ),
      InsightType.clip => ExpansionTile(
        leading: const Icon(Icons.movie_outlined),
        title: Text('Clip insight$breed'),
        subtitle: Text(when),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          ClipInsightCard(
            insight: ClipInsight.fromJson(
              (p['insight']! as Map).cast<String, Object?>(),
            ),
          ),
        ],
      ),
    };
  }

  static String _percent(Object? score) =>
      '${(((score as num?) ?? 0) * 100).round()}%';
}
