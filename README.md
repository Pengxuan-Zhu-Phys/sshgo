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
sshgo show example            # Show connection settings and the default tool directory
sshgo doctor example          # Diagnose a connection without prompting
sshgo session example         # Open or resume the remote tmux session named work
sshgo example --screen list    # List remote tmux sessions
sshgo tunnel example 8888     # Forward remote port 8888 to local port 8888
sshgo setup example remote-root /scratch/your_username/tools
sshgo setup example warpify --dry-run
sshgo --download example /remote/file ~/Downloads/
sshgo --upload example ./file /remote/directory/
sshgo --speed example         # Download 10 MiB of test data
sshgo --speed example 100     # Change the test size in MiB
sshgo export ./sshgo.yaml     # Save SSH config and per-host tool paths
sshgo import ./sshgo.yaml     # Restore them on this machine
sshgo --version               # Show the installed version
sshgo --help
```

`sshgo show HOST` displays selected settings resolved by OpenSSH, such as the hostname, user, port, jump host and identity file paths. It also displays SSHGo's saved `RemoteRoot` and any `PasswordFrom` alias. It does not display passwords, key contents or arbitrary configured commands. To connect to an alias that shares a command name, put `--` before the alias, as in `sshgo -- session`.

Transfers support files and directories. Existing destination files can be overwritten. `scp -r` follows symbolic links when traversing directories. Quote paths containing spaces or shell metacharacters. Download destinations default to the current local directory; upload destinations default to the remote home directory.

If you already have a shell function or alias named `sshgo`, it may take precedence over the installed executable. Remove that existing definition or call the executable by its installed path when migrating.

## Passwords and host keys

SSH keys and normal interactive SSH password prompts work without a keyring. `sshgo --set-password example` optionally saves the server password in macOS Keychain, or on Linux in a desktop Secret Service keyring through `secret-tool` (package `libsecret-tools`). Linux requires an available, unlocked Secret Service session; on headless systems, use SSH keys or enter the password interactively. `sshgo --forget-password example` deletes the saved password.

When using a saved password, SSHGo requires a previously verified server host key. For a new host, run `sshgo --manual example`, verify its host fingerprint and accept it before using the saved password.

For a connection where both hops use the same SSH user and password, run `sshgo setup HOST password-from SOURCE` to reuse the existing keyring entry for `SOURCE`. `HOST` must use a single named `ProxyJump`. The jump must connect directly using the source's port and either its hostname or a `HostKeyAlias` matching that hostname. Both hops require trusted host keys. The setting is local to `HOST` and stores only the source alias. Remove it with `sshgo setup HOST password-from --clear`.

Put `--no-keyring` first to skip saved passwords for a single operation, for example `sshgo --no-keyring --download example /remote/file`. This also works for connections, uploads and speed tests, and lets OpenSSH handle authentication normally.

The optional speed test uses `pv` and measures remote-to-local SSH throughput without writing the test data to disk. A test only succeeds if the requested byte count arrives. Measurements include SSH transport overhead.

## Connection diagnostics and port forwarding

`sshgo doctor HOST` resolves the OpenSSH configuration and tests a fresh direct connection by running `true`. It checks connectivity, verifies the server host key, and attempts non-interactive authentication. It does not try saved passwords or update `known_hosts`. For hosts configured with `ProxyJump` or `ProxyCommand`, it reports the proxy setting and skips the live probe, since the proxy can use its own authentication and trust settings.

`sshgo tunnel HOST REMOTE_PORT [LOCAL_PORT]` forwards a port on the server's loopback interface to a port on this machine. The local port defaults to the remote port. For example, if Jupyter is running on `thread` at `127.0.0.1:8888`, run `sshgo tunnel thread 8888 8889` and open `http://127.0.0.1:8889`. The tunnel runs in the foreground. Press Ctrl+C to stop it. Use `sshgo --no-keyring tunnel HOST REMOTE_PORT` to leave authentication to OpenSSH.

## Resume a remote session

`sshgo session HOST [NAME]` creates a named tmux session or attaches to it if it exists. The name defaults to `work`. For example, run `sshgo session example analysis`, detach with the default tmux keys Ctrl+B then d, and run the same command to return to your work. The remote host must have `tmux` on its SSH command PATH.

`sshgo HOST --screen` opens the same `work` session. Pass a name to open or resume a different session, or use an action:

```sh
sshgo example --screen analysis        # Open or resume analysis
sshgo example --screen new             # Start a new session named w01, w02, and so on
sshgo example --screen new analysis    # Start a new session with an explicit name
sshgo example --screen list            # List sessions on the remote node
sshgo example --screen resume analysis # Attach only if analysis exists
sshgo example --screen detach analysis # Disconnect clients and keep the session running
sshgo --screen --help
```

`new` uses the first available name in the `w01`, `w02`, … sequence. Pass a name to `new` to choose it yourself. If that name already exists, use `resume` to attach to it. The list shows the session name, attachment status, age since creation, and window count.

To leave a session running from inside it, press Ctrl+B then d. To finish it after your work is done, run `exit` in its last shell. Sessions stay on the node where you started them. Reconnect to that node after a network interruption.

## Prepare remote tools on project or scratch storage

Save a default directory once per SSH alias. Choose an existing absolute path on the remote host outside its home directory. The remote host needs Python 3.6 or later.

```sh
sshgo setup example remote-root /scratch/your_username/tools
sshgo setup example remote-root                   # Print the saved path
sshgo show example                                # Show the saved path and SSH settings
sshgo setup example warpify --dry-run             # Preview using the saved path
sshgo setup example warpify
sshgo setup example vscode-server
sshgo setup example vscode-server /project/other/tools --dry-run
```

SSHGo saves these settings locally under `${XDG_CONFIG_HOME:-$HOME/.config}/sshgo/hosts/`. `sshgo setup HOST remote-root DIR` only saves the default locally. An explicit path passed to a tool setup takes precedence for that invocation.

Use `sshgo COMMAND --help` for command-specific usage, for example `sshgo doctor --help` or `sshgo --download --help`. For details on a setup action, use `sshgo setup HOST ACTION --help`.

- **Warp SSH extension** uses a stable Warp client. SSHGo links the remote `~/.warp` to `REMOTE_ROOT/warpify`, and Warp installs the matching SSH extension the next time you connect from Warp and accept the prompt. If `~/.warp` already exists at a different location, SSHGo stops so you can review the existing files. Use storage that allows running binaries and creating Unix sockets, and check the [Warp SSH requirements](https://docs.warp.dev/terminal/warpify/ssh).
- **VS Code Server** uses the Remote-SSH extension. SSHGo prepares `REMOTE_ROOT/vscode-server` and prints a `remote.SSH.serverInstallPath` entry. Merge it into your local VS Code User Settings JSON, then connect using the same SSH alias. VS Code installs the matching server on connect.

If a host alias is named `setup`, connect with `sshgo -- setup`.

## Move configuration to another machine

Run `sshgo export ./sshgo.yaml`, transfer the file privately, then run `sshgo import ./sshgo.yaml` on the new machine. These commands require local Python 3 with PyYAML. On Debian or Ubuntu, install `python3-yaml`. On macOS, install PyYAML in the Python environment used by `sshgo`, such as an active virtual environment.

The YAML contains `~/.ssh/config` and SSHGo's per-alias `remote-root` settings. Private keys, passwords in the system keyring, `password-from` settings, and `known_hosts` are separate. Treat the export as private because it contains SSH configuration text, including any sensitive values entered directly in that file. `Include` files need to be migrated separately.

Export requires a new filename. Import accepts identical local files and stops on conflicts before writing configuration. Use a YAML backup you trust, since the restored OpenSSH configuration will be used for future connections.

## Prepare a Homebrew tap

After creating the matching GitHub tag, download its source archive from `https://github.com/Pengxuan-Zhu-Phys/sshgo/archive/refs/tags/v1.0.3.tar.gz`. Then render a formula using the exact downloaded archive:

```sh
python3 scripts/render-homebrew-formula.py 1.0.3 sshgo-1.0.3.tar.gz --output /path/to/homebrew-tap/Formula/sshgo.rb
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
