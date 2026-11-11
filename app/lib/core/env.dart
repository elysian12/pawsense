/// Compile-time configuration, injected with
/// `flutter run --dart-define-from-file=dart_defines.json`.
///
/// Copy `dart_defines.example.json` to `dart_defines.json` (gitignored).
/// Android emulators reach the host machine at `http://10.0.2.2:8080`,
/// iOS simulators at `http://localhost:8080`.
abstract final class Env {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// Bearer token for the PawSense backend. Not a third-party secret: the
  /// Anthropic key lives only on the backend.
  static const apiToken = String.fromEnvironment('API_TOKEN');

  /// Empty disables Sentry entirely.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static final double sentryTracesSampleRate =
      double.tryParse(
        const String.fromEnvironment('SENTRY_TRACES_SAMPLE_RATE'),
      ) ??
      0.2;
}
