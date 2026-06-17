#!/usr/bin/env bash
set -euo pipefail
need_cmd() { command -v "$1" >/dev/null 2>&1; }
fail() { echo "ERROR: $1" >&2; exit 1; }
echo "== Outlook WebApp installer (Chromium app mode) =="
# Install Chromium only if missing
need_install_chromium=0
if ! need_cmd chromium && [ ! -x /snap/bin/chromium ]; then
  need_install_chromium=1
fi
if [ "$need_install_chromium" -eq 1 ]; then
  echo "-- Chromium not found; will install it (requires internet)."
  if need_cmd getent; then
    getent hosts snapcraft.io >/dev/null 2>&1 || fail "No DNS/internet access (cannot resolve snapcraft.io)."
  fi
  if need_cmd curl; then
    curl -fsSL --max-time 6 https://snapcraft.io/ >/dev/null 2>&1 || fail "Cannot reach Snap Store (https://snapcraft.io)."
  elif need_cmd wget; then
    wget -q --spider --timeout=6 https://snapcraft.io/ || fail "Cannot reach Snap Store (https://snapcraft.io)."
  else
    echo "Note: curl/wget not found; skipping HTTP reachability check."
  fi
  need_cmd snap || fail "snap is not installed/available on this system."
  echo "-- Installing Chromium (snap)..."
  sudo snap install chromium || fail "Failed to install Chromium via snap."
else
  echo "-- Chromium already present; skipping installation."
fi
# Determine chromium command path
CHROMIUM_BIN="chromium"
if ! need_cmd "$CHROMIUM_BIN"; then
  if [ -x /snap/bin/chromium ]; then
    CHROMIUM_BIN="/snap/bin/chromium"
  else
    fail "chromium command not found."
  fi
fi
# System-wide directory, visible to ALL users
APPS_DIR="/usr/share/applications"
DESKTOP_FILE="$APPS_DIR/m365-outlook.desktop"
sudo tee "$DESKTOP_FILE" > /dev/null <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Outlook
Comment=Outlook (Web) - Chromium app window
Exec=${CHROMIUM_BIN} --app=https://outlook.office.com/ --class=m365-outlook
Terminal=false
Icon=chromium
Categories=Office;Network;
StartupWMClass=m365-outlook
DESKTOP

if need_cmd update-desktop-database; then
  sudo update-desktop-database "/usr/share/applications" >/dev/null 2>&1 || true
fi
echo
echo "Done. Open 'Show Applications' and search: Outlook"
echo "If you previously installed 'Outlook (PWA)', remove it in Chromium: chrome://apps"