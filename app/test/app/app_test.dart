import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pawsense/app/app.dart';
import 'package:pawsense/app/di/injection.dart';
import 'package:pawsense/app/router.dart';
import 'package:pawsense/features/insights_feed/domain/insights_repository.dart';
import 'package:pawsense/features/settings/presentation/settings_cubit.dart';
import 'package:pawsense/ml/breed_classifier.dart';
import 'package:pawsense/ml/frame_scheduler.dart';
import 'package:pawsense/ml/pet_detector.dart';

class _MockDetector extends Mock implements PetDetector;

class _MockClassifier extends Mock implements BreedClassifier;

class _MockInsights extends Mock implements InsightsRepository;

void main() {
  setUp(() {
    final detector = _MockDetector();
    when(detector.load).thenAnswer((_) async {});
    when(detector.dispose).thenAnswer((_) async {});
    final insights = _MockInsights();
    when(() => insights.watchFeed(filter: any(named: 'filter')))
        .thenAnswer((_) => Stream.value(const []));

    GetIt.I
      ..registerSingleton<SettingsCubit>(SettingsCubit())
      ..registerFactory<PetDetector>(() => detector)
      ..registerFactoryParam<BreedClassifier, BreedEngine?, void>((_, _) {
        final c = _MockClassifier();
        when(() => c.engineName).thenReturn('fake');
        when(c.load).thenAnswer((_) async {});
        when(c.dispose).thenAnswer((_) async {});
        return c;
      })
      ..registerFactory<FrameScheduler>(FrameScheduler.new)
      ..registerSingleton<InsightsRepository>(insights);
  });

  tearDown(GetIt.I.reset);

  Future<void> pumpApp(WidgetTester tester, {required bool granted}) async {
    await tester.pumpWidget(
      PawSenseApp(router: createRouter(hasPermissions: () async => granted)),
    );
    // Not pumpAndSettle: the Live tab shows an indeterminate spinner while
    // the (absent) camera starts.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('shows the 4 tabs and switches between them', (tester) async {
    await pumpApp(tester, granted: true);

    final nav = find.byType(NavigationBar);
    for (final tab in ['Live', 'Sound', 'Clips', 'Feed']) {
      expect(find.descendant(of: nav, matching: find.text(tab)), findsOne);
    }

    await tester.tap(find.descendant(of: nav, matching: find.text('Feed')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.widgetWithText(AppBar, 'Feed'), findsOne);
  });

  testWidgets('redirects to onboarding without permissions', (tester) async {
    await pumpApp(tester, granted: false);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.widgetWithText(AppBar, 'Welcome'), findsOne);
  });

  test('DI resolves the permissions check', () {
    final getIt = GetIt.asNewInstance();
    configureDependencies(getIt);
    expect(getIt<PermissionsCheck>(), same(cameraAndMicrophoneGranted));
  });
}
