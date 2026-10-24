/// User-facing descriptions without exposing storage maps or internal field names.
String articleSourceText(Object? value) {
  if (value is! Map) return 'Eigener Entwurf';
  final area = value['kind'] == 'global'
      ? 'Globaler Katalog'
      : value['scope'] == 'company'
      ? 'Firmenstamm'
      : 'Persönlicher Stamm';
  final manufacturer = value['manufacturerName'];
  return '$area${manufacturer == null ? '' : ' / $manufacturer'} · Version ${value['version']}\nQuellartikel: ${value['articleId']}';
}

String articleVersionText(Map<String, dynamic> article) {
  final layers = article['layers'] as Map;
  final symbol = layers['symbol'] as Map;
  final mechanical = layers['mechanical'] as Map;
  final electrical = layers['electrical'] as Map;
  final thermal = layers['thermal'] as Map;
  String val(Object? v) => v == null || v == '' ? 'unbekannt' : '$v';
  final terminals = (symbol['terminals'] as List)
      .map((t) => '${t['id']}: ${t['label']}')
      .join(', ');
  return '${article['articleNumber']} · ${article['name']}\n'
      'Herkunft: ${article['origin']}\nLizenz: ${article['license']}\n'
      '${articleSourceText(article['source'])}\n'
      'Symbol: ${val(symbol['reference'])} · Rechte: ${val(symbol['license'])}\n'
      'Anschlüsse: ${terminals.isEmpty ? 'nicht erfasst' : terminals}\n'
      'Maße (B × H × T) [mm]: ${val(mechanical['widthMm'])} × ${val(mechanical['heightMm'])} × ${val(mechanical['depthMm'])}\n'
      'Ansicht: ${val(mechanical['viewReference'])}\n'
      'Nennspannung [V]: ${val(electrical['voltageV'])} · Nennstrom [A]: ${val(electrical['currentA'])}\n'
      'Verlustleistung [W]: ${val(thermal['powerLossW'])}\nBedingungen: ${val(thermal['conditions'])}\n'
      'Notizen: ${val(article['notes'])}';
}
