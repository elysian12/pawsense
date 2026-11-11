/// Value types shared by the ML engine layer, blocs and the data layer.
///
/// Everything here is plain data and safe to send across isolates
/// (no handles, no closures).
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:equatable/equatable.dart';

/// Kind of pet. Detections only ever produce [cat] or [dog]; [unknown] is for
/// user-facing entities (clips, insights) where nothing was detected.
enum PetType { cat, dog, unknown }

/// One detected pet in a frame.
class Detection extends Equatable {
  const new({required this.label, required this.score, required this.box})
    : assert(label != PetType.unknown, 'detections are cat or dog');

  /// [PetType.cat] or [PetType.dog].
  final PetType label;

  /// Detector confidence in [0, 1].
  final double score;

  /// Bounding box in NORMALIZED [0, 1] coordinates of the upright preview
  /// image (sensor rotation already applied, origin top-left). Multiply by the
  /// preview widget size to paint it.
  final Rect box;

  @override
  List<Object?> get props => [label, score, box];
}

/// One breed label with its confidence, as returned by a `BreedClassifier`.
class BreedPrediction extends Equatable {
  const new({required this.label, required this.confidence});

  /// A line of `ml/labels/breeds.txt`, e.g. `Abyssinian`, `beagle`.
  final String label;

  /// Softmax probability in [0, 1].
  final double confidence;

  @override
  List<Object?> get props => [label, confidence];
}

/// Result of processing one frame.
///
/// `PetDetector.detect` fills [detections] and [detectionMs]. The live
/// pipeline then runs the breed classifier on the primary detection (only
/// every Nth processed frame) and builds a new result with [breeds],
/// [classificationMs] and [engine] set.
class DetectionResult extends Equatable {
  const new({
    required this.detections,
    required this.detectionMs,
    required this.engine,
    this.breeds = const [],
    this.classificationMs,
  });

  /// Pets above the score threshold, highest score first.
  final List<Detection> detections;

  /// Smoothed top-k breeds for the primary (first) detection; empty when no
  /// classification ran for this frame.
  final List<BreedPrediction> breeds;

  /// Wall-clock inference time of the detector for this frame.
  final double detectionMs;

  /// Wall-clock inference time of the breed classifier, null when it did not
  /// run for this frame.
  final double? classificationMs;

  /// Engine that produced the breed result (`tflite` / `coreml`), or the
  /// detector engine when no classification ran.
  final String engine;

  @override
  List<Object?> get props => [
    detections,
    breeds,
    detectionMs,
    classificationMs,
    engine,
  ];
}

enum FrameFormat { yuv420, bgra8888 }

/// A camera frame copied out of a [CameraImage] so it can be sent to the
/// inference isolate (the plugin reuses CameraImage buffers after the
/// callback returns).
///
/// - [FrameFormat.yuv420] (Android): 3 planes Y, U, V. U/V are subsampled 2x2
///   and may be interleaved: use [bytesPerPixel] (pixel stride) and
///   [bytesPerRow] (row stride) when reading them.
/// - [FrameFormat.bgra8888] (iOS): 1 plane, 4 bytes per pixel, rows may be
///   padded (use [bytesPerRow]).
///
/// [width]/[height] are in sensor orientation; rotate by [sensorOrientation]
/// degrees clockwise to get the upright image.
class FrameData {
  const new({
    required this.planes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.width,
    required this.height,
    required this.format,
    required this.sensorOrientation,
    required this.timestamp,
  });

  /// Copies [image]'s planes. [sensorOrientation] comes from
  /// `CameraDescription.sensorOrientation`.
  ///
  /// Throws [UnsupportedError] for formats other than yuv420 / bgra8888
  /// (request those with `imageFormatGroup` when creating the controller).
  factory fromCameraImage(
    CameraImage image, {
    required int sensorOrientation,
    DateTime? timestamp,
  }) {
    final format = switch (image.format.group) {
      ImageFormatGroup.yuv420 => FrameFormat.yuv420,
      ImageFormatGroup.bgra8888 => FrameFormat.bgra8888,
      final other => throw UnsupportedError('Unsupported frame format $other'),
    };
    return FrameData(
      planes: [for (final p in image.planes) Uint8List.fromList(p.bytes)],
      bytesPerRow: [for (final p in image.planes) p.bytesPerRow],
      bytesPerPixel: [for (final p in image.planes) p.bytesPerPixel],
      width: image.width,
      height: image.height,
      format: format,
      sensorOrientation: sensorOrientation,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  final List<Uint8List> planes;
  final List<int> bytesPerRow;

  /// Pixel stride per plane; null when the platform does not report it.
  final List<int?> bytesPerPixel;
  final int width;
  final int height;
  final FrameFormat format;

  /// 0, 90, 180 or 270.
  final int sensorOrientation;
  final DateTime timestamp;
}

enum SoundKind { dog, cat }

/// A debounced bark/meow event (reported once a class stays above its
/// threshold for 2 consecutive windows, then suppressed for a cooldown).
class SoundEvent extends Equatable {
  const new({
    required this.kind,
    required this.label,
    required this.score,
    required this.timestamp,
  });

  final SoundKind kind;

  /// The YAMNet display name that triggered it, e.g. `Bark`, `Meow`.
  final String label;

  /// YAMNet score in [0, 1].
  final double score;
  final DateTime timestamp;

  @override
  List<Object?> get props => [kind, label, score, timestamp];
}

/// Per-window YAMNet output for the live meter (about 2 per second).
class SoundScores extends Equatable {
  const new({
    required this.topLabel,
    required this.topScore,
    required this.dogScore,
    required this.catScore,
    required this.rms,
  });

  /// Highest-scoring of all 521 YAMNet classes (may be `Speech`, `Silence`...).
  final String topLabel;
  final double topScore;

  /// Max score over the dog classes (Dog, Bark, Yip, Howl, Bow-wow, Growling,
  /// Whimper (dog)).
  final double dogScore;

  /// Max score over the cat classes (Cat, Purr, Meow, Hiss, Caterwaul).
  final double catScore;

  /// Root-mean-square level of the window's samples in [0, 1].
  final double rms;

  @override
  List<Object?> get props => [topLabel, topScore, dogScore, catScore, rms];
}

/// Why the frame scheduler runs at its current rate.
enum SchedulerMode {
  /// Pet in view: as fast as inference allows.
  full,

  /// No pet for N seconds: about 2 fps.
  idle,

  /// Battery below 20%.
  lowBattery,

  /// Device reports a serious/critical thermal state.
  thermal,
}

/// Live statistics from the frame scheduler for the HUD and METRICS.md.
class SchedulerStats extends Equatable {
  const new({
    required this.processedFps,
    required this.droppedFrames,
    required this.avgInferenceMs,
    required this.p95InferenceMs,
    required this.mode,
  });

  static const initial = SchedulerStats(
    processedFps: 0,
    droppedFrames: 0,
    avgInferenceMs: 0,
    p95InferenceMs: 0,
    mode: SchedulerMode.full,
  );

  final double processedFps;

  /// Total frames dropped since start (busy or rate-limited).
  final int droppedFrames;
  final double avgInferenceMs;
  final double p95InferenceMs;
  final SchedulerMode mode;

  @override
  List<Object?> get props => [
    processedFps,
    droppedFrames,
    avgInferenceMs,
    p95InferenceMs,
    mode,
  ];
}
