final class TripoCredential {
  const TripoCredential({
    required this.name,
    required this.apiKey,
    required this.fingerprint,
    required this.createdAt,
    this.balance,
    this.frozen,
  });

  final String name;
  final String apiKey;
  final String fingerprint;
  final DateTime createdAt;
  final double? balance;
  final double? frozen;

  String get maskedKey {
    final normalized = apiKey.trim();
    final suffix = normalized.length <= 4
        ? normalized
        : normalized.substring(normalized.length - 4);
    final prefix = normalized.startsWith('tsk_') ? 'tsk_' : '';
    return '${prefix}••••••$suffix';
  }

  TripoCredential copyWith({
    String? name,
    double? balance,
    double? frozen,
  }) {
    return TripoCredential(
      name: name ?? this.name,
      apiKey: apiKey,
      fingerprint: fingerprint,
      createdAt: createdAt,
      balance: balance ?? this.balance,
      frozen: frozen ?? this.frozen,
    );
  }
}

abstract interface class ActiveTripoCredentialProvider {
  Future<TripoCredential?> getActive();

  Future<TripoCredential?> findByFingerprint(String fingerprint);
}
