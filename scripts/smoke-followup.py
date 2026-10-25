#!/usr/bin/env python3
"""Isolated synthetic Nachtrag fixture and real PostgreSQL/API authorization checks."""
import base64, importlib.util, json, os, secrets, subprocess, time
from pathlib import Path
spec = importlib.util.spec_from_file_location('m4', Path(__file__).with_name('smoke-m4.py'))
m4 = importlib.util.module_from_spec(spec); spec.loader.exec_module(m4)
r, P = m4.request, m4.P

def main():
    stamp = str(time.time_ns())
    op = r('/api/auth/login', {'username': m4.config['SUPER_ADMIN_BOOTSTRAP_USERNAME'], 'password': m4.config['SUPER_ADMIN_BOOTSTRAP_PASSWORD']}, operator=True)['token']
    username = 'followup-' + stamp
    created = r('/api/operator', {'action': 'managed', 'operation': 'create', 'requestId': username, 'name': 'TEST Nachtrag ' + stamp, 'username': username, 'confirmed': True, 'reason': 'Synthetische Nachtrag-Abnahme'}, op, operator=True)
    password = secrets.token_urlsafe(20)
    r('/api/company/auth/activate', {'token': created['activationToken'], 'password': password})
    a = {'username': username, 'password': password, 'token': r('/api/company/auth/login', {'username': username, 'password': password})['token']}
    employee = r('/api/company/users', {'username': username + '-zeichner'}, a['token'], expected=201)
    employee_password = secrets.token_urlsafe(20)
    r('/api/company/auth/activate', {'token': employee['activationToken'], 'password': employee_password})
    e = {'id': employee['userId'], 'username': username + '-zeichner', 'password': employee_password, 'token': r('/api/company/auth/login', {'username': username + '-zeichner', 'password': employee_password})['token']}
    group = r(P + 'project-groups', {'name': 'TEST Team Montage', 'memberIds': [e['id']]}, a['token'], expected=201)
    project = r(P + 'projects', {'name': 'TEST Nachtrag Zeichnung', 'groupIds': [group['id']]}, a['token'], expected=201)
    path = P + 'projects/' + project['id']
    drawing = json.loads(subprocess.check_output(['dart', 'run', 'bin/followup_sample.dart'], cwd=m4.ROOT / 'backend/ecad_core'))
    r(path + '/drawing', {'version': 1, 'drawing': drawing}, e['token'], method='PUT')
    r(P + 'project-groups', {'name': 'Forbidden'}, e['token'], expected=403)
    api_token = r(P + 'automation/tokens', {'confirmed': True, 'label': 'TEST Gruppenrechte', 'projectIds': [project['id']], 'allowProposals': True}, e['token'], expected=201)['token']
    r(P + 'automation/projects/' + project['id'], token=api_token)
    r(path + '/offline', {'confirmed': True}, e['token'])
    revoked = r(P + 'project-groups/' + group['id'], {**group, 'memberIds': []}, a['token'], method='PATCH')
    for suffix in ['', '/drawing', '/drawing/history', '/documents?version=2']:
        r(path + suffix, token=e['token'], expected=404)
    r(path + '/offline/upload', {}, e['token'], expected=404)
    r(P + 'automation/projects/' + project['id'], token=api_token, expected=404)
    r(P + 'project-groups/' + group['id'], group, a['token'], method='PATCH', expected=409)
    group = r(P + 'project-groups/' + group['id'], {**revoked, 'memberIds': [e['id']]}, a['token'], method='PATCH')
    r(path, token=e['token'])
    # Add local library fixtures with clearly separated origin and a drawn symbol.
    definition = {'id': 'followup-symbol', 'name': 'TEST Symbol', 'code': 'A', 'role': 'generic', 'ports': [{'id': '1', 'label': '1', 'x': 0, 'y': -40}, {'id': '2', 'label': '2', 'x': 0, 'y': 40}], 'primitives': [{'kind': 'rect', 'x': -20, 'y': -20, 'x2': 20, 'y2': 20}]}
    for scope in ('personal', 'company'):
        body = {'scope': scope, 'articleNumber': 'TEST-' + scope.upper(), 'name': 'TEST Bibliothek ' + scope, 'origin': 'Eigene synthetische Abnahme', 'license': 'CC0-1.0', 'layers': {'symbol': {'definition': definition, 'license': 'CC0-1.0', 'terminals': [{'id': '1', 'label': '1'}, {'id': '2', 'label': '2'}]}}}
        r(P + 'articles', body, a['token'], expected=201)
    packet = r(path + '/documents?version=2', token=a['token'])
    Path('/tmp/libre-followup.pdf').write_bytes(base64.b64decode(packet['pdf']))
    text = subprocess.check_output(['pdftotext', '/tmp/libre-followup.pdf', '-']).decode()
    assert 'Kontaktkamm' in text and 'Schließer' in text and 'Öffner' in text
    state = {'a': a, 'employee': e, 'group': group, 'project': project, 'drawing': drawing}
    fd = os.open('/tmp/libre-ecad-followup-state.json', os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f: json.dump(state, f)
    r('/api/auth/logout', token=op, method='POST', expected=204, operator=True)
    print('PASS real SQL groups, grants/revocation, CAS, offline/API scope, relay PDF and synthetic browser fixture')

if __name__ == '__main__': main()
