# sshgo

A small SSH connection picker, file transfer helper and download speed test for Ubuntu and Debian. It uses your existing OpenSSH configuration and SSH keys.

## Install

Download `sshgo_0.1.0_all.deb` from this repository and install it on Ubuntu or Debian:

```sh
sudo apt install ./sshgo_0.1.0_all.deb
```

Configure hosts in `~/.ssh/config`. The package does not contain user SSH configuration, keys or passwords.

```sshconfig
Host example
  HostName server.example.com
  User your_username
```

```sh
sshgo                         # Pick a server
sshgo --list                  # List servers
sshgo example                 # Connect
sshgo --download example /remote/file ~/Downloads/
sshgo --upload example ./file /remote/directory/
sshgo --speed example         # Download 10 MiB of test data
sshgo --speed example 100     # Change the test size in MiB
sshgo --help
```

Transfers support files and directories. Existing destination files can be overwritten. `scp -r` follows symbolic links when traversing directories. Quote paths containing spaces or shell metacharacters. Download destinations default to the current local directory; upload destinations default to the remote home directory.

## Passwords and host keys

SSH keys and normal interactive SSH password prompts work without a keyring. Optional `sshgo --set-password example` stores a server password in a desktop Secret Service keyring using `secret-tool` (package `libsecret-tools`); an available unlocked Secret Service session is required. This feature is often unavailable in headless SSH sessions; use SSH keys or enter the password interactively there. `sshgo --forget-password example` deletes the saved password.

When using a saved password, SSHGo requires a previously verified server host key. For a new host, run `sshgo --manual example`, verify its host fingerprint and accept it before using the saved password.

The optional speed test uses `pv` and measures remote-to-local SSH throughput without writing the test data to disk. Measurements include SSH transport overhead.

## Build

On macOS, Debian or Ubuntu, run `./scripts/build-deb.sh` with Python 3. The package is created in `dist/`. The build contains no personal SSH configuration, credentials, SSH keys or host lists.

## Release

Run `./sshgorel 0.1.1 --branch main --dry` to check release inputs without making changes. Omit `--dry` to build the Debian package, commit release metadata, push to the specified existing remote branch, create a tag, and upload the package to GitHub Releases. The release command requires `git`, `python3`, an authenticated `gh`, a clean checkout and the current commit matching the named remote branch. It creates no local branch.
