import 'package:equatable/equatable.dart';
import 'package:pawsense/ml/ml_types.dart';

/// Lifecycle of a clip. [wireName] is the snake_case form used in docs and by
/// the backend's WS `status` message.
enum ClipStatus {
  /// Keyframes saved locally, waiting for network (the "queued" badge).
  pendingUpload('pending_upload'),
  uploading('uploading'),

  /// Uploaded (has a jobId); insight is streaming over the WebSocket.
  analyzing('analyzing'),
  analyzed('analyzed'),

  /// Terminal error ([Clip.error] says why). `ClipRepository.retry` re-queues.
  failed('failed');

  new(this.wireName);

  final String wireName;
}

/// A recorded clip. Written to Drift BEFORE any network call.
class Clip extends Equatable {
  const new({
    required this.id,
    required this.status,
    required this.framePaths,
    required this.createdAt,
    required this.petType,
    this.jobId,
    this.error,
    this.breedHint,
  });

  /// Client-generated UUID v4; the backend's idempotency key (`clipId`).
  final String id;
  final ClipStatus status;

  /// Absolute paths of the 5 keyframe JPEGs (768px, quality ~80).
  final List<String> framePaths;

  /// Backend job id, set once the upload returned 202.
  final String? jobId;

  /// Human-readable reason when [status] is [ClipStatus.failed].
  final String? error;
  final DateTime createdAt;
  final PetType petType;

  /// Breed label from live detection at record time, if any.
  final String? breedHint;

  @override
  List<Object?> get props => [
    id,
    status,
    framePaths,
    jobId,
    error,
    createdAt,
    petType,
    breedHint,
  ];
}
