import 'package:bloc_test/bloc_test.dart';
import 'package:pawsense/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:permission_handler/permission_handler.dart';

ReadPermissions _returns(List<PermissionStatus> s) =>
    () async => s;

void main() {
  const granted = PermissionStatus.granted;
  const denied = PermissionStatus.denied;
  const permanentlyDenied = PermissionStatus.permanentlyDenied;

  blocTest<OnboardingCubit, OnboardingStatus>(
    'granted when camera and mic are granted',
    build: () => OnboardingCubit(request: _returns([granted, granted])),
    act: (c) => c.request(),
    expect: () => [OnboardingStatus.requesting, OnboardingStatus.granted],
  );

  blocTest<OnboardingCubit, OnboardingStatus>(
    'denied when one is denied',
    build: () => OnboardingCubit(request: _returns([granted, denied])),
    act: (c) => c.request(),
    expect: () => [OnboardingStatus.requesting, OnboardingStatus.denied],
  );

  blocTest<OnboardingCubit, OnboardingStatus>(
    'permanently denied wins over denied (needs the Settings app)',
    build: () =>
        OnboardingCubit(request: _returns([denied, permanentlyDenied])),
    act: (c) => c.request(),
    expect: () => [
      OnboardingStatus.requesting,
      OnboardingStatus.permanentlyDenied,
    ],
  );

  blocTest<OnboardingCubit, OnboardingStatus>(
    'recheck after returning from Settings picks up the grant',
    build: () => OnboardingCubit(
      request: _returns([permanentlyDenied, granted]),
      check: _returns([granted, granted]),
    ),
    act: (c) async {
      await c.request();
      await c.recheck();
    },
    skip: 2,
    expect: () => [OnboardingStatus.requesting, OnboardingStatus.granted],
  );

  blocTest<OnboardingCubit, OnboardingStatus>(
    'recheck does nothing before the user was asked',
    build: () => OnboardingCubit(check: _returns([granted, granted])),
    act: (c) => c.recheck(),
    expect: () => <OnboardingStatus>[],
  );
}
