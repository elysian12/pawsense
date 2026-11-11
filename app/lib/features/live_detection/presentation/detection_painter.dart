import 'package:flutter/rendering.dart';
import 'package:pawsense/ml/ml_types.dart';

/// Screen rect of a [Detection.box] (normalized, upright preview) when the
/// upright preview of size [preview] is drawn into [canvas] with [fit],
/// centered. With [BoxFit.cover] parts of the box may lie off-canvas.
Rect mapNormalizedBox(
  Rect box, {
  required Size preview,
  required Size canvas,
  BoxFit fit = BoxFit.cover,
}) {
  final sizes = applyBoxFit(fit, preview, canvas);
  // `source` is the visible part of the preview, `destination` its size on
  // screen; their ratio is the scale of the whole image.
  final scale = sizes.destination.width / sizes.source.width;
  final shown = Alignment.center.inscribe(
    preview * scale,
    Offset.zero & canvas,
  );
  return Rect.fromLTRB(
    shown.left + box.left * shown.width,
    shown.top + box.top * shown.height,
    shown.left + box.right * shown.width,
    shown.top + box.bottom * shown.height,
  );
}

/// Box label, e.g. `dog 92% · beagle 71%`. Also the overlay's semantics.
String detectionLabel(Detection d, [BreedPrediction? breed]) => [
  '${d.label.name} ${(d.score * 100).round()}%',
  if (breed != null) '${breed.label} ${(breed.confidence * 100).round()}%',
].join(' · ');

/// Draws detection boxes over a camera preview shown with [fit].
/// The first detection gets the smoothed [breed] label.
class DetectionPainter extends CustomPainter {
  new({
    required this.detections,
    required this.preview,
    this.breed,
    this.fit = BoxFit.cover,
    this.color = const Color(0xFFFFB74D),
  });

  final List<Detection> detections;
  final Size preview;
  final BreedPrediction? breed;
  final BoxFit fit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final fill = Paint()..color = color;
    for (final (i, d) in detections.indexed) {
      final rect = mapNormalizedBox(
        d.box,
        preview: preview,
        canvas: size,
        fit: fit,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        stroke,
      );
      final text = detectionLabel(d, i == 0 ? breed : null);
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Color(0xFF000000),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      // Label above the box, or inside it when the box touches the top.
      final top = rect.top - tp.height - 4 >= 0
          ? rect.top - tp.height - 4
          : rect.top;
      final left = rect.left.clamp(0.0, size.width - tp.width - 8);
      canvas.drawRect(
        Rect.fromLTWH(left, top, tp.width + 8, tp.height + 4),
        fill,
      );
      tp
        ..paint(canvas, Offset(left + 4, top + 2))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(DetectionPainter old) =>
      old.detections != detections ||
      old.breed != breed ||
      old.preview != preview ||
      old.fit != fit;
}
