#!/usr/bin/env python3
"""Exercise the wiki's dump/restore/archive commands using isolated synthetic data."""
import json
from pathlib import Path
import subprocess
import tempfile
import uuid

REPO = Path(__file__).resolve().parents[1]
project = 'libre-m8-backup-' + uuid.uuid4().hex[:10]
image = subprocess.check_output(['docker', 'compose', 'images', '-q', 'company-users-service'], cwd=REPO, text=True).strip()
if not image:
    raise SystemExit('Build the company-users-service image first')
with tempfile.TemporaryDirectory(prefix='libre-m8-runbook-') as temp:
    override = Path(temp) / 'compose.json'
    override.write_text(json.dumps({'services': {'company-users-service': {'image': image, 'pull_policy': 'never'}}}))
    compose = ['docker', 'compose', '-p', project, '-f', str(REPO / 'docker-compose.yml'), '-f', str(override)]
    def run(*args, data=None):
        result = subprocess.run(compose + list(args), input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=REPO)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors='replace'))
        return result.stdout
    databases = [('super-admin-db', 'super_admin'), ('global-articles-db', 'global_articles'), ('company-users-db', 'company_users')]
    try:
        run('up', '-d', '--wait', *(service for service, _ in databases))
        for service, name in databases:
            run('exec', '-T', service, 'psql', '-v', 'ON_ERROR_STOP=1', '-U', name, '-d', name, '-c', "CREATE TABLE m8_restore_fixture(id int PRIMARY KEY, label text); INSERT INTO m8_restore_fixture VALUES (1, 'synthetic M8 recovery');")
            dump = run('exec', '-T', service, 'pg_dump', '-U', name, '-d', name, '-Fc')
            listing = run('exec', '-T', service, 'pg_restore', '--list', data=dump)
            assert b'm8_restore_fixture' in listing
            run('exec', '-T', service, 'createdb', '-U', name, 'restore_check')
            run('exec', '-T', service, 'pg_restore', '--exit-on-error', '--no-owner', '-U', name, '-d', 'restore_check', data=dump)
            recovered = run('exec', '-T', service, 'psql', '-U', name, '-d', 'restore_check', '-Atc', 'SELECT label FROM m8_restore_fixture WHERE id=1')
            assert recovered.strip() == b'synthetic M8 recovery'
            print(f'PASS {service}: custom-format dump, list, restore, data verification', flush=True)
        run('run', '--rm', '--no-deps', '-T', '--entrypoint', 'sh', 'company-users-service', '-c', 'printf "synthetic archive\n" > /var/lib/libre-ecad/archives/m8-fixture.txt')
        archive = run('run', '--rm', '--no-deps', '-T', '--entrypoint', 'tar', 'company-users-service', '-C', '/var/lib/libre-ecad/archives', '-czf', '-', '.')
        run('run', '--rm', '--no-deps', '-T', '--entrypoint', 'rm', 'company-users-service', '/var/lib/libre-ecad/archives/m8-fixture.txt')
        run('run', '--rm', '--no-deps', '-T', '--entrypoint', 'tar', 'company-users-service', '-C', '/var/lib/libre-ecad/archives', '-xzf', '-', data=archive)
        recovered = run('run', '--rm', '--no-deps', '-T', '--entrypoint', 'cat', 'company-users-service', '/var/lib/libre-ecad/archives/m8-fixture.txt')
        assert recovered == b'synthetic archive\n'
        print('PASS archive volume: tar export, restore and exact content; no live data used', flush=True)
    finally:
        # Only this invocation's random Compose project and its disposable volumes.
        run('down', '--volumes', '--remove-orphans')
