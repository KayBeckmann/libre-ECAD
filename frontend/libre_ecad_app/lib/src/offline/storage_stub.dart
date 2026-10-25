Future<String?> readVault() async => throw UnsupportedError(
  'Offline-Kopien sind nur im installierten Client verfügbar.',
);
Future<void> writeVault(String? expected, String value) async =>
    throw UnsupportedError('Web bleibt servergebunden.');
Future<void> deleteVault() async =>
    throw UnsupportedError('Web bleibt servergebunden.');
