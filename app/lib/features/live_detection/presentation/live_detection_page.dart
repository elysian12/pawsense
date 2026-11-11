import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsense/app/router.dart';
import 'package:pawsense/core/log.dart';
import 'package:pawsense/features/live_detection/presentation/detection_painter.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_bloc.dart';
import 'package:pawsense/features/settings/presentation/settings_cubit.dart';
import 'package:pawsense/ml/breed_classifier.dart';
import 'package:pawsense/ml/frame_scheduler.dart';
import 'package:pawsense/ml/ml_types.dart';

/// Lists the device cameras. E2E registers `() async => []` in GetIt so the
/// real camera (and its system permission dialog) never opens on CI.
typedef ListCameras = Future<List<CameraDescription>> Function();

/// Builds a [LiveDetectionBloc] from DI and starts it with the current
/// settings. Shared by the Live tab and the battery test.
LiveDetectionBloc createLiveDetectionBloc() {
  final getIt = GetIt.I;
  return LiveDetectionBloc(
    detector: getIt(),
    classifierFor: (engine) => getIt<BreedClassifier>(param1: engine),
    schedulerFor: ({required adaptive}) =>
        adaptive ? getIt<FrameScheduler>() : fixedRateScheduler(),
    insights: getIt(),
  )..add(LiveStarted(getIt<SettingsCubit>().state));
}

/// The "before" baseline for the battery measurement: the same scheduler
/// with every adaptive part neutralised. It still drops frames while one is
/// in flight (never queues) but otherwise runs at camera rate, ignoring
/// idle, battery and thermal state.
FrameScheduler fixedRateScheduler() => FrameScheduler(
  k: 0,
  idleInterval: Duration.zero,
  lowBatteryInterval: Duration.zero,
  thermalInterval: Duration.zero,
);

class LiveDetectionPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: GetIt.I<SettingsCubit>()),
      BlocProvider(create: (_) => createLiveDetectionBloc()),
    ],
    child: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Live'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: const LiveDetectionView(),
    ),
  );
}

/// Full-screen camera preview + detection overlay + debug HUD. Needs a
/// [LiveDetectionBloc] and the [SettingsCubit] above it.
///
/// The camera only runs while this widget is visible: its tab is selected
/// (TickerMode), its route is on top and the app is resumed. Otherwise the
/// controller is disposed so the camera is free for other screens/apps.
class LiveDetectionView extends StatefulWidget {
  const new({super.key});

  @override
  State<LiveDetectionView> createState() => _LiveDetectionViewState();
}

class _LiveDetectionViewState extends State<LiveDetectionView> {
  late final AppLifecycleListener _lifecycle;
  bool _appResumed = true;
  bool _visible = false;
  CameraController? _controller;
  String? _cameraError;

  /// Serializes camera start/stop so fast tab switches can't interleave.
  Future<void> _pending = Future.value();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        _appResumed = s == AppLifecycleState.resumed;
        _sync();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _sync();
  }

  void _sync() {
    final run = _visible && _appResumed;
    _pending = _pending.then((_) => run ? _start() : _stop());
  }

  Future<void> _start() async {
    if (_controller != null || !mounted) return;
    try {
      final cameras = await (GetIt.I.isRegistered<ListCameras>()
          ? GetIt.I<ListCameras>()
          : availableCameras)();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera on this device');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      final bloc = context.read<LiveDetectionBloc>();
      await controller.startImageStream((image) {
        // Frames can still arrive while the camera shuts down after the
        // page (and its bloc) are gone.
        if (bloc.isClosed) return;
        bloc.add(
          LiveFrameArrived(
            () => FrameData.fromCameraImage(
              image,
              // iOS: camera_avfoundation rotates the stream connection to
              // the device orientation, so frames are already upright.
              // Android (CameraX) delivers them in sensor orientation.
              sensorOrientation: Platform.isIOS ? 0 : camera.sensorOrientation,
            ),
          ),
        );
      });
      setState(() {
        _controller = controller;
        _cameraError = null;
      });
    } on Exception catch (e) {
      // CameraException (denied, in use) or PlatformException (no plugin).
      log('Camera start failed', error: e);
      final message = e is CameraException ? e.description ?? e.code : '$e';
      if (mounted) setState(() => _cameraError = message);
    }
  }

  Future<void> _stop() async {
    final controller = _controller;
    if (controller == null) return;
    if (mounted) setState(() => _controller = null);
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException catch (e) {
      log('stopImageStream failed', error: e);
    }
    await controller.dispose();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _visible = false;
    unawaited(_pending.then((_) => _stop()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showHud = context.select<SettingsCubit, bool>((c) => c.state.showHud);
    // previewSize is in sensor (landscape) orientation; the UI is upright.
    final sensor = controller?.value.previewSize ?? const Size(640, 480);
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final preview = portrait ? Size(sensor.height, sensor.width) : sensor;
    return BlocListener<SettingsCubit, SettingsState>(
      listener: (context, s) =>
          context.read<LiveDetectionBloc>().add(LiveSettingsChanged(s)),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null)
              _Preview(controller: controller, size: preview)
            else
              Center(
                child: _cameraError == null
                    ? const CircularProgressIndicator()
                    : Text(
                        _cameraError!,
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
            // Outside _Preview so detections show (and E2E can assert them)
            // even without a camera, e.g. on a simulator.
            _DetectionOverlay(preview: preview),
            if (showHud)
              const Positioned(
                left: 12,
                bottom: 12,
                child: SafeArea(child: LiveHud()),
              ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const new({required this.controller, required this.size});

  final CameraController controller;

  /// Upright preview size.
  final Size size;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.cover,
    clipBehavior: Clip.hardEdge,
    child: SizedBox.fromSize(size: size, child: CameraPreview(controller)),
  );
}

/// Boxes + labels of the current detections, drawn over the preview.
class _DetectionOverlay extends StatelessWidget {
  const new({required this.preview});

  final Size preview;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<LiveDetectionBloc, LiveDetectionState>(
        buildWhen: (a, b) =>
            a.detections != b.detections || a.breeds != b.breeds,
        builder: (_, s) => Semantics(
          label: [
            for (final (i, d) in s.detections.indexed)
              detectionLabel(d, i == 0 ? s.breeds.firstOrNull : null),
          ].join(', '),
          child: CustomPaint(
            painter: DetectionPainter(
              detections: s.detections,
              preview: preview,
              breed: s.breeds.firstOrNull,
            ),
          ),
        ),
      );
}

/// Debug HUD: camera/processed fps, drops, inference ms, engine, mode.
class LiveHud extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<LiveDetectionBloc, LiveDetectionState>(
        builder: (context, s) {
          String ms(double? v) => v == null ? '–' : v.toStringAsFixed(1);
          final engine = s.engine.isEmpty ? '–' : s.engine;
          final lines = [
            if (s.status == LiveStatus.loading) 'loading models…',
            if (s.error != null) 'error: ${s.error}',
            'camera ${s.cameraFps.toStringAsFixed(1)} fps',
            'processed ${s.stats.processedFps.toStringAsFixed(1)} fps',
            'dropped ${s.stats.droppedFrames}',
            'inference avg ${ms(s.stats.avgInferenceMs)} ms',
            'inference p95 ${ms(s.stats.p95InferenceMs)} ms',
            'detect ${ms(s.detectionMs)} ms',
            'breed $engine ${ms(s.classificationMs)} ms',
            if (s.adaptive)
              'mode ${s.stats.mode.name}'
            else
              'mode fixed (adaptive off)',
          ];
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                lines.join('\n'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.3,
                ),
              ),
            ),
          );
        },
      );
}
