import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ecad_core/ecad_core.dart';
import 'package:ecad_documents/ecad_documents.dart' as pdf;

import '../api/workspace_api.dart';
import '../api/company_users_api.dart';
import '../models.dart';
import 'vault.dart';

class OfflineApi extends WorkspaceApi {
  OfflineApi(this.vault, this.packetId) : super(_session(vault.get(packetId)));
  final OfflineVault vault;
  final String packetId;
  static Session _session(Json p) => Session(
    token: '',
    username: p['username'],
    role: UserRole.zeichner,
    companyName: p['companyName'],
    backendUrl: Uri.parse(p['backendUrl']),
  );
  @override
  bool get isOffline => true;
  @override
  Future<Json> request(String method, String path, [Json? body]) async {
    final p = vault.get(packetId);
    vault.check(p);
    final project = p['project'] as Json;
    final base = 'projects/${project['id']}';
    Json drawingResponse() => {
      'projectId': project['id'],
      'projectName':
          '${project['name']} · OFFLINE · lokal ${p['localRevision']}',
      'version': p['baseVersion'],
      'drawing': project['drawing'],
      'updatedAt': p['issuedAt'],
      'updatedBy': p['userId'],
    };
    if (path == '$base/drawing') {
      if (method == 'GET') return drawingResponse();
      if (method == 'PUT') {
        if (body?['version'] != p['baseVersion']) {
          throw ApiException(
            'Lokale Basis stimmt nicht überein.',
            statusCode: 409,
          );
        }
        project['drawing'] = validateDrawing(body?['drawing']);
        p['localRevision'] = (p['localRevision'] as int) + 1;
        await vault.put(p);
        return drawingResponse();
      }
    }
    if (method == 'GET' && path == '$base/drawing/history') {
      return {
        'versions': [drawingResponse()],
      };
    }
    if (method == 'GET' && path == '$base/releases') {
      return {'releases': <Json>[]};
    }
    if (method == 'GET' &&
        path == '$base/documents?version=${p['baseVersion']}') {
      final regular = await rootBundle.load(
        'assets/fonts/NotoSans-Regular.ttf',
      );
      final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      return {
        'source': 'offline',
        'project': project,
        'data': documentData(project),
        'findings': drawingFindings(project['drawing']),
        'pdf': base64Encode(
          await pdf.projectPdf(
            project,
            status: 'OFFLINE-ENTWURF - NICHT FREIGEGEBEN',
            stamp: 'Basis V${p['baseVersion']} / lokal ${p['localRevision']}',
            regularFont: regular.buffer.asUint8List(
              regular.offsetInBytes,
              regular.lengthInBytes,
            ),
            boldFont: bold.buffer.asUint8List(
              bold.offsetInBytes,
              bold.lengthInBytes,
            ),
          ),
        ),
      };
    }
    throw ApiException(
      'Diese Aktion ist offline nicht verfügbar. Es erfolgt kein Netzwerkzugriff.',
      statusCode: 403,
    );
  }
}
