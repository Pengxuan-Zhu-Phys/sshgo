#!/usr/bin/env bash
# Create a signed single-snapshot APT repository; never alters an existing output.
set -euo pipefail
usage() {
  printf '%s\n' 'Usage: ./scripts/build-apt-repo.sh OUTPUT_DIR SIGNING_KEY PACKAGE.deb [PACKAGE.deb ...]' \
    'Requires apt-ftparchive (apt-utils), dpkg-scanpackages (dpkg-dev), gzip and gpg.'
}
if [[ ${1-} == --help || ${1-} == -h ]]; then usage; exit 0; fi
if (( $# < 3 )); then usage >&2; exit 2; fi
output=$1
key=$2
shift 2
if [[ ! "$key" =~ ^[[:xdigit:]]{40}$ && ! "$key" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo '[apt] Provide the full 40- or 64-digit signing-key fingerprint.' >&2; exit 2
fi
for tool in apt-ftparchive dpkg-scanpackages dpkg-deb gpg gzip python3; do
  command -v "$tool" >/dev/null || { echo "[apt] Missing command: $tool" >&2; exit 1; }
done
[[ ! -e "$output" && ! -L "$output" ]] || { echo '[apt] Output already exists; choose a new directory.' >&2; exit 1; }
parent=$(dirname "$output")
base=$(basename "$output")
[[ -d "$parent" && "$base" != . && "$base" != .. ]] || { echo '[apt] Output parent must exist.' >&2; exit 1; }
parent=$(cd "$parent" && pwd)
stage=$(mktemp -d "$parent/.sshgo-apt.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/pool/main/s/sshgo" "$stage/dists/stable/main/binary-amd64" "$stage/dists/stable/main/binary-arm64" "$stage/dists/stable/main/binary-all"
for package in "$@"; do
  [[ -f "$package" && ! -L "$package" ]] || { echo "[apt] Missing or symlinked package: $package" >&2; exit 1; }
  [[ $(dpkg-deb -f "$package" Package) == sshgo && $(dpkg-deb -f "$package" Architecture) == all ]] || { echo "[apt] Expected an architecture-independent sshgo package: $package" >&2; exit 1; }
  name=$(basename "$package")
  [[ ! -e "$stage/pool/main/s/sshgo/$name" ]] || { echo "[apt] Duplicate package name: $name" >&2; exit 1; }
  cp "$package" "$stage/pool/main/s/sshgo/$name"
done
(
  cd "$stage"
  dpkg-scanpackages --multiversion pool /dev/null > dists/stable/main/binary-all/Packages
  for arch in all amd64 arm64; do
    if [[ "$arch" != all ]]; then cp dists/stable/main/binary-all/Packages "dists/stable/main/binary-$arch/Packages"; fi
    gzip -n -c "dists/stable/main/binary-$arch/Packages" > "dists/stable/main/binary-$arch/Packages.gz"
  done
  apt-ftparchive -o APT::FTPArchive::Release::Origin=sshgo \
    -o APT::FTPArchive::Release::Label=sshgo \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o 'APT::FTPArchive::Release::Architectures=amd64 arm64 all' \
    -o APT::FTPArchive::Release::Components=main release dists/stable > Release.tmp
  mv Release.tmp dists/stable/Release
  gpg --batch --local-user "$key" --armor --detach-sign --output dists/stable/Release.gpg dists/stable/Release
  gpg --batch --local-user "$key" --clearsign --output dists/stable/InRelease dists/stable/Release
  gpg --armor --export "$key" > sshgo-archive-key.asc
  [[ -s sshgo-archive-key.asc ]] || { echo '[apt] Could not export the signing public key.' >&2; exit 1; }
)
if [[ -e "$parent/$base" || -L "$parent/$base" ]]; then echo '[apt] Output appeared during build; stopping.' >&2; exit 1; fi
mv "$stage" "$parent/$base"
trap - EXIT
printf '[apt] Signed repository ready: %s\n' "$parent/$base"
