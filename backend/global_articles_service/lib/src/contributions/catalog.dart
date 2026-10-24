import 'package:shared_server_kit/shared_server_kit.dart';
import '../repository.dart';

/// Private workflow records are never returned by the public catalog API.
class ContributionCatalog {
  ContributionCatalog(this.records, this.seeds);
  final Records records;
  final ArticleRepository seeds;
  Future<List<Json>> publicArticles() => records.transaction(
    (tx) async => [
      for (final d in await tx.list('contribution'))
        if (d['published'] != null)
          Map<String, dynamic>.from(d['published'] as Map),
    ],
  );
  Future<Json?> publicArticle(String id) => records.transaction((tx) async {
    final d = await tx.get('contribution', id);
    return d?['published'] as Json?;
  });
  Future<List<Json>> publicHistory(String id) =>
      records.transaction((tx) async {
        final revisions = await tx.history('contribution', id);
        return [
          for (final d in revisions)
            if (d['event'] == 'approve')
              {
                'event': 'published',
                'article': d['published'],
                'at': d['updatedAt'],
              }
            else if (d['event'] == 'withdraw' && d['everPublished'] == true)
              {
                'event': 'withdrawn',
                'reason': d['publicReason'],
                'at': d['updatedAt'],
              },
        ];
      });
  Future<Json> user(Json actor, Json body) => records.transaction((tx) async {
    final company = requiredText(actor, 'companyId');
    final user = requiredText(actor, 'userId');
    final action = requiredText(body, 'action');
    final owner = '$company/$user';
    final grant = await tx.get('manufacturer', company);
    if (action == 'list')
      return {
        'results': [
          for (final d in await tx.list('contribution'))
            if (d['owner'] == owner) d,
        ],
        'manufacturer': grant == null
            ? null
            : {'name': grant['name'], 'active': grant['active']},
      };
    if (action == 'create') {
      final source = requiredText(body, 'source');
      if (!['userUpload', 'manufacturer'].contains(source))
        throw ApiProblem(
          400,
          'Nur User-Upload oder zugewiesener Herstellerbereich.',
        );
      if (source == 'manufacturer') _requireGrant(actor, grant);
      final d = {
        'id': 'contrib-${SessionTokens.generate()}',
        'owner': owner,
        'companyId': company,
        'source': source,
        'manufacturerName': source == 'manufacturer' ? grant!['name'] : null,
        'state': 'draft',
        'payload': _payload(body),
        'published': null,
        'everPublished': false,
        'event': 'create',
      };
      return tx.put(
        'contribution',
        d,
        expected: 0,
        actor: owner,
        reason: 'Öffentlicher Entwurf bewusst angelegt',
      );
    }
    final id = requiredText(body, 'id');
    final d = await tx.get('contribution', id);
    if (d == null || d['owner'] != owner)
      throw ApiProblem(404, 'Beitrag nicht gefunden.');
    if (action == 'history')
      return {'entries': await tx.history('contribution', id)};
    final version = expectedVersion(body);
    final reason = requiredText(body, 'reason', max: 2000);
    switch (action) {
      case 'edit':
        if (d['state'] == 'review')
          throw ApiProblem(409, 'Eingereichten Beitrag zuerst zurückziehen.');
        d['payload'] = _payload(body);
        d['state'] = 'draft';
      case 'submit':
        confirmed(body);
        if (d['state'] != 'draft')
          throw ApiProblem(409, 'Nur Entwürfe können eingereicht werden.');
        if (d['source'] == 'manufacturer')
          _requireGrant(actor, grant, name: d['manufacturerName'] as String);
        d['state'] = 'review';
      case 'withdraw':
        confirmed(body);
        d['state'] = 'withdrawn';
        d['published'] = null;
        d['publicReason'] = reason;
      default:
        throw ApiProblem(400, 'Unbekannte Aktion.');
    }
    d['event'] = action;
    return tx.put(
      'contribution',
      d,
      expected: version,
      actor: owner,
      reason: reason,
    );
  });
  void _requireGrant(Json actor, Json? grant, {String? name}) {
    if (actor['role'] != 'admin' ||
        grant == null ||
        grant['active'] != true ||
        (name != null && grant['name'] != name)) {
      throw ApiProblem(
        403,
        'Keine aktive Zuordnung zu diesem Herstellerbereich.',
      );
    }
  }

  Future<Json> operator(Json body) => records.transaction((tx) async {
    final actor = requiredText(body, 'actor');
    final action = requiredText(body, 'action');
    if (action == 'list')
      return {
        'contributions': await tx.list('contribution'),
        'manufacturers': await tx.list('manufacturer'),
      };
    if (action == 'history')
      return {
        'entries': await tx.history('contribution', requiredText(body, 'id')),
      };
    if (action == 'manufacturerHistory')
      return {
        'entries': await tx.history(
          'manufacturer',
          requiredText(body, 'companyId'),
        ),
      };
    final reason = requiredText(body, 'reason', max: 2000);
    confirmed(body);
    final version = expectedVersion(body);
    if (action == 'manufacturer') {
      final company = requiredText(body, 'companyId');
      final old = await tx.get('manufacturer', company);
      final name = requiredText(body, 'name');
      if (old != null && old['name'] != name)
        throw ApiProblem(
          409,
          'Herstelleridentität bleibt unverändert. Neue Identität benötigt ein eigenes Konto.',
        );
      if (body['active'] is! bool)
        throw ApiProblem(400, 'active erforderlich.');
      final evidence = requiredText(body, 'evidence', max: 2000);
      return tx.put(
        'manufacturer',
        {
          'id': company,
          'name': name,
          'active': body['active'],
          'evidence': evidence,
          'verification': 'identity-only',
        },
        expected: version,
        actor: actor,
        reason: reason,
      );
    }
    final id = requiredText(body, 'id');
    final d = await tx.get('contribution', id);
    if (d == null) throw ApiProblem(404, 'Beitrag nicht gefunden.');
    if (action == 'approve') {
      if (d['state'] != 'review')
        throw ApiProblem(409, 'Beitrag ist nicht in Prüfung.');
      if (d['source'] == 'manufacturer') {
        final grant = await tx.get('manufacturer', d['companyId'] as String);
        _requireGrant(
          {'role': 'admin'},
          grant,
          name: d['manufacturerName'] as String,
        );
      }
      final releases = (await tx.history(
        'contribution',
        id,
      )).where((d) => d['event'] == 'approve').length;
      d['published'] = {
        ...d['payload'] as Json,
        'id': id,
        'version': releases + 1,
        'source': d['source'],
        'manufacturerName': d['manufacturerName'],
        'identityVerification': d['source'] == 'manufacturer'
            ? 'identity-only'
            : 'none',
        'technicalStatus': 'unverified',
        'publishedAt': DateTime.now().toUtc().toIso8601String(),
      };
      d['state'] = 'published';
      d['everPublished'] = true;
    } else if (action == 'reject') {
      if (d['state'] != 'review')
        throw ApiProblem(409, 'Beitrag ist nicht in Prüfung.');
      d['state'] = 'draft';
    } else if (action == 'withdraw') {
      d['state'] = 'withdrawn';
      d['published'] = null;
      d['publicReason'] = reason;
    } else {
      throw ApiProblem(400, 'Unbekannte Aktion.');
    }
    d['event'] = action;
    return tx.put(
      'contribution',
      d,
      expected: version,
      actor: actor,
      reason: reason,
    );
  });
  Future<List<Json>> duplicates(String number) async {
    final local = (await seeds.search(number))
        .where((a) => a.articleNumber.toLowerCase() == number.toLowerCase())
        .map((a) => a.toJson());
    return [
      ...local,
      ...(await publicArticles()).where(
        (a) =>
            (a['articleNumber'] as String).toLowerCase() ==
            number.toLowerCase(),
      ),
    ];
  }
}

Json _payload(Json body) {
  if (body['rightsConfirmed'] != true)
    throw ApiProblem(
      400,
      'Rechte zur öffentlichen Weitergabe müssen bestätigt werden.',
    );
  final raw = body['payload'];
  if (raw is! Json) throw ApiProblem(400, 'Öffentliche Vorschau erforderlich.');
  final license = requiredText(raw, 'license', max: 1000);
  // SPDX identifiers simplify attribution; moderation still checks source compatibility.
  if (!['CC0-1.0', 'CC-BY-4.0', 'CC-BY-SA-4.0'].contains(license))
    throw ApiProblem(400, 'Unterstützte Datenlizenz auswählen.');
  final layers = <String, dynamic>{};
  final input = raw['layers'];
  if (input != null && input is! Json)
    throw ApiProblem(400, 'Ungültige technische Daten.');
  for (final entry in {
    'mechanical': ['widthMm', 'heightMm', 'depthMm'],
    'electrical': ['voltageV', 'currentA'],
    'thermal': ['powerLossW'],
  }.entries) {
    final layer = (input as Json?)?[entry.key];
    if (layer != null && layer is! Json)
      throw ApiProblem(400, 'Ungültige Ebene.');
    final clean = <String, dynamic>{'status': 'unverified'};
    for (final key in entry.value) {
      final value = (layer as Json?)?[key];
      if (value != null &&
          (value is! num || !value.isFinite || value < 0 || value > 1e9))
        throw ApiProblem(400, 'Ungültiger Messwert: $key');
      clean[key] = value;
    }
    if (entry.key == 'thermal') {
      final conditions = (layer as Json?)?['conditions'] ?? '';
      if (conditions is! String || conditions.length > 2000)
        throw ApiProblem(400, 'Ungültige thermische Bedingungen.');
      clean['conditions'] = conditions;
    }
    layers[entry.key] = clean;
  }
  // No local paths, notes, project data, user IDs or original source chains.
  layers['symbol'] = {
    'status': 'unverified',
    'reference': '',
    'license': '',
    'terminals': <dynamic>[],
  };
  layers['mechanical']['viewReference'] = '';
  return {
    'articleNumber': requiredText(raw, 'articleNumber'),
    'name': requiredText(raw, 'name'),
    'license': license,
    'origin': requiredText(raw, 'origin', max: 2000),
    'attribution': requiredText(raw, 'attribution', max: 1000),
    'layers': layers,
  };
}
