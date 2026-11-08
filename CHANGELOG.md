# Changelog

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
