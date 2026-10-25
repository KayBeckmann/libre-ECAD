import 'dart:io';
import 'dart:typed_data';
import 'package:ecad_core/ecad_core.dart';
import 'package:ecad_documents/ecad_documents.dart' as renderer;
export 'package:ecad_documents/ecad_documents.dart' show sheetSvg;

Future<Uint8List> projectPdf(
  Json project, {
  required String status,
  required String stamp,
  Json? approval,
}) async {
  final root = Platform.environment['PDF_FONT_DIR'] ?? 'assets/fonts';
  return renderer.projectPdf(
    project,
    status: status,
    stamp: stamp,
    approval: approval,
    regularFont: await File('$root/NotoSans-Regular.ttf').readAsBytes(),
    boldFont: await File('$root/NotoSans-Bold.ttf').readAsBytes(),
  );
}
