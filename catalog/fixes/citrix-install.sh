#!/bin/bash
# Citrix Workspace - finishes the install AFTER the user has downloaded
# the .deb from citrix.com. Runs as root via pkexec.
set -u

REAL_UID="${PKEXEC_UID:-$(id -u)}"
USER_HOME=$(getent passwd "$REAL_UID" | cut -d: -f6)
DL="$USER_HOME/Downloads"

DEB=$(ls "$DL"/icaclient_*.deb 2>/dev/null | sort -V | tail -1)

if [ -z "$DEB" ]; then
    echo "No Citrix installer found in $DL"
    echo ""
    echo "Please download it first:"
    echo "  1. Open the Citrix download page (see the steps in the app)"
    echo "  2. Download the Debian package (.deb) for 64-bit"
    echo "  3. Then click 'Fix it' again."
    exit 1
fi

echo "Found installer: $DEB"
echo "Installing Citrix Workspace..."

echo "icaclient app_protection/install_app_protection select no" \
    | debconf-set-selections 2>/dev/null || true

if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "$DEB"; then
    echo "Fixing dependencies and retrying..."
    DEBIAN_FRONTEND=noninteractive apt-get -f install -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$DEB"
fi

if [ -d /opt/Citrix/ICAClient/keystore/cacerts ]; then
    ln -sf /usr/share/ca-certificates/mozilla/* \
        /opt/Citrix/ICAClient/keystore/cacerts/ 2>/dev/null || true
    /opt/Citrix/ICAClient/util/ctx_rehash 2>/dev/null || true
fi

echo ""
echo "Done. Open Citrix Workspace from the menu and enter your work server address."