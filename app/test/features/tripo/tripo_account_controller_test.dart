import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/local/tripo_credential_repository.dart';
import 'package:mohsen_tripo/src/data/supabase/generation_gateway.dart';
import 'package:mohsen_tripo/src/features/tripo/tripo_account_controller.dart';

final class MemoryStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

final class FakeValidator implements TripoCredentialValidationGateway {
  final Map<String, TripoCreditBalance> valid = {};

  @override
  Future<TripoCreditBalance> getCreditBalanceForApiKey(String apiKey) async {
    final result = valid[apiKey];
    if (result == null) throw StateError('invalid key');
    return result;
  }
}

void main() {
  test('clipboard candidate is validated before becoming active', () async {
    final repository = SecureTripoCredentialRepository(MemoryStore());
    final validator = FakeValidator()
      ..valid['tsk_valid_key_12345678901234567890'] =
          const TripoCreditBalance(available: 600, frozen: 0);
    final controller = TripoAccountController(
      repository: repository,
      validator: validator,
      readClipboardText: () async => 'tsk_valid_key_12345678901234567890',
      openConsole: () async => true,
    );

    await controller.load();
    await controller.scanClipboard();

    expect(controller.candidateKey, 'tsk_valid_key_12345678901234567890');
    expect(controller.active, isNull);

    await controller.confirmCandidate(name: 'Trial');

    expect(controller.active?.name, 'Trial');
    expect(controller.active?.balance, 600);
    expect(controller.candidateKey, isNull);
  });

  test('invalid copied key never replaces working active credential', () async {
    final repository = SecureTripoCredentialRepository(MemoryStore());
    final current = await repository.saveAndActivate(
      name: 'Working',
      apiKey: 'tsk_working_key_12345678901234567890',
      balance: 100,
      frozen: 0,
    );
    final controller = TripoAccountController(
      repository: repository,
      validator: FakeValidator(),
      readClipboardText: () async => 'tsk_invalid_key_12345678901234567890',
      openConsole: () async => true,
    );

    await controller.load();
    await controller.scanClipboard();
    await controller.confirmCandidate(name: 'Broken');

    expect(controller.active?.fingerprint, current.fingerprint);
    expect(controller.errorCode, 'invalid_key');
  });

  test('unrelated clipboard text is ignored', () async {
    final controller = TripoAccountController(
      repository: SecureTripoCredentialRepository(MemoryStore()),
      validator: FakeValidator(),
      readClipboardText: () async => 'hello world',
      openConsole: () async => true,
    );

    await controller.scanClipboard();

    expect(controller.candidateKey, isNull);
  });

  test('opening console uses injected external browser action', () async {
    var opened = 0;
    final controller = TripoAccountController(
      repository: SecureTripoCredentialRepository(MemoryStore()),
      validator: FakeValidator(),
      readClipboardText: () async => null,
      openConsole: () async {
        opened += 1;
        return true;
      },
    );

    final result = await controller.openTripoConsole();

    expect(result, isTrue);
    expect(opened, 1);
  });
}
