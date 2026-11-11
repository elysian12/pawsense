import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pawsense/ml/frame_converter.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:pawsense/ml/pet_detector.dart' show floatsOf;
import 'package:pawsense/ml/tflite_isolate.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Which implementation backs [BreedClassifier]. [coreml] exists on iOS only
/// and is chosen in Settings.
enum BreedEngine { tflite, coreml }

/// Classifies the pet inside a box into one of the 37 Oxford-IIIT Pet breeds
/// (labels in `ml/labels/breeds.txt`, model output order).
abstract interface class BreedClassifier {
  /// `tflite` or `coreml`, shown in the HUD.
  String get engineName;

  Future<void> load();

  /// Crops [frame] to [normalizedBox] (normalized upright-preview coordinates,
  /// as in Detection.box), resizes to 224x224 and returns the top-3 breeds,
  /// highest confidence first. Raw per-frame output: smoothing over frames is
  /// the caller's job.
  Future<List<BreedPrediction>> classify(FrameData frame, Rect normalizedBox);

  Future<void> dispose();
}

/// The breed model or its labels are missing or do not match. Thrown by
/// `load()` so the UI can show the message and keep detection running.
class ModelUnavailableException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}

/// TFLite breed classifier: `assets/models/breeds.tflite` +
/// `assets/models/breeds.txt` (one label per line, output-index order),
/// both produced by `ml/export_tflite.py`.
///
/// Expected tensors: input `[1, 224, 224, 3]` RGB, float32 in 0..255 (any
/// normalization is baked into the model) or uint8; output float32
/// `[1, 37]` probabilities.
class TfliteBreedClassifier implements BreedClassifier {
  new(this._isolate, {AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const modelAsset = 'assets/models/breeds.tflite';
  static const labelsAsset = 'assets/models/breeds.txt';

  final TfliteIsolate _isolate;
  final AssetBundle _bundle;
  List<String>? _labels;

  @override
  String get engineName => 'tflite';

  @override
  Future<void> load() async {
    final ByteData data;
    final List<String> labels;
    try {
      data = await _bundle.load(modelAsset);
      labels = (await _bundle.loadString(labelsAsset))
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } on Object {
      throw const ModelUnavailableException(
        'Breed model not bundled: add assets/models/breeds.tflite and '
        'breeds.txt (see ml/README.md). Detection still works.',
      );
    }
    final info = await _isolate.run(
      LoadModelTask(
        TfliteModel.breeds,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
    );
    final classes = info.outputShapes.first.last;
    if (info.inputShape.join('x') != '1x${_size}x${_size}x3' ||
        (info.inputType != TensorType.float32 &&
            info.inputType != TensorType.uint8) ||
        classes != labels.length) {
      throw ModelUnavailableException(
        'breeds.tflite does not match: input ${info.inputType} '
        '${info.inputShape}, $classes outputs, ${labels.length} labels.',
      );
    }
    _labels = labels;
  }

  @override
  Future<List<BreedPrediction>> classify(
    FrameData frame,
    Rect normalizedBox,
  ) async {
    final labels = _labels;
    if (labels == null) {
      throw const ModelUnavailableException('Breed model is not loaded');
    }
    final top = await _isolate.run(_ClassifyTask(frame, normalizedBox));
    return [
      for (final (i, p) in top)
        BreedPrediction(label: labels[i], confidence: p),
    ];
  }

  @override
  Future<void> dispose() async {
    _labels = null;
    await _isolate.run(const UnloadModelTask(TfliteModel.breeds));
  }
}

const _size = 224;

// Reused for every crop; allocated once, inside the inference isolate.
final _rgb = Uint8List(_size * _size * 3);
final _floats = Float32List(_size * _size * 3);

final class _ClassifyTask extends IsolateTask<List<(int, double)>> {
  const new(this.frame, this.box);

  final FrameData frame;
  final Rect box;

  @override
  TfliteModel get model => TfliteModel.breeds;

  @override
  List<(int, double)> run(TfliteWorker worker) {
    final interpreter = worker[TfliteModel.breeds];
    // 10% margin: the training images show the whole pet with some context.
    final crop = box.inflate(
      0.1 * (box.width > box.height ? box.width : box.height),
    );
    convertFrameToRgb(
      frame,
      _rgb,
      dstWidth: _size,
      dstHeight: _size,
      crop: crop,
    );
    final input = interpreter.getInputTensor(0);
    if (input.type == TensorType.uint8) {
      input.data = _rgb;
    } else {
      for (var i = 0; i < _rgb.length; i++) {
        _floats[i] = _rgb[i].toDouble();
      }
      input.data = _floats.buffer.asUint8List();
    }
    interpreter.invoke();
    final probs = floatsOf(interpreter.getOutputTensor(0));
    return topK(probs, 3);
  }
}

/// Indices and values of the [k] largest entries of [values], largest first.
List<(int, double)> topK(List<double> values, int k) {
  final top = <(int, double)>[];
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (top.length == k && v <= top.last.$2) continue;
    var at = top.length;
    while (at > 0 && top[at - 1].$2 < v) {
      at--;
    }
    top.insert(at, (i, v));
    if (top.length > k) top.removeLast();
  }
  return top;
}
