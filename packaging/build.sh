#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
PKG="build/linuxfixit_${VERSION}_all"

rm -rf build
mkdir -p "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/share/linuxfixit" \
         "$PKG/usr/share/applications" "$PKG/etc/linuxfixit"

cat > "$PKG/DEBIAN/control" << CTRL
Package: linuxfixit
Version: ${VERSION}
Architecture: all
Maintainer: IT Support <it@example.com>
Depends: python3, python3-gi, python3-yaml, gir1.2-gtk-4.0, gir1.2-adw-1, pkexec | policykit-1
Section: utils
Priority: optional
Description: Self-service fix tool for common problems
 One-click script fixes (with admin authentication where needed)
 and step-by-step cards for manual fixes.
CTRL

install -m 755 src/fixhelper "$PKG/usr/bin/fixhelper"
cp -r catalog "$PKG/usr/share/linuxfixit/catalog"
install -m 644 packaging/fixhelper.desktop "$PKG/usr/share/applications/"
# ship ONLY the fake example to /etc/linuxfixit/  (never the real config.yaml)
install -m 644 config.example.yaml "$PKG/etc/linuxfixit/config.example.yaml"
chmod 755 "$PKG"/usr/share/linuxfixit/catalog/fixes/*.sh

dpkg-deb --build --root-owner-group "$PKG"
echo ""
echo "Built: ${PKG}.deb"
echo ""
echo "=== SAFETY CHECK: what config files are inside the .deb? ==="
dpkg-deb -c "${PKG}.deb" | grep -i config || echo "(no config files - check build)"
echo "You should see ONLY config.example.yaml above, never config.yaml"