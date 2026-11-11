import 'dart:math' as math;
import 'dart:typed_data';

/// Cuts a 16 kHz mono PCM16 little-endian byte stream into YAMNet windows of
/// [windowSize] samples (15,600 = 0.975 s), advancing [hop] samples
/// (7,800 = 50% overlap) between windows.
///
/// Chunks from the recorder have arbitrary sizes and may split a sample
/// across two chunks; the odd byte is carried over.
class AudioWindower {
  new({this.windowSize = 15600, this.hop = 7800})
    : assert(hop > 0 && hop <= windowSize, 'hop must be in 1..windowSize'),
      _buf = Int16List(windowSize);

  final int windowSize;
  final int hop;
  final Int16List _buf;
  int _filled = 0;
  int? _carry;

  /// Feeds raw bytes and returns every window completed by them (copies,
  /// safe to send to another isolate).
  List<Int16List> add(Uint8List pcm) {
    final windows = <Int16List>[];
    var i = 0;
    final carry = _carry;
    if (carry != null && pcm.isNotEmpty) {
      _push(carry | (pcm[0] << 8), windows);
      _carry = null;
      i = 1;
    }
    for (; i + 1 < pcm.length; i += 2) {
      _push(pcm[i] | (pcm[i + 1] << 8), windows);
    }
    if (i < pcm.length) _carry = pcm[i];
    return windows;
  }

  void reset() {
    _filled = 0;
    _carry = null;
  }

  void _push(int sample, List<Int16List> windows) {
    // Int16List keeps the low 16 bits as a signed value: 0xFFFF -> -1.
    _buf[_filled++] = sample;
    if (_filled < windowSize) return;
    windows.add(Int16List.fromList(_buf));
    _buf.setRange(0, windowSize - hop, _buf, hop);
    _filled = windowSize - hop;
  }
}

/// Converts PCM16 samples to float32 in [-1, 1) into [out] (reused, no
/// allocation) and returns the window's RMS level in [0, 1].
double pcm16ToFloat(Int16List samples, Float32List out) {
  var sumSq = 0.0;
  for (var i = 0; i < samples.length; i++) {
    final f = samples[i] / 32768;
    out[i] = f;
    sumSq += f * f;
  }
  return samples.isEmpty ? 0 : math.sqrt(sumSq / samples.length);
}
