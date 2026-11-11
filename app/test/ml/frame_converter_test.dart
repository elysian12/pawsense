import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/ml/frame_converter.dart';
import 'package:pawsense/ml/ml_types.dart';

/// 3x2 BGRA frame; pixel (x, y) has R = 10*x + y + 1, G = 100, B = 200.
FrameData bgra({int rotation = 0, int rowPadding = 0}) {
  const w = 3;
  const h = 2;
  const row = w * 4;
  final bytes = Uint8List((row + rowPadding) * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * (row + rowPadding) + x * 4;
      bytes
        ..[i] = 200
        ..[i + 1] = 100
        ..[i + 2] = 10 * x + y + 1
        ..[i + 3] = 255;
    }
  }
  return FrameData(
    planes: [bytes],
    bytesPerRow: [row + rowPadding],
    bytesPerPixel: [4],
    width: w,
    height: h,
    format: FrameFormat.bgra8888,
    sensorOrientation: rotation,
    timestamp: DateTime(2026),
  );
}

/// Red channel of the output, as rows.
List<List<int>> reds(Uint8List rgb, int w, int h) => [
  for (var y = 0; y < h; y++)
    [for (var x = 0; x < w; x++) rgb[(y * w + x) * 3]],
];

void main() {
  test('BGRA -> RGB, row padding ignored', () {
    final out = Uint8List(3 * 2 * 3);
    convertFrameToRgb(bgra(rowPadding: 8), out, dstWidth: 3, dstHeight: 2);
    expect(out.sublist(0, 3), [1, 100, 200]);
    expect(reds(out, 3, 2), [
      [1, 11, 21],
      [2, 12, 22],
    ]);
  });

  test('rotation 90 / 180 / 270 give the upright image', () {
    final out = Uint8List(2 * 3 * 3);
    // Sensor 3x2 rotated 90 degrees clockwise is 2 wide, 3 tall.
    convertFrameToRgb(bgra(rotation: 90), out, dstWidth: 2, dstHeight: 3);
    expect(reds(out, 2, 3), [
      [2, 1],
      [12, 11],
      [22, 21],
    ]);
    convertFrameToRgb(bgra(rotation: 270), out, dstWidth: 2, dstHeight: 3);
    expect(reds(out, 2, 3), [
      [21, 22],
      [11, 12],
      [1, 2],
    ]);
    final flipped = Uint8List(3 * 2 * 3);
    convertFrameToRgb(bgra(rotation: 180), flipped, dstWidth: 3, dstHeight: 2);
    expect(reds(flipped, 3, 2), [
      [22, 12, 2],
      [21, 11, 1],
    ]);
  });

  test('crop selects a normalized upright region and resizes it', () {
    final out = Uint8List(2 * 2 * 3);
    convertFrameToRgb(
      bgra(),
      out,
      dstWidth: 2,
      dstHeight: 2,
      crop: const Rect.fromLTRB(2 / 3, 0, 1, 1),
    );
    expect(reds(out, 2, 2), [
      [21, 21],
      [22, 22],
    ]);
  });

  test('YUV420 with interleaved chroma (pixel stride 2) -> RGB', () {
    // 2x2 image, one chroma sample. Y = 76, U = 85, V = 255 is ~pure red.
    final y = Uint8List.fromList([76, 76, 76, 76]);
    final uv = Uint8List.fromList([85, 255]); // U then V interleaved
    final frame = FrameData(
      planes: [y, uv, Uint8List.sublistView(uv, 1)],
      bytesPerRow: [2, 2, 2],
      bytesPerPixel: [1, 2, 2],
      width: 2,
      height: 2,
      format: FrameFormat.yuv420,
      sensorOrientation: 0,
      timestamp: DateTime(2026),
    );
    final out = Uint8List(2 * 2 * 3);
    convertFrameToRgb(frame, out, dstWidth: 2, dstHeight: 2);
    expect(out.sublist(0, 3), [254, 1, 0]);

    final grey = FrameData(
      planes: [
        Uint8List.fromList([128, 128, 128, 128]),
        Uint8List.fromList([128]),
        Uint8List.fromList([128]),
      ],
      bytesPerRow: [2, 1, 1],
      bytesPerPixel: [1, 1, 1],
      width: 2,
      height: 2,
      format: FrameFormat.yuv420,
      sensorOrientation: 0,
      timestamp: DateTime(2026),
    );
    convertFrameToRgb(grey, out, dstWidth: 2, dstHeight: 2);
    expect(out, List.filled(12, 128));
  });
}
