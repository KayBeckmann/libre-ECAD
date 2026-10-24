/// Original synthetic teaching glyphs, covered by the repository MIT license.
/// No standards database or manufacturer symbol is embedded.
class SymbolDefinition {
  const SymbolDefinition(
    this.key,
    this.name,
    this.group,
    this.deviceType,
    this.code,
    this.ports,
    this.allPorts,
  );
  final String key, name, group, deviceType, code;
  final List<String> ports, allPorts;
}

const symbolLibrary = <SymbolDefinition>[
  SymbolDefinition(
    'supply',
    'Einspeisung',
    'Verteilerabgang',
    'supply',
    'G',
    ['L', 'N'],
    ['L', 'N'],
  ),
  SymbolDefinition(
    'breaker',
    'Schutzgerät',
    'Verteilerabgang',
    'breaker',
    'Q',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'terminal',
    'Klemme',
    'Verteilerabgang',
    'terminal',
    'X',
    ['1'],
    ['1'],
  ),
  SymbolDefinition(
    'switch',
    'Schalter',
    'Steuer- / Motorabgang',
    'switch',
    'S',
    ['1', '2'],
    ['1', '2'],
  ),
  SymbolDefinition(
    'coil',
    'Relaisspule',
    'Steuer- / Motorabgang',
    'relay',
    'K',
    ['A1', 'A2'],
    ['A1', 'A2', '13', '14'],
  ),
  SymbolDefinition(
    'contact',
    'Relaiskontakt',
    'Steuer- / Motorabgang',
    'relay',
    'K',
    ['13', '14'],
    ['A1', 'A2', '13', '14'],
  ),
  SymbolDefinition(
    'motor',
    'Motor',
    'Steuer- / Motorabgang',
    'motor',
    'M',
    ['U', 'V', 'W', 'PE'],
    ['U', 'V', 'W', 'PE'],
  ),
];

SymbolDefinition symbolByKey(String key) => symbolLibrary.firstWhere(
  (s) => s.key == key,
  orElse: () => throw FormatException('Unbekanntes Symbol: $key'),
);
