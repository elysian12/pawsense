import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';

part 'feed_event.dart';
part 'feed_state.dart';

/// Reverse-chronological feed straight from Drift's `watch()`.
class FeedBloc extends Bloc<FeedEvent, FeedState> {
  new(this._repository) : super(const FeedState()) {
    on<FeedFilterChanged>(_onFilterChanged);
    on<_FeedUpdated>(
      (e, emit) => emit(
        FeedState(filter: state.filter, insights: e.insights, loading: false),
      ),
    );
  }

  final InsightsRepository _repository;
  StreamSubscription<List<Insight>>? _feed;

  /// Also the start event: `FeedFilterChanged(null)` shows everything.
  void _onFilterChanged(FeedFilterChanged event, Emitter<FeedState> emit) {
    emit(FeedState(filter: event.filter, insights: state.insights));
    unawaited(_feed?.cancel());
    _feed = _repository
        .watchFeed(filter: event.filter)
        .listen((items) => add(_FeedUpdated(items)));
  }

  @override
  Future<void> close() async {
    await _feed?.cancel();
    await super.close();
  }
}
