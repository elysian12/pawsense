import 'dart:developer' as developer;

/// App-wide logger (`dart:developer`). Read it in DevTools → Logging in debug
/// and profile builds; release builds have no VM service, so nothing is shown.
/// Keep messages free of user data.
void log(
  String message, {
  String name = 'pawsense',
  Object? error,
  StackTrace? stackTrace,
}) => developer.log(message, name: name, error: error, stackTrace: stackTrace);
