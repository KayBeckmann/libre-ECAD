import 'package:ecad_core/ecad_core.dart';
import 'package:flutter/material.dart';

class CalculationsScreen extends StatefulWidget {
  const CalculationsScreen({
    super.key,
    required this.drawing,
    required this.editable,
  });
  final Json drawing;
  final bool editable;
  @override
  State<CalculationsScreen> createState() => _CalculationsScreenState();
}

class _CalculationsScreenState extends State<CalculationsScreen> {
  late Json d = cloneJson(widget.drawing);
  String? error;
  bool get enabled =>
      widget.editable &&
      MediaQuery.sizeOf(context).width >= 1000 &&
      MediaQuery.sizeOf(context).height -
              kToolbarHeight -
              MediaQuery.paddingOf(context).vertical >=
          500;
  Future<void> edit(String kind, [Json? old]) async {
    final name = TextEditingController(text: old?['name'] ?? ''),
        source = TextEditingController(text: old?['source'] ?? ''),
        conditions = TextEditingController(text: old?['conditions'] ?? '');
    final inputs = {
      for (final k in calculationFields[kind]!.keys)
        k: TextEditingController(text: '${old?['inputs']?[k] ?? ''}'),
    };
    var phase = old?['phase'] ?? 'balanced3';
    String? route = old?['routeId'];
    final devices = <String>{
      ...(old?['deviceIds'] as List? ?? []).cast<String>(),
    };
    final routes = <Json>[
      for (final p in d['plans'] ?? []) ...p['routes'] ?? [],
    ];
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(
            kind == 'voltage' ? 'Leitung / Spannungsfall' : 'Wärmebilanz',
          ),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Rechenvorschlag ohne Normfreigabe. Herstellerdaten und Einsatzbedingungen ausdrücklich angeben. Fehlende Angaben ergeben kein Ergebnis.',
                  ),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Bezeichnung'),
                  ),
                  TextField(
                    controller: source,
                    decoration: const InputDecoration(
                      labelText: 'Datenquelle / Hersteller / Revision',
                    ),
                  ),
                  TextField(
                    controller: conditions,
                    decoration: const InputDecoration(
                      labelText: 'Einsatzbedingungen / Temperatur / Verlegung',
                    ),
                  ),
                  if (kind == 'voltage') ...[
                    DropdownButtonFormField<String>(
                      initialValue: phase,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: 'single',
                          child: Text('Einphasig, Hin- und Rückleiter'),
                        ),
                        DropdownMenuItem(
                          value: 'balanced3',
                          child: Text('Dreiphasig, symmetrische Last'),
                        ),
                      ],
                      onChanged: (v) => set(() => phase = v),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: route ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Längenquelle',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Manuell eingetragene Länge'),
                        ),
                        for (final r in routes)
                          DropdownMenuItem(
                            value: r['id'],
                            child: Text(r['name']),
                          ),
                      ],
                      onChanged: (v) => set(() => route = v == '' ? null : v),
                    ),
                  ],
                  for (final e in calculationFields[kind]!.entries)
                    TextField(
                      controller: inputs[e.key],
                      enabled: e.key != 'lengthM' || route == null,
                      decoration: InputDecoration(labelText: e.value),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  if (kind == 'thermal') ...[
                    const Text(
                      'Verlustleistung aus gespeicherten Artikelversionen:',
                    ),
                    for (final dev in objects(d, 'devices'))
                      CheckboxListTile(
                        value: devices.contains(dev['id']),
                        title: Text(
                          '${dev['bmk']} · ${dev['article']?['powerLossW'] ?? '?'} W',
                        ),
                        subtitle: Text(
                          dev['article']?['thermalConditions'] ??
                              'Bezugsbedingungen fehlen',
                        ),
                        onChanged: (v) => set(() {
                          if (v == true) {
                            devices.add(dev['id']);
                          } else {
                            devices.remove(dev['id']);
                          }
                        }),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Rechenfall übernehmen'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted && enabled) {
      try {
        final input = <String, dynamic>{};
        for (final e in inputs.entries) {
          final text = e.value.text.trim();
          final value = num.tryParse(text.replaceAll(',', '.'));
          if (text.isNotEmpty && value == null) {
            throw FormatException(
              '${calculationFields[kind]![e.key]}: Zahl erwartet.',
            );
          }
          input[e.key] = value;
        }
        final row = {
          'id': old?['id'] ?? newId(),
          'name': name.text,
          'kind': kind,
          'source': source.text,
          'conditions': conditions.text,
          'inputs': input,
          if (kind == 'voltage') 'phase': phase,
          'routeId': ?route,
          if (kind == 'thermal') 'deviceIds': devices.toList(),
        };
        final next = cloneJson(d),
            list = next.putIfAbsent('calculations', () => []) as List;
        list.removeWhere((v) => v['id'] == row['id']);
        list.add(row);
        validateDrawing(next);
        setState(() {
          d = next;
          error = null;
        });
      } catch (e) {
        setState(() => error = '$e');
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in [name, source, conditions, ...inputs.values]) {
      c.dispose();
    }
  }

  String display(Object? v) => v is num
      ? v.toStringAsFixed(3)
      : v == true
      ? 'ja'
      : v == false
      ? 'nein'
      : '$v';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Berechnungen'),
      actions: [
        TextButton(
          onPressed: enabled
              ? () => Navigator.pop(context, validateDrawing(d))
              : null,
          child: const Text('Rechenfälle übernehmen'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const Text(
          'Alle Ergebnisse werden aus dem aktuellen Entwurf abgeleitet. Änderungen an Leitungswegen, Maßstab und Artikelverlustleistung werden beim nächsten Öffnen und im PDF neu berechnet.',
        ),
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: enabled ? () => edit('voltage') : null,
              child: const Text('Leitung / Spannungsfall'),
            ),
            OutlinedButton(
              onPressed: enabled ? () => edit('thermal') : null,
              child: const Text('Wärmebilanz'),
            ),
          ],
        ),
        for (final c in (d['calculations'] as List? ?? []).cast<Json>()) ...[
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  c['name'],
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Rechenfall bearbeiten',
                onPressed: enabled ? () => edit(c['kind'], c) : null,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Rechenfall entfernen',
                onPressed: enabled
                    ? () =>
                          setState(() => (d['calculations'] as List).remove(c))
                    : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Builder(
            builder: (context) {
              final result = calculate(d, c);
              return Semantics(
                container: true,
                explicitChildNodes: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result['status'] == 'incomplete'
                          ? 'UNVOLLSTÄNDIG – kein Ergebnis'
                          : 'UNGEPRÜFTER RECHENVORSCHLAG',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text('${c['source']}\n${c['conditions']}'),
                    for (final e in (result['inputs'] as Json).entries)
                      Text(
                        '${calculationFields[c['kind']]![e.key]}: ${display(e.value)}',
                      ),
                    const SizedBox(height: 12),
                    for (final e in (result['results'] as Json).entries)
                      Text(
                        '${calculationResultLabels[e.key] ?? e.key}: ${display(e.value)}',
                      ),
                    for (final message in result['messages'])
                      Text('• $message'),
                    Text('Rechengrundlage: ${result['reference']}'),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    ),
  );
}
