import 'dart:convert';
import 'package:postgres/postgres.dart';

typedef Document = Map<String, dynamic>;

abstract class WorkspaceStore {
  Future<List<Document>> list(String companyId, String kind);
  Future<Document?> get(String companyId, String kind, String id);
  Future<void> create(String companyId, String kind, Document document);

  /// Atomic compare-and-swap; stale clients must explicitly reload and decide.
  Future<bool> update(
    String companyId,
    String kind,
    Document document,
    int expectedVersion,
  );
  Future<List<Document>> history(String companyId, String kind, String id);
}

Document _copy(Document document) =>
    jsonDecode(jsonEncode(document)) as Document;

class MemoryWorkspaceStore implements WorkspaceStore {
  final _rows = <String, List<Document>>{};
  String _key(String company, String kind, String id) => '$company/$kind/$id';
  @override
  Future<List<Document>> list(String companyId, String kind) async => [
    for (final entry in _rows.entries)
      if (entry.key.startsWith('$companyId/$kind/')) _copy(entry.value.last),
  ];
  @override
  Future<Document?> get(String companyId, String kind, String id) async {
    final versions = _rows[_key(companyId, kind, id)];
    return versions == null ? null : _copy(versions.last);
  }

  @override
  Future<void> create(String companyId, String kind, Document document) async {
    final key = _key(companyId, kind, document['id'] as String);
    if (_rows.containsKey(key)) throw StateError('Duplicate ID');
    _rows[key] = [_copy(document)];
  }

  @override
  Future<bool> update(
    String companyId,
    String kind,
    Document document,
    int expectedVersion,
  ) async {
    final versions = _rows[_key(companyId, kind, document['id'] as String)];
    if (versions == null || versions.last['version'] != expectedVersion)
      return false;
    versions.add(_copy(document));
    return true;
  }

  @override
  Future<List<Document>> history(
    String companyId,
    String kind,
    String id,
  ) async => (_rows[_key(companyId, kind, id)] ?? []).map(_copy).toList();
}

class PostgresWorkspaceStore implements WorkspaceStore {
  PostgresWorkspaceStore(this.db);
  final Connection db;
  Document _decode(Object? raw) => raw is String
      ? jsonDecode(raw) as Document
      : Map<String, dynamic>.from(raw as Map);
  @override
  Future<List<Document>> list(String companyId, String kind) async {
    final rows = await db.execute(
      Sql.named(
        'SELECT document FROM workspace_documents '
        'WHERE company_id=@company AND kind=@kind ORDER BY id',
      ),
      parameters: {'company': companyId, 'kind': kind},
    );
    return rows.map((row) => _decode(row[0])).toList();
  }

  @override
  Future<Document?> get(String companyId, String kind, String id) async {
    final rows = await db.execute(
      Sql.named(
        'SELECT document FROM workspace_documents '
        'WHERE company_id=@company AND kind=@kind AND id=@id',
      ),
      parameters: {'company': companyId, 'kind': kind, 'id': id},
    );
    return rows.isEmpty ? null : _decode(rows.first[0]);
  }

  @override
  Future<void> create(String companyId, String kind, Document document) async {
    // A single statement makes document + immutable history atomic.
    await db.execute(
      Sql.named('''
      WITH inserted AS (
        INSERT INTO workspace_documents(company_id,kind,id,version,document)
        VALUES (@company,@kind,@id,1,CAST(@document AS jsonb)) RETURNING *
      ) INSERT INTO workspace_history(company_id,kind,id,version,document)
        SELECT company_id,kind,id,version,document FROM inserted
    '''),
      parameters: {
        'company': companyId,
        'kind': kind,
        'id': document['id'],
        'document': jsonEncode(document),
      },
    );
  }

  @override
  Future<bool> update(
    String companyId,
    String kind,
    Document document,
    int expectedVersion,
  ) async {
    final rows = await db.execute(
      Sql.named('''
      WITH updated AS (
        UPDATE workspace_documents SET version=version+1, document=CAST(@document AS jsonb)
        WHERE company_id=@company AND kind=@kind AND id=@id AND version=@expected RETURNING *
      ) INSERT INTO workspace_history(company_id,kind,id,version,document)
        SELECT company_id,kind,id,version,document FROM updated RETURNING version
    '''),
      parameters: {
        'company': companyId,
        'kind': kind,
        'id': document['id'],
        'document': jsonEncode(document),
        'expected': expectedVersion,
      },
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<Document>> history(
    String companyId,
    String kind,
    String id,
  ) async {
    final rows = await db.execute(
      Sql.named(
        'SELECT document FROM workspace_history '
        'WHERE company_id=@company AND kind=@kind AND id=@id ORDER BY version',
      ),
      parameters: {'company': companyId, 'kind': kind, 'id': id},
    );
    return rows.map((row) => _decode(row[0])).toList();
  }
}
