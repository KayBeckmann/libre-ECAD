#!/usr/bin/env python3
"""Verify independent site operation by briefly stopping each private site."""
import argparse
from pathlib import Path
import subprocess
import time
from urllib.error import URLError
from urllib.request import urlopen

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--homepage', default='http://127.0.0.1:8187')
parser.add_argument('--wiki', default='http://127.0.0.1:8188')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
compose = ['docker', 'compose', '-p', 'libre-ecad-sites']
if (repo / '.sites.env').exists():
    compose += ['--env-file', '.sites.env']
compose += ['-f', 'compose.sites.yml']


def reachable(origin):
    try:
        with urlopen(origin + '/health.txt', timeout=2) as response:
            return response.status == 200
    except (URLError, TimeoutError):
        return False


assert reachable(args.homepage) and reachable(args.wiki), 'Start both sites first'
for service, stopped, other in [('wiki', args.wiki, args.homepage), ('homepage', args.homepage, args.wiki)]:
    try:
        subprocess.run(compose + ['stop', service], cwd=repo, check=True, capture_output=True)
        assert not reachable(stopped), f'{service} still reachable'
        assert reachable(other), f'Other site failed while {service} stopped'
        print(f'PASS {service} stopped; other site remains available', flush=True)
    finally:
        subprocess.run(compose + ['start', service], cwd=repo, check=True, capture_output=True)
        for _ in range(30):
            if reachable(stopped):
                break
            time.sleep(.5)
        assert reachable(stopped), f'{service} did not restart'
print('PASS both independent sites restored', flush=True)
