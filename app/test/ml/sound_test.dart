import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawsense/ml/audio_windower.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:pawsense/ml/sound_classifier.dart';
import 'package:pawsense/ml/sound_debouncer.dart';

Uint8List pcm(Iterable<int> samples) =>
    Int16List.fromList(samples.toList()).buffer.asUint8List();

void main() {
  group('AudioWindower', () {
    test('15600-sample windows with 50% overlap', () {
      final w = AudioWindower();
      expect(w.add(pcm(List.generate(15599, (i) => i % 1000))), isEmpty);
      final first = w.add(pcm([7]));
      expect(first, hasLength(1));
      expect(first.single.length, 15600);
      expect(first.single.last, 7);

      final second = w.add(pcm(List.filled(7800, -3)));
      expect(second, hasLength(1));
      // Second window starts at sample 7800 of the first.
      expect(second.single.first, first.single[7800]);
      expect(second.single.last, -3);
    });

    test('a sample split across chunks survives', () {
      final w = AudioWindower(windowSize: 2, hop: 2);
      final bytes = pcm([-2, 300]);
      expect(w.add(Uint8List.sublistView(bytes, 0, 3)), isEmpty);
      final out = w.add(Uint8List.sublistView(bytes, 3));
      expect(out.single, [-2, 300]);
    });

    test('pcm16ToFloat scales to [-1, 1) and returns RMS', () {
      final out = Float32List(4);
      final rms = pcm16ToFloat(
        Int16List.fromList([-32768, 16384, 0, 32767]),
        out,
      );
      expect(out[0], -1);
      expect(out[1], 0.5);
      expect(rms, closeTo(0.75, 1e-3));
    });
  });

  group('SoundDebouncer', () {
    final t0 = DateTime(2026);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('fires after 2 consecutive windows, then cools down', () {
      final d = SoundDebouncer();
      expect(d.add(SoundKind.dog, 'Bark', 0.8, at(0)), isNull);
      final e = d.add(SoundKind.dog, 'Bark', 0.7, at(487));
      expect(
        e,
        SoundEvent(
          kind: SoundKind.dog,
          label: 'Bark',
          score: 0.7,
          timestamp: at(487),
        ),
      );
      // Still barking inside the 3 s cooldown: silent.
      for (var ms = 975; ms < 3487; ms += 487) {
        expect(d.add(SoundKind.dog, 'Bark', 0.9, at(ms)), isNull);
      }
      expect(d.add(SoundKind.dog, 'Bark', 0.9, at(3600)), isNotNull);
    });

    test('a single loud window or a gap resets the streak', () {
      final d = SoundDebouncer();
      expect(d.add(SoundKind.cat, 'Meow', 0.9, at(0)), isNull);
      expect(d.add(SoundKind.cat, 'Meow', 0.1, at(487)), isNull);
      expect(d.add(SoundKind.cat, 'Meow', 0.9, at(975)), isNull);
      // Kinds are independent.
      expect(d.add(SoundKind.dog, 'Bark', 0.9, at(975)), isNull);
      expect(d.add(SoundKind.cat, 'Meow', 0.9, at(1462)), isNotNull);
    });
  });

  test('class map parses quoted names and has every pet class', () {
    final names = parseYamnetClassMap(
      File('assets/models/yamnet_class_map.csv').readAsStringSync(),
    );
    expect(names, hasLength(521));
    expect(names[0], 'Speech');
    expect(names[1], 'Child speech, kid speaking');
    expect(names.toSet().containsAll({...dogClasses, ...catClasses}), isTrue);
  });
}
