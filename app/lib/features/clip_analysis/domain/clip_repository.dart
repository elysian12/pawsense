import 'package:pawsense/features/clip_analysis/domain/clip.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_analysis_event.dart';
import 'package:pawsense/ml/ml_types.dart';

/// Offline-first clip store + upload/analysis pipeline.
///
/// Writes go to Drift first; a sync queue uploads `pendingUpload` clips when
/// connectivity returns (retry with exponential backoff), then opens the
/// WebSocket for the job.
abstract interface class ClipRepository {
  /// Saves a new clip with a fresh UUID and status [ClipStatus.pendingUpload]
  /// and enqueues it for upload. Never touches the network itself, so it
  /// works in airplane mode.
  Future<Clip> createPendingClip({
    required List<String> framePaths,
    required PetType petType,
    String? breedHint,
  });

  /// All clips, newest first, live from Drift.
  Stream<List<Clip>> watchClips();

  /// Analysis events for one clip. Emits the current status first, then
  /// everything that happens until [ClipAnalysisDone] (after which the stream
  /// closes). Reconnects to the same jobId if the socket drops; for an already
  /// analyzed clip it emits the stored insight and done.
  Stream<ClipAnalysisEvent> watchAnalysis(String clipId);

  /// Re-queues a [ClipStatus.failed] clip (same clipId, so the backend
  /// deduplicates).
  Future<void> retry(String clipId);
}
