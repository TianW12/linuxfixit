#!/bin/bash
set -u

# reads the drive list direct from config.yaml
CONFIG="/etc/linuxfixit/config.yaml"

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

echo "Step 1: Unmounting network drives..."
while IFS= read -r DRIVE; do
    umount -l "$DRIVE" 2>/dev/null || true
done <<< "$PATHS"

echo "Step 2: Removing fstab entries (stops auto-remount)..."
# comment out the fstab line for each configured drive.
# \|...| lets sed use | as the address delimiter, so paths with / need no escaping.
while IFS= read -r DRIVE; do
    sed -i "\|$DRIVE|s|^|#REMOVED# |" /etc/fstab
done <<< "$PATHS"

echo "Step 3: Reloading systemd..."
systemctl daemon-reload

echo "Step 4: Removing mount point folders..."
while IFS= read -r DRIVE; do
    rm -rf "$DRIVE"
done <<< "$PATHS"

echo ""
echo "Done. Clean state:"
mount | grep /mnt || echo "(nothing mounted under /mnt — clean!)"
echo ""
echo "You can go to DTU Linux Setup and click Network Drives."