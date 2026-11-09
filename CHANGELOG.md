# Changelog

## Unreleased

- Add `sshgo doctor HOST` to diagnose direct SSH connections without prompting or changing host trust.
- Add `sshgo tunnel HOST REMOTE_PORT [LOCAL_PORT]` to forward a remote service to local loopback.
- Add `sshgo session HOST [NAME]` to open or resume a remote tmux session.
- Add `sshgo HOST --screen` with automatic `w01`-style or explicit session names, resume and detach, and a list with status, age and window count.
- Add `sshgo setup` to prepare Warp and VS Code Server storage outside the remote home directory.
- Show or save the default tool directory per SSH alias with `sshgo setup HOST remote-root [REMOTE_ROOT]`.
- Add dedicated help for each command and each remote setup action.
- Export and restore local SSH configuration and per-alias remote roots with a private YAML file.
- Reuse an existing keyring password on a verified two-hop connection with `sshgo setup HOST password-from SOURCE`.

## 1.0.2 — 2026-11-09
- List each explicit alias on a `Host` line as a separate connection.

## 1.0.1 — 2026-11-09
- Add `sshgo show HOST` for connection settings and `sshgo --version` for the installed version.
- Add `--no-keyring` for individual connections, transfers and speed tests.
- Report invalid command arguments and preserve OpenSSH configuration errors.
- Fail speed tests if the received byte count differs from the requested size.

## 1.0.0 — 2026-11-03
- License the project under the MIT License.

- Support macOS Keychain and Linux Secret Service through one portable executable.
- Prepare Homebrew formula rendering and signed APT repository generation.
- Add the SSH server picker and file uploads and downloads.
- Add a download speed test and optional password storage.
- Add a portable Debian package builder.
