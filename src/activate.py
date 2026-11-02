#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Check native runtime minimums before touching the shared profile."""
import os
from pathlib import Path
import re
import sys


def main():
    for key in ('ROOT', 'DESTDIR'):
        if os.environ.get(key, '/') not in ('', '/'):
            raise ValueError('activation requires the live host root')
    base = Path('/usr/share/lunar-impurifier')
    current = base.joinpath('runtime-version').read_text().strip()
    requirements = [p.read_text().strip() for p in base.joinpath('requirements').glob('*')]
    for value in [current, *requirements]:
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', value):
            raise ValueError('invalid native runtime version')
    if any(tuple(map(int, current.split('.'))) < tuple(map(int, minimum.split('.'))) for minimum in requirements):
        raise ValueError('native runtime is too old; upgrade lunar-impurifier')
    os.execv('/usr/sbin/nix-profile-engine', ['nix-profile-engine', 'reconcile'])


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print('lunar-impurifier: ' + str(error), file=sys.stderr)
        sys.exit(1)
