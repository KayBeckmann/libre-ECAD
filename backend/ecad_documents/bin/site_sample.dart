// Synthetic preview rendered by the same engine as project SVG exports.
import 'dart:io';
import 'package:ecad_core/ecad_core.dart';
import 'package:ecad_documents/ecad_documents.dart';

void main() {
  final drawing = sampleDrawing('three-phase');
  stdout.write(sheetSvg(drawing, (drawing['sheets'] as List).first['id']));
}
