import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pawsense/ml/coreml_breed_classifier.dart';
import 'package:pawsense/ml/ml_types.dart';

/// Sensor frame 40x20 BGRA: left half red, right half blue, rows padded.
FrameData _frame({required int rotation}) {
  const w = 40;
  const h = 20;
  const stride = w * 4 + 16;
  final bytes = Uint8List(stride * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * stride + x * 4;
      bytes[x < w ~/ 2 ? i + 2 : i] = 255; // BGRA: red at +2, blue at +0
      bytes[i + 3] = 255;
    }
  }
  return FrameData(
    planes: [bytes],
    bytesPerRow: const [stride],
    bytesPerPixel: const [4],
    width: w,
    height: h,
    format: FrameFormat.bgra8888,
    sensorOrientation: rotation,
    timestamp: DateTime(2026),
  );
}

/// Average (r, b) of a decoded JPEG.
(double, double) _meanRedBlue(Uint8List jpeg) {
  final image = img.decodeJpg(jpeg)!;
  expect((image.width, image.height), (coreMlInputSize, coreMlInputSize));
  var r = 0.0;
  var b = 0.0;
  for (final p in image) {
    r += p.r;
    b += p.b;
  }
  final n = image.width * image.height;
  return (r / n, b / n);
}

void main() {
  test('sensorBox maps upright boxes for each rotation', () {
    const box = Rect.fromLTRB(0.1, 0.2, 0.3, 0.6);
    expect(sensorBox(box, 0), box);
    expect(sensorBox(box, 90), const Rect.fromLTRB(0.2, 0.7, 0.6, 0.9));
    expect(sensorBox(box, 180), const Rect.fromLTRB(0.7, 0.4, 0.9, 0.8));
    expect(sensorBox(box, 270), const Rect.fromLTRB(0.4, 0.1, 0.8, 0.3));
  });

  test('cropToJpeg crops the upright box: rotation 90 puts red on top', () {
    // Rotating the frame 90 deg clockwise turns its red left half into the
    // upright image's top half.
    final frame = _frame(rotation: 90);
    final (topR, topB) = _meanRedBlue(
      cropToJpeg(frame, const Rect.fromLTRB(0, 0, 1, 0.5)),
    );
    final (botR, botB) = _meanRedBlue(
      cropToJpeg(frame, const Rect.fromLTRB(0, 0.5, 1, 1)),
    );
    expect(topR, greaterThan(200));
    expect(topB, lessThan(55));
    expect(botB, greaterThan(200));
    expect(botR, lessThan(55));
  });

  test('cropToJpeg without rotation keeps red on the left', () {
    final (r, b) = _meanRedBlue(
      cropToJpeg(_frame(rotation: 0), const Rect.fromLTRB(0, 0, 0.5, 1)),
    );
    expect(r, greaterThan(200));
    expect(b, lessThan(55));
  });

  test('classify sends a JPEG and maps the top-3 reply', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('pawsense/coreml');
    MethodCall? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          sent = call;
          return {
            'predictions': [
              {'label': 'Bengal', 'confidence': 0.8},
              {'label': 'Egyptian_Mau', 'confidence': 0.15},
            ],
            'inferenceMs': 4.2,
          };
        });

    const classifier = CoreMLBreedClassifier();
    final result = await classifier.classify(
      _frame(rotation: 90),
      const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
    );

    expect(classifier.engineName, 'Core ML');
    expect(sent?.method, 'classify');
    final jpeg =
        (sent!.arguments as Map<Object?, Object?>)['jpeg']! as Uint8List;
    expect(jpeg.sublist(0, 2), [0xFF, 0xD8]); // JPEG SOI marker
    expect(result, const [
      BreedPrediction(label: 'Bengal', confidence: 0.8),
      BreedPrediction(label: 'Egyptian_Mau', confidence: 0.15),
    ]);
  });
}
