import '../../core/errors/app_failure.dart';

abstract interface class AuthPort {
  String? get currentUserId;

  Future<String?> signInAnonymously();
}

final class SessionBootstrapper {
  const SessionBootstrapper(this._auth);

  final AuthPort _auth;

  Future<String> ensureSession() async {
    final existingUserId = _auth.currentUserId?.trim();
    if (existingUserId != null && existingUserId.isNotEmpty) {
      return existingUserId;
    }

    try {
      final anonymousUserId = (await _auth.signInAnonymously())?.trim();
      if (anonymousUserId == null || anonymousUserId.isEmpty) {
        throw AppFailure.authentication();
      }
      return anonymousUserId;
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw AppFailure.authentication();
    }
  }
}
