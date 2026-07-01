#!/bin/bash
# Build a (optionally GPG-signed) flat APT repository from the .deb files in build/.
# Output goes into ./public/, ready to be served by GitHub Pages (or any web host).
#
# Local test (UNSIGNED, for inspecting the layout only):
#     ./packaging/build.sh && ./packaging/make-apt-repo.sh
#
# Signed (used by CI, needs a private key already imported into gpg):
#     GPG_KEY_ID=<your-key-id> GPG_PASSPHRASE=<pass> ./packaging/make-apt-repo.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="public"
ORIGIN="LinuxFixIt"
LABEL="LinuxFixIt"
SUITE="stable"
CODENAME="stable"

rm -rf "$OUT"
mkdir -p "$OUT"

# GitHub Pages must NOT run Jekyll over the repo files.
touch "$OUT/.nojekyll"

# Collect every .deb produced by build.sh
shopt -s nullglob
debs=(build/*.deb)
if [ "${#debs[@]}" -eq 0 ]; then
    echo "ERROR: no .deb files found in build/. Run ./packaging/build.sh first." >&2
    exit 1
fi
cp "${debs[@]}" "$OUT/"

cd "$OUT"

# --- Package index (flat repo: indexes live next to the .deb files) ---
dpkg-scanpackages --multiversion . > Packages
gzip -9 -k -f Packages

# --- Release file (lists the indexes + their checksums) ---
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="$ORIGIN" \
    -o APT::FTPArchive::Release::Label="$LABEL" \
    -o APT::FTPArchive::Release::Suite="$SUITE" \
    -o APT::FTPArchive::Release::Codename="$CODENAME" \
    -o APT::FTPArchive::Release::Architectures="all" \
    -o APT::FTPArchive::Release::Components="main" \
    release . > Release

# --- Sign the Release file so apt can trust the repo ---
if [ -n "${GPG_KEY_ID:-}" ]; then
    rm -f Release.gpg InRelease
    GPG=(gpg --batch --yes --local-user "$GPG_KEY_ID")
    if [ -n "${GPG_PASSPHRASE:-}" ]; then
        GPG+=(--pinentry-mode loopback --passphrase "$GPG_PASSPHRASE")
    fi
    "${GPG[@]}" -abs -o Release.gpg Release      # detached signature
    "${GPG[@]}" --clearsign -o InRelease Release # inline-signed copy

    # Publish the PUBLIC key so users can verify (this is safe to share).
    gpg --export "$GPG_KEY_ID"          > linuxfixit-archive-keyring.gpg
    gpg --armor --export "$GPG_KEY_ID"  > linuxfixit-archive-keyring.asc
    echo "Signed repository with key: $GPG_KEY_ID"
else
    echo "WARNING: GPG_KEY_ID not set -> repository is UNSIGNED."
    echo "         This is fine for local inspection but apt will refuse it."
fi

echo ""
echo "APT repository built in: $(pwd)"
ls -la
