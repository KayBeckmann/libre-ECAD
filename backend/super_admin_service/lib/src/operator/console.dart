import 'package:shared_server_kit/shared_server_kit.dart';

class OperatorConsole {
  OperatorConsole({
    required this.records,
    required this.companies,
    required this.catalog,
  });
  final Records records;
  final InternalApi companies, catalog;
  Future<Json> execute(String actor, Json body) async {
    final action = requiredText(body, 'action');
    // Browser-supplied actor/mode never reaches another service.
    final b = {...body, 'actor': actor};
    if (action == 'overview') {
      final managed = await companies.call(
        '/internal/operator/dispatch',
        method: 'POST',
        body: {'action': 'list', 'actor': actor},
      );
      return records.transaction(
        (tx) async => {
          ...managed,
          'external': await tx.list('external'),
          'contracts': await tx.list('contract'),
          'payments': await tx.list('payment'),
        },
      );
    }
    if (action == 'catalog') {
      final operation = requiredText(b, 'operation');
      if (![
        'list',
        'history',
        'inspect',
        'manufacturerHistory',
        'manufacturer',
        'approve',
        'reject',
        'withdraw',
      ].contains(operation))
        throw ApiProblem(400, 'Unbekannte Katalogaktion.');
      if (operation == 'manufacturer')
        await _requireManaged(requiredText(b, 'companyId'), actor);
      return catalog.call(
        '/internal/contributions',
        method: 'POST',
        body: {...b, 'action': operation, 'mode': 'operator'},
      );
    }
    if (action == 'managed') {
      final operation = requiredText(b, 'operation');
      if (![
        'list',
        'create',
        'users',
        'audit',
        'access',
        'addAdmin',
        'userAccess',
        'activation',
      ].contains(operation))
        throw ApiProblem(400, 'Unbekannte Firmenaktion.');
      return companies.call(
        '/internal/operator/dispatch',
        method: 'POST',
        body: {...b, 'action': operation},
      );
    }
    if (action == 'history') {
      final kind = requiredText(b, 'kind');
      if (!['contract', 'external', 'payment'].contains(kind))
        throw ApiProblem(400, 'Unbekannte Historie.');
      return records.transaction(
        (tx) async => {
          'entries': await tx.history(kind, requiredText(b, 'id')),
        },
      );
    }
    confirmed(b);
    final reason = requiredText(b, 'reason', max: 2000);
    if (action == 'external') {
      final url = Uri.tryParse(requiredText(b, 'url', max: 1000));
      if (url == null ||
          !['https', 'http'].contains(url.scheme) ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          url.hasQuery ||
          url.hasFragment)
        throw ApiProblem(
          400,
          'Backend-URL ohne Zugangsdaten oder Query erforderlich.',
        );
      final id = requiredText(b, 'id', max: 100);
      if (!RegExp(r'^external-[a-zA-Z0-9-]+$').hasMatch(id))
        throw ApiProblem(400, 'Externe ID erforderlich.');
      return records.transaction(
        (tx) => tx.put(
          'external',
          {
            'id': id,
            'name': requiredText(b, 'name'),
            'url': url.toString(),
            'provider': requiredText(b, 'provider'),
            'mode': 'external',
          },
          expected: expectedVersion(b),
          actor: actor,
          reason: reason,
        ),
      );
    }
    final company = requiredText(b, 'companyId');
    await _requireManaged(company, actor);
    if (action == 'contract') {
      final status = requiredText(b, 'status');
      if (!['unknown', 'trial', 'active', 'ended'].contains(status))
        throw ApiProblem(400, 'Ungültiger Vertragsstatus.');
      return records.transaction(
        (tx) => tx.put(
          'contract',
          {
            'id': company,
            'status': status,
            'reference': requiredText(b, 'reference', max: 1000),
          },
          expected: expectedVersion(b),
          actor: actor,
          reason: reason,
        ),
      );
    }
    if (action == 'payment') {
      final status = requiredText(b, 'status');
      if (!['open', 'success', 'failed'].contains(status))
        throw ApiProblem(400, 'Ungültiger Zahlungsstatus.');
      final amount = b['amountMinor'];
      if (amount is! int || amount < 0 || amount > 100000000000)
        throw ApiProblem(
          400,
          'Betrag in kleinsten Währungseinheiten erforderlich.',
        );
      final currency = requiredText(b, 'currency');
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency))
        throw ApiProblem(400, 'Währung als dreistelliger Code erforderlich.');
      final date = requiredText(b, 'date');
      final parsed = DateTime.tryParse(date);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != date)
        throw ApiProblem(400, 'Gültiges Belegdatum erforderlich.');
      final reference = requiredText(b, 'reference', max: 1000);
      final id = requiredText(b, 'id', max: 100);
      return records.transaction((tx) async {
        if (await tx.get('payment', id) != null) throw Conflict();
        final corrects = b['corrects'];
        if (corrects != null && corrects != '') {
          if (corrects is! String)
            throw ApiProblem(400, 'Korrektur-ID ungültig.');
          final old = await tx.get('payment', corrects);
          if (old == null || old['companyId'] != company)
            throw ApiProblem(
              400,
              'Korrektur muss einen Beleg dieser Firma referenzieren.',
            );
          if ((await tx.list('payment')).any((p) => p['corrects'] == corrects))
            throw ApiProblem(
              409,
              'Bereits korrigiert; bitte den letzten Korrekturbeleg referenzieren.',
            );
        }
        return tx.put(
          'payment',
          {
            'id': id,
            'companyId': company,
            'status': status,
            'amountMinor': amount,
            'currency': currency,
            'date': date,
            'reference': reference,
            'corrects': corrects,
            'source': 'manual',
          },
          expected: 0,
          actor: actor,
          reason: reason,
        );
      });
    }
    throw ApiProblem(400, 'Unbekannte Aktion.');
  }

  Future<void> _requireManaged(String id, String actor) async {
    final d = await companies.call(
      '/internal/operator/dispatch',
      method: 'POST',
      body: {'action': 'list', 'actor': actor},
    );
    if (!(d['companies'] as List).any((c) => c['id'] == id))
      throw ApiProblem(
        404,
        'Keine lokale Managed-Firma. Externe Backends werden nicht ferngesteuert.',
      );
  }
}
