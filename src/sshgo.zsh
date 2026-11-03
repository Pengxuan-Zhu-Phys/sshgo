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
# UI uses stderr except help/list; SSH stdout remains suitable for pipelines.
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
      printf '    %s%-34s%s %s\n' "$accent" "$1" "$reset" "$2" >&$fd ;;
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

sshgo() {
  local mode=connect target choice host ssh_config account hostname port service
  local -a hosts
  case "${1-}" in
    --set-password) mode=save; shift ;;
    --forget-password) mode=forget; shift ;;
    --manual) mode=manual; shift ;;
    --speed) mode=speed; shift ;;
    --download) mode=download; shift ;;
    --upload) mode=upload; shift ;;
    -h|--help)
      _sshgo_ui 1 header 'Your servers, one command.'
      _sshgo_ui 1 section 'CONNECT'
      _sshgo_ui 1 command 'sshgo' 'Choose a server'
      _sshgo_ui 1 command 'sshgo HOST' 'Connect by name or number'
      _sshgo_ui 1 command 'sshgo --list' 'Show saved connections'
      _sshgo_ui 1 command 'sshgo --manual HOST' 'Connect without a saved password'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'PASSWORDS'
      _sshgo_ui 1 command 'sshgo --set-password HOST' 'Save or update in the system keyring'
      _sshgo_ui 1 command 'sshgo --forget-password HOST' 'Remove the saved password'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'FILE TRANSFER'
      _sshgo_ui 1 command 'sshgo --download HOST REMOTE [LOCAL]' 'Download a file or folder'
      _sshgo_ui 1 command 'sshgo --upload HOST LOCAL [REMOTE]' 'Upload a file or folder'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'SPEED TEST'
      _sshgo_ui 1 command 'sshgo --speed HOST [MiB]' 'Download test · default 10 MiB'
      _sshgo_ui 1 blank
      _sshgo_ui 1 section 'EXAMPLES'
      _sshgo_ui 1 command 'sshgo example' 'Open a remote shell'
      _sshgo_ui 1 command 'sshgo example hostname' 'Run a remote command'
      _sshgo_ui 1 command 'sshgo --speed example 100' 'Test with 100 MiB'
      _sshgo_ui 1 blank
      _sshgo_ui 1 hint 'Connection options: sshgo HOST [ssh arguments...]'
      _sshgo_ui 1 hint 'Servers: ~/.ssh/config  ·  Colour: respects NO_COLOR'
      _sshgo_ui 1 blank
      return 0 ;;
  esac
  target="${1-}"
  (( $# > 0 )) && shift
  hosts=()
  if [[ -r "$HOME/.ssh/config" ]]; then
    hosts=("${(@f)$(awk '
      tolower($1) == "host" {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /^#/) break
          if ($i !~ /[*?!]/) { if (!seen[$i]++) print $i; break }
        }
      }
    ' "$HOME/.ssh/config")}")
  fi
  if [[ "$target" == --list && "$mode" == connect ]]; then
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
  if [[ -z "$target" ]]; then
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
  if [[ "$mode" == speed ]]; then
    local size="${1-10}"
    if (( $# > 1 )) || [[ "$size" != <-> ]] || (( ${#size} > 6 )); then
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
    local -a speed_status
    _sshgo_ui 2 header 'Download speed test'
    _sshgo_ui 2 field 'Server' "$target"
    _sshgo_ui 2 field 'Direction' 'Remote → local'
    _sshgo_ui 2 field 'Transfer' "$size_mib MiB"
    _sshgo_ui 2 blank
    # The normal connection path preserves keyring authentication. -W waits
    # for data, keeping connection/authentication time out of the progress timer.
    sshgo "$target" -T -o Compression=no \
      "dd if=/dev/zero bs=1048576 count=${size_mib} 2>/dev/null" \
      | command pv -W -f -s "$(( size_mib * 1048576 ))" \
          -F '  %p  %b  %t  %r  avg %a' > /dev/null
    speed_status=( "${pipestatus[@]}" )
    if (( speed_status[1] != 0 )); then
      _sshgo_ui 2 error "Speed test failed (SSH exit ${speed_status[1]}); no valid measurement."
      return "${speed_status[1]}"
    fi
    if (( speed_status[2] != 0 )); then
      _sshgo_ui 2 error 'The speed display could not finish.'
      return "${speed_status[2]}"
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
    if (( $# < 1 || $# > 2 )) || [[ -z "${1-}" || ( $# == 2 && -z "${2-}" ) ]]; then
      _sshgo_ui 2 error 'Provide a source path and optionally a destination path.'
      _sshgo_ui 2 hint "Usage: sshgo --$mode HOST SOURCE [DESTINATION]"
      return 2
    fi
    config_args=()
  else
    config_args=("$@")
  fi

  # Resolve user/host/port with SSH itself, including aliases and option overrides.
  ssh_config=$(command /usr/bin/ssh -G "$target" "${config_args[@]}" 2>/dev/null) || {
    _sshgo_ui 2 error 'Could not resolve the SSH configuration.'
    return 2
  }
  account=$(printf '%s\n' "$ssh_config" | awk '$1 == "user" { print $2; exit }')
  hostname=$(printf '%s\n' "$ssh_config" | awk '$1 == "hostname" { print $2; exit }')
  port=$(printf '%s\n' "$ssh_config" | awk '$1 == "port" { print $2; exit }')
  if [[ -z "$account" || -z "$hostname" || -z "$port" ]]; then
    _sshgo_ui 2 error 'The SSH configuration needs a user, hostname, and port.'
    return 2
  fi
  service="sshgo:ssh:${hostname}:${port}"
  case "$mode" in
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
    if _sshgo_secret_exists "$service" "$account"; then
      if [[ ! -x "$SSHGO_LIBDIR/sshgo-askpass" ]]; then
        _sshgo_ui 2 error 'The password helper is missing.'
        return 1
      fi
      SSH_ASKPASS="$SSHGO_LIBDIR/sshgo-askpass" SSH_ASKPASS_REQUIRE=force \
        SSHGO_KEYCHAIN_SERVICE="$service" SSHGO_KEYCHAIN_ACCOUNT="$account" \
        SSHGO_KEYCHAIN_HOST="$hostname" LC_ALL=C \
        command /usr/bin/scp -o StrictHostKeyChecking=yes \
          -o NumberOfPasswordPrompts=1 \
          -o PreferredAuthentications=publickey,password \
          -o KbdInteractiveAuthentication=no "${scp_args[@]}" || rc=$?
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
  if _sshgo_secret_exists "$service" "$account"; then
    if [[ ! -x "$SSHGO_LIBDIR/sshgo-askpass" ]]; then
      _sshgo_ui 2 error 'The password helper is missing.'
      _sshgo_ui 2 hint "Connect manually: sshgo --manual $target"
      return 1
    fi
    SSH_ASKPASS="$SSHGO_LIBDIR/sshgo-askpass" SSH_ASKPASS_REQUIRE=force \
      SSHGO_KEYCHAIN_SERVICE="$service" SSHGO_KEYCHAIN_ACCOUNT="$account" \
      SSHGO_KEYCHAIN_HOST="$hostname" LC_ALL=C \
      command /usr/bin/ssh \
        -o StrictHostKeyChecking=yes \
        -o NumberOfPasswordPrompts=1 \
        -o PreferredAuthentications=publickey,password \
        -o KbdInteractiveAuthentication=no \
        "$target" "$@"
  else
    command /usr/bin/ssh "$target" "$@"
  fi
}
