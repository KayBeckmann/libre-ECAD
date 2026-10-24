import 'dart:convert';
import 'package:ecad_core/ecad_core.dart';

void main() => print(jsonEncode({for (final kind in ['distribution','motor']) kind: sampleDrawing(kind)}));
