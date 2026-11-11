import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:pawsense/ml/ml_types.dart';

const _fullFrame = Rect.fromLTRB(0, 0, 1, 1);

/// Writes [frame] into [out] as packed RGB (3 bytes per pixel, row-major,
/// top-left origin) of size [dstWidth] x [dstHeight], upright.
///
/// [crop] selects a region in normalized upright coordinates (the same space
/// as `Detection.box`); it is clamped to the frame. The region is stretched to
/// fill the output, so a detector box on the output maps straight back to the
/// upright frame.
///
/// One fused pass per OUTPUT pixel: map it into the upright image, undo the
/// sensor rotation to find the source pixel, and convert only that pixel to
/// RGB. There is no full-size RGB intermediate and nothing is allocated, so
/// the same [out] buffer is reused for every frame. Runs inside the TFLite
/// isolate.
///
/// The `image` package is not used here: its YUV/rotate/resize helpers
/// allocate a new full-size image per step, which this hot path avoids.
// ponytail: nearest-neighbour sampling, fine for 640x480 -> 320 downscales;
// switch to bilinear if small-object recall suffers. Front-camera mirroring is
// not undone (pets are filmed with the back camera).
void convertFrameToRgb(
  FrameData frame,
  Uint8List out, {
  required int dstWidth,
  required int dstHeight,
  Rect crop = _fullFrame,
}) {
  if (out.length < dstWidth * dstHeight * 3) {
    throw ArgumentError.value(out.length, 'out', 'too small');
  }
  final w = frame.width;
  final h = frame.height;
  final rotation = frame.sensorOrientation % 360;
  final left = crop.left.clamp(0.0, 1.0);
  final top = crop.top.clamp(0.0, 1.0);
  final cropW = crop.right.clamp(0.0, 1.0) - left;
  final cropH = crop.bottom.clamp(0.0, 1.0) - top;

  final p0 = frame.planes[0];
  final row0 = frame.bytesPerRow[0];
  final yuv = frame.format == FrameFormat.yuv420;
  final p1 = yuv ? frame.planes[1] : p0;
  final p2 = yuv ? frame.planes[2] : p0;
  final pix0 = frame.bytesPerPixel[0] ?? 1;
  final row1 = yuv ? frame.bytesPerRow[1] : 0;
  final pix1 = yuv ? frame.bytesPerPixel[1] ?? 1 : 0;
  final row2 = yuv ? frame.bytesPerRow[2] : 0;
  final pix2 = yuv ? frame.bytesPerPixel[2] ?? 1 : 0;

  var o = 0;
  for (var y = 0; y < dstHeight; y++) {
    // Normalized upright coordinates of the output pixel centre.
    final v = top + (y + 0.5) / dstHeight * cropH;
    for (var x = 0; x < dstWidth; x++) {
      final u = left + (x + 0.5) / dstWidth * cropW;

      // Upright (u, v) -> sensor (nx, ny). The upright image is the sensor
      // image rotated clockwise by `rotation`.
      double nx;
      double ny;
      switch (rotation) {
        case 90:
          nx = v;
          ny = 1 - u;
        case 180:
          nx = 1 - u;
          ny = 1 - v;
        case 270:
          nx = 1 - v;
          ny = u;
        default:
          nx = u;
          ny = v;
      }
      var sx = (nx * w).toInt();
      var sy = (ny * h).toInt();
      if (sx >= w) sx = w - 1;
      if (sy >= h) sy = h - 1;

      if (yuv) {
        // BT.601 YUV -> RGB in 10-bit fixed point. U/V are subsampled 2x2 and
        // may be interleaved (pixel stride 2), hence the strides.
        final yy = p0[sy * row0 + sx * pix0];
        final cx = sx >> 1;
        final cy = sy >> 1;
        final uu = p1[cy * row1 + cx * pix1] - 128;
        final vv = p2[cy * row2 + cx * pix2] - 128;
        out[o] = _clamp(yy + ((1436 * vv) >> 10));
        out[o + 1] = _clamp(yy - ((352 * uu + 731 * vv) >> 10));
        out[o + 2] = _clamp(yy + ((1815 * uu) >> 10));
      } else {
        final i = sy * row0 + sx * 4; // BGRA
        out[o] = p0[i + 2];
        out[o + 1] = p0[i + 1];
        out[o + 2] = p0[i];
      }
      o += 3;
    }
  }
}

int _clamp(int c) => c < 0 ? 0 : (c > 255 ? 255 : c);
