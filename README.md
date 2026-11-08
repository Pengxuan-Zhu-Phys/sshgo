# sshgo

SSH connection picker, file transfers and download speed tests for macOS, Ubuntu and Debian. It uses your existing OpenSSH configuration and SSH keys. Transfers require OpenSSH 8.9 or newer with SFTP support on the server.

## Install

The Debian package can be built on macOS, Ubuntu or Debian with Python 3:

```sh
./scripts/build-deb.sh
sudo apt install ./dist/sshgo_1.0.2_all.deb
```

Run the `apt install` command on an Ubuntu or Debian machine. A Homebrew tap and a signed APT repository can be prepared as described below; they are not automatically published.

Configure hosts in `~/.ssh/config`. No user SSH configuration, keys or passwords are included in the project or package.

```sshconfig
Host example
  HostName server.example.com
  User your_username
```

Each explicit alias gets its own entry in the picker and `--list`. For example, `Host lab work` lists both `lab` and `work`, even if they connect to the same endpoint.

```sh
sshgo                         # Pick a server
sshgo --list                  # List servers
sshgo example                 # Connect
sshgo show example            # Show effective connection settings
sshgo --download example /remote/file ~/Downloads/
sshgo --upload example ./file /remote/directory/
sshgo --speed example         # Download 10 MiB of test data
sshgo --speed example 100     # Change the test size in MiB
sshgo --version               # Show the installed version
sshgo --help
```

`sshgo show HOST` displays selected settings resolved by OpenSSH, such as the hostname, user, port, jump host and identity file paths. It does not display passwords, key contents or arbitrary configured commands. If your SSH alias is named `show`, connect with `sshgo -- show`.

Transfers support files and directories. Existing destination files can be overwritten. `scp -r` follows symbolic links when traversing directories. Quote paths containing spaces or shell metacharacters. Download destinations default to the current local directory; upload destinations default to the remote home directory.

If you already have a shell function or alias named `sshgo`, it may take precedence over the installed executable. Remove that existing definition or call the executable by its installed path when migrating.

## Passwords and host keys

SSH keys and normal interactive SSH password prompts work without a keyring. `sshgo --set-password example` optionally saves the server password in macOS Keychain, or on Linux in a desktop Secret Service keyring through `secret-tool` (package `libsecret-tools`). Linux requires an available, unlocked Secret Service session; on headless systems, use SSH keys or enter the password interactively. `sshgo --forget-password example` deletes the saved password.

When using a saved password, SSHGo requires a previously verified server host key. For a new host, run `sshgo --manual example`, verify its host fingerprint and accept it before using the saved password.

Put `--no-keyring` first to skip saved passwords for a single operation, for example `sshgo --no-keyring --download example /remote/file`. This also works for connections, uploads and speed tests, and lets OpenSSH handle authentication normally.

The optional speed test uses `pv` and measures remote-to-local SSH throughput without writing the test data to disk. A test only succeeds if the requested byte count arrives. Measurements include SSH transport overhead.

## Prepare a Homebrew tap

After creating the matching GitHub tag, download its source archive from `https://github.com/Pengxuan-Zhu-Phys/sshgo/archive/refs/tags/v1.0.2.tar.gz`. Then render a formula using the exact downloaded archive:

```sh
python3 scripts/render-homebrew-formula.py 1.0.2 sshgo-1.0.2.tar.gz --output /path/to/homebrew-tap/Formula/sshgo.rb
```

Review and publish the formula in your tap. Once published, users can install it with `brew install Pengxuan-Zhu-Phys/tap/sshgo` if the tap repository is named `homebrew-tap`. The renderer embeds the archive's SHA-256; use the archive downloaded from the tag, not a locally generated substitute.

## Prepare a signed APT repository

On Debian or Ubuntu, install `apt-utils`, `dpkg-dev`, `gnupg`, `gzip` and Python 3. Use an existing signing key managed outside this repository:

```sh
./scripts/build-deb.sh
./scripts/build-apt-repo.sh dist/apt-repo YOUR_KEY_FINGERPRINT dist/sshgo_1.0.2_all.deb
```

The output path must not already exist. The generated snapshot includes `Packages`, `Release`, `InRelease`, `Release.gpg`, the public key, and the package. Multiple `.deb` arguments preserve multiple package versions in a snapshot. Publish this directory to an HTTPS static host such as GitHub Pages. Configure clients with the verified public key using APT's `signed-by` option; never commit a private signing key. Repository creation, key management, hosting, and deployment are not performed by the build script.

After publishing, a Debian or Ubuntu user can configure the source as follows, replacing the placeholder URL. Verify the key fingerprint through a separate trusted channel before installing the key:

```sh
APT_REPO_URL="https://YOUR_APT_HOST"
curl -fsSL "$APT_REPO_URL/sshgo-archive-key.asc" -o /tmp/sshgo-archive-key.asc
gpg --show-keys --fingerprint /tmp/sshgo-archive-key.asc
sudo install -d -m 755 /etc/apt/keyrings
sudo install -m 644 /tmp/sshgo-archive-key.asc /etc/apt/keyrings/sshgo.asc
printf 'deb [signed-by=/etc/apt/keyrings/sshgo.asc] %s stable main\n' "$APT_REPO_URL" | sudo tee /etc/apt/sources.list.d/sshgo.list
sudo apt update
sudo apt install sshgo
```

The prepared repository publishes indices for amd64 and arm64 clients and contains architecture-independent packages.

## License

MIT. See [LICENSE](LICENSE).
