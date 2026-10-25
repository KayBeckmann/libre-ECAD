#!/usr/bin/env python3
"""Build, exercise and package a Linux development download. Never uses a real vault."""
import argparse
import ctypes
import ctypes.util
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
APP = REPO / 'frontend/libre_ecad_app'


def wait_window(display, process):
    lib = ctypes.CDLL(ctypes.util.find_library('X11'))
    lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
    lib.XOpenDisplay.restype = ctypes.c_void_p
    lib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    lib.XDefaultRootWindow.restype = ctypes.c_ulong
    lib.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)), ctypes.POINTER(ctypes.c_uint)]
    lib.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_char_p)]
    lib.XFree.argtypes = [ctypes.c_void_p]
    lib.XCloseDisplay.argtypes = [ctypes.c_void_p]
    connection = lib.XOpenDisplay(display.encode())
    if not connection:
        raise RuntimeError('Virtual display unavailable')
    try:
        for _ in range(100):
            if process.poll() is not None:
                raise RuntimeError('Release exited before displaying a window')
            root, parent = ctypes.c_ulong(), ctypes.c_ulong()
            children, count = ctypes.POINTER(ctypes.c_ulong)(), ctypes.c_uint()
            lib.XQueryTree(connection, lib.XDefaultRootWindow(connection), ctypes.byref(root), ctypes.byref(parent), ctypes.byref(children), ctypes.byref(count))
            found = False
            for i in range(count.value):
                name = ctypes.c_char_p()
                if lib.XFetchName(connection, children[i], ctypes.byref(name)) and name.value:
                    found |= 'libre' in name.value.decode(errors='replace').lower()
                    lib.XFree(name)
            if children:
                lib.XFree(children)
            if found:
                time.sleep(3)
                if process.poll() is not None:
                    raise RuntimeError('Release closed immediately after launch')
                return
            time.sleep(.2)
        raise RuntimeError('Release window not found')
    finally:
        lib.XCloseDisplay(connection)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xvfb', default=shutil.which('Xvfb'))
    args = parser.parse_args()
    if not args.xvfb:
        parser.error('Install Xvfb or pass --xvfb /path/to/Xvfb')
    source = subprocess.check_output(['git', 'rev-parse', json.loads((ROOT / 'version.json').read_text())['app_source']], cwd=REPO, text=True).strip()
    paths = ['frontend/libre_ecad_app', 'backend/ecad_core', 'backend/ecad_documents/lib', 'backend/ecad_documents/pubspec.yaml', 'backend/ecad_documents/pubspec.lock']
    subprocess.run(['git', 'diff', '--exit-code', source, '--', *paths], cwd=REPO, check=True)
    if subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', *paths], cwd=REPO).strip():
        raise RuntimeError('Untracked app source files must be committed first')
    artifacts = ROOT / 'artifacts'
    artifacts.mkdir(exist_ok=True)
    # A failed verification must never keep an earlier success manifest.
    (artifacts / 'linux.json').unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix='libre-ecad-native-test-m8-') as temp:
        temp = Path(temp)
        env = dict(os.environ, XDG_DATA_HOME=str(temp / 'data'), XDG_CONFIG_HOME=str(temp / 'config'))
        checks = []
        with (artifacts / 'verification.txt').open('w') as log:
            log.write(f'LibreECAD development download\nSource: {source}\nHost: {platform.platform()}\n')
            log.write(Path('/etc/os-release').read_text() + '\n')
            log.flush()
            def run(name, command):
                print(f'Checking {name}', flush=True)
                log.write(f'\n=== {name}: {" ".join(command)} ===\n'); log.flush()
                subprocess.run(command, cwd=APP, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
                checks.append(name)
            read_fd, write_fd = os.pipe()
            xvfb = subprocess.Popen([args.xvfb, '-displayfd', str(write_fd), '-screen', '0', '1440x1000x24', '-nolisten', 'tcp'], pass_fds=(write_fd,), stdout=log, stderr=log)
            os.close(write_fd)
            try:
                import select
                if not select.select([read_fd], [], [], 15)[0]:
                    raise RuntimeError('Xvfb did not report a display')
                with os.fdopen(read_fd) as pipe:
                    display_number = pipe.readline().strip()
                if not display_number.isdigit():
                    raise RuntimeError('Xvfb failed to start')
                env['DISPLAY'] = ':' + display_number
                run('flutter-analyze', ['flutter', 'analyze'])
                run('flutter-test', ['flutter', 'test'])
                run('linux-native-integration', ['flutter', 'test', 'integration_test/offline_native_test.dart', '-d', 'linux'])
                run('linux-release-build', ['flutter', 'build', 'linux', '--release'])
                # Test the same release bundle that is packaged below.
                exe = APP / 'build/linux/x64/release/bundle/libre_ecad_app'
                process = subprocess.Popen([str(exe)], cwd=exe.parent, env=env, stdout=log, stderr=log)
                try:
                    wait_window(env['DISPLAY'], process)
                    checks.append('linux-release-launch')
                    log.write('\nPASS linux-release-launch: native X11 window present and process alive\n')
                finally:
                    process.terminate()
                    process.wait(timeout=15)
            finally:
                xvfb.terminate()
                xvfb.wait(timeout=15)
            log.write('\nAll required checks passed. Virtual-display Linux acceptance only.\n')
        filename = f'libre-ecad-linux-x64-{source[:7]}.tar.gz'
        with tarfile.open(artifacts / filename, 'w:gz') as archive:
            archive.add(APP / 'build/linux/x64/release/bundle', arcname='libre-ecad')
            archive.add(REPO / 'LICENSE', arcname='libre-ecad/LICENSE.txt')
        data = (artifacts / filename).read_bytes()
        info = {'file': filename, 'source': source, 'date': datetime.now(timezone.utc).isoformat(), 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data), 'checks': checks, 'log_sha256': hashlib.sha256((artifacts / 'verification.txt').read_bytes()).hexdigest()}
        (artifacts / 'linux.json').write_text(json.dumps(info, indent=2) + '\n')
        print(f'Verified {filename}: {info["sha256"]}', flush=True)


if __name__ == '__main__':
    main()
