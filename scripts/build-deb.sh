#!/usr/bin/env bash
# Build an architecture-independent Debian package on Linux or macOS.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$root/dist}"
command -v python3 >/dev/null || { echo '[build-deb] python3 is required' >&2; exit 1; }
python3 - "$root" "$out" <<'PY'
import io, os, re, sys, tarfile, tempfile
from pathlib import Path
root, output = map(Path, sys.argv[1:])
control = (root / 'debian/control').read_bytes()
versions = re.findall(rb'(?m)^Version:\s*([^\s]+)\s*$', control)
if len(versions) != 1 or not re.fullmatch(rb'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', versions[0]):
    raise SystemExit('[build-deb] Expected one X.Y.Z Version in debian/control')
version = versions[0].decode('ascii')
files = {
    'usr/bin/sshgo': (root / 'src/sshgo', 0o755),
    'usr/lib/sshgo/sshgo.zsh': (root / 'src/sshgo.zsh', 0o644),
    'usr/lib/sshgo/sshgo-askpass': (root / 'src/sshgo-askpass', 0o755),
    'usr/share/doc/sshgo/README.md': (root / 'README.md', 0o644),
    'usr/share/doc/sshgo/copyright': (root / 'LICENSE', 0o644),
}
def tarball(entries):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w:xz', format=tarfile.USTAR_FORMAT) as archive:
        dirs = {'.'}
        for name in entries:
            parent = Path(name).parent
            while str(parent) != '.':
                dirs.add('./' + parent.as_posix()); parent = parent.parent
        for name in sorted(dirs, key=lambda item: (item.count('/'), item)):
            info = tarfile.TarInfo(name); info.type = tarfile.DIRTYPE; info.mode = 0o755
            info.uid = info.gid = 0; info.uname = info.gname = 'root'; info.mtime = 0
            archive.addfile(info)
        for name, (content, mode) in entries.items():
            info = tarfile.TarInfo('./' + name); info.size = len(content); info.mode = mode
            info.uid = info.gid = 0; info.uname = info.gname = 'root'; info.mtime = 0
            archive.addfile(info, io.BytesIO(content))
    return buf.getvalue()
def ar_member(name, data):
    fields = (f'{name:<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n').encode('ascii')
    if len(fields) != 60: raise SystemExit('[build-deb] Invalid ar header')
    return fields + data + (b'\n' if len(data) % 2 else b'')
control_tar = tarball({'control': (control, 0o644)})
data_tar = tarball({name: (path.read_bytes(), mode) for name, (path, mode) in files.items()})
package = b'!<arch>\n' + ar_member('debian-binary', b'2.0\n') + ar_member('control.tar.xz', control_tar) + ar_member('data.tar.xz', data_tar)
output.mkdir(parents=True, exist_ok=True)
path = output / f'sshgo_{version}_all.deb'
fd, temporary = tempfile.mkstemp(prefix='.sshgo-', dir=output)
try:
    with os.fdopen(fd, 'wb') as f: f.write(package)
    os.chmod(temporary, 0o644); os.replace(temporary, path)
finally:
    if os.path.exists(temporary): os.unlink(temporary)
print(f'[build-deb] Built {path}')
PY
