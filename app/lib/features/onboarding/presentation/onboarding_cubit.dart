import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

enum OnboardingStatus {
  initial,
  requesting,
  granted,
  denied,
  permanentlyDenied,
}

typedef ReadPermissions = Future<List<PermissionStatus>> Function();

const List<Permission> _required = [Permission.camera, Permission.microphone];

Future<List<PermissionStatus>> _requestAll() async =>
    (await _required.request()).values.toList();

Future<List<PermissionStatus>> _checkAll() =>
    Future.wait([for (final p in _required) p.status]);

/// Camera + microphone permission flow. `request` shows the system prompts;
/// `check` only reads the current status (used after the user comes back
/// from the system Settings app).
class OnboardingCubit extends Cubit<OnboardingStatus> {
  new({ReadPermissions? request, ReadPermissions? check})
    : _request = request ?? _requestAll,
      _check = check ?? _checkAll,
      super(OnboardingStatus.initial);

  final ReadPermissions _request;
  final ReadPermissions _check;

  Future<void> request() => _update(_request);

  /// Re-reads statuses without prompting; no-op until the user was asked once.
  Future<void> recheck() async {
    if (state == OnboardingStatus.denied ||
        state == OnboardingStatus.permanentlyDenied) {
      await _update(_check);
    }
  }

  Future<void> _update(ReadPermissions read) async {
    emit(OnboardingStatus.requesting);
    emit(_reduce(await read()));
  }

  static OnboardingStatus _reduce(List<PermissionStatus> statuses) {
    if (statuses.every((s) => s.isGranted || s.isLimited)) {
      return OnboardingStatus.granted;
    }
    // iOS reports a second denial as permanentlyDenied; restricted (parental
    // controls) can also only be changed in system Settings.
    if (statuses.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return OnboardingStatus.permanentlyDenied;
    }
    return OnboardingStatus.denied;
  }
}
