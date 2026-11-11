import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_bloc.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_page.dart';
import 'package:pawsense/features/settings/presentation/settings_cubit.dart';
import 'package:pawsense/ml/ml_types.dart';

class _MockLiveBloc extends MockBloc<LiveDetectionEvent, LiveDetectionState>
    implements LiveDetectionBloc;

void main() {
  late _MockLiveBloc bloc;
  late SettingsCubit settings;

  setUpAll(
    () => registerFallbackValue(const LiveSettingsChanged(SettingsState())),
  );

  setUp(() {
    bloc = _MockLiveBloc();
    settings = SettingsCubit();
    when(() => bloc.state).thenReturn(
      const LiveDetectionState(
        status: LiveStatus.ready,
        cameraFps: 29.6,
        engine: 'Core ML',
        classificationMs: 7.25,
        stats: SchedulerStats(
          processedFps: 11,
          droppedFrames: 42,
          avgInferenceMs: 31.5,
          p95InferenceMs: 48,
          mode: SchedulerMode.idle,
        ),
      ),
    );
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<LiveDetectionBloc>.value(value: bloc),
        ],
        child: const Scaffold(body: LiveDetectionView()),
      ),
    ),
  );

  testWidgets('HUD shows fps, drops, inference ms, engine and mode', (
    tester,
  ) async {
    await pump(tester);
    final hud = find.byType(LiveHud);
    for (final text in [
      'camera 29.6 fps',
      'processed 11.0 fps',
      'dropped 42',
      'inference avg 31.5 ms',
      'inference p95 48.0 ms',
      'breed Core ML 7.3 ms',
      'mode idle',
    ]) {
      expect(
        find.descendant(of: hud, matching: find.textContaining(text)),
        findsOne,
        reason: text,
      );
    }
  });

  testWidgets('HUD toggle hides it; settings changes reach the bloc', (
    tester,
  ) async {
    await pump(tester);
    settings.setShowHud(show: false);
    await tester.pump();
    expect(find.byType(LiveHud), findsNothing);
    final sent = verify(() => bloc.add(captureAny())).captured.single;
    expect(
      (sent as LiveSettingsChanged).settings,
      const SettingsState(showHud: false),
    );
  });

  testWidgets('no camera plugin (tests/simulator): shows an error, no crash', (
    tester,
  ) async {
    await pump(tester);
    // The platform-channel failure arrives on the real event loop.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('MissingPluginException'), findsOne);
    expect(tester.takeException(), isNull);
  });
}
