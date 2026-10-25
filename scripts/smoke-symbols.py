#!/usr/bin/env python3
"""Live symbol/three-phase regression in the isolated smoke-m4 test company."""
import base64, importlib.util, json, os, subprocess, time
from pathlib import Path
spec = importlib.util.spec_from_file_location('m4', Path(__file__).with_name('smoke-m4.py'))
m4 = importlib.util.module_from_spec(spec); spec.loader.exec_module(m4)
r, P = m4.request, m4.P

def main():
    state = json.loads(Path('/tmp/libre-ecad-m4-state.json').read_text())
    a = state['a']
    a['token'] = r('/api/company/auth/login', {'username': a['username'], 'password': a['password']})['token']
    stamp = str(time.time_ns())
    definition = {'id': 'test-symbol', 'name': 'TEST Kontakt', 'code': 'K', 'role': 'no',
        'ports': [{'id': '13', 'label': '13', 'x': 0, 'y': -40}, {'id': '14', 'label': '14', 'x': 0, 'y': 40}],
        'primitives': [{'kind': 'line', 'x': 0, 'y': -40, 'x2': 0, 'y2': -20}, {'kind': 'line', 'x': 0, 'y': 40, 'x2': 20, 'y2': -20}]}
    body = {'scope': 'personal', 'articleNumber': 'TEST-SYMBOL-'+stamp, 'name': 'TEST eigener Kontakt '+stamp,
        'license': 'CC0', 'origin': 'Eigener synthetischer Test', 'layers': {'symbol': {'license': 'CC0', 'definition': definition,
        'terminals': [{'id': p['id'], 'label': p['label']} for p in definition['ports']]}}}
    article = r(P+'articles', body, a['token'], expected=201)
    assert article['layers']['symbol']['definition'] == definition
    samples = json.loads(subprocess.check_output(['dart', 'run', 'bin/samples.dart'], cwd=m4.ROOT/'backend/ecad_core'))
    drawing = samples['three-phase']
    project = r(P+'projects', {'name': 'TEST Symbole und Drehstrom '+stamp}, a['token'], expected=201)
    saved = r(P+'projects/'+project['id']+'/drawing', {'version': 1, 'drawing': drawing}, a['token'], method='PUT')
    assert saved['drawing'] == drawing
    packet = r(P+'projects/'+project['id']+'/documents?version=2', token=a['token'])
    # The endpoint returns the generated PDF and its versioned source.
    pdf = base64.b64decode(packet['pdf'])
    assert pdf.startswith(b'%PDF')
    Path('/tmp/libre-symbols-live.pdf').write_bytes(pdf)
    out = {'a': a, 'projectId': project['id'], 'projectName': project['name'], 'articleId': article['id'], 'articleName': article['name']}
    path = Path('/tmp/libre-ecad-symbols-state.json')
    fd = os.open(path, os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f: json.dump(out, f)
    print('PASS live API: article vectors, three-phase plan with seven conductors, relay identity and PDF persisted in test company')

if __name__ == '__main__': main()
