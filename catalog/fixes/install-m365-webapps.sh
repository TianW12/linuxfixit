#!/usr/bin/env bash
set -euo pipefail

# Installs Chromium (Snap) ONLY if it is not already present.
# Creates/updates app-like launchers for Microsoft 365 web apps:
# Microsoft 365, Outlook, Word, Excel, PowerPoint, Teams.
#
# NOTE about duplicates:
# If you previously installed these as Chromium PWAs (e.g. "Outlook (PWA)"),
# you may see duplicate icons. Remove the PWA(s) via Chromium -> chrome://apps (right-click -> Remove).

need_cmd() { command -v "$1" >/dev/null 2>&1; }
fail() { echo "ERROR: $1" >&2; exit 1; }

echo "== Microsoft 365 WebApps installer (Chromium app mode) =="

# Install Chromium if missing
need_install_chromium=0
if ! need_cmd chromium && [ ! -x /snap/bin/chromium ]; then
  need_install_chromium=1
fi

# Network checks only if we need to install Chromium
if [ "$need_install_chromium" -eq 1 ]; then
  echo "-- Chromium not found; will install it (requires internet)."

  # Basic DNS check
  if need_cmd getent; then
    getent hosts snapcraft.io >/dev/null 2>&1 || fail "No DNS/internet access (cannot resolve snapcraft.io). Connect to the internet and try again."
  fi

  # Quick HTTPS reachability check (silent)
  if need_cmd curl; then
    curl -fsSL --max-time 6 https://snapcraft.io/ >/dev/null 2>&1 \
      || fail "Cannot reach the Snap Store (https://snapcraft.io). Check internet/proxy/VPN and try again."
  elif need_cmd wget; then
    wget -q --spider --timeout=6 https://snapcraft.io/ \
      || fail "Cannot reach the Snap Store (https://snapcraft.io). Check internet/proxy/VPN and try again."
  else
    echo "Note: curl/wget not found; skipping HTTP reachability check."
  fi

  need_cmd snap || fail "snap is not installed/available on this system (Ubuntu 24.04 normally includes snap)."

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

# system-wide directory, visible to ALL users
APPS_DIR="/usr/share/applications"


create_desktop() {
  local id="$1" name="$2" url="$3" icon="$4"
  local file="$APPS_DIR/${id}.desktop"

  sudo tee "$file" > /dev/null <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
Comment=${name} (Web) - Chromium app window
Exec=${CHROMIUM_BIN} --app=${url} --class=${id}
Terminal=false
Icon=${icon}
Categories=Office;Network;
StartupWMClass=${id}
DESKTOP


  echo "Created/updated: $file"
}

GEN_ICON="web-browser"

create_desktop "m365-home"        "Microsoft 365" "https://www.microsoft365.com/"                   "$GEN_ICON"
create_desktop "m365-outlook"     "Outlook"       "https://outlook.office.com/"                    "$GEN_ICON"
create_desktop "m365-word"        "Word"          "https://www.microsoft365.com/launch/word"       "$GEN_ICON"
create_desktop "m365-excel"       "Excel"         "https://www.microsoft365.com/launch/excel"      "$GEN_ICON"
create_desktop "m365-powerpoint"  "PowerPoint"    "https://www.microsoft365.com/launch/powerpoint" "$GEN_ICON"
create_desktop "m365-teams"       "Teams"         "https://teams.microsoft.com/"                   "$GEN_ICON"

# Refresh desktop database (optional)
if need_cmd update-desktop-database; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

echo
echo "Done."
echo "Open 'Show Applications' and search: Microsoft 365, Outlook, Word, Excel, PowerPoint, Teams."
echo "If you see duplicates like 'Outlook (PWA)', remove them in Chromium: chrome://apps."
