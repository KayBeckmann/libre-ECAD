import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Einheitliche JSON-Antworten für alle Dienste — ein Fehlerformat,
/// das Frontend und API-Clients gleich auswerten können, statt jeder
/// Dienst erfindet sein eigenes.
Response jsonOk(Object? body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Response jsonError(String message, {int status = 400}) => jsonOk({'error': message}, status: status);

Response healthResponse() => jsonOk({'status': 'ok'});
