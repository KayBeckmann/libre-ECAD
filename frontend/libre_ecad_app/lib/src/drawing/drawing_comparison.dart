import 'dart:convert';

import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';

import 'drawing_canvas.dart';

/// Read-only, independently navigable sheets with exact data available beside them.
class DrawingComparison extends StatelessWidget {
  const DrawingComparison({
    super.key,
    required this.left,
    required this.right,
    required this.leftTitle,
    required this.rightTitle,
  });
  final Json left, right;
  final String leftTitle, rightTitle;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Pläne vergleichen'),
            Tab(text: 'Daten vergleichen'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Preview(drawing: left, title: leftTitle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Preview(drawing: right, title: rightTitle),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _data(leftTitle, left)),
                  const VerticalDivider(),
                  Expanded(child: _data(rightTitle, right)),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _data(String title, Json d) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      Expanded(
        child: SingleChildScrollView(
          child: SelectableText(
            const JsonEncoder.withIndent('  ').convert(d),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    ],
  );
}

class _Preview extends StatefulWidget {
  const _Preview({required this.drawing, required this.title});
  final Json drawing;
  final String title;
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  String? sheet;
  @override
  Widget build(BuildContext context) {
    final sheets = objects(widget.drawing, 'sheets');
    if (sheets.isEmpty) {
      return Center(child: Text('${widget.title}: keine Blätter'));
    }
    final id = sheet ?? sheets.first['id'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          value: id,
          isExpanded: true,
          items: [
            for (final s in sheets)
              DropdownMenuItem(
                value: s['id'],
                child: Text(
                  '${s['number']} · ${s['title']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => sheet = v),
        ),
        Expanded(
          child: DrawingCanvas(
            key: ValueKey(id),
            drawing: widget.drawing,
            sheetId: id,
            projectName: widget.title,
            version: 0,
            selected: null,
            editable: false,
            onTap: (_) {},
            onSelect: (_) {},
            onMove: (_, _) {},
            onPort: (_) {},
          ),
        ),
      ],
    );
  }
}
