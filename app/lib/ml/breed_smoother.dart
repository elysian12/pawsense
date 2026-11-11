import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:pawsense/ml/ml_types.dart';

/// Decides when to run the breed classifier and smooths its output so the
/// label on screen does not flicker between frames.
///
/// - [shouldClassify]: classify on the first box, then every [every]th
///   processed frame, or sooner when the box moved a lot (IoU with the last
///   classified box below [iouThreshold], i.e. likely a different pet/view).
/// - [update]: exponential moving average (weight [alpha]) of each label's
///   confidence over the raw top-3 results, bias-corrected so the first
///   results are not artificially low. Returns the smoothed top [topK].
/// - [reset] when the pet leaves the frame.
class BreedSmoother {
  new({
    this.alpha = 0.3,
    this.every = 5,
    this.iouThreshold = 0.5,
    this.topK = 3,
  });

  final double alpha;
  final int every;
  final double iouThreshold;
  final int topK;

  Rect? _lastBox;
  int _sinceLast = 0;
  final _ema = <String, double>{};
  double _weight = 0;

  bool shouldClassify(Rect box) {
    _sinceLast++;
    final last = _lastBox;
    if (last != null && _sinceLast < every && iou(last, box) >= iouThreshold) {
      return false;
    }
    _lastBox = box;
    _sinceLast = 0;
    return true;
  }

  List<BreedPrediction> update(List<BreedPrediction> raw) {
    _ema.updateAll((_, s) => s * (1 - alpha));
    for (final p in raw) {
      _ema[p.label] = (_ema[p.label] ?? 0) + alpha * p.confidence;
    }
    _weight = _weight * (1 - alpha) + alpha;
    _ema.removeWhere((_, s) => s / _weight < 0.01);
    final sorted = _ema.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in sorted.take(topK))
        BreedPrediction(label: e.key, confidence: e.value / _weight),
    ];
  }

  void reset() {
    _lastBox = null;
    _sinceLast = 0;
    _ema.clear();
    _weight = 0;
  }
}

/// Intersection over union of two boxes, 0 when they do not overlap.
double iou(Rect a, Rect b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (w <= 0 || h <= 0) return 0;
  final inter = w * h;
  return inter / (a.width * a.height + b.width * b.height - inter);
}
