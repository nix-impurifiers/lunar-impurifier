#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Run actual lin/lrm transactions, then report profile activation errors."""
import os
from pathlib import Path
import re
import subprocess
import sys


def main():
    if os.geteuid() != 0:
        raise ValueError('native Lunar requires root')
    for key in ('ROOT', 'DESTDIR'):
        if os.environ.get(key, '/') not in ('', '/'):
            raise ValueError('native Lunar requires the live host root')
    args = sys.argv[1:]
    options = []
    if args[:2] == ['install', '--from']:
        if len(args) < 4 or not Path(args[2]).is_dir():
            raise ValueError('--from requires an existing native source-cache directory')
        options = ['--from', str(Path(args[2]).resolve())]
        args = [args[0], *args[3:]]
    if not args or any(not re.fullmatch(r'[a-z0-9][a-z0-9+._-]*', a) for a in args):
        raise ValueError('use install [--from DIRECTORY] MODULE...; remove MODULE...; or reconcile')
    status = 0
    if args[0] == 'install' and len(args) > 1:
        log = Path('/var/log/lunar/activity')
        offset = log.stat().st_size if log.exists() else 0
        status = subprocess.run(['lin', '-c', *options, *args[1:]]).returncode
        with log.open('rb') as stream:
            stream.seek(offset)
            entries = [line.decode().rstrip('\n').split('\t') for line in stream]
        completed = {row[2] for row in entries if len(row) >= 5 and row[1] == 'lin' and row[4] == 'success'}
        if not set(args[1:]).issubset(completed):
            print('lunar-impurifier: native lin did not complete every requested module', file=sys.stderr)
            status = status or 1
    elif args[0] == 'remove' and len(args) > 1:
        status = subprocess.run(['lrm', *args[1:]]).returncode
        query = subprocess.run(['/bin/bash', '-c', '. /var/lib/lunar/bootstrap >/dev/null; for module in "$@"; do if module_installed "$module"; then exit 1; fi; done', 'lunar-impurifier', *args[1:]])
        status = status or query.returncode
    elif args != ['reconcile']:
        raise ValueError('use install [--from DIRECTORY] MODULE...; remove MODULE...; or reconcile')
    activation = subprocess.run(['/usr/sbin/lunar-impurifier-activate']).returncode
    return status or activation


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print('lunar-impurifier: ' + str(error), file=sys.stderr)
        sys.exit(1)
