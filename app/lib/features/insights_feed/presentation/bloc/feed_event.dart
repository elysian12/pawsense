part of 'feed_bloc.dart';

sealed class FeedEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// A filter chip was tapped; null means All.
final class FeedFilterChanged extends FeedEvent {
  const new(this.filter);

  final InsightType? filter;

  @override
  List<Object?> get props => [filter];
}

final class _FeedUpdated extends FeedEvent {
  const new(this.insights);

  final List<Insight> insights;

  @override
  List<Object?> get props => [insights];
}
