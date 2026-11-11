import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:pawsense/ml/sound_classifier.dart';

sealed class SoundListenerEvent {
  const new();
}

final class SoundListenStarted extends SoundListenerEvent {
  const new();
}

final class SoundListenStopped extends SoundListenerEvent {
  const new();
}

final class _ScoresReceived extends SoundListenerEvent {
  const new(this.scores);
  final SoundScores scores;
}

final class _SoundDetected extends SoundListenerEvent {
  const new(this.event);
  final SoundEvent event;
}

enum SoundStatus { idle, starting, listening, failure }

class SoundState extends Equatable {
  const new({
    this.status = SoundStatus.idle,
    this.scores,
    this.events = const [],
    this.error,
  });

  final SoundStatus status;

  /// Latest YAMNet window, null until the first one arrives.
  final SoundScores? scores;

  /// Debounced bark/meow events this session, newest first.
  final List<SoundEvent> events;
  final String? error;

  SoundState copyWith({
    SoundStatus? status,
    SoundScores? scores,
    List<SoundEvent>? events,
    String? error,
  }) => SoundState(
    status: status ?? this.status,
    scores: scores ?? this.scores,
    events: events ?? this.events,
    error: error,
  );

  @override
  List<Object?> get props => [status, scores, events, error];
}

/// Drives the Sound tab: starts/stops the YAMNet listener, mirrors its live
/// scores and saves every debounced event to the feed.
class SoundBloc extends Bloc<SoundListenerEvent, SoundState> {
  new(this._classifier, this._insights) : super(const SoundState()) {
    on<SoundListenStarted>(_onStarted);
    on<SoundListenStopped>(_onStopped);
    on<_ScoresReceived>(_onScores);
    on<_SoundDetected>(_onDetected);
    // Both streams are broadcast and outlive start/stop cycles.
    _subs = [
      _classifier.scores.listen((s) => add(_ScoresReceived(s))),
      _classifier.events.listen((e) => add(_SoundDetected(e))),
    ];
  }

  static const maxEvents = 50;

  final SoundClassifier _classifier;
  final InsightsRepository _insights;
  late final List<StreamSubscription<Object?>> _subs;
  bool _loaded = false;

  Future<void> _onStarted(
    SoundListenStarted event,
    Emitter<SoundState> emit,
  ) async {
    if (state.status case SoundStatus.starting || SoundStatus.listening) {
      return;
    }
    emit(state.copyWith(status: SoundStatus.starting));
    try {
      if (!_loaded) {
        await _classifier.load();
        _loaded = true;
      }
      await _classifier.start();
      emit(state.copyWith(status: SoundStatus.listening));
    } on Object catch (e) {
      emit(state.copyWith(status: SoundStatus.failure, error: '$e'));
    }
  }

  Future<void> _onStopped(
    SoundListenStopped event,
    Emitter<SoundState> emit,
  ) async {
    if (state.status != SoundStatus.listening) return;
    await _classifier.stop();
    emit(SoundState(events: state.events)); // clears the stale meter
  }

  void _onScores(_ScoresReceived event, Emitter<SoundState> emit) {
    if (state.status == SoundStatus.listening) {
      emit(state.copyWith(scores: event.scores));
    }
  }

  Future<void> _onDetected(
    _SoundDetected event,
    Emitter<SoundState> emit,
  ) async {
    emit(
      state.copyWith(
        events: [event.event, ...state.events].take(maxEvents).toList(),
      ),
    );
    // A failed write surfaces through the bloc observer (Sentry); the live
    // list above is already updated.
    await _insights.addSound(event.event);
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    // The classifier is a DI factory owned by this bloc.
    if (state.status == SoundStatus.listening) await _classifier.stop();
    await _classifier.dispose();
    await super.close();
  }
}
