import 'dart:math' as math;
import 'drawing.dart';
import 'planning.dart';

/// Explicit engineering estimates. No embedded normative tables or automatic sizing.
const calculationReferences = {
  'voltage':
      'https://www.electrical-installation.org/enwiki/Calculation_of_voltage_drop_in_steady_load_conditions',
  'thermal':
      'https://info.rittalenclosures.com/hubfs/PDFs_-_White_Papers/Brochure-Technical-Aspects-of-Enclosures.pdf',
};
const calculationFields = {
  'voltage': {
    'currentA': 'Betriebsstrom [A]',
    'voltageV': 'Nennspannung [V]',
    'lengthM': 'Leitungslänge einfach [m]',
    'areaMm2': 'Gewählter Querschnitt [mm²]',
    'resistanceOhmPerKm': 'Widerstand bei Betriebstemperatur [Ω/km]',
    'reactanceOhmPerKm': 'Reaktanz [Ω/km]',
    'cosPhi': 'cos φ (induktiv)',
    'limitPercent': 'Projektgrenze Spannungsfall [%]',
    'ampacityA': 'Strombelastbarkeit im gewählten Einsatzfall [A]',
    'breakerA': 'Bemessungsstrom Schutzgerät [A]',
  },
  'thermal': {
    'ambientC': 'Umgebung [°C]',
    'insideC': 'Zieltemperatur innen [°C]',
    'areaM2': 'Wirksame Gehäusefläche [m²]',
    'coefficient': 'Wärmedurchgang [W/(m²·K)]',
  },
};
const calculationResultLabels = {
  'factor': 'Leiterfaktor',
  'sinPhi': 'sin φ',
  'impedanceTermOhmPerKm': 'R·cos φ + X·sin φ [Ω/km]',
  'lengthKm': 'Rechenlänge [km]',
  'dropV': 'Spannungsfall [V]',
  'dropPercent': 'Spannungsfall [%]',
  'withinEnteredLimit': 'Eingegebene Projektgrenze eingehalten',
  'currentRelation': 'Ib ≤ In ≤ Iz nach Eingaben',
  'minimumAreaVoltageMm2':
      'Rechnerischer Mindestquerschnitt nur für Spannungsfall [mm²]',
  'reactanceDropV': 'Spannungsfallanteil der Reaktanz [V]',
  'deviceLossW': 'Summe Geräteverlustleistung [W]',
  'deltaK': 'Temperaturdifferenz [K]',
  'surfaceDissipationW': 'Wärmeabgabe über Fläche [W]',
  'requiredCoolingW': 'Verbleibende Kühlleistung [W]',
  'requiredHeatingW': 'Verbleibende Heizleistung [W]',
};
void validateCalculations(Json d) {
  final raw = d['calculations'] ?? [];
  final ids = <String>{};
  if (raw is! List || raw.length > 100)
    throw const FormatException('Maximal 100 Rechenfälle.');
  for (final c in raw) {
    if (c is! Json ||
        c.keys.any(
          (k) => !{
            'id',
            'name',
            'kind',
            'source',
            'conditions',
            'inputs',
            'phase',
            'routeId',
            'deviceIds',
          }.contains(k),
        ) ||
        !calculationFields.containsKey(c['kind']))
      throw const FormatException('Ungültiger Rechenfall.');
    for (final k in ['id', 'name', 'source', 'conditions'])
      if (c[k] is! String || c[k].length > 2000)
        throw const FormatException('Ungültiger Rechenfalltext.');
    if (c['id'].isEmpty || c['name'].trim().isEmpty || !ids.add(c['id']))
      throw const FormatException('Name/ID des Rechenfalls erforderlich.');
    if (c['inputs'] is! Json)
      throw const FormatException('Recheneingaben fehlen.');
    for (final e in (c['inputs'] as Json).entries)
      if (!calculationFields[c['kind']]!.containsKey(e.key) ||
          (e.value != null &&
              (e.value is! num ||
                  !(e.value as num).isFinite ||
                  (e.value as num).abs() > 1e9)))
        throw const FormatException('Ungültiger Rechenwert.');
    if (c['kind'] == 'voltage' && !['single', 'balanced3'].contains(c['phase']))
      throw const FormatException(
        'Einphasig oder symmetrisch dreiphasig wählen.',
      );
    if (c['routeId'] != null &&
        !(d['plans'] as List? ?? []).any(
          (p) =>
              (p['routes'] as List? ?? []).any((r) => r['id'] == c['routeId']),
        ))
      throw const FormatException('Leitungsweg des Rechenfalls fehlt.');
    if (c['kind'] == 'thermal' &&
        (c['deviceIds'] is! List ||
            c['deviceIds'].length > 500 ||
            c['deviceIds'].toSet().length != c['deviceIds'].length ||
            c['deviceIds'].any(
              (id) => !objects(d, 'devices').any((v) => v['id'] == id),
            )))
      throw const FormatException('Geräte des Wärmefalls fehlen.');
  }
}

Json calculate(Json d, Json c) {
  final input = <String, dynamic>{...c['inputs'] as Json}, missing = <String>[];
  final result = <String, dynamic>{
    'id': c['id'],
    'name': c['name'],
    'kind': c['kind'],
    'reference': calculationReferences[c['kind']],
    'source': c['source'],
    'conditions': c['conditions'],
    'status': 'incomplete',
    'inputs': input,
    'messages': missing,
    'results': <String, dynamic>{},
  };
  if ((c['source'] as String).trim().isEmpty)
    missing.add('Herkunft der Eingangsdaten fehlt.');
  if ((c['conditions'] as String).trim().isEmpty)
    missing.add('Einsatzbedingungen fehlen.');
  if (c['routeId'] != null) {
    final p = (d['plans'] as List).cast<Json>().firstWhere(
      (p) => (p['routes'] as List? ?? []).any((r) => r['id'] == c['routeId']),
    );
    input['lengthM'] = routeLength(
      d,
      p,
      (p['routes'] as List).cast<Json>().firstWhere(
        (r) => r['id'] == c['routeId'],
      ),
    )['metres'];
  }
  for (final key in calculationFields[c['kind']]!.keys) {
    final v = input[key];
    if (v is! num ||
        !v.isFinite ||
        (['ambientC', 'insideC'].contains(key)
            ? v < -273.15
            : ['reactanceOhmPerKm'].contains(key)
            ? v < 0
            : v <= 0))
      missing.add(
        '${calculationFields[c['kind']]![key]} fehlt oder ist unplausibel.',
      );
  }
  if (c['kind'] == 'voltage') {
    if (input['cosPhi'] is num && input['cosPhi'] > 1)
      missing.add('cos φ muss zwischen 0 und 1 liegen.');
    if (missing.isNotEmpty) return result;
    final cos = (input['cosPhi'] as num).toDouble(),
        sin = math.sqrt(1 - cos * cos),
        factor = c['phase'] == 'single' ? 2.0 : math.sqrt(3);
    final r = (input['resistanceOhmPerKm'] as num),
        x = (input['reactanceOhmPerKm'] as num),
        length = (input['lengthM'] as num) / 1000,
        current = input['currentA'] as num;
    final drop = factor * current * length * (r * cos + x * sin),
        percent = drop / (input['voltageV'] as num) * 100;
    final reactanceDrop = factor * current * length * x * sin;
    final resistiveBudget =
        (input['voltageV'] as num) * (input['limitPercent'] as num) / 100 -
        reactanceDrop;
    result['results'] = {
      'reactanceDropV': reactanceDrop,
      if (resistiveBudget > 0)
        'minimumAreaVoltageMm2':
            factor *
            current *
            length *
            r *
            (input['areaMm2'] as num) *
            cos /
            resistiveBudget,
      'factor': factor,
      'sinPhi': sin,
      'impedanceTermOhmPerKm': r * cos + x * sin,
      'lengthKm': length,
      'dropV': drop,
      'dropPercent': percent,
      'withinEnteredLimit': percent <= (input['limitPercent'] as num),
      'currentRelation':
          current <= input['breakerA'] &&
          input['breakerA'] <= input['ampacityA'],
    };
    if (resistiveBudget <= 0)
      missing.add(
        'Reaktanzanteil erreicht die Projektgrenze bereits. Kein endlicher Querschnitt löst dies unter den eingegebenen Annahmen.',
      );
    missing.add(
      'Querschnitt nur aus Spannungsfall mit R·S konstant: gleiches Leitermaterial und gleiche Temperatur, unveränderte Reaktanz. Keine Normquerschnitt-Auswahl; Strombelastbarkeit und Herstellerdaten für einen geänderten Querschnitt neu prüfen.',
    );
    missing.add(
      'Nur Spannungsfall und eingegebene Stromrelation. Kurzschluss, Abschaltung, Verlegung, Häufung und Schutzkoordination separat prüfen. Kein automatisch empfohlener Querschnitt.',
    );
  } else {
    var loss = 0.0;
    final deviceIds = (c['deviceIds'] as List);
    if (deviceIds.isEmpty)
      missing.add('Keine Geräte für die Wärmebilanz gewählt.');
    for (final id in deviceIds) {
      final dev = objectById(d, 'devices', id), a = dev['article'];
      if (a == null ||
          a['powerLossW'] == null ||
          (a['thermalConditions'] as String).trim().isEmpty) {
        missing.add(
          '${dev['bmk']}: Verlustleistung oder Bezugsbedingungen fehlen.',
        );
      } else {
        loss += (a['powerLossW'] as num).toDouble();
      }
    }
    if (missing.isNotEmpty) return result;
    final delta = (input['insideC'] as num) - (input['ambientC'] as num),
        surface =
            (input['coefficient'] as num) * (input['areaM2'] as num) * delta;
    result['results'] = {
      'deviceLossW': loss,
      'deltaK': delta,
      'surfaceDissipationW': surface,
      'requiredCoolingW': math.max(0, loss - surface),
      'requiredHeatingW': math.max(0, surface - loss),
    };
    missing.add(
      'Stationäre Überschlagsbilanz mit eingegebener wirksamer Fläche. Einbau, Lüftung, Hotspots und Betriebsbedingungen separat prüfen.',
    );
  }
  result['status'] = 'estimate';
  missing.add('Ungeprüfter Rechenvorschlag; keine Norm- oder Anlagenfreigabe.');
  return result;
}
