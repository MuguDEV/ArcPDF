class VaultInitException implements Exception {
  final String message;
  VaultInitException(this.message);

  @override
  String toString() => 'VaultInitException: $message';
}
