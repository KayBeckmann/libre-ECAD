import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _file() async {
  final dir = Directory(
    '${(await getApplicationSupportDirectory()).path}/offline',
  );
  await dir.create(recursive: true);
  if (!Platform.isWindows) await Process.run('chmod', ['700', dir.path]);
  return File('${dir.path}/vault.json');
}

Future<String?> readVault() async {
  final f = await _file();
  return await f.exists() ? f.readAsString() : null;
}

Future<void> _tail = Future.value();

Future<void> writeVault(String? expected, String value) {
  final pending = _tail.then((_) => _writeVault(expected, value));
  _tail = pending.then<void>((_) {}, onError: (Object _) {});
  return pending;
}

Future<void> _writeVault(String? expected, String value) async {
  final f = await _file();
  final lock = await File('${f.path}.lock').open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
    final current = await f.exists() ? await f.readAsString() : null;
    if (current != expected) {
      throw StateError(
        'Die lokale Ablage wurde in einem anderen Fenster geändert. Neu entsperren; Entwurf vorher sichern.',
      );
    }
    final temp = File('${f.path}.tmp');
    await temp.writeAsString(value, flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', temp.path]);
    await temp.rename(f.path);
  } finally {
    await lock.unlock();
    await lock.close();
  }
}
