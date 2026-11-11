import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsense/features/clip_analysis/presentation/clips_page.dart';
import 'package:pawsense/features/insights_feed/presentation/feed_page.dart';
import 'package:pawsense/features/live_detection/presentation/live_detection_page.dart';
import 'package:pawsense/features/onboarding/presentation/onboarding_page.dart';
import 'package:pawsense/features/settings/presentation/settings_page.dart';
import 'package:pawsense/features/sound/presentation/sound_page.dart';
import 'package:permission_handler/permission_handler.dart';

abstract final class AppRoutes {
  static const live = '/live';
  static const sound = '/sound';
  static const clips = '/clips';
  static const feed = '/feed';
  static const onboarding = '/onboarding';
  static const settings = '/settings';
}

/// Whether the app may leave onboarding. Registered in DI so E2E tests can
/// replace it with `() async => true`.
typedef PermissionsCheck = Future<bool> Function();

Future<bool> cameraAndMicrophoneGranted() async =>
    (await Permission.camera.isGranted) &&
    (await Permission.microphone.isGranted);

GoRouter createRouter({required PermissionsCheck hasPermissions}) => GoRouter(
  initialLocation: AppRoutes.live,
  redirect: (context, state) async {
    final granted = await hasPermissions();
    final onOnboarding = state.matchedLocation == AppRoutes.onboarding;
    if (!granted && !onOnboarding) return AppRoutes.onboarding;
    if (granted && onOnboarding) return AppRoutes.live;
    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (_, _) => const OnboardingPage(),
    ),
    GoRoute(path: AppRoutes.settings, builder: (_, _) => const SettingsPage()),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => _TabShell(shell: shell),
      branches: [
        _branch(AppRoutes.live, const LiveDetectionPage()),
        _branch(AppRoutes.sound, const SoundPage()),
        _branch(AppRoutes.clips, const ClipsPage()),
        _branch(AppRoutes.feed, const FeedPage()),
      ],
    ),
  ],
);

StatefulShellBranch _branch(String path, Widget page) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (_, _) => page)],
);

class _TabShell extends StatelessWidget {
  const new({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) =>
          shell.goBranch(i, initialLocation: i == shell.currentIndex),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.videocam_outlined),
          label: 'Live',
        ),
        NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'Sound'),
        NavigationDestination(icon: Icon(Icons.movie_outlined), label: 'Clips'),
        NavigationDestination(icon: Icon(Icons.timeline), label: 'Feed'),
      ],
    ),
  );
}
