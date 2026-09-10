#!/usr/bin/env python3
"""Read-only process/status correlation. Stops with the selected DSH app."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.parse
import urllib.request


def counts(snapshot):
    rows = snapshot.get('rows', [])
    result = {'doing': 0, 'done': 0, 'error': 0, 'decision': 0}
    for row in rows:
        if row.get('ask') or row.get('approval'):
            result['decision'] += 1
        elif row.get('busy'):
            result['doing'] += 1
        elif (row.get('lastTurn') or {}).get('failed'):
            result['error'] += 1
        elif row.get('unread'):
            result['done'] += 1
    result['sidebarFresh'] = isinstance(snapshot.get('sidebarSyncedAt'), (int, float))
    return result


def status(runtime):
    file = json.loads(runtime.read_text())
    origin = urllib.parse.urlsplit(file['origin'])
    if origin.scheme != 'http' or origin.hostname not in ('127.0.0.1', 'localhost', '::1'):
        raise ValueError('not loopback')
    request = urllib.request.Request(file['origin'] + '/dsh-notch/status', headers={'Authorization': 'Bearer ' + file['token']})
    # Never send local credentials through a machine proxy or follow redirects.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    with opener.open(request, timeout=1) as response:
        snapshot = json.load(response)
    if snapshot.get('ok') is not True:
        raise ValueError('invalid snapshot')
    return counts(snapshot)


def processes(app_pid, base):
    result = []
    output = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,rss=,comm='], text=True, timeout=2)
    for line in output.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) != 4:
            continue
        pid, parent, rss, command = fields
        if command.startswith(base) or (int(parent) == app_pid and command.endswith('/node')):
            role = ('renderer' if 'DSH Helper (Renderer)' in command else
                    'notch' if command.endswith('/dsh-notch') else
                    'app' if int(pid) == app_pid else
                    'host' if command.endswith('/node') else 'helper')
            result.append({'pid': int(pid), 'role': role, 'rssKB': int(rss)})
    return result


def main():
    app_pid, app_path, output = int(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    runtime = Path.home() / '.dsh/dsh-notch/runtime.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    previous = None
    heartbeat = 0
    while True:
        began = time.monotonic()
        try:
            rows = processes(app_pid, str(app_path / 'Contents') + '/')
            alive = any(row['pid'] == app_pid and row['role'] == 'app' for row in rows)
            try:
                board = status(runtime) if alive else {'unavailable': 'app-ended'}
            except Exception as error:
                board = {'unavailable': type(error).__name__}
            signature = ([(r['pid'], r['role']) for r in rows], board)
            if signature != previous or began - heartbeat >= 30:
                event = {'at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                         'event': 'state-change' if signature != previous else 'heartbeat',
                         'appPid': app_pid, 'processes': rows, 'notch': board,
                         'sampleDurationMs': round((time.monotonic()-began)*1000),
                         'exitReason': 'unavailable-to-external-observer'}
                if output.exists() and output.stat().st_size >= 1024 * 1024:
                    os.replace(output, str(output) + '.1')
                with output.open('a') as file:
                    file.write(json.dumps(event) + '\n')
                os.chmod(output, 0o600)
                previous, heartbeat = signature, began
            if not alive:
                return
        except (OSError, subprocess.SubprocessError):
            pass
        time.sleep(max(.1, 1 - (time.monotonic() - began)))


if __name__ == '__main__':
    main()
