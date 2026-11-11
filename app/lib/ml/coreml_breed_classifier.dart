import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pawsense/core/log.dart';
import 'package:pawsense/ml/breed_classifier.dart';
import 'package:pawsense/ml/ml_types.dart';

/// iOS-only [BreedClassifier] backed by Core ML through the `pawsense/coreml`
/// method channel (`ios/Runner/CoreMLBreedClassifier.swift`).
///
/// Dart crops the pet box out of the BGRA frame, rotates it upright and
/// encodes a 224x224 JPEG off the UI isolate; Swift runs the model with
/// Vision and returns the top 3.
class CoreMLBreedClassifier implements BreedClassifier {
  const new();

  static const _channel = MethodChannel('pawsense/coreml');

  @override
  String get engineName => 'Core ML';

  @override
  Future<void> load() => _channel.invokeMethod<void>('load');

  @override
  Future<List<BreedPrediction>> classify(
    FrameData frame,
    Rect normalizedBox,
  ) async {
    // ponytail: Isolate.run per call (~ms spawn cost) is fine because the
    // live pipeline classifies only every Nth frame; move into the long-lived
    // TFLite isolate if it ever runs per frame.
    final jpeg = await Isolate.run(() => cropToJpeg(frame, normalizedBox));
    final reply = await _channel.invokeMapMethod<String, Object?>('classify', {
      'jpeg': jpeg,
    });
    final ms = reply?['inferenceMs'] as double?;
    log('Core ML inference ${ms?.toStringAsFixed(1)} ms', name: 'coreml');
    return [
      for (final p in reply?['predictions'] as List<Object?>? ?? const [])
        if (p case {'label': final String label, 'confidence': final num c})
          BreedPrediction(label: label, confidence: c.toDouble()),
    ];
  }

  @override
  Future<void> dispose() => _channel.invokeMethod<void>('dispose');
}

/// Side of the square JPEG sent to Core ML (the model's input size).
const coreMlInputSize = 224;

/// Crops [uprightBox] (normalized, upright-preview coordinates) out of a
/// BGRA [frame], rotates the crop upright and returns it as a 224x224 JPEG.
///
/// Crops in sensor coordinates first so only the box is rotated and resized.
@visibleForTesting
Uint8List cropToJpeg(FrameData frame, Rect uprightBox) {
  if (frame.format != FrameFormat.bgra8888) {
    throw UnsupportedError('Core ML path expects bgra8888 frames (iOS)');
  }
  final rotation = frame.sensorOrientation % 360;
  final b = sensorBox(uprightBox, rotation);
  final x0 = (b.left * frame.width).floor().clamp(0, frame.width - 1);
  final y0 = (b.top * frame.height).floor().clamp(0, frame.height - 1);
  final x1 = (b.right * frame.width).ceil().clamp(x0 + 1, frame.width);
  final y1 = (b.bottom * frame.height).ceil().clamp(y0 + 1, frame.height);

  final full = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: frame.planes.first.buffer,
    bytesOffset: frame.planes.first.offsetInBytes,
    rowStride: frame.bytesPerRow.first,
    numChannels: 4,
    order: img.ChannelOrder.bgra,
  );
  final crop = img.copyCrop(
    full,
    x: x0,
    y: y0,
    width: x1 - x0,
    height: y1 - y0,
  );
  final upright = rotation == 0 ? crop : img.copyRotate(crop, angle: rotation);
  final resized = img.copyResize(
    upright,
    width: coreMlInputSize,
    height: coreMlInputSize,
    interpolation: img.Interpolation.linear,
  );
  return img.encodeJpg(resized, quality: 90);
}

/// Maps a normalized box in the upright image to the sensor image, where the
/// upright image is the sensor image rotated [rotation] degrees clockwise.
@visibleForTesting
Rect sensorBox(Rect upright, int rotation) {
  final Rect(:left, :top, :right, :bottom) = upright;
  return switch (rotation) {
    90 => Rect.fromLTRB(top, 1 - right, bottom, 1 - left),
    180 => Rect.fromLTRB(1 - right, 1 - bottom, 1 - left, 1 - top),
    270 => Rect.fromLTRB(1 - bottom, left, 1 - top, right),
    _ => upright,
  };
}
