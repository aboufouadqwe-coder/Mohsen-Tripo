import 'package:flutter/foundation.dart';

import '../../data/local/tripo_credential_repository.dart';
import '../../data/supabase/generation_gateway.dart';
import '../../domain/tripo/tripo_credential.dart';

typedef ClipboardTextReader = Future<String?> Function();
typedef TripoConsoleOpener = Future<bool> Function();

final class TripoAccountController extends ChangeNotifier {
  TripoAccountController({
    required this.repository,
    required this.validator,
    required this.readClipboardText,
    required this.openConsole,
  });

  final TripoCredentialRepository repository;
  final TripoCredentialValidationGateway validator;
  final ClipboardTextReader readClipboardText;
  final TripoConsoleOpener openConsole;

  List<TripoCredential> saved = const [];
  TripoCredential? active;
  String? candidateKey;
  String? errorCode;
  bool busy = false;
  bool _disposed = false;

  Future<void> load() async {
    if (_disposed) return;
    try {
      saved = await repository.list();
      active = await repository.getActive();
      errorCode = null;
    } catch (_) {
      errorCode = 'credential_store_failed';
    }
    _notify();
  }

  Future<bool> openTripoConsole() async {
    try {
      final opened = await openConsole();
      if (!opened) errorCode = 'browser_open_failed';
      _notify();
      return opened;
    } catch (_) {
      errorCode = 'browser_open_failed';
      _notify();
      return false;
    }
  }

  Future<void> scanClipboard() async {
    if (_disposed || busy) return;
    try {
      final raw = (await readClipboardText())?.trim();
      if (raw == null || !_looksLikeTripoKey(raw)) return;
      if (active?.apiKey == raw) return;
      candidateKey = raw;
      errorCode = null;
      _notify();
    } catch (_) {
      // Clipboard access can be denied by the OS. Do not turn that into a
      // persistent error; the manual import button can be tried again.
    }
  }

  Future<void> confirmCandidate({String? name}) async {
    final key = candidateKey;
    if (_disposed || busy || key == null) return;
    busy = true;
    errorCode = null;
    _notify();

    try {
      final balance = await validator.getCreditBalanceForApiKey(key);
      final displayName = (name ?? '').trim().isEmpty
          ? 'Tripo ${saved.length + 1}'
          : name!.trim();
      await repository.saveAndActivate(
        name: displayName,
        apiKey: key,
        balance: balance.available,
        frozen: balance.frozen,
      );
      candidateKey = null;
      await load();
    } catch (_) {
      errorCode = 'invalid_key';
      candidateKey = null;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> refreshBalance() async {
    final credential = active;
    if (_disposed || busy || credential == null) return;
    busy = true;
    errorCode = null;
    _notify();
    try {
      final balance =
          await validator.getCreditBalanceForApiKey(credential.apiKey);
      await repository.saveAndActivate(
        name: credential.name,
        apiKey: credential.apiKey,
        balance: balance.available,
        frozen: balance.frozen,
      );
      await load();
    } catch (_) {
      errorCode = 'balance_failed';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> activate(String fingerprint) async {
    if (_disposed || busy) return;
    try {
      await repository.activate(fingerprint);
      await load();
      await refreshBalance();
    } catch (_) {
      errorCode = 'credential_switch_failed';
      _notify();
    }
  }

  Future<void> deleteCredential(String fingerprint) async {
    if (_disposed || busy) return;
    try {
      await repository.delete(fingerprint);
      await load();
    } catch (_) {
      errorCode = 'credential_delete_failed';
      _notify();
    }
  }

  void dismissCandidate() {
    candidateKey = null;
    _notify();
  }

  bool _looksLikeTripoKey(String value) =>
      value.startsWith('tsk') && value.length >= 20 && !value.contains(' ');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
