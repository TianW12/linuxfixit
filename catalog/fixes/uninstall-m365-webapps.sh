#!/usr/bin/env bash
set -euo pipefail
echo "== Uninstall Microsoft 365 WebApp launchers (m365-*.desktop) =="
APPS_DIR="/usr/share/applications"
count=$(ls -1 "$APPS_DIR"/m365-*.desktop 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" = "0" ]; then
  echo "No launchers found (no $APPS_DIR/m365-*.desktop)."
else
  echo "-- Removing $count launcher(s)..."
  sudo rm -f "$APPS_DIR"/m365-*.desktop
  echo "-- Removed."
fi
# Refresh desktop database
if command -v update-desktop-database >/dev/null 2>&1; then
  sudo update-desktop-database "/usr/share/applications" >/dev/null 2>&1 || true
fi
echo
echo "Done."
echo "Note: If you installed Outlook/Teams/etc as Chromium PWAs, those are separate."
echo "To remove PWAs: open Chromium and go to chrome://apps, right-click the app -> Remove."