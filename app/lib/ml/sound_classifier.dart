import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pawsense/ml/audio_windower.dart';
import 'package:pawsense/ml/ml_types.dart';
import 'package:pawsense/ml/pet_detector.dart' show floatsOf;
import 'package:pawsense/ml/sound_debouncer.dart';
import 'package:pawsense/ml/tflite_isolate.dart';
import 'package:record/record.dart';

/// Listens to the microphone (16 kHz mono PCM16) and classifies 0.975 s
/// windows with YAMNet, 50% overlap.
///
/// Both streams are broadcast and stay open across [start]/[stop] cycles;
/// they close on [dispose].
abstract interface class SoundClassifier {
  /// Loads YAMNet and the class map. Call once before [start].
  Future<void> load();

  /// One value per window while started, for the level meter / top label.
  Stream<SoundScores> get scores;

  /// Debounced dog/cat events (2 consecutive windows above threshold, then a
  /// cooldown of a few seconds per kind).
  Stream<SoundEvent> get events;

  /// Starts the microphone. Requires microphone permission.
  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}

/// YAMNet display names that count as a dog / a cat.
const dogClasses = {
  'Dog',
  'Bark',
  'Yip',
  'Howl',
  'Bow-wow',
  'Growling',
  'Whimper (dog)',
};
const catClasses = {'Cat', 'Purr', 'Meow', 'Hiss', 'Caterwaul'};

/// Display names from `yamnet_class_map.csv` (`index,mid,display_name`,
/// names with commas are double-quoted), in model output order.
List<String> parseYamnetClassMap(String csv) => [
  for (final line in csv.split('\n').skip(1))
    if (line.trim().isNotEmpty) _unquote(line.split(',').skip(2).join(',')),
];

String _unquote(String s) {
  final t = s.trim();
  return t.startsWith('"') && t.endsWith('"')
      ? t.substring(1, t.length - 1).replaceAll('""', '"')
      : t;
}

/// YAMNet from Kaggle Models `google/yamnet/tfLite/classification-tflite`.
///
/// Tensors as inspected: input float32 `[15600]` mono 16 kHz waveform in
/// [-1, 1]; output float32 `[1, 521]` class scores (AudioSet ontology,
/// independent sigmoids, not a softmax). Runs on CPU (XNNPACK): the model's
/// spectrogram front end is not GPU-friendly and a window takes only a few ms.
///
/// The microphone stream is cut into windows on the main isolate (cheap
/// bookkeeping); PCM16 -> float conversion and inference run in the TFLite
/// isolate. If YAMNet is still busy when the next window is ready, that
/// window is dropped.
class TfliteSoundClassifier implements SoundClassifier {
  new(
    this._isolate, {
    AudioRecorder Function()? recorder,
    SoundDebouncer? debouncer,
    AssetBundle? bundle,
  }) : _newRecorder = recorder ?? AudioRecorder.new,
       _debouncer = debouncer ?? SoundDebouncer(),
       _bundle = bundle ?? rootBundle;

  static const modelAsset = 'assets/models/yamnet.tflite';
  static const classMapAsset = 'assets/models/yamnet_class_map.csv';

  final TfliteIsolate _isolate;
  final AudioRecorder Function() _newRecorder;
  final SoundDebouncer _debouncer;
  final AssetBundle _bundle;
  final _windower = AudioWindower();
  final _scores = StreamController<SoundScores>.broadcast();
  final _events = StreamController<SoundEvent>.broadcast();

  List<String> _labels = const [];
  List<int> _dogIdx = const [];
  List<int> _catIdx = const [];
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _mic;

  @override
  Stream<SoundScores> get scores => _scores.stream;

  @override
  Stream<SoundEvent> get events => _events.stream;

  @override
  Future<void> load() async {
    _labels = parseYamnetClassMap(await _bundle.loadString(classMapAsset));
    _dogIdx = [
      for (var i = 0; i < _labels.length; i++)
        if (dogClasses.contains(_labels[i])) i,
    ];
    _catIdx = [
      for (var i = 0; i < _labels.length; i++)
        if (catClasses.contains(_labels[i])) i,
    ];
    final data = await _bundle.load(modelAsset);
    final info = await _isolate.run(
      LoadModelTask(
        TfliteModel.yamnet,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        useGpu: false,
      ),
    );
    if (info.outputShapes.first.last != _labels.length) {
      throw TfliteException(
        'YAMNet outputs ${info.outputShapes.first} but the class map has '
        '${_labels.length} names',
      );
    }
  }

  @override
  Future<void> start() async {
    if (_mic != null) return;
    final recorder = _recorder ??= _newRecorder();
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _mic = stream.listen(_onPcm, onError: _scores.addError);
  }

  @override
  Future<void> stop() async {
    await _mic?.cancel();
    _mic = null;
    await _recorder?.stop();
    _windower.reset();
    _debouncer.reset();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder?.dispose();
    await _scores.close();
    await _events.close();
    await _isolate.run(const UnloadModelTask(TfliteModel.yamnet));
  }

  void _onPcm(Uint8List pcm) {
    for (final window in _windower.add(pcm)) {
      if (_isolate.isBusy(TfliteModel.yamnet)) continue; // drop, never queue
      unawaited(_classify(window));
    }
  }

  Future<void> _classify(Int16List window) async {
    try {
      final out = await _isolate.run(_YamnetTask(window, _dogIdx, _catIdx));
      if (_scores.isClosed) return;
      final now = DateTime.now();
      _scores.add(
        SoundScores(
          topLabel: _labels[out.top],
          topScore: out.topScore,
          dogScore: out.dogScore,
          catScore: out.catScore,
          rms: out.rms,
        ),
      );
      for (final event in [
        if (out.dog >= 0)
          _debouncer.add(SoundKind.dog, _labels[out.dog], out.dogScore, now),
        if (out.cat >= 0)
          _debouncer.add(SoundKind.cat, _labels[out.cat], out.catScore, now),
      ]) {
        if (event != null) _events.add(event);
      }
    } on Object catch (e, st) {
      if (!_scores.isClosed) _scores.addError(e, st);
    }
  }
}

/// Reused for every window; allocated once, inside the inference isolate.
final _waveform = Float32List(15600);

final class _YamnetTask extends IsolateTask<_YamnetOut> {
  const new(this.window, this.dogIdx, this.catIdx);

  final Int16List window;
  final List<int> dogIdx;
  final List<int> catIdx;

  @override
  TfliteModel get model => TfliteModel.yamnet;

  @override
  _YamnetOut run(TfliteWorker worker) {
    final interpreter = worker[TfliteModel.yamnet];
    final rms = pcm16ToFloat(window, _waveform);
    interpreter.getInputTensor(0).data = _waveform.buffer.asUint8List();
    interpreter.invoke();
    final s = floatsOf(interpreter.getOutputTensor(0));
    var top = 0;
    for (var i = 1; i < s.length; i++) {
      if (s[i] > s[top]) top = i;
    }
    int best(List<int> idx) =>
        idx.fold(-1, (b, i) => b < 0 || s[i] > s[b] ? i : b);
    final dog = best(dogIdx);
    final cat = best(catIdx);
    return _YamnetOut(
      top: top,
      topScore: s[top],
      dog: dog,
      dogScore: dog < 0 ? 0 : s[dog],
      cat: cat,
      catScore: cat < 0 ? 0 : s[cat],
      rms: rms,
    );
  }
}

class _YamnetOut {
  const new({
    required this.top,
    required this.topScore,
    required this.dog,
    required this.dogScore,
    required this.cat,
    required this.catScore,
    required this.rms,
  });

  final int top;
  final double topScore;
  final int dog;
  final double dogScore;
  final int cat;
  final double catScore;
  final double rms;
}
