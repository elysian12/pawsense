import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/features/live_detection/presentation/detection_painter.dart';
import 'package:pawsense/ml/ml_types.dart';

void main() {
  const box = Rect.fromLTRB(0.25, 0.25, 0.75, 0.75);

  group('mapNormalizedBox', () {
    test('same aspect: plain scale', () {
      final r = mapNormalizedBox(
        box,
        preview: const Size(480, 640),
        canvas: const Size(300, 400),
      );
      expect(r, const Rect.fromLTRB(75, 100, 225, 300));
    });

    test('cover crops the sides of a wider preview', () {
      // 3:4 preview on a 9:19.5-ish phone: scaled to 800 tall -> 600 wide,
      // centered -> 150 px cut off on each side of a 300 px canvas.
      final r = mapNormalizedBox(
        box,
        preview: const Size(480, 640),
        canvas: const Size(300, 800),
      );
      expect(r, const Rect.fromLTRB(0, 200, 300, 600));
    });

    test('contain letterboxes', () {
      final r = mapNormalizedBox(
        box,
        preview: const Size(480, 640),
        canvas: const Size(300, 800),
        fit: BoxFit.contain,
      );
      // 300 wide -> 400 tall, centered: 200 px bars top and bottom.
      expect(r, const Rect.fromLTRB(75, 300, 225, 500));
    });
  });

  testWidgets('paints one rounded box per detection', (tester) async {
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 300,
          height: 400,
          child: CustomPaint(
            key: const Key('overlay'),
            painter: DetectionPainter(
              preview: const Size(480, 640),
              detections: const [
                Detection(label: PetType.dog, score: 0.9, box: box),
              ],
              breed: const BreedPrediction(label: 'beagle', confidence: 0.8),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const Key('overlay')),
      paints..rrect(
        rrect: RRect.fromRectAndRadius(
          const Rect.fromLTRB(75, 100, 225, 300),
          const Radius.circular(8),
        ),
      ),
    );
  });
}
