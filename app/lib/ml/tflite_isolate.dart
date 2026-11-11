import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// The models the inference isolate can hold, one interpreter each.
enum TfliteModel { detector, breeds, yamnet }

/// A unit of work that runs INSIDE the inference isolate.
///
/// Tasks are the typed request messages: the main isolate sends the task
/// object, the isolate calls [run] and sends back its result of type [R].
/// Fields must be sendable (typed data, numbers, strings, enums, `Rect`).
abstract class IsolateTask<R> {
  const new();

  TfliteModel get model;

  R run(TfliteWorker worker);
}

class TfliteException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'TfliteException: $message';
}

/// What [LoadModelTask] found out about a model.
class ModelInfo {
  const new({
    required this.delegate,
    required this.inputShape,
    required this.inputType,
    required this.outputShapes,
  });

  /// `gpu` (Android), `metal` (iOS) or `cpu` (XNNPACK-accelerated).
  final String delegate;
  final List<int> inputShape;
  final TensorType inputType;
  final List<List<int>> outputShapes;
}

/// Creates the interpreter for [model] from flatbuffer [bytes] (read with
/// rootBundle on the main isolate: asset loading needs platform channels,
/// the inference isolate has none) and runs one warm-up inference.
final class LoadModelTask extends IsolateTask<ModelInfo> {
  const new(this.model, this.bytes, {this.useGpu = true});

  @override
  final TfliteModel model;
  final Uint8List bytes;
  final bool useGpu;

  @override
  ModelInfo run(TfliteWorker worker) =>
      worker.load(model, bytes, useGpu: useGpu);
}

final class UnloadModelTask extends IsolateTask<void> {
  const new(this.model);

  @override
  final TfliteModel model;

  @override
  void run(TfliteWorker worker) => worker.unload(model);
}

/// Isolate-side state: the interpreters and their delegates.
class TfliteWorker {
  final _interpreters = <TfliteModel, Interpreter>{};
  final _delegates = <TfliteModel, Delegate>{};

  Interpreter operator [](TfliteModel model) =>
      _interpreters[model] ??
      (throw StateError('${model.name} model is not loaded'));

  /// Tries the GPU delegate (Android) / Metal delegate (iOS) first, then
  /// CPU, keeping the first that loads AND runs. The CPU path already uses
  /// XNNPACK: the TFLite runtime applies it by default. An explicit
  /// `XNNPackDelegate` segfaults natively in tflite_flutter 0.12.1 on Android
  /// (an uncatchable crash), so it is deliberately not a candidate.
  ModelInfo load(TfliteModel model, Uint8List bytes, {required bool useGpu}) {
    unload(model);
    final candidates = <(String, Delegate? Function())>[
      if (useGpu && Platform.isAndroid) ('gpu', GpuDelegateV2.new),
      if (useGpu && Platform.isIOS) ('metal', GpuDelegate.new),
      ('cpu', () => null),
    ];
    final errors = <String>[];
    for (final (name, makeDelegate) in candidates) {
      Delegate? delegate;
      Interpreter? interpreter;
      try {
        delegate = makeDelegate();
        final options = InterpreterOptions()..threads = 2;
        if (delegate != null) options.addDelegate(delegate);
        interpreter = Interpreter.fromBuffer(bytes, options: options)
          ..allocateTensors()
          ..invoke(); // warm-up; also surfaces delegate failures now
        _interpreters[model] = interpreter;
        if (delegate != null) _delegates[model] = delegate;
        return ModelInfo(
          delegate: name,
          inputShape: interpreter.getInputTensor(0).shape,
          inputType: interpreter.getInputTensor(0).type,
          outputShapes: [
            for (final t in interpreter.getOutputTensors()) t.shape,
          ],
        );
      } on Object catch (e) {
        interpreter?.close();
        delegate?.delete();
        errors.add('$name: $e');
      }
    }
    throw TfliteException('Could not load ${model.name}: ${errors.join('; ')}');
  }

  void unload(TfliteModel model) {
    _interpreters.remove(model)?.close();
    _delegates.remove(model)?.delete();
  }

  void close() => TfliteModel.values.forEach(unload);
}

/// Main-isolate handle to ONE long-lived inference isolate that owns every
/// TFLite interpreter.
///
/// Why not `compute()` per frame: spawning an isolate costs milliseconds, and
/// each spawn would have to rebuild the interpreter (model parse, delegate
/// compile, tensor allocation, warm-up) and copy the model again. Here the
/// interpreters stay warm and only frames/results cross the boundary.
///
/// The isolate is spawned on the first [run] (in practice the first model
/// `load()`), so building the DI graph in tests spawns nothing.
///
/// At most ONE request per model is in flight: [run] throws [StateError] when
/// [isBusy]; callers drop work instead of queueing. Every [traceEvery]th
/// request per model is wrapped in a Sentry performance transaction
/// (`ml.inference`), so tracing costs nothing on most frames.
class TfliteIsolate {
  new({this.traceEvery = 30});

  final int traceEvery;

  final _busy = <TfliteModel>{};
  final _runs = <TfliteModel, int>{};
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  Isolate? _isolate;
  ReceivePort? _inbox;
  late final Future<SendPort> _port = _spawn();

  bool isBusy(TfliteModel model) => _busy.contains(model);

  Future<R> run<R>(IsolateTask<R> task) async {
    final model = task.model;
    // Unloading is queued behind any in-flight request (the isolate handles
    // messages in order), so it skips the one-in-flight rule.
    final exclusive = task is! UnloadModelTask;
    if (exclusive && !_busy.add(model)) {
      throw StateError('${model.name} already has a request in flight');
    }
    final n = _runs[model] = (_runs[model] ?? 0) + 1;
    final span = (n - 1) % traceEvery == 0
        ? Sentry.startTransaction('tflite ${model.name}', 'ml.inference')
        : null;
    try {
      final port = await _port;
      final id = _nextId++;
      final completer = _pending[id] = Completer<Object?>();
      port.send((id, task));
      final result = await completer.future as R;
      span?.status = const SpanStatus.ok();
      return result;
    } catch (e) {
      span
        ?..throwable = e
        ..status = const SpanStatus.internalError();
      rethrow;
    } finally {
      if (exclusive) _busy.remove(model);
      if (span != null) unawaited(span.finish());
    }
  }

  Future<void> dispose() async {
    final isolate = _isolate;
    if (isolate == null) return;
    // The worker frees the interpreters, closes its port and exits; killing
    // it here could skip that native cleanup.
    (await _port).send(null);
    _inbox?.close();
    for (final c in _pending.values) {
      c.completeError(const TfliteException('isolate disposed'));
    }
    _pending.clear();
  }

  Future<SendPort> _spawn() async {
    final inbox = _inbox = ReceivePort('tflite');
    final port = Completer<SendPort>();
    inbox.listen((message) {
      if (message is SendPort) return port.complete(message);
      final (id, result, error) = message! as (int, Object?, String?);
      final completer = _pending.remove(id);
      if (error == null) {
        completer?.complete(result);
      } else {
        completer?.completeError(TfliteException(error));
      }
    });
    _isolate = await Isolate.spawn(
      _isolateMain,
      inbox.sendPort,
      debugName: 'tflite',
    );
    return await port.future;
  }
}

void _isolateMain(SendPort out) {
  final inbox = ReceivePort();
  final worker = TfliteWorker();
  out.send(inbox.sendPort);
  inbox.listen((message) {
    if (message == null) {
      worker.close();
      inbox.close();
      return;
    }
    final (id, task) = message as (int, IsolateTask<Object?>);
    try {
      out.send((id, task.run(worker), null));
    } on Object catch (e, st) {
      out.send((id, null, '$e\n$st'));
    }
  });
}
