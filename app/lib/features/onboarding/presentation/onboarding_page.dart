import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsense/app/router.dart';
import 'package:pawsense/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    // E2E registers a fake [ReadPermissions] to skip the system prompts.
    create: (_) => OnboardingCubit(
      request: GetIt.I.isRegistered<ReadPermissions>() ? GetIt.I() : null,
    ),
    child: const OnboardingView(),
  );
}

class OnboardingView extends StatefulWidget {
  const new({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Picks up permissions granted in the system Settings app.
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<OnboardingCubit>().recheck(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocConsumer<OnboardingCubit, OnboardingStatus>(
      listener: (context, status) {
        if (status == OnboardingStatus.granted) context.go(AppRoutes.live);
      },
      builder: (context, status) => Scaffold(
        appBar: AppBar(title: const Text('Welcome')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.pets, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  'PawSense watches and listens for your pet',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const ListTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text('Camera'),
                  subtitle: Text(
                    'Detects your pet and its breed live. Frames are '
                    'processed on this phone.',
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.mic_none),
                  title: Text('Microphone'),
                  subtitle: Text(
                    'Hears barks and meows, on device. Also records clip '
                    'audio.',
                  ),
                ),
                const Spacer(),
                if (status == OnboardingStatus.denied)
                  const _Notice(
                    'PawSense needs both permissions. Tap below to try again.',
                  ),
                if (status == OnboardingStatus.permanentlyDenied) ...[
                  const _Notice(
                    'Permission was denied. Enable Camera and Microphone for '
                    'PawSense in Settings, then come back.',
                  ),
                  const SizedBox(height: 12),
                  const FilledButton(
                    onPressed: openAppSettings,
                    child: Text('Open settings'),
                  ),
                ] else
                  FilledButton(
                    onPressed: status == OnboardingStatus.requesting
                        ? null
                        : context.read<OnboardingCubit>().request,
                    child: const Text('Allow camera & microphone'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}
