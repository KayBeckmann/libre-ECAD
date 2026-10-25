import 'dart:convert';
import 'package:ecad_core/ecad_core.dart';

void main() {
  final d = emptyDrawing(), sid = objects(emptyDrawing(), 'sheets').first['id'];
  d['sheets'] = [
    {'id': sid, 'number': 1, 'title': 'TEST Nachtrag · Relaisgruppe'},
    {'id': newId(), 'number': 2, 'title': 'TEST Zielblatt'},
  ];
  final coil = addSymbol(d, 'coil', sid, 200, 240);
  final no = addSymbol(d, 'contact', sid, 440, 240, deviceId: coil['deviceId']);
  final nc = addSymbol(d, 'contact_nc', sid, 680, 240, deviceId: coil['deviceId']);
  addSymbol(d, 'motor', sid, 1000, 520);
  d['wires'] = [
    {'id': newId(), 'sheetId': sid, 'from': portRef(coil['id'], 'A1'), 'to': portRef(no['id'], instancePorts(d, no).first)},
    {'id': newId(), 'sheetId': sid, 'from': portRef(no['id'], instancePorts(d, no).last), 'to': portRef(nc['id'], instancePorts(d, nc).first)},
  ];
  print(jsonEncode(validateDrawing(d)));
}
