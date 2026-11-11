import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pawsense/ml/frame_converter.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:pawsense/ml/tflite_isolate.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Detects cats and dogs in camera frames (EfficientDet-Lite0 on TFLite).
///
/// Implementations run inference off the UI isolate. Callers must not call
/// [detect] again before the previous future completes (the frame scheduler
/// drops frames instead of queueing them).
abstract interface class PetDetector {
  /// Loads the model and warms up the interpreter. Call once before [detect].
  Future<void> load();

  /// Returns cat/dog detections above the score threshold, with boxes in
  /// normalized upright-preview coordinates. `breeds` is empty and
  /// `classificationMs` null in the result.
  Future<DetectionResult> detect(FrameData frame);

  Future<void> dispose();
}

/// EfficientDet-Lite0 (COCO, 90 classes, with metadata) from Kaggle Models
/// `tensorflow/efficientdet/tfLite/lite0-detection-metadata`.
///
/// Tensors as inspected with the TFLite interpreter:
/// - input 0: uint8 `[1, 320, 320, 3]` RGB 0..255 (quantization is inside).
/// - output 0: float32 `[1, 25, 4]` boxes `[ymin, xmin, ymax, xmax]`,
///   normalized to the input image.
/// - output 1: float32 `[1, 25]` class index into `coco_labels.txt`
///   (0 = person, 16 = cat, 17 = dog).
/// - output 2: float32 `[1, 25]` scores, output 3: float32 `[1]` count.
///
/// The input is the whole upright frame stretched to 320x320, so the
/// normalized boxes already are normalized upright-preview coordinates.
class TflitePetDetector implements PetDetector {
  new(this._isolate, {this.scoreThreshold = 0.5, AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const modelAsset = 'assets/models/efficientdet_lite0.tflite';
  static const labelsAsset = 'assets/models/coco_labels.txt';

  final TfliteIsolate _isolate;
  final AssetBundle _bundle;

  /// Minimum detector score to keep a cat/dog box.
  double scoreThreshold;

  int _catClass = -1;
  int _dogClass = -1;
  String _engine = 'tflite';

  @override
  Future<void> load() async {
    final labels = (await _bundle.loadString(labelsAsset))
        .split('\n')
        .map((l) => l.trim())
        .toList();
    _catClass = labels.indexOf('cat');
    _dogClass = labels.indexOf('dog');
    final data = await _bundle.load(modelAsset);
    final info = await _isolate.run(
      LoadModelTask(
        TfliteModel.detector,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
    );
    if (info.inputType != TensorType.uint8 ||
        info.inputShape.join('x') != '1x${_size}x${_size}x3') {
      throw TfliteException(
        'Unexpected detector input ${info.inputType} ${info.inputShape}',
      );
    }
    _engine = 'tflite-${info.delegate}';
  }

  @override
  Future<DetectionResult> detect(FrameData frame) => _isolate.run(
    _DetectTask(
      frame,
      threshold: scoreThreshold,
      catClass: _catClass,
      dogClass: _dogClass,
      engine: _engine,
    ),
  );

  @override
  Future<void> dispose() =>
      _isolate.run(const UnloadModelTask(TfliteModel.detector));
}

const _size = 320;

/// Reused for every frame. Top-level finals are created lazily per isolate,
/// so this is allocated once, inside the inference isolate.
final _input = Uint8List(_size * _size * 3);

final class _DetectTask extends IsolateTask<DetectionResult> {
  const new(
    this.frame, {
    required this.threshold,
    required this.catClass,
    required this.dogClass,
    required this.engine,
  });

  final FrameData frame;
  final double threshold;
  final int catClass;
  final int dogClass;
  final String engine;

  @override
  TfliteModel get model => TfliteModel.detector;

  @override
  DetectionResult run(TfliteWorker worker) {
    final interpreter = worker[TfliteModel.detector];
    convertFrameToRgb(frame, _input, dstWidth: _size, dstHeight: _size);
    interpreter.getInputTensor(0).data = _input;
    final watch = Stopwatch()..start();
    interpreter.invoke();
    final ms = watch.elapsedMicroseconds / 1000;

    final boxes = floatsOf(interpreter.getOutputTensor(0));
    final classes = floatsOf(interpreter.getOutputTensor(1));
    final scores = floatsOf(interpreter.getOutputTensor(2));
    final count = floatsOf(interpreter.getOutputTensor(3))[0].toInt();
    final detections = <Detection>[];
    for (var i = 0; i < count && i < scores.length; i++) {
      final c = classes[i].round();
      final label = c == catClass
          ? PetType.cat
          : (c == dogClass ? PetType.dog : null);
      if (label == null || scores[i] < threshold) continue;
      detections.add(
        Detection(
          label: label,
          score: scores[i],
          box: Rect.fromLTRB(
            boxes[i * 4 + 1].clamp(0, 1),
            boxes[i * 4].clamp(0, 1),
            boxes[i * 4 + 3].clamp(0, 1),
            boxes[i * 4 + 2].clamp(0, 1),
          ),
        ),
      );
    }
    detections.sort((a, b) => b.score.compareTo(a.score));
    return DetectionResult(
      detections: detections,
      detectionMs: ms,
      engine: engine,
    );
  }
}

/// Zero-copy float32 view of an output tensor's native buffer. Valid until
/// the next `invoke()`.
Float32List floatsOf(Tensor tensor) {
  final bytes = tensor.data;
  return bytes.buffer.asFloat32List(
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 4,
  );
}
