#!/usr/bin/env python3
"""Render a tap formula from the exact downloaded GitHub tag archive."""
import argparse
import hashlib
import re
import sys
import tarfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('version', help='Release version, e.g. 1.0.0')
parser.add_argument('archive', type=Path, help='GitHub archive downloaded for this exact tag')
parser.add_argument('--output', type=Path, help='Formula output path; default is stdout')
args = parser.parse_args()
if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', args.version):
    parser.error('version must be X.Y.Z')
with tarfile.open(args.archive, 'r:gz') as archive:
    names = set(archive.getnames())
    prefix = f'sshgo-{args.version}'
    required = {f'{prefix}/src/sshgo', f'{prefix}/src/sshgo.zsh', f'{prefix}/src/sshgo-askpass', f'{prefix}/debian/control', f'{prefix}/LICENSE'}
    if not required.issubset(names):
        parser.error('archive does not contain the expected files for this version')
    control = archive.extractfile(f'{prefix}/debian/control').read().decode('utf-8')
    if re.findall(r'(?m)^Version:\s*(\S+)\s*$', control) != [args.version]:
        parser.error('archive package version does not match the requested version')
sha = hashlib.sha256(args.archive.read_bytes()).hexdigest()
template = Path(__file__).resolve().parent.parent / 'packaging/homebrew/sshgo.rb.in'
formula = template.read_text().replace('@VERSION@', args.version).replace('@SHA256@', sha)
if args.output:
    if args.output.exists():
        parser.error(f'output exists: {args.output}')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(formula)
else:
    sys.stdout.write(formula)
