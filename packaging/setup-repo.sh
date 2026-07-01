#!/bin/bash
# One-time setup on a USER's computer: add the LinuxFixIt APT repository so the
# tool installs and AUTO-UPDATES through the normal system updater.
#
#   curl -fsSL https://tianw12.github.io/linuxfixit/setup-repo.sh | sudo bash
#   sudo apt-get install linuxfixit
#
# Run again any time to refresh the signing key.
set -euo pipefail

REPO_URL="https://tianw12.github.io/linuxfixit"
KEYRING="/usr/share/keyrings/linuxfixit-archive-keyring.gpg"
LIST="/etc/apt/sources.list.d/linuxfixit.list"

# Re-run with sudo if not root.
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

echo "Downloading repository signing key..."
tmpkey="$(mktemp)"
trap 'rm -f "$tmpkey"' EXIT
curl -fsSL "$REPO_URL/linuxfixit-archive-keyring.gpg" -o "$tmpkey"

# Basic sanity check: must be a real GPG key, not an HTML error page.
if ! gpg --show-keys "$tmpkey" >/dev/null 2>&1; then
    echo "ERROR: downloaded key is not a valid GPG key. Aborting." >&2
    exit 1
fi
install -m 644 "$tmpkey" "$KEYRING"

echo "Adding APT source..."
echo "deb [signed-by=$KEYRING] $REPO_URL ./" > "$LIST"

echo "Refreshing package lists..."
apt-get update

echo ""
echo "Done. Install with:  sudo apt-get install linuxfixit"
echo "Updates will now appear in the normal system updater."
