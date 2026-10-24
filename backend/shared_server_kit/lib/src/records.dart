import 'dart:convert';
import 'package:postgres/postgres.dart';

typedef Json = Map<String, dynamic>;
Json cloneJson(Json value) => jsonDecode(jsonEncode(value)) as Json;

/// The transaction lock serializes state changes, including authorization checks.
/// Each new revision and its audit snapshot are written in the same transaction.
abstract class Records {
  Future<T> transaction<T>(Future<T> Function(RecordSession) action);
}

abstract class RecordSession {
  Future<List<Json>> list(String kind);
  Future<Json?> get(String kind, String id);
  Future<List<Json>> history(String kind, String id);
  Future<Json> put(
    String kind,
    Json value, {
    required int expected,
    required String actor,
    required String reason,
  });
}

class Conflict implements Exception {}

class MemoryRecords implements Records {
  Map<String, List<Json>> _rows = {};
  Future<void> _tail = Future.value();
  @override
  Future<T> transaction<T>(Future<T> Function(RecordSession) action) {
    final result = _tail.then((_) async {
      final copy = _rows.map((k, v) => MapEntry(k, v.map(cloneJson).toList()));
      final value = await action(_MemorySession(copy));
      _rows = copy;
      return value;
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

class _MemorySession implements RecordSession {
  _MemorySession(this.rows);
  final Map<String, List<Json>> rows;
  @override
  Future<List<Json>> list(String kind) async => [
    for (final e in rows.entries)
      if (e.key.startsWith('$kind/')) cloneJson(e.value.last),
  ];
  @override
  Future<Json?> get(String kind, String id) async =>
      rows['$kind/$id'] == null ? null : cloneJson(rows['$kind/$id']!.last);
  @override
  Future<List<Json>> history(String kind, String id) async =>
      (rows['$kind/$id'] ?? []).map(cloneJson).toList();
  @override
  Future<Json> put(
    String kind,
    Json value, {
    required int expected,
    required String actor,
    required String reason,
  }) async {
    final key = '$kind/${value['id']}';
    final versions = rows[key] ?? [];
    if ((versions.isEmpty ? 0 : versions.last['version']) != expected)
      throw Conflict();
    final next = _revision(value, expected, actor, reason);
    rows[key] = [...versions, cloneJson(next)];
    return next;
  }
}

Json _revision(Json value, int expected, String actor, String reason) => {
  ...value,
  'version': expected + 1,
  'actor': actor,
  'reason': reason,
  'updatedAt': DateTime.now().toUtc().toIso8601String(),
};

class PostgresRecords implements Records {
  PostgresRecords(this.db);
  final SessionExecutor db;
  Future<void> migrate() async {
    await db.runTx((tx) async {
      await tx.execute('SELECT pg_advisory_xact_lock(28471823)');
      await tx.execute(
        '''CREATE TABLE IF NOT EXISTS m3_records (
        kind TEXT NOT NULL, id TEXT NOT NULL, version INTEGER NOT NULL CHECK(version>0), document JSONB NOT NULL,
        PRIMARY KEY(kind,id), CHECK(document->>'id'=id), CHECK((document->>'version')::int=version))''',
      );
      await tx.execute(
        '''CREATE TABLE IF NOT EXISTS m3_history (
        kind TEXT NOT NULL,id TEXT NOT NULL,version INTEGER NOT NULL,document JSONB NOT NULL,
        PRIMARY KEY(kind,id,version),FOREIGN KEY(kind,id) REFERENCES m3_records(kind,id))''',
      );
    });
  }

  @override
  Future<T> transaction<T>(Future<T> Function(RecordSession) action) =>
      db.runTx((tx) async {
        await tx.execute('SELECT pg_advisory_xact_lock(28471823)');
        return action(_PostgresSession(tx));
      });
}

class _PostgresSession implements RecordSession {
  _PostgresSession(this.db);
  final TxSession db;
  Json decode(Object? raw) => raw is String
      ? jsonDecode(raw) as Json
      : Map<String, dynamic>.from(raw as Map);
  @override
  Future<List<Json>> list(String kind) async => (await db.execute(
    Sql.named('SELECT document FROM m3_records WHERE kind=@kind ORDER BY id'),
    parameters: {'kind': kind},
  )).map((r) => decode(r[0])).toList();
  @override
  Future<Json?> get(String kind, String id) async {
    final rows = await db.execute(
      Sql.named('SELECT document FROM m3_records WHERE kind=@kind AND id=@id'),
      parameters: {'kind': kind, 'id': id},
    );
    return rows.isEmpty ? null : decode(rows.first[0]);
  }

  @override
  Future<List<Json>> history(String kind, String id) async => (await db.execute(
    Sql.named(
      'SELECT document FROM m3_history WHERE kind=@kind AND id=@id ORDER BY version',
    ),
    parameters: {'kind': kind, 'id': id},
  )).map((r) => decode(r[0])).toList();
  @override
  Future<Json> put(
    String kind,
    Json value, {
    required int expected,
    required String actor,
    required String reason,
  }) async {
    final old = await get(kind, value['id'] as String);
    if ((old?['version'] ?? 0) != expected) throw Conflict();
    final next = _revision(value, expected, actor, reason);
    final params = {
      'kind': kind,
      'id': value['id'],
      'version': expected + 1,
      'document': jsonEncode(next),
    };
    await db.execute(
      Sql.named(
        '''INSERT INTO m3_records(kind,id,version,document) VALUES(@kind,@id,@version,CAST(@document AS jsonb))
      ON CONFLICT(kind,id) DO UPDATE SET version=EXCLUDED.version,document=EXCLUDED.document''',
      ),
      parameters: params,
    );
    await db.execute(
      Sql.named(
        'INSERT INTO m3_history(kind,id,version,document) VALUES(@kind,@id,@version,CAST(@document AS jsonb))',
      ),
      parameters: params,
    );
    return next;
  }
}
