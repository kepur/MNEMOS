#!/usr/bin/env python3
"""oMLX backend control for the switcher's start/health scripts.

    omlx_ctl.py loaded MODEL   exit 0 when MODEL is loaded in oMLX
    omlx_ctl.py ensure MODEL   start oMLX if needed, free other models, load MODEL
    omlx_ctl.py release        free oMLX's GPU memory before another backend loads

oMLX is the user's own app (port and API key come from ~/.omlx/settings.json).
Unloading a single model needs an admin session, so freeing memory restarts the
oMLX server, which comes back with nothing loaded.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gateway_core import install_backend_auth, omlx_endpoint  # noqa: E402

CLI = '/Applications/oMLX.app/Contents/MacOS/omlx-cli'


def base():
    return f'http://127.0.0.1:{omlx_endpoint()[0]}'


def status():
    """oMLX /api/status, or None when the server is not answering."""
    try:
        with urllib.request.urlopen(base() + '/api/status', timeout=5) as r:
            return json.load(r)
    except (OSError, ValueError):
        return None


def loaded(st):
    return list((st or {}).get('loaded_models') or [])


def cli(*args):
    return subprocess.run([CLI, *args], capture_output=True, text=True).returncode == 0


def wait_status(timeout):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        st = status()
        if st:
            return st
        time.sleep(1)
    return None


def release():
    st = status()
    if st and loaded(st):
        print('oMLX: releasing ' + ', '.join(loaded(st)), flush=True)
        cli('restart', '--timeout', '120')
    return 0


def ensure(model, timeout=900):
    st = status()
    if st is None:
        cli('start', '--timeout', '120')
        st = wait_status(120)
        if st is None:
            print('oMLX server did not start', file=sys.stderr)
            return 1
    others = [m for m in loaded(st) if m != model]
    if others:
        print('oMLX: releasing ' + ', '.join(others), flush=True)
        cli('restart', '--timeout', '120')
        st = wait_status(120)
    if model in loaded(st):
        return 0
    url = base() + '/admin/api/models/' + urllib.parse.quote(model, safe='') + '/load'
    try:
        urllib.request.urlopen(urllib.request.Request(url, data=b'', method='POST'), timeout=timeout).read()
    except urllib.error.HTTPError as exc:
        if exc.code not in (202, 409):  # 409: already loading
            print(f'oMLX load {model} failed: HTTP {exc.code} {exc.read()[:300]!r}', file=sys.stderr)
            return 1
    except OSError:
        pass  # long loads may outlive the request; poll below
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if model in loaded(status()):
            print(f'oMLX: {model} loaded', flush=True)
            return 0
        time.sleep(2)
    print(f'oMLX: {model} not loaded after {timeout}s', file=sys.stderr)
    return 1


def main(argv):
    install_backend_auth()
    if len(argv) >= 2 and argv[0] == 'loaded':
        return 0 if argv[1] in loaded(status()) else 1
    if len(argv) >= 2 and argv[0] == 'ensure':
        return ensure(argv[1])
    if argv[:1] == ['release']:
        return release()
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
