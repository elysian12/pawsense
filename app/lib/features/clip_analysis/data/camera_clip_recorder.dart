import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart'
    show FcVideoThumbnailTime, FcVideoThumbnailTimeUnit;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pawsense/features/clip_analysis/domain/clip_recorder.dart';

/// Records with `camera` and extracts keyframes from the finished file.
///
/// Keyframe method (spec Phase 5): `fc_native_video_thumbnail` decodes the
/// frame at each timestamp natively (AVAssetImageGenerator with zero time
/// tolerance on iOS; MediaMetadataRetriever.getScaledFrameAtTime with
/// OPTION_CLOSEST_SYNC on Android, so Android frames snap to the nearest
/// sync frame, usually within ~1 s). Output: JPEG, longest side 768 px,
/// quality 80, in the documents directory so queued clips survive restarts.
///
/// Fallback NOT implemented: sampling the camera image stream every 2 s while
/// recording (`startVideoRecording(onAvailable:)`) and JPEG-encoding the
/// frames. Switch to it if a device returns no thumbnail (we throw then).
///
/// The camera is opened in [initialize] and released in [dispose], once per
/// recording, so it does not stay locked while the Clips tab is idle.
class CameraClipRecorder implements ClipRecorder {
  new({FcNativeVideoThumbnail? thumbnails})
    : _thumbnails = thumbnails ?? FcNativeVideoThumbnail();

  final FcNativeVideoThumbnail _thumbnails;

  /// The open camera, for a preview while recording; null when released.
  final controller = ValueNotifier<CameraController?>(null);
  String? _lastVideo;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('No camera available');
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    // 720p: the smallest preset whose long side exceeds the 768 px keyframes.
    final c = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await c.initialize();
    controller.value = c;
  }

  @override
  Future<String> recordClip(
    Duration length, {
    void Function(Duration remaining)? onTick,
  }) async {
    final c = controller.value;
    if (c == null) throw StateError('initialize() first');
    const tick = Duration(seconds: 1);
    await c.startVideoRecording();
    for (var left = length; left > Duration.zero; left -= tick) {
      onTick?.call(left);
      await Future<void>.delayed(left < tick ? left : tick);
    }
    final file = await c.stopVideoRecording();
    return _lastVideo = file.path;
  }

  @override
  Future<List<String>> extractKeyframes(
    String videoPath,
    List<Duration> at,
  ) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = await Directory(p.join(docs.path, 'keyframes'))
        .create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final (i, t) in at.indexed)
        await _extract(videoPath, p.join(dir.path, '${stamp}_$i.jpg'), t),
    ];
  }

  Future<String> _extract(String video, String dest, Duration at) async {
    final ok = await _thumbnails.saveThumbnailToFile(
      srcFile: video,
      destFile: dest,
      width: 768,
      height: 768,
      format: 'jpeg',
      quality: 80,
      at: FcVideoThumbnailTime(
        at.inMilliseconds,
        FcVideoThumbnailTimeUnit.milliseconds,
      ),
    );
    if (!ok) throw StateError('No keyframe at $at');
    return dest;
  }

  /// Releases the camera and deletes the recorded video (only the keyframes
  /// are uploaded).
  @override
  Future<void> dispose() async {
    final c = controller.value;
    controller.value = null;
    await c?.dispose();
    final video = _lastVideo;
    _lastVideo = null;
    if (video != null && File(video).existsSync()) await File(video).delete();
  }
}
