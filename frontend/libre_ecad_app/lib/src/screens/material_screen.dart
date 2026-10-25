import 'dart:convert';
import 'dart:typed_data';

import 'package:ecad_core/ecad_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class MaterialScreen extends StatelessWidget {
  const MaterialScreen({
    super.key,
    required this.project,
    required this.source,
  });
  final Json project;
  final String source;
  @override
  Widget build(BuildContext context) {
    Json packet;
    try {
      packet = materialPacket(project, source: source);
    } catch (e) {
      return Scaffold(
        appBar: AppBar(title: const Text('Materialübergabe')),
        body: Padding(padding: const EdgeInsets.all(24), child: Text('$e')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Materialübergabe · WerkkernERP')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${project['name']} · Arbeitsstand V${project['version']}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Vorschau geplanter Mengen aus dem aktuellen Entwurf. Jede Geräte-ID zählt einmal, auch bei mehreren Darstellungen. Artikelversion und Variante bleiben getrennt. Preise, Lager und Aufträge werden nicht geändert.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              try {
                await FilePicker.saveFile(
                  fileName: 'libre-ecad-material-v${project['version']}.json',
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                  bytes: Uint8List.fromList(utf8.encode(canonicalJson(packet))),
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Importvorschau als JSON speichern'),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Artikel / Version')),
                DataColumn(label: Text('Bezeichnung')),
                DataColumn(label: Text('Menge')),
                DataColumn(label: Text('Einheit')),
                DataColumn(label: Text('Betriebsmittel')),
              ],
              rows: [
                for (final r in packet['items'])
                  DataRow(
                    cells: [
                      DataCell(
                        Text('${r['articleNumber']} / V${r['articleVersion']}'),
                      ),
                      DataCell(Text(r['name'])),
                      DataCell(Text('${r['quantity']}')),
                      DataCell(
                        Text(r['unit'] == 'piece' ? 'Stück' : r['unit']),
                      ),
                      DataCell(Text((r['bmks'] as List).join(', '))),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Ohne Artikelzuordnung (${(packet['unassigned'] as List).length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final r in packet['unassigned'])
            ListTile(
              title: Text('${r['bmk']} · ${r['label']}'),
              subtitle: Text(r['reason']),
            ),
          SelectableText('Paket-ID: ${packet['packetId']}'),
          const Text(
            'Wiederholtes Laden derselben Paket-ID ersetzt die Importvorschau. Im ERP bestehende Artikel ausdrücklich zuordnen; eine Bezeichnung allein ist keine stabile Artikelidentität.',
          ),
        ],
      ),
    );
  }
}
