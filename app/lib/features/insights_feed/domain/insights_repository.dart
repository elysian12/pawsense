import 'package:pawsense/features/clip_analysis/domain/clip_insight.dart';
import 'package:pawsense/features/insights_feed/domain/insight.dart';
import 'package:pawsense/ml/ml_types.dart';

/// Offline-first feed. Every write goes to Drift; the UI only reads
/// [watchFeed].
abstract interface class InsightsRepository {
  /// Newest first. [filter] null means all types.
  Stream<List<Insight>> watchFeed({InsightType? filter});

  /// Records a live detection. Throttled by the implementation: at most one
  /// detection entry per [petType] per minute; extra calls are silently
  /// ignored. [at] defaults to now (tests pass a fixed time).
  Future<void> addDetection({
    required PetType petType,
    required double score,
    String? breed,
    DateTime? at,
  });

  /// Records a debounced bark/meow event (`type: sound`).
  Future<void> addSound(SoundEvent event);

  /// Records a finished clip analysis (`type: clip`). Idempotent per
  /// [clipId]: a replayed insight after a reconnect does not duplicate it.
  Future<void> addClipInsight({
    required String clipId,
    required PetType petType,
    required ClipInsight insight,
    String? breed,
  });
}
