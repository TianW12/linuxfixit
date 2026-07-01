#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Derive the version from git tags.
# - Exact tag (e.g. v0.1.7)            -> 0.1.7
# - Commits after a tag                -> 0.1.7+5.gabc1234   (debian-friendly)
# - No tags / not a git checkout       -> 0.0.0~dev<date>
# An explicit argument still overrides: ./packaging/build.sh 0.1.9
if [ "${1:-}" != "" ]; then
    VERSION="$1"
elif git -C . describe --tags >/dev/null 2>&1; then
    RAW="$(git describe --tags --long --dirty 2>/dev/null)"
    # strip a leading "v": v0.1.7-5-gabc1234 -> 0.1.7-5-gabc1234
    RAW="${RAW#v}"
    if printf '%s' "$RAW" | grep -q -- '-0-g'; then
        # exact tag, no extra commits -> clean version (drop -0-g<hash>[-dirty])
        VERSION="${RAW%%-0-g*}"
    else
        # tag + commits: 0.1.7-5-gabc1234 -> 0.1.7+5.gabc1234 (valid deb version)
        VERSION="$(printf '%s' "$RAW" | sed -E 's/-([0-9]+)-g/+\1.g/; s/-dirty$/.dirty/')"
    fi
else
    VERSION="0.0.0~dev$(date +%Y%m%d)"
fi
echo "Building version: ${VERSION}"
PKG="build/linuxfixit_${VERSION}_all"

rm -rf build
mkdir -p "$PKG/DEBIAN" "$PKG/usr/bin" "$PKG/usr/share/linuxfixit" \
         "$PKG/usr/share/applications" "$PKG/etc/linuxfixit"

cat > "$PKG/DEBIAN/control" << CTRL
Package: linuxfixit
Version: ${VERSION}
Architecture: all
Maintainer: IT Support <it@example.com>
Depends: python3, python3-gi, python3-yaml, gir1.2-gtk-4.0, gir1.2-adw-1, pkexec | policykit-1, python3-pil, zenity
Section: utils
Priority: optional
Description: Self-service fix tool for common problems
 One-click script fixes (with admin authentication where needed)
 and step-by-step cards for manual fixes.
CTRL

install -m 755 src/linuxfixit "$PKG/usr/bin/linuxfixit"
cp -r catalog "$PKG/usr/share/linuxfixit/catalog"
install -m 644 packaging/linuxfixit.desktop "$PKG/usr/share/applications/"
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