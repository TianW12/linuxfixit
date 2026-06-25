#!/usr/bin/env bash

# The shebang — tells the system "run this file with bash." /usr/bin/env bash finds bash wherever it's installed.

# Three safety switches so the script fails loudly instead of silently doing the wrong thing:

# -e → stop immediately if any command fails.
# -u → error if you use a variable that was never set (catches typos).
# -o pipefail → if any command in a pipe fails, the whole pipe counts as failed.

set -euo pipefail

# A variable holding the connection name. Everywhere below uses "$CONN"
CONN="DTUsecure"

# 1. Ask for the password via a GUI box — NOTHING is stored in this file
# kdialog --password "..." → pops the GUI password box.
# $( ... ) → command substitution: runs the command and captures its output.
# PASSWORD="..." → stores what you typed.
# || exit 1 → "or exit": if you click Cancel, the script stops cleanly.

# [ -z "$PASSWORD" ] → "is the password empty?"
# If you clicked OK without typing, it prints a message and stops — so you never store a blank password.
PASSWORD="$(kdialog --password "Enter your DTU password for ${CONN}:")" || exit 1
if [ -z "$PASSWORD" ]; then
  echo "No password entered — aborting."
  exit 1
fi

# 2. Move the secret OUT of KDE Wallet into the root-only system file
# Tells NetworkManager: store the password yourself (in the root-only system file), 
# 0 = system-owned, not in KDE Wallet. This is the line that kills the wallet prompt.
nmcli connection modify "$CONN" 802-1x.password-flags 0
# Actually writes password into that system storage.
nmcli connection modify "$CONN" 802-1x.password "$PASSWORD"

# 3. Prefer DTUsecure over the open guest network
# Sets DTUsecure's priority to 10 (default is 0). W
# hen several known networks are in range, NM joins the highest priority : DTUsecure wins over guest.
nmcli connection modify "$CONN" connection.autoconnect-priority 10
# Also disables autoconnect for the open guest network, so it won't steal the connection.
nmcli connection modify DTUguest connection.autoconnect no || true

# 4. Reconnect now
# Connects DTUsecure right now, so you don't have to reboot to see it work.
nmcli connection up "$CONN" || true

unset PASSWORD   # don't leave it lying in memory
echo "Done — ${CONN} will now connect automatically, no wallet prompt."