import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:ecad_core/ecad_core.dart';

/// Git is a derived archive; SQL history decides which candidate was approved.
/// Files, commit time, parent and identity are retained for exact reconstruction.
class GitArchive {
  GitArchive(this.root);
  final String root;
  Future<String> write(String company, String project, Json packet) async {
    final key = sha256.convert(utf8.encode('$company/$project')).toString();
    final dir = Directory('$root/$key.git');
    await dir.create(recursive: true);
    Future<String> git(List<String> args, {List<int>? input}) async {
      final process = await Process.start(
        'git',
        ['--git-dir=${dir.path}', ...args],
        environment: {
          'GIT_AUTHOR_NAME': 'LibreECAD',
          'GIT_AUTHOR_EMAIL': 'archive@libre-ecad.local',
          'GIT_COMMITTER_NAME': 'LibreECAD',
          'GIT_COMMITTER_EMAIL': 'archive@libre-ecad.local',
          'GIT_AUTHOR_DATE': packet['at'],
          'GIT_COMMITTER_DATE': packet['at'],
          'GIT_CONFIG_NOSYSTEM': '1',
          'GIT_CONFIG_GLOBAL': '/dev/null',
        },
      );
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      if (input != null) process.stdin.add(input);
      await process.stdin.close();
      final code = await process.exitCode;
      final result = await stdout;
      await stderr;
      if (code != 0)
        throw FileSystemException(
          'Projektarchiv konnte nicht geschrieben werden.',
        );
      return result.trim();
    }

    if (!await File('${dir.path}/HEAD').exists()) await git(['init', '--bare']);
    final files = Map<String, dynamic>.from(packet['files']);
    final names = files.keys.toList()..sort();
    final entries = <String>[];
    for (final name in names) {
      if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name))
        throw FormatException('Ungültiger Archivname.');
      final hash = await git([
        'hash-object',
        '-w',
        '--stdin',
      ], input: base64Decode(files[name]));
      entries.add('100644 blob $hash\t$name\n');
    }
    final tree = await git(['mktree'], input: utf8.encode(entries.join()));
    final parent = packet['parent'] as String?;
    final commit = await git([
      'commit-tree',
      tree,
      if (parent != null) ...['-p', parent],
    ], input: utf8.encode('LibreECAD ${packet['id']}\n'));
    if (packet['commit'] != null && packet['commit'] != commit)
      throw FileSystemException('Archivprüfung fehlgeschlagen.');
    await git(['update-ref', 'refs/heads/candidate-${packet['id']}', commit]);
    return commit;
  }
}
