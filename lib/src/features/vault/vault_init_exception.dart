class VaultInitException implements Exception {
  final String message;
  const VaultInitException(this.message);
  @override
  String toString() => 'VaultInitException: $message';
}
