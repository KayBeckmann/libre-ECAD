import 'store.dart';

/// Explicit units and nullable values; zero is data, never a stand-in for missing.
Document articleFields(Document d) {
  String text(String key, {int max = 200, bool optional = false}) {
    final v = d[key];
    if (optional && v == null) return '';
    if (v is! String || (!optional && v.trim().isEmpty) || v.length > max) {
      throw FormatException(
        '$key: Text ${optional ? "" : "erforderlich, "}maximal $max Zeichen.',
      );
    }
    return v.trim();
  }

  final raw = d['layers'];
  if (raw is! Map<String, dynamic>)
    throw FormatException('layers ist erforderlich.');
  final layers = <String, dynamic>{};
  const numericFields = {
    'mechanical': ['widthMm', 'heightMm', 'depthMm'],
    'electrical': ['voltageV', 'currentA'],
    'thermal': ['powerLossW'],
  };
  for (final name in ['symbol', 'mechanical', 'electrical', 'thermal']) {
    final layer = raw[name] ?? <String, dynamic>{};
    if (layer is! Map<String, dynamic>)
      throw FormatException('Ungültige Ebene: $name');
    final clean = <String, dynamic>{'status': 'unverified'};
    for (final key in numericFields[name] ?? <String>[]) {
      final v = layer[key];
      if (v != null && (v is! num || !v.isFinite || v < 0 || v > 1e9)) {
        throw FormatException(
          '$key muss eine endliche, nicht negative Zahl sein.',
        );
      }
      clean[key] = v;
    }
    for (final key in switch (name) {
      'symbol' => ['reference', 'license'],
      'mechanical' => ['viewReference'],
      'thermal' => ['conditions'],
      _ => <String>[],
    }) {
      final v = layer[key] ?? '';
      if (v is! String || v.length > 2000)
        throw FormatException('$key: maximal 2000 Zeichen.');
      clean[key] = v.trim();
    }
    if (name == 'symbol') {
      final terminals = layer['terminals'] ?? <dynamic>[];
      if (terminals is! List || terminals.length > 256)
        throw FormatException('Maximal 256 Anschlüsse.');
      final ids = <String>{};
      clean['terminals'] = <Document>[];
      for (final t in terminals) {
        if (t is! Map ||
            t['id'] is! String ||
            (t['id'] as String).trim().isEmpty ||
            (t['id'] as String).length > 100 ||
            !ids.add(t['id'] as String) ||
            t['label'] is! String ||
            (t['label'] as String).length > 100) {
          throw FormatException(
            'Anschlüsse brauchen eindeutige IDs und Bezeichnungen (max. 100 Zeichen).',
          );
        }
        (clean['terminals'] as List).add({'id': t['id'], 'label': t['label']});
      }
    }
    layers[name] = clean;
  }
  return {
    'articleNumber': text('articleNumber'),
    'name': text('name'),
    'license': text('license', max: 1000),
    'origin': text('origin', max: 2000),
    'notes': text('notes', max: 4000, optional: true),
    'layers': layers,
  };
}

Document withArticleWarnings(Document a) {
  final layers = a['layers'] as Map;
  final symbol = layers['symbol'] as Map;
  const labels = {
    'widthMm': 'Breite [mm]',
    'heightMm': 'Höhe [mm]',
    'depthMm': 'Tiefe [mm]',
    'voltageV': 'Nennspannung [V]',
    'currentA': 'Nennstrom [A]',
    'powerLossW': 'Verlustleistung [W]',
  };
  final missing = <String>[];
  if ((symbol['reference'] as String).isEmpty)
    missing.add('Schaltsymbol-Referenz fehlt');
  if ((symbol['license'] as String).isEmpty)
    missing.add('Symbollizenz ungeklärt');
  if ((symbol['terminals'] as List).isEmpty)
    missing.add('Anschlussbelegung fehlt');
  for (final entry in {
    'mechanical': ['widthMm', 'heightMm', 'depthMm'],
    'electrical': ['voltageV', 'currentA'],
    'thermal': ['powerLossW'],
  }.entries) {
    for (final field in entry.value) {
      if ((layers[entry.key] as Map)[field] == null)
        missing.add('${labels[field]} fehlt');
    }
  }
  if (((layers['thermal'] as Map)['conditions'] as String).isEmpty)
    missing.add('Thermische Einsatzbedingungen fehlen');
  return {
    ...a,
    'warnings': [
      'Ungeprüfte Eingaben – keine Berechnungs- oder Normfreigabe.',
      ...missing,
    ],
  };
}
