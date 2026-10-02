import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/tripo/tripo_credential.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore([
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  ]) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

abstract interface class TripoCredentialRepository
    implements ActiveTripoCredentialProvider {
  Future<List<TripoCredential>> list();
  Future<TripoCredential> saveAndActivate({
    required String name,
    required String apiKey,
    double? balance,
    double? frozen,
  });
  Future<void> activate(String fingerprint);
  Future<void> delete(String fingerprint);
}

final class SecureTripoCredentialRepository
    implements TripoCredentialRepository {
  SecureTripoCredentialRepository(
    this._store, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const _storageKey = 'mohsen_tripo_credentials_v1';

  final SecureKeyValueStore _store;
  final DateTime Function() _now;

  @override
  Future<List<TripoCredential>> list() async {
    final state = await _readState();
    return state.credentials;
  }

  @override
  Future<TripoCredential?> getActive() async {
    final state = await _readState();
    final active = state.activeFingerprint;
    if (active == null) return null;
    for (final credential in state.credentials) {
      if (credential.fingerprint == active) return credential;
    }
    return null;
  }

  @override
  Future<TripoCredential?> findByFingerprint(String fingerprint) async {
    final normalized = fingerprint.trim();
    if (normalized.isEmpty) return null;
    final state = await _readState();
    for (final credential in state.credentials) {
      if (credential.fingerprint == normalized) return credential;
    }
    return null;
  }

  @override
  Future<TripoCredential> saveAndActivate({
    required String name,
    required String apiKey,
    double? balance,
    double? frozen,
  }) async {
    final normalizedKey = apiKey.trim();
    final normalizedName = name.trim();
    if (normalizedKey.isEmpty) {
      throw AppFailure.validation('Tripo API key is empty.');
    }

    final fingerprint = _fingerprint(normalizedKey);
    final state = await _readState();
    final credential = TripoCredential(
      name: normalizedName.isEmpty ? 'Tripo' : normalizedName,
      apiKey: normalizedKey,
      fingerprint: fingerprint,
      createdAt: _now().toUtc(),
      balance: balance,
      frozen: frozen,
    );

    final updated = <TripoCredential>[];
    var replaced = false;
    for (final existing in state.credentials) {
      if (existing.fingerprint == fingerprint) {
        updated.add(
          TripoCredential(
            name: credential.name,
            apiKey: normalizedKey,
            fingerprint: fingerprint,
            createdAt: existing.createdAt,
            balance: balance ?? existing.balance,
            frozen: frozen ?? existing.frozen,
          ),
        );
        replaced = true;
      } else {
        updated.add(existing);
      }
    }
    if (!replaced) updated.add(credential);

    await _writeState(
      _CredentialState(
        activeFingerprint: fingerprint,
        credentials: updated,
      ),
    );
    return (await findByFingerprint(fingerprint))!;
  }

  @override
  Future<void> activate(String fingerprint) async {
    final state = await _readState();
    final exists = state.credentials.any(
      (credential) => credential.fingerprint == fingerprint,
    );
    if (!exists) {
      throw AppFailure.validation('Saved Tripo credential was not found.');
    }
    await _writeState(
      _CredentialState(
        activeFingerprint: fingerprint,
        credentials: state.credentials,
      ),
    );
  }

  @override
  Future<void> delete(String fingerprint) async {
    final state = await _readState();
    final remaining = state.credentials
        .where((credential) => credential.fingerprint != fingerprint)
        .toList(growable: false);
    final nextActive = state.activeFingerprint == fingerprint
        ? (remaining.isEmpty ? null : remaining.last.fingerprint)
        : state.activeFingerprint;
    if (remaining.isEmpty) {
      await _store.delete(_storageKey);
      return;
    }
    await _writeState(
      _CredentialState(
        activeFingerprint: nextActive,
        credentials: remaining,
      ),
    );
  }

  String _fingerprint(String apiKey) =>
      sha256.convert(utf8.encode(apiKey)).toString();

  Future<_CredentialState> _readState() async {
    try {
      final raw = await _store.read(_storageKey);
      if (raw == null || raw.trim().isEmpty) {
        return const _CredentialState(
          activeFingerprint: null,
          credentials: [],
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final active = decoded['active_fingerprint'];
      final items = decoded['credentials'];
      if (items is! List) throw const FormatException();

      final credentials = <TripoCredential>[];
      for (final item in items) {
        if (item is! Map) continue;
        final map = Map<String, Object?>.from(item);
        final name = map['name'];
        final key = map['api_key'];
        final fingerprint = map['fingerprint'];
        final createdAt = map['created_at'];
        if (name is! String ||
            key is! String ||
            fingerprint is! String ||
            createdAt is! String) {
          continue;
        }
        final date = DateTime.tryParse(createdAt);
        if (date == null) continue;
        credentials.add(
          TripoCredential(
            name: name,
            apiKey: key,
            fingerprint: fingerprint,
            createdAt: date,
            balance: (map['balance'] as num?)?.toDouble(),
            frozen: (map['frozen'] as num?)?.toDouble(),
          ),
        );
      }
      return _CredentialState(
        activeFingerprint: active is String ? active : null,
        credentials: credentials,
      );
    } catch (_) {
      throw AppFailure.storage();
    }
  }

  Future<void> _writeState(_CredentialState state) async {
    try {
      await _store.write(
        _storageKey,
        jsonEncode({
          'active_fingerprint': state.activeFingerprint,
          'credentials': state.credentials
              .map(
                (credential) => {
                  'name': credential.name,
                  'api_key': credential.apiKey,
                  'fingerprint': credential.fingerprint,
                  'created_at': credential.createdAt.toUtc().toIso8601String(),
                  'balance': credential.balance,
                  'frozen': credential.frozen,
                },
              )
              .toList(growable: false),
        }),
      );
    } catch (_) {
      throw AppFailure.storage();
    }
  }
}

final class _CredentialState {
  const _CredentialState({
    required this.activeFingerprint,
    required this.credentials,
  });

  final String? activeFingerprint;
  final List<TripoCredential> credentials;
}
