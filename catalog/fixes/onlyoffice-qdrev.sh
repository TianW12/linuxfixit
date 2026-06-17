#!/bin/bash
# Grant OnlyOffice access to ALL configured network drives. Runs as user, no root.
set -u

# reads direct from config.yaml when installing
CONFIG="/etc/fixhelper/config.yaml"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: config not found at $CONFIG"
    echo "An administrator must create it first (see README)."
    exit 1
fi

PATHS=$(grep -A20 '^netdrive_paths:' "$CONFIG" \
        | grep -E '^\s*-\s*"' \
        | cut -d'"' -f2)

if [ -z "$PATHS" ]; then
    echo "ERROR: no netdrive_paths found in $CONFIG"
    exit 1
fi

if ! flatpak info org.onlyoffice.desktopeditors >/dev/null 2>&1; then
    echo "OnlyOffice (Flatpak) not found."
    echo "If it is a snap: sudo snap connect onlyoffice-desktopeditors:removable-media"
    exit 1
fi

while IFS= read -r DRIVE; do
    flatpak override --user --filesystem="$DRIVE" org.onlyoffice.desktopeditors
    echo "Granted OnlyOffice access to: $DRIVE"
done <<< "$PATHS"

echo ""
echo "Done. Close and reopen OnlyOffice, then try your network drives."