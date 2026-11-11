part of 'feed_bloc.dart';

final class FeedState extends Equatable {
  const new({this.filter, this.insights = const [], this.loading = true});

  /// null = All.
  final InsightType? filter;

  /// Newest first.
  final List<Insight> insights;
  final bool loading;

  @override
  List<Object?> get props => [filter, insights, loading];
}
