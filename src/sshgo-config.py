"""Export and restore SSHGo's local configuration without running SSH."""

import os
from pathlib import Path
import re
import sys
import tempfile
from urllib.parse import unquote

try:
    import yaml
except ImportError:
    sys.exit("sshgo: export and import need PyYAML for python3. On Debian or Ubuntu, install python3-yaml.")


FORMAT = "sshgo-config-v1"
SUFFIX = ".remote-root"
MAX_BYTES = 1024 * 1024
SAFE_NAME_BYTES = b"abcdefghijklmnopqrstuvwxyz0123456789._-"


class ConfigLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        result = {}
        for key, value in self.construct_pairs(node, deep=deep):
            if not isinstance(key, str) or key in result:
                raise ValueError("YAML mapping keys must be unique strings.")
            result[key] = value
        return result


class SSHConfig(str):
    pass


class ConfigDumper(yaml.SafeDumper):
    pass


ConfigDumper.add_representer(SSHConfig, lambda dumper, value: dumper.represent_scalar(
    "tag:yaml.org,2002:str", value, style="|"
))


def read_text(path):
    if not path.is_file():
        raise ValueError(f"Expected a regular file: {path}")
    with path.open("rb") as stream:
        content = stream.read(MAX_BYTES + 1)
    if len(content) > MAX_BYTES:
        raise ValueError(f"Configuration file exceeds 1 MiB: {path}")
    return content.decode("utf-8")


def has_control_chars(value):
    return any(ord(char) < 32 or 127 <= ord(char) < 160 for char in value)


def host_filename(alias):
    if not isinstance(alias, str) or not alias or alias.startswith("-") or has_control_chars(alias):
        raise ValueError("Invalid SSH alias in remote_roots.")
    # Match the byte escaping in _sshgo_host_config_path.
    key = "".join(chr(byte) if byte in SAFE_NAME_BYTES else f"%{byte:02x}" for byte in alias.encode("utf-8"))
    if len(key) + len(SUFFIX) > 255:
        raise ValueError("SSH alias is too long for a remote-root setting.")
    return key + SUFFIX


def validate_root(value):
    if not isinstance(value, str) or not value.startswith("/") or has_control_chars(value):
        raise ValueError("Every remote root must be an absolute path on the remote host.")


def validate_ssh_config(value):
    if not isinstance(value, str) or "\0" in value:
        raise ValueError("ssh_config must contain SSH configuration text.")
    if re.search(r"^[ \t]*include(?:[ \t=]|$)", value, re.IGNORECASE | re.MULTILINE):
        raise ValueError("SSH Include files are not portable in this format. Migrate them separately before using this command.")
    if re.search(r"-----BEGIN [^\r\n]*PRIVATE KEY-----", value):
        raise ValueError("ssh_config contains private key material.")


def write_new(path, content):
    """Write privately and publish without replacing an existing path."""
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".sshgo-", delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(content)
            stream.flush()
            os.link(temporary, path)
        finally:
            temporary.unlink()


def export_config(bundle, ssh_config, hosts):
    config = read_text(ssh_config) if os.path.lexists(ssh_config) else None
    if config is not None:
        validate_ssh_config(config)
    roots = {}
    for path in sorted(hosts.glob(f"*{SUFFIX}")):
        alias = unquote(path.name[:-len(SUFFIX)], errors="strict")
        if path.is_symlink() or path.name != host_filename(alias):
            raise ValueError(f"Invalid remote-root configuration file: {path}")
        value = read_text(path).rstrip("\n")
        validate_root(value)
        roots[alias] = value
    data = {"format": FORMAT, "ssh_config": SSHConfig(config) if config is not None else None, "remote_roots": roots}
    payload = yaml.dump(data, Dumper=ConfigDumper, allow_unicode=True, sort_keys=False).encode("utf-8")
    if len(payload) > MAX_BYTES:
        raise ValueError("The YAML export would exceed 1 MiB.")
    write_new(bundle, payload)
    print(f"Exported SSH configuration and {len(roots)} remote-root settings to {bundle}")


def import_config(bundle, ssh_config, hosts):
    data = yaml.load(read_text(bundle), Loader=ConfigLoader)
    if not isinstance(data, dict) or set(data) != {"format", "ssh_config", "remote_roots"} or data["format"] != FORMAT:
        raise ValueError("Expected a YAML configuration exported by sshgo.")
    config, roots = data["ssh_config"], data["remote_roots"]
    if not isinstance(roots, dict):
        raise ValueError("remote_roots must be a mapping of aliases to paths.")
    files = {}
    if config is not None:
        validate_ssh_config(config)
        files[ssh_config] = config
    for alias, value in roots.items():
        validate_root(value)
        files[hosts / host_filename(alias)] = value + "\n"

    pending = {}
    for path, content in files.items():
        if os.path.lexists(path):
            if (path.parent == hosts and path.is_symlink()) or read_text(path) != content:
                raise ValueError(f"Existing configuration differs: {path}. Back it up and resolve the conflict before importing.")
        else:
            pending[path] = content.encode("utf-8")

    created = []
    try:
        for path, content in pending.items():
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            write_new(path, content)
            created.append(path)
    except (OSError, KeyboardInterrupt):
        for path in reversed(created):
            if path.is_file() and not path.is_symlink() and path.read_bytes() == pending[path]:
                path.unlink()
        raise
    print(f"Imported {len(created)} configuration files. Identical files were already in place.")


def main():
    action, filename, host_dir = sys.argv[1:]
    os.umask(0o077)
    operation = {"export": export_config, "import": import_config}[action]
    operation(Path(filename).expanduser(), Path.home() / ".ssh/config", Path(host_dir))


if __name__ == "__main__":
    try:
        main()
    except yaml.YAMLError as error:
        mark = getattr(error, "problem_mark", None)
        location = f" at line {mark.line + 1}" if mark else ""
        sys.exit(f"sshgo: invalid YAML{location}.")
    except (OSError, ValueError) as error:
        sys.exit(f"sshgo: {error}")
    except KeyboardInterrupt:
        sys.exit(130)
