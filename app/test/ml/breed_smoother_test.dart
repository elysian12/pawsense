import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/ml/breed_classifier.dart';
import 'package:pawsense/ml/breed_smoother.dart';
import 'package:pawsense/ml/ml_types.dart';

void main() {
  List<BreedPrediction> raw(Map<String, double> m) => [
    for (final e in m.entries)
      BreedPrediction(label: e.key, confidence: e.value),
  ];

  test('one flickering frame does not flip the label', () {
    final s = BreedSmoother();
    expect(
      s.update(raw({'beagle': 0.8, 'pug': 0.1})).first,
      const BreedPrediction(label: 'beagle', confidence: 0.8),
    );
    s
      ..update(raw({'beagle': 0.8, 'pug': 0.1}))
      ..update(raw({'beagle': 0.8, 'pug': 0.1}));
    final flicker = s.update(raw({'pug': 0.9, 'beagle': 0.05}));
    expect(flicker.first.label, 'beagle');
    expect(flicker.length, 2);
  });

  test('a sustained change does flip the label', () {
    final s = BreedSmoother()..update(raw({'beagle': 0.8}));
    for (var i = 0; i < 5; i++) {
      s.update(raw({'pug': 0.9}));
    }
    expect(s.update(raw({'pug': 0.9})).first.label, 'pug');
  });

  test('classifies every Nth frame or when the box jumps', () {
    final s = BreedSmoother(every: 3);
    const a = Rect.fromLTRB(0.1, 0.1, 0.5, 0.5);
    const near = Rect.fromLTRB(0.12, 0.1, 0.52, 0.5);
    const far = Rect.fromLTRB(0.6, 0.6, 0.9, 0.9);
    expect(s.shouldClassify(a), isTrue);
    expect(s.shouldClassify(near), isFalse);
    expect(s.shouldClassify(near), isFalse);
    expect(s.shouldClassify(near), isTrue); // 3rd frame since
    expect(s.shouldClassify(far), isTrue); // IoU 0
    s.reset();
    expect(s.shouldClassify(far), isTrue);
  });

  test('iou', () {
    const a = Rect.fromLTRB(0, 0, 2, 2);
    expect(iou(a, a), 1);
    expect(iou(a, const Rect.fromLTRB(1, 0, 3, 2)), closeTo(1 / 3, 1e-9));
    expect(iou(a, const Rect.fromLTRB(3, 3, 4, 4)), 0);
  });

  test('topK picks the largest values in order', () {
    expect(topK([0.1, 0.5, 0.2, 0.9, 0.3], 3), [(3, 0.9), (1, 0.5), (4, 0.3)]);
    expect(topK([0.4], 3), [(0, 0.4)]);
  });
}
