import 'package:flutter_test/flutter_test.dart';
import 'package:mohsen_tripo/src/data/local/tripo_credential_repository.dart';

final class MemorySecureStore implements SecureKeyValueStore {
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

void main() {
  test('saveAndActivate persists and restores an active Tripo credential', () async {
    final store = MemorySecureStore();
    final repository = SecureTripoCredentialRepository(
      store,
      now: () => DateTime.utc(2026, 9, 26, 0, 0),
    );

    final saved = await repository.saveAndActivate(
      name: 'Tripo 1',
      apiKey: 'tsk_example_secret_1234567890',
      balance: 600,
      frozen: 0,
    );

    final restored = await SecureTripoCredentialRepository(store).getActive();

    expect(restored?.fingerprint, saved.fingerprint);
    expect(restored?.apiKey, 'tsk_example_secret_1234567890');
    expect(restored?.name, 'Tripo 1');
    expect(restored?.maskedKey, startsWith('tsk_'));
    expect(restored?.maskedKey, endsWith('7890'));
    expect(restored?.maskedKey, isNot(contains('example_secret')));
  });

  test('findByFingerprint returns the credential that created a job', () async {
    final repository = SecureTripoCredentialRepository(MemorySecureStore());

    final first = await repository.saveAndActivate(
      name: 'First',
      apiKey: 'tsk_first_key_12345678901234567890',
    );
    await repository.saveAndActivate(
      name: 'Second',
      apiKey: 'tsk_second_key_12345678901234567890',
    );

    final found = await repository.findByFingerprint(first.fingerprint);

    expect(found?.name, 'First');
    expect(found?.apiKey, 'tsk_first_key_12345678901234567890');
  });

  test('deleting active credential promotes another saved credential', () async {
    final repository = SecureTripoCredentialRepository(MemorySecureStore());

    final first = await repository.saveAndActivate(
      name: 'First',
      apiKey: 'tsk_first_key_12345678901234567890',
    );
    final second = await repository.saveAndActivate(
      name: 'Second',
      apiKey: 'tsk_second_key_12345678901234567890',
    );

    await repository.delete(second.fingerprint);
    final active = await repository.getActive();

    expect(active?.fingerprint, first.fingerprint);
  });
}
