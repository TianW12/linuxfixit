#!/bin/bash
set -e

echo "Step 1: Unmounting network drives..."
umount -l /mnt/Personal  2>/dev/null || true
umount -l /mnt/Qdrev     2>/dev/null || true

echo "Step 2: Removing fstab entries (stops auto-remount)..."
sed -i '/Personal\|Qdrev/s|^|#REMOVED# |' /etc/fstab

echo "Step 3: Reloading systemd..."
systemctl daemon-reload

echo "Step 4: Removing mount point folders..."
rm -rf /mnt/Personal
rm -rf /mnt/Qdrev

echo ""
echo "Done. Clean state:"
mount | grep /mnt || echo "(nothing mounted under /mnt — clean!)"
echo ""
echo "You can go to DTU Linux Setup and click Network Drives."