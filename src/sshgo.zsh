# Native credential backends. Passwords are never stored in arguments or files.
_sshgo_secret_exists() {
  if [[ "$(uname -s)" == Darwin ]]; then
    /usr/bin/security find-generic-password -a "$2" -s "$1" >/dev/null 2>&1
  else
    command -v secret-tool >/dev/null 2>&1 || return 1
    command secret-tool lookup service "$1" account "$2" >/dev/null 2>&1
  fi
}
_sshgo_secret_store() {
  if [[ "$(uname -s)" == Darwin ]]; then
    /usr/bin/security add-generic-password -U -a "$2" -s "$1" -l "sshgo: $2@$3:$4" -w
  else
    if ! command -v secret-tool >/dev/null 2>&1; then
      _sshgo_ui 2 error 'Password storage needs secret-tool and an unlocked Secret Service keyring.'
      _sshgo_ui 2 hint 'Install libsecret-tools; SSH keys work without a desktop keyring.'
      return 1
    fi
    command secret-tool store --label="sshgo: $2@$3:$4" service "$1" account "$2" || {
      _sshgo_ui 2 error 'Could not access the Secret Service keyring.'
      return 1
    }
  fi
}
_sshgo_secret_clear() {
  if [[ "$(uname -s)" == Darwin ]]; then
    /usr/bin/security delete-generic-password -a "$2" -s "$1"
  else
    command -v secret-tool >/dev/null 2>&1 || { _sshgo_ui 2 error 'Password storage needs secret-tool.'; return 1; }
    command secret-tool clear service "$1" account "$2"
  fi
}

# Quick SSH connections for zsh. Passwords can be stored in the platform keyring.
# UI uses stderr except for command results.
_sshgo_ui() {
  local fd="$1" kind="$2"
  shift 2
  local accent='' bold='' muted='' green='' red='' reset=''
  if [[ -t "$fd" && "${TERM-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    accent=$'\e[36m' bold=$'\e[1m' muted=$'\e[2m'
    green=$'\e[32m' red=$'\e[31m' reset=$'\e[0m'
  fi
  case "$kind" in
    header)
      printf '\n  %s%sSSHGO%s  %s%s%s\n\n' "$bold" "$accent" "$reset" "$muted" "$1" "$reset" >&$fd ;;
    section)
      printf '  %s%s%s\n' "$bold" "$1" "$reset" >&$fd ;;
    command)
      local -i width=${COLUMNS:-80} label_width=34
      (( width > 0 )) || width=80
      (( ${#1} <= label_width )) || label_width=${#1}
      if (( 6 + label_width + ${#2} <= width )); then
        printf '    %s%-34s%s  %s\n' "$accent" "$1" "$reset" "$2" >&$fd
      else
        printf '    %s%s%s\n      %s\n' "$accent" "$1" "$reset" "$2" >&$fd
      fi ;;
    text)
      printf '  %s\n' "$1" >&$fd ;;
    host)
      if (( ${COLUMNS:-80} >= 100 )); then
        printf '  %s%2d%s  %s%-14s%s %s%s%s\n' "$accent" "$1" "$reset" "$bold" "$2" "$reset" "$muted" "$3" "$reset" >&$fd
      else
        printf '  %s%2d%s  %s%s%s\n      %s%s%s\n' "$accent" "$1" "$reset" "$bold" "$2" "$reset" "$muted" "$3" "$reset" >&$fd
      fi ;;
    field)
      printf '  %s%-10s%s %s\n' "$muted" "$1" "$reset" "$2" >&$fd ;;
    hint)
      printf '  %s%s%s\n' "$muted" "$1" "$reset" >&$fd ;;
    prompt)
      printf '\n  %s\n  %s›%s ' "$1" "$accent" "$reset" >&$fd ;;
    info)
      printf '  %s›%s %s\n' "$accent" "$reset" "$1" >&$fd ;;
    success)
      printf '  %s✓%s %s\n' "$green" "$reset" "$1" >&$fd ;;
    error)
      printf '  %s!%s %s\n' "$red" "$reset" "$1" >&$fd ;;
    blank) printf '\n' >&$fd ;;
  esac
}

_sshgo_command_help() {
  local topic="$1" usage="$2" title detail example='' example_hint=''
  local -a details
  case "$topic" in
    list)
      title='Saved connections'
      details=('List explicit host aliases from ~/.ssh/config.'
        'Print one alias per line when output is redirected.') ;;
    show)
      title='Connection settings'
      details=('Show effective SSH settings and saved per-host settings.'
        'HOST can be an SSH alias or a number from sshgo --list.') ;;
    manual)
      title='Manual login'
      details=('Connect with OpenSSH and skip the SSHGo saved password.'
        'Arguments after HOST are passed to SSH.')
      example='sshgo --manual example -v' example_hint='Connect with verbose SSH output' ;;
    doctor)
      title='Connection diagnostics'
      details=('Check reachability, host keys and non-interactive authentication.'
        'For ProxyJump or ProxyCommand, report the proxy and skip the live probe.')
      example='sshgo doctor example' example_hint='Check the connection' ;;
    tunnel)
      title='Port forwarding'
      details=('Forward a service from remote 127.0.0.1 to local 127.0.0.1.'
        'LOCAL_PORT defaults to REMOTE_PORT. Ports range from 1 to 65535.'
        'Press Ctrl+C to close the tunnel.')
      example='sshgo tunnel example 8888 8889' example_hint='Open remote 8888 on local 8889' ;;
    session)
      title='Persistent remote session'
      details=('Open or resume a named tmux session on the remote host.'
        'NAME defaults to work. Use letters, numbers, underscores or hyphens.'
        'Start the name with a letter, number or underscore.'
        'Requires a terminal and tmux on the remote host.'
        'Detach with Ctrl+B, then d. Reconnect with the same command.')
      example='sshgo session example analysis' example_hint='Open or resume analysis' ;;
    screen)
      title='Persistent remote sessions'
      details=('Open or resume a remote tmux session. NAME defaults to work.'
        'Use new for the first free w01, w02, ... or pass a name.'
        'AGE measures time since creation.'
        'Requires tmux on the remote host. Reconnect to the same node.'
        'Use Ctrl+B, then d to leave the session running.'
        'When finished, run exit in the last shell to close the session.')
      example='sshgo example --screen' example_hint='Open or resume work' ;;
    setup)
      title='Remote tools'
      details=('Prepare remote tools in an existing directory outside the remote home.'
        'Omit REMOTE_ROOT to use the saved path. Tool setup needs remote Python 3.')
      example='sshgo setup example warpify --dry-run' example_hint='Preview Warp storage' ;;
    remote-root)
      title='Default remote tool directory'
      details=('Omit REMOTE_ROOT to show the saved path for HOST.'
        'Pass an absolute path to save it locally for that alias.'
        'Tool setup checks the path on the remote host.')
      example='sshgo setup example remote-root /scratch/alice/tools' example_hint='Save the default path' ;;
    password-from)
      title='Reuse a saved password'
      details=('Reuse the password for SOURCE on HOST and its single ProxyJump alias.'
        'Both hops must use the same user, and the jump must share the SSH identity of SOURCE.'
        'Omit SOURCE to show the setting. Use --clear to remove the reference.')
      example='sshgo setup compute password-from gateway' example_hint='Reuse the gateway password for compute' ;;
    warpify)
      title='Warp SSH extension'
      details=('Prepare REMOTE_ROOT/warpify and link the remote ~/.warp to it.'
        'Setup stops if ~/.warp is a directory or links elsewhere.'
        'Connect from stable Warp and accept its SSH extension prompt.'
        'Omit REMOTE_ROOT to use the saved path.')
      example='sshgo setup example warpify --dry-run' example_hint='Preview the directory and link' ;;
    vscode-server)
      title='VS Code Server'
      details=('Prepare REMOTE_ROOT/vscode-server and print a serverInstallPath entry.'
        'Merge it into local VS Code User Settings JSON, then use Remote-SSH.'
        'Omit REMOTE_ROOT to use the saved path.')
      example='sshgo setup example vscode-server --dry-run' example_hint='Preview the VS Code settings' ;;
    save)
      title='Save server password'
      details=('Prompt for the server password and save it in the system keyring.'
        'Uses macOS Keychain or Linux Secret Service with secret-tool.') ;;
    forget)
      title='Remove saved password'
      details=('Remove the saved server password from the system keyring.') ;;
    download)
      title='Download files'
      details=('Download a remote file or directory over SFTP.'
        'LOCAL defaults to the current directory. Existing files may be overwritten.')
      example='sshgo --download example /remote/file ./downloads/' example_hint='Download into ./downloads/' ;;
    upload)
      title='Upload files'
      details=('Upload a local file or directory over SFTP.'
        'REMOTE defaults to the remote home. Existing files may be overwritten.')
      example='sshgo --upload example ./file /remote/directory/' example_hint='Upload into a remote directory' ;;
    speed)
      title='Download speed test'
      details=('Measure SSH download throughput without saving the data.'
        'MiB defaults to 10. Use a whole number from 1 to 999999. Requires pv.')
      example='sshgo --speed example 100' example_hint='Test with 100 MiB' ;;
    export)
      title='Export SSH configuration'
      details=('Save ~/.ssh/config and per-host remote roots to a private YAML file.'
        'Requires Python 3 and PyYAML. Choose a new output file.'
        'SSH keys, saved passwords, and known_hosts stay separate.')
      example='sshgo export ./sshgo.yaml' example_hint='Create a portable backup' ;;
    import)
      title='Import SSH configuration'
      details=('Restore the SSH config and remote roots from a trusted SSHGo YAML file.'
        'Requires Python 3 and PyYAML. Conflicting local files stop the import.')
      example='sshgo import ./sshgo.yaml' example_hint='Restore configuration on this machine' ;;
    version)
      title='Version'
      details=('Print the installed SSHGo version.') ;;
  esac
  printf 'Usage: %s\n' "$usage"
  _sshgo_ui 1 header "$title"
  for detail in "${details[@]}"; do _sshgo_ui 1 text "$detail"; done
  _sshgo_ui 1 blank
  if [[ "$topic" == setup || "$topic" == screen ]]; then
    _sshgo_ui 1 section 'ACTIONS'
    if [[ "$topic" == setup ]]; then
      _sshgo_ui 1 command 'remote-root [DIR]' 'Show or save the default tool path'
      _sshgo_ui 1 command 'password-from [SOURCE]' 'Reuse a saved password for a jump connection'
      _sshgo_ui 1 command 'warpify [DIR]' 'Prepare storage for Warp'
      _sshgo_ui 1 command 'vscode-server [DIR]' 'Prepare storage for VS Code Server'
    else
      _sshgo_ui 1 command 'new [NAME]' 'Start a new session, e.g. w01'
      _sshgo_ui 1 command 'list' 'Show status, age and window count'
      _sshgo_ui 1 command 'resume [NAME]' 'Attach to an existing session'
      _sshgo_ui 1 command 'detach [NAME]' 'Detach clients, keep tasks running'
    fi
    _sshgo_ui 1 blank
  fi
  _sshgo_ui 1 section 'OPTIONS'
  _sshgo_ui 1 command '-h, --help' 'Show this message and exit.'
  case "$topic" in
    setup|warpify|vscode-server)
      _sshgo_ui 1 command '--dry-run' 'Preview changes without creating files' ;;
  esac
  case "$topic" in
    tunnel|session|screen|setup|warpify|vscode-server|download|upload|speed)
      _sshgo_ui 1 command '--no-keyring' 'Skip saved passwords (before command)' ;;
  esac
  if [[ -n "$example" ]]; then
    _sshgo_ui 1 blank
    _sshgo_ui 1 section 'EXAMPLES'
    _sshgo_ui 1 command "$example" "$example_hint"
  fi
  if [[ "$topic" == setup ]]; then
    _sshgo_ui 1 blank
    _sshgo_ui 1 hint 'Action help: sshgo setup HOST ACTION --help'
  fi
  _sshgo_ui 1 blank
}

_sshgo_hosts() {
  local fd="$1"
  shift
  local host details endpoint i=1
  _sshgo_ui "$fd" header "$# saved connections"
  for host in "$@"; do
    # SSH resolves the actual endpoint, including defaults and Include files.
    details=$(command /usr/bin/ssh -G "$host" 2>/dev/null)
    endpoint=$(printf '%s\n' "$details" | awk '
      $1 == "user" { user = $2 }
      $1 == "hostname" { host = $2 }
      $1 == "port" { port = $2 }
      END { if (user != "" && host != "") {
        printf "%s@%s", user, host
        if (port != "" && port != "22") printf "  ·  port %s", port
      } }
    ')
    _sshgo_ui "$fd" host "$i" "$host" "${endpoint:-Configuration unavailable}"
    (( i += 1 ))
  done
}

_sshgo_doctor() {
  local target="$1" endpoint="$2" config="$3" diagnostic proxy
  local -i rc
  _sshgo_ui 1 header 'SSH connection check'
  _sshgo_ui 1 field 'Host' "$target"
  _sshgo_ui 1 field 'Endpoint' "$endpoint"
  _sshgo_ui 1 success 'OpenSSH resolved the configuration.'

  proxy=$(printf '%s\n' "$config" | awk '
    ($1 == "proxyjump" || $1 == "proxycommand") && tolower($2) != "none" { print $1; exit }
  ')
  if [[ -n "$proxy" ]]; then
    _sshgo_ui 2 error "Connection probe skipped because $target uses $proxy."
    _sshgo_ui 2 hint "Check the jump host separately, or run sshgo --manual ${(q)target} to test interactively."
    return 1
  fi

  # Exercise a fresh direct connection without prompting or modifying trust.
  if diagnostic=$(LC_ALL=C command /usr/bin/ssh -n -T \
      -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
      -o StrictHostKeyChecking=yes -o CheckHostIP=no -o UpdateHostKeys=no \
      -o NoHostAuthenticationForLocalhost=no \
      -o ControlPath=none -o ProxyCommand=none -o ClearAllForwardings=yes \
      -o ForkAfterAuthentication=no -o PermitLocalCommand=no -o AddKeysToAgent=no \
      -o ForwardAgent=no -o ForwardX11=no -o Tunnel=no \
      -o RemoteCommand=none -o SessionType=default -o LogLevel=ERROR \
      "$target" true 2>&1 >/dev/null); then
    _sshgo_ui 1 success 'Connected, verified the host key, and authenticated without a password prompt.'
    return 0
  else
    rc=$?
  fi

  case "${diagnostic:l}" in
    *'remote host identification has changed'*|*'revoked host key detected'*)
      _sshgo_ui 2 error 'The server presented a changed or revoked host key.'
      _sshgo_ui 2 hint 'Verify the fingerprint with the server administrator before updating known_hosts.' ;;
    *'host key verification failed'*|*'host key is known'*)
      _sshgo_ui 2 error 'The server host key could not be verified.'
      _sshgo_ui 2 hint "Verify the fingerprint, then connect interactively with sshgo --manual ${(q)target}." ;;
    *'could not resolve hostname'*)
      _sshgo_ui 2 error 'The hostname could not be resolved.'
      _sshgo_ui 2 hint 'Check HostName and your DNS, VPN or Tailscale connection.' ;;
    *'connection refused'*)
      _sshgo_ui 2 error 'The server refused the SSH connection.'
      _sshgo_ui 2 hint 'Check the SSH port and whether the SSH service is running.' ;;
    *'timed out'*|*'operation timeout'*|*'no route to host'*|*'network is unreachable'*)
      _sshgo_ui 2 error 'The SSH connection timed out or the network route is unavailable.'
      _sshgo_ui 2 hint 'Check your network, VPN or Tailscale and the server firewall.' ;;
    *'permission denied'*|*'too many authentication failures'*)
      _sshgo_ui 2 error 'SSH authentication failed in the non-interactive probe.'
      _sshgo_ui 2 hint "Check your user and SSH key, or run sshgo --manual ${(q)target} to test a password." ;;
    *)
      _sshgo_ui 2 error "The SSH probe did not complete (SSH exit $rc)."
      _sshgo_ui 2 hint "Run sshgo --manual ${(q)target} -v for more detail." ;;
  esac
  [[ -z "$diagnostic" ]] || printf '%s\n' "$diagnostic" >&2
  return 1
}

_sshgo_valid_root() {
  [[ "$1" == /* && "$1" != *[[:cntrl:]]* ]]
}

_sshgo_hosts_config_dir() {
  local config_home="${XDG_CONFIG_HOME-}"
  [[ "$config_home" == /* ]] || config_home="$HOME/.config"
  printf '%s/sshgo/hosts\n' "$config_home"
}

_sshgo_host_config_path() {
  emulate -L zsh
  unsetopt multibyte
  local target="$1" key='' char escaped
  local -i i
  # Escape non-portable bytes, including uppercase on case-insensitive disks.
  for (( i=1; i<=${#target}; i++ )); do
    char="${target[i]}"
    case "$char" in
      [a-z0-9._-]) key+="$char" ;;
      *) printf -v escaped '%%%02x' "'$char"; key+="$escaped" ;;
    esac
  done
  printf '%s/%s.%s\n' "$(_sshgo_hosts_config_dir)" "$key" "${2:-remote-root}"
}

_sshgo_write_host_setting() (
  local config_file="$1" temporary
  umask 077
  command mkdir -p -- "${config_file:h}" || return 1
  temporary=$(command mktemp "${config_file:h}/.sshgo.XXXXXXXX") || return 1
  trap 'command rm -f -- "$temporary"' EXIT
  printf '%s\n' "$2" > "$temporary" && command mv -f -- "$temporary" "$config_file"
)

_sshgo_config_value() {
  command awk -v key="$2" '$1 == key { print substr($0, length(key) + 2); exit }' <<< "$1"
}

_sshgo_simple_alias() {
  [[ "$1" == [a-zA-Z0-9_]* && "$1" != *[^a-zA-Z0-9._-]* ]]
}

_sshgo_password_source() {
  local config_file source
  config_file=$(_sshgo_host_config_path "$1" password-from) || return 1
  if [[ -L "$config_file" || ( -e "$config_file" && ! -f "$config_file" ) ]]; then
    _sshgo_ui 2 error "Expected a regular config file: $config_file"
    return 1
  fi
  if (( $# == 1 )); then
    [[ -f "$config_file" ]] || return 0
    source=$(<"$config_file") || return 1
    if ! _sshgo_simple_alias "$source"; then
      _sshgo_ui 2 error "Invalid password source in $config_file."
      return 2
    fi
    printf '%s\n' "$source"
  elif [[ "$2" == --clear ]]; then
    command rm -f -- "$config_file"
  elif _sshgo_simple_alias "$2"; then
    _sshgo_write_host_setting "$config_file" "$2"
  else
    _sshgo_ui 2 error 'Provide a plain SSH alias for the saved password.'
    return 2
  fi
}

_sshgo_shared_password_route() {
  local ssh_config="$1" source="$2" account="$3" hostname="$4" port="$5"
  local jump source_config jump_config source_host source_port jump_host jump_key
  jump=$(_sshgo_config_value "$ssh_config" proxyjump)
  if ! _sshgo_simple_alias "$jump" || [[ "$jump" == none ]]; then
    _sshgo_ui 2 error 'Password reuse requires a single ProxyJump alias.'
    return 2
  fi
  source_config=$(command /usr/bin/ssh -G -o LogLevel=ERROR "$source") || return $?
  jump_config=$(command /usr/bin/ssh -G -o LogLevel=ERROR "$jump") || return $?
  source_host=$(_sshgo_config_value "$source_config" hostname)
  source_port=$(_sshgo_config_value "$source_config" port)
  jump_host=$(_sshgo_config_value "$jump_config" hostname)
  jump_key=$(_sshgo_config_value "$jump_config" hostkeyalias)
  if [[ "$account" != "$(_sshgo_config_value "$source_config" user)" ||
        "$account" != "$(_sshgo_config_value "$jump_config" user)" ||
        "${jump_key:-$jump_host}" != "$source_host" ||
        "$(_sshgo_config_value "$jump_config" port)" != "$source_port" ||
        -n "$(_sshgo_config_value "$jump_config" proxyjump)" ||
        -n "$(_sshgo_config_value "$jump_config" proxycommand)" ]]; then
    _sshgo_ui 2 error 'Password reuse requires a direct jump with the source host key, port and user.'
    return 2
  fi
  # ProxyCommand is evaluated by the shell. Only embed validated endpoint values.
  if [[ -z "$source_host" || "$source_host" == *[^a-zA-Z0-9._:-]* ||
        -z "$hostname" || "$hostname" == *[^a-zA-Z0-9._:-]* ||
        "$port" != <-> || "$source_port" != <-> ]]; then
    _sshgo_ui 2 error 'Unsupported SSH endpoint for password reuse.'
    return 2
  fi
  # Give the jump its own exact askpass prompt and enforce host checks on both SSH clients.
  local proxy="ProxyCommand=/usr/bin/env SSHGO_KEYCHAIN_HOST='$source_host' /usr/bin/ssh"
  proxy+=' -o ProxyCommand=none -o StrictHostKeyChecking=yes -o NoHostAuthenticationForLocalhost=no'
  proxy+=' -o NumberOfPasswordPrompts=1 -o PreferredAuthentications=publickey,password -o KbdInteractiveAuthentication=no'
  proxy+=" -W '[$hostname]:$port' -- '$jump'"
  printf '%s\t%s\n' "sshgo:ssh:${source_host}:${source_port}" "$proxy"
}

_sshgo_config_bundle() {
  local libdir="${SSHGO_LIBDIR-}"
  if [[ -z "$libdir" ]]; then
    local source_file="${(%):-%x}"
    libdir="${source_file:A:h}"
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    _sshgo_ui 2 error 'Configuration export and import require Python 3 and PyYAML.'
    return 1
  fi
  command python3 -B "$libdir/sshgo-config.py" "$@" "$(_sshgo_hosts_config_dir)"
}

_sshgo_remote_root() {
  local target="$1" config_file root
  config_file=$(_sshgo_host_config_path "$target") || return 1
  if [[ -L "$config_file" || ( -e "$config_file" && ! -f "$config_file" ) ]]; then
    _sshgo_ui 2 error "Expected a regular config file: $config_file"
    return 1
  fi
  if (( $# == 1 )); then
    [[ -f "$config_file" ]] || return 0
    root=$(<"$config_file") || return 1
    if ! _sshgo_valid_root "$root"; then
      _sshgo_ui 2 error "Invalid remote root in $config_file."
      _sshgo_ui 2 hint "Set it again with sshgo setup ${(q)target} remote-root /remote/path."
      return 2
    fi
    printf '%s\n' "$root"
    return 0
  fi

  root="$2"
  if ! _sshgo_valid_root "$root"; then
    _sshgo_ui 2 error 'The remote root must be an absolute path on the remote host.'
    return 2
  fi
  _sshgo_write_host_setting "$config_file" "$root" || return 1
  _sshgo_ui 2 success "Saved the default remote root for $target."
}

_sshgo_setup() {
  emulate -L zsh
  local target="$1" tool="$2" root="$3" dry_run="$4" use_keyring="$5"
  local -a options
  (( use_keyring )) || options=(--no-keyring)
  # Quote each argument for the remote shell. Python reads the program from SSH stdin.
  sshgo "${options[@]}" -- "$target" -T \
    -o RemoteCommand=none -o SessionType=default -o StdinNull=no \
    -o ClearAllForwardings=yes -o PermitLocalCommand=no -o ForkAfterAuthentication=no \
    "python3 -IBS - ${(qq)tool} ${(qq)root} ${(qq)target} ${(qq)dry_run}" <<'PY'
import json
import os
from pathlib import Path
import stat
import sys


def check_directory(path):
    if path.is_symlink():
        raise ValueError(f"Tool directory cannot be a symlink: {path}")
    try:
        info = path.stat()
    except FileNotFoundError:
        return False
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid():
        raise ValueError(f"Tool directory must be a directory you own: {path}")
    if info.st_mode & 0o022 or not os.access(path, os.W_OK | os.X_OK):
        raise ValueError(f"Tool directory must be writable by you and protected from other writers: {path}")
    return True


def check_link(link, destination):
    if not os.path.lexists(link):
        return False
    if link.is_symlink() and link.resolve() == destination:
        return True
    raise ValueError(f"{link} already exists. Review it before setting up a different location.")


def prepare(tool, root, host, dry_run):
    home = Path.home().resolve(strict=True)
    root = Path(root).resolve(strict=True)
    if root == home or home in root.parents or root == Path(root.anchor):
        raise ValueError(f"Choose a project or scratch directory outside your home: {root}")
    if not root.is_dir():
        raise ValueError(f"Remote root is not a directory: {root}")

    destination = root / tool
    if destination == home:
        raise ValueError(f"Tool directory would be your home: {destination}")
    if not check_directory(destination) and not os.access(root, os.W_OK | os.X_OK):
        raise ValueError(f"Remote root is not writable: {root}")
    link = home / ".warp" if tool == "warpify" else None
    if link and not check_link(link, destination) and not os.access(home, os.W_OK | os.X_OK):
        raise ValueError(f"Cannot create a Warp symlink in {home}")

    if dry_run:
        print(f"Dry run: would prepare {destination}", file=sys.stderr)
    else:
        destination.mkdir(mode=0o700, exist_ok=True)
        check_directory(destination)
        if link and not check_link(link, destination):
            try:
                link.symlink_to(destination, target_is_directory=True)
            except FileExistsError:
                if not check_link(link, destination):
                    raise
        print(f"Ready: {destination}", file=sys.stderr)

    if link:
        print(f"Warp data path: {link} -> {destination}")
        print("After setup, connect from stable Warp and accept its SSH extension prompt.", file=sys.stderr)
    else:
        print("Merge this entry into your local VS Code User Settings JSON, then reconnect via Remote-SSH:", file=sys.stderr)
        print(json.dumps({"remote.SSH.serverInstallPath": {host: str(destination)}}, indent=2))


tool, root, host, dry_run = sys.argv[1:]
try:
    prepare(tool, root, host, dry_run == "--dry-run")
except (OSError, RuntimeError, ValueError) as exc:
    sys.exit(f"sshgo setup: {exc}")
PY
}

_sshgo_session_command() {
  emulate -L zsh
  local script
  script=$(cat <<'SH'
if ! command -v tmux >/dev/null 2>&1; then
  printf '%s\n' 'sshgo: tmux is not on the remote PATH. Install or load tmux, then retry.' >&2
  exit 127
fi

list_sessions() {
  if output=$(LC_ALL=C tmux list-sessions -F "$1" 2>&1); then
    printf '%s\n' "$output"
  else
    rc=$?
    case "$output" in
      'no server running on '*|'error connecting to '*'(No such file or directory)') return 0 ;;
      *) printf '%s\n' "$output" >&2; return "$rc" ;;
    esac
  fi
}

case "$1" in
  open) exec tmux new-session -A -s "$2" ;;
  new)
    name=$2
    if [ -z "$name" ]; then
      sessions=$(list_sessions '#{session_name}') || exit $?
      name=$(printf '%s\n' "$sessions" | LC_ALL=C awk '
        { used[$0] = 1 }
        END {
          number = 1
          while (used[sprintf("w%02d", number)]) number++
          printf "w%02d\n", number
        }
      ') || exit $?
    elif tmux has-session -t "=$name" 2>/dev/null; then
      printf 'sshgo: Session %s already exists. Use --screen resume %s.\n' "$name" "$name" >&2
      exit 1
    fi
    printf 'Starting session %s.\n' "$name" >&2
    exec tmux new-session -s "$name" ;;
  resume) exec tmux attach-session -t "=$2" ;;
  detach)
    tmux detach-client -s "=$2" || exit $?
    printf 'Session %s is detached.\n' "$2" ;;
  list)
    format='#{session_name}|#{?session_attached,attached,detached}|#{session_created}|#{session_windows}'
    output=$(list_sessions "$format") || exit $?
    if [ -n "$output" ]; then
      now=$(date +%s) || exit $?
      printf '%s\n' "$output" | LC_ALL=C awk -F '[|]' -v now="$now" '
        function age(created, seconds, days, hours, minutes) {
          if (created !~ /^[0-9]+$/) return "-"
          seconds = now - created
          if (seconds < 0) seconds = 0
          days = int(seconds / 86400)
          hours = int(seconds / 3600) % 24
          minutes = int(seconds / 60) % 60
          if (days) return sprintf("%dd %02dh", days, hours)
          if (hours) return sprintf("%dh %02dm", hours, minutes)
          if (minutes) return sprintf("%dm %02ds", minutes, seconds % 60)
          return sprintf("%ds", seconds)
        }
        BEGIN { width = 4 }
        NF >= 4 {
          # Parse the final three fields so existing names may contain a pipe.
          row = ++count
          name[row] = $0
          sub(/[|][^|]*[|][^|]*[|][^|]*$/, "", name[row])
          status[row] = $(NF-2)
          elapsed[row] = age($(NF-1))
          windows[row] = $NF
          if (length(name[row]) > width) width = length(name[row])
        }
        END {
          printf "%-*s  %-8s  %-9s  %7s\n", width, "NAME", "STATUS", "AGE", "WINDOWS"
          for (i = 1; i <= count; i++)
            printf "%-*s  %-8s  %-9s  %7s\n", width, name[i], status[i], elapsed[i], windows[i]
        }
      '
    else
      printf '%s\n' 'No tmux sessions.'
    fi ;;
esac
SH
  ) || return $?
  printf 'sh -c %s sshgo-session %s %s\n' "${(qq)script}" "${(qq)1}" "${(qq)2}"
}

sshgo() {
  local mode=connect target choice host ssh_config account hostname port service
  local usage='' installed_version
  local root_usage='sshgo setup HOST remote-root [REMOTE_ROOT]'
  local password_usage='sshgo setup HOST password-from [SOURCE|--clear]'
  local screen_usage=$'sshgo [--no-keyring] HOST --screen [NAME]\n       sshgo [--no-keyring] HOST --screen <new|resume|detach> [NAME]\n       sshgo [--no-keyring] HOST --screen list'
  local -i use_keyring=1 pick_host=$(( $# == 0 )) min_args=1 max_args=1
  local -a hosts
  if [[ "${1-}" == --no-keyring ]]; then
    use_keyring=0
    shift
  fi
  case "${1-}" in
    --set-password) mode=save; usage='sshgo --set-password HOST' ;;
    --forget-password) mode=forget; usage='sshgo --forget-password HOST' ;;
    --manual) mode=manual; usage='sshgo --manual HOST [ssh arguments...]'; max_args=-1 ;;
    --speed) mode=speed; usage='sshgo [--no-keyring] --speed HOST [MiB]'; max_args=2 ;;
    --download) mode=download; usage='sshgo [--no-keyring] --download HOST REMOTE [LOCAL]'; min_args=2; max_args=3 ;;
    --upload) mode=upload; usage='sshgo [--no-keyring] --upload HOST LOCAL [REMOTE]'; min_args=2; max_args=3 ;;
    show) mode=show; usage='sshgo show HOST' ;;
    doctor) mode=doctor; usage='sshgo doctor HOST' ;;
    export) mode=export; usage='sshgo export FILE.yaml' ;;
    import) mode=import; usage='sshgo import FILE.yaml' ;;
    tunnel)
      mode=tunnel
      usage='sshgo [--no-keyring] tunnel HOST REMOTE_PORT [LOCAL_PORT]'
      min_args=2 max_args=3 ;;
    session)
      mode=session
      usage='sshgo [--no-keyring] session HOST [NAME]'
      max_args=2 ;;
    --screen) mode=screen; usage="$screen_usage"; min_args=0; max_args=0 ;;
    setup)
      mode=setup
      usage="sshgo [--no-keyring] setup HOST TOOL [REMOTE_ROOT] [--dry-run]"$'\n       '"$root_usage"$'\n       '"$password_usage"
      min_args=2 max_args=4 ;;
    --list) mode=list; usage='sshgo --list'; min_args=0; max_args=0 ;;
    -h|--help) mode=help; usage='sshgo --help'; min_args=0; max_args=0 ;;
    -V|--version) mode=version; usage='sshgo --version'; min_args=0; max_args=0 ;;
  esac
  if [[ "$mode" != connect || "${1-}" == -- ]]; then
    shift
  fi
  if [[ "$mode" == connect && -n "${1-}" && "$1" != -* && "${2-}" == --screen ]]; then
    mode=screen usage="$screen_usage" max_args=3
    set -- "$1" "${@[3,-1]}"
  fi
  if [[ -n "$usage" ]]; then
    if (( $# == 1 )) && [[ "$mode" != help && "$1" == (-h|--help) ]]; then
      _sshgo_command_help "$mode" "$usage"
      return 0
    fi
    if (( min_args > 0 && $# == 2 )) && [[ -n "$1" && "$1" != -* && "$2" == (-h|--help) ]]; then
      # Keep SSH passthrough and literal transfer paths intact after HOST.
      case "$mode" in
        manual|upload|download) ;;
        *) _sshgo_command_help "$mode" "$usage"; return 0 ;;
      esac
    fi
    if [[ "$mode" == setup && $# == 3 && -n "$1" && "$1" != -* && "$3" == (-h|--help) ]]; then
      case "$2" in
        remote-root) _sshgo_command_help remote-root "$root_usage"; return 0 ;;
        password-from) _sshgo_command_help password-from "$password_usage"; return 0 ;;
        warpify|vscode-server)
          _sshgo_command_help "$2" "sshgo [--no-keyring] setup HOST $2 [REMOTE_ROOT] [--dry-run]"
          return 0 ;;
      esac
    fi
    if [[ "$mode" == screen && $# == 3 && "$2" == (new|list|resume|detach) && "$3" == (-h|--help) ]]; then
      _sshgo_command_help screen "$usage"
      return 0
    fi
    if (( $# < min_args || ( max_args >= 0 && $# > max_args ) )) ||
       { (( min_args > 0 )) && [[ -z "${1-}" || "$1" == -* ]]; }; then
      _sshgo_ui 2 error 'Invalid arguments.'
      _sshgo_ui 2 hint "Usage: $usage"
      return 2
    fi
  elif (( pick_host )); then
    if [[ ! -t 0 ]]; then
      _sshgo_ui 2 error 'The server picker needs an interactive terminal.'
      _sshgo_ui 2 hint 'Provide a host: sshgo HOST. List aliases: sshgo --list.'
      return 2
    fi
  elif [[ -z "${1-}" ]]; then
    _sshgo_ui 2 error 'Provide a host name or number.'
    _sshgo_ui 2 hint 'Usage: sshgo [--no-keyring] HOST [ssh arguments...]'
    return 2
  fi
  case "$mode" in
    export|import) _sshgo_config_bundle "$mode" "$1"; return $? ;;
    screen)
      if (( min_args == 0 )); then
        _sshgo_command_help screen "$usage"
        return 0
      fi ;;
    help)
      printf '%s\n' 'Usage: sshgo [--no-keyring] [HOST [SSH_ARGS...]]' \
        '       sshgo [--no-keyring] COMMAND [ARGS...]'
      _sshgo_ui 1 header 'Your servers, one command.'
      _sshgo_ui 1 section 'CONNECT'
      _sshgo_ui 1 command 'sshgo' 'Choose a server'
      _sshgo_ui 1 command 'sshgo HOST' 'Connect by name or number'
      _sshgo_ui 1 command 'sshgo --list' 'Show saved connections'
      _sshgo_ui 1 command 'sshgo show HOST' 'Show SSH settings and default tool path'
      _sshgo_ui 1 command 'sshgo doctor HOST' 'Diagnose an SSH connection'
      _sshgo_ui 1 command 'sshgo session HOST [NAME]' 'Open or resume a tmux session'
      _sshgo_ui 1 command 'sshgo HOST --screen [NAME]' 'Open or manage a tmux session'
      _sshgo_ui 1 command 'sshgo --manual HOST' 'Connect without a saved password'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'PORT FORWARDING'
      _sshgo_ui 1 command 'sshgo tunnel HOST REMOTE [LOCAL]' 'Forward a remote port to this machine'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'REMOTE TOOLS'
      _sshgo_ui 1 command 'sshgo setup HOST remote-root [DIR]' 'Show or save the default tool path'
      _sshgo_ui 1 command 'sshgo setup HOST TOOL [DIR]' 'Prepare a remote tool outside home'
      _sshgo_ui 1 hint 'Tools: warpify, vscode-server  ·  Preview changes with --dry-run'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'CONFIGURATION'
      _sshgo_ui 1 command 'sshgo export FILE.yaml' 'Save SSH configuration and tool paths'
      _sshgo_ui 1 command 'sshgo import FILE.yaml' 'Restore settings on this machine'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'PASSWORDS'
      _sshgo_ui 1 command 'sshgo --set-password HOST' 'Save or update in the system keyring'
      _sshgo_ui 1 command 'sshgo --forget-password HOST' 'Remove the saved password'
      _sshgo_ui 1 command 'sshgo setup HOST password-from SOURCE' 'Reuse a saved password for a jump connection'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'FILE TRANSFER'
      _sshgo_ui 1 command 'sshgo --download HOST REMOTE [LOCAL]' 'Download a file or folder'
      _sshgo_ui 1 command 'sshgo --upload HOST LOCAL [REMOTE]' 'Upload a file or folder'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'SPEED TEST'
      _sshgo_ui 1 command 'sshgo --speed HOST [MiB]' 'Download test · default 10 MiB'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'OPTIONS'
      _sshgo_ui 1 command 'sshgo --help' 'Show this message and exit.'
      _sshgo_ui 1 command 'sshgo --version' 'Show the installed version'
      _sshgo_ui 1 command 'sshgo --no-keyring ...' 'Skip saved passwords for one operation'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'EXAMPLES'
      _sshgo_ui 1 command 'sshgo example' 'Open a remote shell'
      _sshgo_ui 1 command 'sshgo example hostname' 'Run a remote command'
      _sshgo_ui 1 command 'sshgo --speed example 100' 'Test with 100 MiB'
      _sshgo_ui 1 blank
      _sshgo_ui 1 hint 'Command help: sshgo COMMAND --help'
      _sshgo_ui 1 hint 'Session help: sshgo --screen --help'
      _sshgo_ui 1 hint 'Connection options: sshgo HOST [ssh arguments...]'
      _sshgo_ui 1 hint 'Servers: ~/.ssh/config  ·  Colour: respects NO_COLOR'
      _sshgo_ui 1 blank
      return 0 ;;
    version)
      if [[ -n "${SSHGO_LIBDIR-}" && -r "$SSHGO_LIBDIR/version" ]] &&
         IFS= read -r installed_version < "$SSHGO_LIBDIR/version" &&
         [[ "$installed_version" == <->.<->.<-> ]]; then
        printf 'sshgo %s\n' "$installed_version"
        return 0
      fi
      _sshgo_ui 2 error 'Installed version metadata is missing or invalid.'
      _sshgo_ui 2 hint 'Run the executable installed by the sshgo package.'
      return 1 ;;
  esac
  target="${1-}"
  (( $# > 0 )) && shift
  hosts=()
  if [[ -r "$HOME/.ssh/config" ]]; then
    hosts=("${(@f)$(awk '
      tolower($1) == "host" {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /^#/) break
          if ($i !~ /[*?!]/ && !seen[$i]++) print $i
        }
      }
    ' "$HOME/.ssh/config")}")
  fi
  if [[ "$mode" == list ]]; then
    if [[ -t 1 ]]; then
      _sshgo_hosts 1 "${hosts[@]}"
      _sshgo_ui 1 blank
      _sshgo_ui 1 hint 'Connect: sshgo HOST  ·  Test speed: sshgo --speed HOST'
      _sshgo_ui 1 blank
    else
      for host in "${hosts[@]}"; do printf '%s\n' "$host"; done
    fi
    return 0
  fi
  if (( pick_host )); then
    if (( ${#hosts[@]} == 0 )); then
      _sshgo_ui 2 error 'No servers configured.'
      _sshgo_ui 2 hint 'Add a Host entry to ~/.ssh/config, then run sshgo.'
      return 1
    fi
    _sshgo_hosts 2 "${hosts[@]}"
    _sshgo_ui 2 prompt 'Select a number or host · q to cancel'
    IFS= read -r choice || return 1
    case "$choice" in q|Q|'') return 0 ;; esac
    target="$choice"
  fi
  if [[ "$target" == <-> ]]; then
    if (( ${#target} > 6 )); then
      _sshgo_ui 2 error 'Invalid server number.'
      return 2
    fi
    local index=$(( 10#$target ))
    if (( index < 1 || index > ${#hosts[@]} )); then
      _sshgo_ui 2 error "Choose a server number from 1 to ${#hosts[@]}."
      _sshgo_ui 2 hint 'Use sshgo --list to see your connections.'
      return 2
    fi
    target="${hosts[index]}"
  fi
  case "$target" in
    -*)
      _sshgo_ui 2 error "Unknown option: $target"
      _sshgo_ui 2 hint 'Run sshgo --help for available commands.'
      return 2 ;;
  esac
  if [[ "$mode" == setup ]]; then
    if [[ "$1" == password-from ]]; then
      if (( $# > 2 )); then
        _sshgo_ui 2 error 'Provide at most one password source.'
        _sshgo_ui 2 hint "Usage: $password_usage"
        return 2
      fi
      shift
      _sshgo_password_source "$target" "$@"
      return $?
    fi
    if [[ "$1" == remote-root ]]; then
      case "$#" in
        1)
          local saved_root
          saved_root=$(_sshgo_remote_root "$target") || return $?
          printf '%s\n' "${saved_root:-Not set}"
          return 0 ;;
        2) _sshgo_remote_root "$target" "$2"; return $? ;;
        *)
          _sshgo_ui 2 error 'Provide at most one remote root path.'
          _sshgo_ui 2 hint "Usage: $root_usage"
          return 2 ;;
      esac
    fi
    local setup_tool="$1" setup_root="${2-}" dry_run="${3-}"
    if (( $# == 2 )) && [[ "$setup_root" == --dry-run ]]; then
      setup_root='' dry_run=--dry-run
    elif { (( $# >= 2 )) && ! _sshgo_valid_root "$setup_root"; } ||
         { (( $# == 3 )) && [[ "$dry_run" != --dry-run ]]; }; then
      _sshgo_ui 2 error 'Expected an absolute remote path followed by optional --dry-run.'
      _sshgo_ui 2 hint "Usage: $usage"
      return 2
    fi
    if [[ "$setup_tool" != (warpify|vscode-server) ]]; then
      _sshgo_ui 2 error "Unknown remote tool: $setup_tool"
      _sshgo_ui 2 hint "Usage: $usage"
      return 2
    fi
    if [[ -z "$setup_root" ]]; then
      setup_root=$(_sshgo_remote_root "$target") || return $?
      if [[ -z "$setup_root" ]]; then
        _sshgo_ui 2 error "No default remote root saved for $target."
        _sshgo_ui 2 hint "Save one with sshgo setup ${(q)target} remote-root /remote/path, or pass a path to setup."
        return 2
      fi
    fi
    _sshgo_setup "$target" "$setup_tool" "$setup_root" "$dry_run" "$use_keyring"
    return $?
  fi
  if [[ "$mode" == tunnel ]]; then
    local remote_port="$1" local_port="${2-$1}"
    if [[ "$remote_port" != <-> || "$local_port" != <-> ]] ||
       (( ${#remote_port} > 5 || ${#local_port} > 5 )); then
      _sshgo_ui 2 error 'Ports must be whole numbers from 1 to 65535.'
      _sshgo_ui 2 hint "Usage: $usage"
      return 2
    fi
    remote_port=$(( 10#$remote_port ))
    local_port=$(( 10#$local_port ))
    if (( remote_port < 1 || remote_port > 65535 || local_port < 1 || local_port > 65535 )); then
      _sshgo_ui 2 error 'Ports must be from 1 to 65535.'
      _sshgo_ui 2 hint "Usage: $usage"
      return 2
    fi
    _sshgo_ui 2 header 'SSH tunnel'
    _sshgo_ui 2 field 'Local' "127.0.0.1:$local_port"
    _sshgo_ui 2 field 'Remote' "$target · 127.0.0.1:$remote_port"
    _sshgo_ui 2 hint "For a web service, open http://127.0.0.1:$local_port after SSH connects."
    _sshgo_ui 2 hint 'Press Ctrl+C to stop the tunnel.'
    set -- -N -T -o ExitOnForwardFailure=yes -o ClearAllForwardings=no \
      -o ForkAfterAuthentication=no \
      -o ControlPath=none -o RemoteCommand=none -o PermitLocalCommand=no \
      -L "127.0.0.1:$local_port:127.0.0.1:$remote_port"
  fi
  if [[ "$mode" == (session|screen) ]]; then
    local session_action=open
    if [[ "$mode" == screen ]]; then
      case "${1-}" in
        new|list|resume|detach) session_action="$1"; shift ;;
      esac
      if (( $# > 1 )) || { [[ "$session_action" == list ]] && (( $# > 0 )); }; then
        _sshgo_ui 2 error 'Unexpected arguments for --screen.'
        _sshgo_ui 2 hint "Usage: $usage"
        return 2
      fi
    fi
    local session_name="${1-work}"
    if [[ "$session_action" == new ]] && (( $# == 0 )); then
      session_name=''
    elif [[ -z "$session_name" || "$session_name" == -* || "$session_name" == *[^a-zA-Z0-9_-]* ]]; then
      _sshgo_ui 2 error 'Use letters, numbers, hyphens or underscores. Start with a letter, number or underscore.'
      _sshgo_ui 2 hint "Usage: $usage"
      return 2
    fi
    local -a session_options
    if [[ "$session_action" == (open|new|resume) ]]; then
      if [[ ! -t 0 || ! -t 1 ]]; then
        _sshgo_ui 2 error 'A remote session needs an interactive terminal.'
        return 2
      fi
      if [[ "$session_action" == new && -z "$session_name" ]]; then
        _sshgo_ui 2 info "New tmux session on $target"
      else
        _sshgo_ui 2 info "Session $session_name on $target"
      fi
      session_options=(-t -o StdinNull=no)
    else
      session_options=(-T -n -o ClearAllForwardings=yes)
    fi
    local session_command
    session_command=$(_sshgo_session_command "$session_action" "$session_name") || return $?
    set -- "${session_options[@]}" -o RemoteCommand=none -o SessionType=default \
      -o ForkAfterAuthentication=no "$session_command"
  fi
  if [[ "$mode" == speed ]]; then
    local size="${1-10}"
    if [[ "$size" != <-> ]] || (( ${#size} > 6 )); then
      _sshgo_ui 2 error 'Test size must be a whole number from 1 to 999999 MiB.'
      _sshgo_ui 2 hint 'Usage: sshgo --speed HOST [MiB]  ·  Default: 10 MiB'
      return 2
    fi
    local size_mib=$(( 10#$size ))
    if (( size_mib < 1 )); then
      _sshgo_ui 2 error 'Test size must be at least 1 MiB.'
      return 2
    fi
    if ! command -v pv >/dev/null 2>&1; then
      _sshgo_ui 2 error 'Speed tests need pv.'
      _sshgo_ui 2 hint 'Install pv with your system package manager.'
      return 1
    fi
    local -a speed_status speed_options
    local received_bytes
    local -i expected_bytes=$(( size_mib * 1048576 ))
    (( use_keyring )) || speed_options=(--no-keyring)
    _sshgo_ui 2 header 'Download speed test'
    _sshgo_ui 2 field 'Server' "$target"
    _sshgo_ui 2 field 'Direction' 'Remote → local'
    _sshgo_ui 2 field 'Transfer' "$size_mib MiB"
    _sshgo_ui 2 blank
    # The normal connection path preserves keyring authentication. -W waits
    # for data, keeping connection/authentication time out of the progress timer.
    received_bytes=$(
      sshgo "${speed_options[@]}" -- "$target" -T -o Compression=no \
        "dd if=/dev/zero bs=1048576 count=${size_mib} 2>/dev/null" \
        | command pv -W -f -s "$expected_bytes" -F '  %p  %b  %t  %r  avg %a' \
        | command wc -c
      speed_status=( "${pipestatus[@]}" )
      if (( speed_status[1] != 0 )); then
        _sshgo_ui 2 error "Speed test failed (SSH exit ${speed_status[1]}); no valid measurement."
        exit "${speed_status[1]}"
      fi
      if (( speed_status[2] != 0 || speed_status[3] != 0 )); then
        _sshgo_ui 2 error 'Could not measure the speed test data.'
        exit 1
      fi
    ) || return $?
    received_bytes="${received_bytes//[[:space:]]/}"
    if [[ "$received_bytes" != "$expected_bytes" ]]; then
      _sshgo_ui 2 error "Received $received_bytes of $expected_bytes expected bytes; no valid measurement."
      return 1
    fi
    _sshgo_ui 2 success 'Transfer complete.'
    _sshgo_ui 2 blank
    return 0
  fi
  if [[ "$mode" == manual ]]; then
    if [[ -t 0 && -t 1 ]]; then
      _sshgo_ui 2 info "Connecting to $target · manual login"
    fi
    command /usr/bin/ssh "$target" "$@"
    return $?
  fi

  # Transfer operands are paths, not SSH options or remote commands.
  local -a config_args
  if [[ "$mode" == download || "$mode" == upload ]]; then
    if [[ -z "$1" || ( $# == 2 && -z "$2" ) ]]; then
      _sshgo_ui 2 error 'Provide a source path and optionally a destination path.'
      _sshgo_ui 2 hint "Usage: $usage"
      return 2
    fi
    config_args=()
  else
    config_args=("$@")
  fi

  # Resolve user/host/port with SSH itself, including aliases and option overrides.
  ssh_config=$(command /usr/bin/ssh -G -o LogLevel=ERROR "$target" "${config_args[@]}") || {
    _sshgo_ui 2 error "Could not resolve the SSH configuration for $target."
    return 2
  }
  if [[ "$mode" == show ]]; then
    local show_root show_source
    show_root=$(_sshgo_remote_root "$target") || return $?
    show_source=$(_sshgo_password_source "$target") || return $?
    _sshgo_ui 1 header 'SSH configuration'
    _sshgo_ui 1 field 'Host' "$target"
    # Only print connection metadata. Arbitrary commands and environment
    # variables in ssh -G output can contain secrets.
    local key value
    while IFS=' ' read -r key value; do
      case "$key" in
        hostname) _sshgo_ui 1 field 'Hostname' "$value" ;;
        user) _sshgo_ui 1 field 'User' "$value" ;;
        port) _sshgo_ui 1 field 'Port' "$value" ;;
        proxyjump) _sshgo_ui 1 field 'ProxyJump' "$value" ;;
        identityfile) _sshgo_ui 1 field 'IdentityFile' "$value" ;;
        identitiesonly) _sshgo_ui 1 field 'IdentitiesOnly' "$value" ;;
        stricthostkeychecking) _sshgo_ui 1 field 'HostKeyCheck' "$value" ;;
      esac
    done <<< "$ssh_config"
    _sshgo_ui 1 field 'RemoteRoot' "${show_root:-Not set}"
    [[ -z "$show_source" ]] || _sshgo_ui 1 field 'PasswordFrom' "$show_source"
    return 0
  fi
  account=$(_sshgo_config_value "$ssh_config" user)
  hostname=$(_sshgo_config_value "$ssh_config" hostname)
  port=$(_sshgo_config_value "$ssh_config" port)
  if [[ -z "$account" || -z "$hostname" || -z "$port" ]]; then
    _sshgo_ui 2 error 'The SSH configuration needs a user, hostname, and port.'
    return 2
  fi
  service="sshgo:ssh:${hostname}:${port}"
  case "$mode" in
    doctor)
      _sshgo_doctor "$target" "${account}@${hostname}:${port}" "$ssh_config"
      return $? ;;
    save)
      _sshgo_ui 2 header 'Save server password'
      _sshgo_ui 2 field 'Account' "${account}@${hostname}:${port}"
      _sshgo_ui 2 hint 'Enter the server password below. It is stored in your system keyring.'
      _sshgo_ui 2 blank
      _sshgo_secret_store "$service" "$account" "$hostname" "$port" || return $?
      _sshgo_ui 2 success 'Password saved.'
      _sshgo_ui 2 hint "Ready to connect: sshgo $target"
      return 0 ;;
    forget)
      _sshgo_secret_clear "$service" "$account" || return $?
      _sshgo_ui 2 success "Saved password deleted for $target."
      return 0 ;;
  esac
  local prompt_host="$hostname" password_source route proxy default_config
  local -a password_options
  if (( use_keyring )); then
    password_source=$(_sshgo_password_source "$target") || return $?
    if [[ -n "$password_source" ]]; then
      if (( ${#config_args[@]} )); then
        # Passthrough options may change where the saved password would go.
        default_config=$(command /usr/bin/ssh -G -o LogLevel=ERROR "$target") || return $?
        local identity_fields='/^(user|hostname|port|hostkeyalias|proxyjump|proxycommand) /'
        if [[ "$(command awk "$identity_fields" <<< "$default_config")" !=
              "$(command awk "$identity_fields" <<< "$ssh_config")" ]]; then
          _sshgo_ui 2 error 'SSH options changed the configured password reuse route.'
          _sshgo_ui 2 hint "Connect manually: sshgo --manual ${(q)target}"
          return 2
        fi
      fi
      route=$(_sshgo_shared_password_route "$ssh_config" "$password_source" "$account" "$hostname" "$port") || return $?
      IFS=$'\t' read -r service proxy <<< "$route"
      prompt_host=$(_sshgo_config_value "$ssh_config" hostkeyalias)
      prompt_host="${prompt_host:-$hostname}"
      password_options=(-o "$proxy" -o NoHostAuthenticationForLocalhost=no)
      if ! _sshgo_secret_exists "$service" "$account"; then
        _sshgo_ui 2 error "No saved password for $password_source."
        _sshgo_ui 2 hint "Save it with sshgo --set-password ${(q)password_source}."
        return 1
      fi
    fi
  fi
  if [[ "$mode" == download || "$mode" == upload ]]; then
    local local_path remote_path remote_operand local_operand ch
    local -i i rc=0
    if [[ "$mode" == download ]]; then
      remote_path="$1"
      local_path="${2-.}"
      # scp's SFTP download expands glob characters; escape literal names.
      remote_operand=''
      for (( i=1; i<=${#remote_path}; i++ )); do
        ch="${remote_path[i]}"
        case "$ch" in
          '\'|'*'|'?'|'['|']') remote_operand+="\\$ch" ;;
          *) remote_operand+="$ch" ;;
        esac
      done
      remote_operand="${target}:${remote_operand}"
    else
      local_path="$1"
      remote_path="${2-.}"
      if [[ ! -e "$local_path" ]]; then
        _sshgo_ui 2 error "Local source does not exist: $local_path"
        return 1
      fi
      remote_operand="${target}:${remote_path}"
    fi
    # Local relative names containing ':' or starting with '-' must stay local.
    local_operand="$local_path"
    [[ "$local_operand" == /* ]] || local_operand="./$local_operand"
    local -a scp_args
    # OpenSSH 8.9 needs -s; later versions also accept it and default to SFTP.
    scp_args=(-s -r)
    if [[ "$mode" == download ]]; then
      scp_args+=("$remote_operand" "$local_operand")
    else
      scp_args+=("$local_operand" "$remote_operand")
    fi
    _sshgo_ui 2 header "${mode:u}"
    _sshgo_ui 2 field 'Server' "$target"
    if [[ "$mode" == download ]]; then
      _sshgo_ui 2 field 'From' "$remote_path"
      _sshgo_ui 2 field 'To' "$local_path"
    else
      _sshgo_ui 2 field 'From' "$local_path"
      _sshgo_ui 2 field 'To' "$remote_path"
    fi
    _sshgo_ui 2 blank
    if (( use_keyring )) && { [[ -n "$password_source" ]] || _sshgo_secret_exists "$service" "$account"; }; then
      if [[ ! -x "$SSHGO_LIBDIR/sshgo-askpass" ]]; then
        _sshgo_ui 2 error 'The password helper is missing.'
        return 1
      fi
      SSH_ASKPASS="$SSHGO_LIBDIR/sshgo-askpass" SSH_ASKPASS_REQUIRE=force \
        SSHGO_KEYCHAIN_SERVICE="$service" SSHGO_KEYCHAIN_ACCOUNT="$account" \
        SSHGO_KEYCHAIN_HOST="$prompt_host" LC_ALL=C \
        command /usr/bin/scp -o StrictHostKeyChecking=yes \
          -o NumberOfPasswordPrompts=1 \
          -o PreferredAuthentications=publickey,password \
          -o KbdInteractiveAuthentication=no "${password_options[@]}" "${scp_args[@]}" || rc=$?
    else
      command /usr/bin/scp "${scp_args[@]}" || rc=$?
    fi
    if (( rc != 0 )); then
      _sshgo_ui 2 error "Transfer failed (exit $rc)."
      return "$rc"
    fi
    _sshgo_ui 2 success 'Transfer complete.'
    return 0
  fi
  if [[ -t 0 && -t 1 && $# == 0 ]]; then
    _sshgo_ui 2 info "Connecting to $target"
    _sshgo_ui 2 hint "${account}@${hostname}:${port}"
  fi
  # Check whether a saved secret is available. OpenSSH uses its askpass interface.
  if (( use_keyring )) && { [[ -n "$password_source" ]] || _sshgo_secret_exists "$service" "$account"; }; then
    if [[ ! -x "$SSHGO_LIBDIR/sshgo-askpass" ]]; then
      _sshgo_ui 2 error 'The password helper is missing.'
      _sshgo_ui 2 hint "Connect manually: sshgo --manual $target"
      return 1
    fi
    SSH_ASKPASS="$SSHGO_LIBDIR/sshgo-askpass" SSH_ASKPASS_REQUIRE=force \
      SSHGO_KEYCHAIN_SERVICE="$service" SSHGO_KEYCHAIN_ACCOUNT="$account" \
      SSHGO_KEYCHAIN_HOST="$prompt_host" LC_ALL=C \
      command /usr/bin/ssh \
        -o StrictHostKeyChecking=yes \
        -o NumberOfPasswordPrompts=1 \
        -o PreferredAuthentications=publickey,password \
        -o KbdInteractiveAuthentication=no \
        "${password_options[@]}" "$target" "$@"
  else
    command /usr/bin/ssh "$target" "$@"
  fi
}
