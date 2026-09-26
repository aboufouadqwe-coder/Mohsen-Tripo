import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/core/errors/app_failure.dart';
import 'package:mohsen_tripo/src/features/bootstrap/session_bootstrapper.dart';

final class FakeAuthPort implements AuthPort {
  FakeAuthPort({
    this.currentUserId,
    this.anonymousUserId = 'anonymous-user',
    this.error,
  });

  @override
  String? currentUserId;

  String? anonymousUserId;
  Object? error;
  int signInAnonymouslyCalls = 0;

  @override
  Future<String?> signInAnonymously() async {
    signInAnonymouslyCalls += 1;
    if (error != null) throw error!;
    currentUserId = anonymousUserId;
    return anonymousUserId;
  }
}

void main() {
  test('creates anonymous session when no session exists', () async {
    final auth = FakeAuthPort(currentUserId: null);
    final bootstrapper = SessionBootstrapper(auth);

    final userId = await bootstrapper.ensureSession();

    expect(userId, 'anonymous-user');
    expect(auth.signInAnonymouslyCalls, 1);
  });

  test('reuses existing anonymous session', () async {
    final auth = FakeAuthPort(currentUserId: 'user-1');
    final bootstrapper = SessionBootstrapper(auth);

    final userId = await bootstrapper.ensureSession();

    expect(userId, 'user-1');
    expect(auth.signInAnonymouslyCalls, 0);
  });

  test('missing user from anonymous sign-in maps to authentication failure', () async {
    final auth = FakeAuthPort(
      currentUserId: null,
      anonymousUserId: null,
    );
    final bootstrapper = SessionBootstrapper(auth);

    await expectLater(
      bootstrapper.ensureSession(),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.category,
          'category',
          AppFailureCategory.authentication,
        ),
      ),
    );
  });

  test('anonymous sign-in exception maps to authentication failure', () async {
    final auth = FakeAuthPort(
      currentUserId: null,
      error: StateError('network details must not escape'),
    );
    final bootstrapper = SessionBootstrapper(auth);

    await expectLater(
      bootstrapper.ensureSession(),
      throwsA(
        isA<AppFailure>()
            .having(
              (failure) => failure.category,
              'category',
              AppFailureCategory.authentication,
            )
            .having(
              (failure) => failure.message.contains('network details'),
              'redacted message',
              isFalse,
            ),
      ),
    );
  });
}
