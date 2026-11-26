#!/usr/bin/env bash
# setup-followme-printer.sh  --  LinuxFixIt card: "Set up the FollowMe printer"
#
# This is the FRIENDLY half. It runs as the normal user (privilege: none), because
# pop-up windows (zenity) need the user's desktop session, and a script started
# through pkexec runs as root WITHOUT access to that desktop.
#
# Flow:
#   0. Ask for the destination: print server + queue name on that server.
#   1. Find existing FollowMe queues on this PC and let the user tick which to remove.
#      Plotter queues (BYG-*, *Plot*, socket://) are never offered.
#   2. Ask for the DTU login (username + password) for the login file.
#   3. Show a summary, then hand everything to the ROOT half
#      (setup-followme-printer-root.sh) through pkexec.
#
# The values travel to the root half on STDIN, never on the command line:
# anything on a command line can be read by every user on the PC with `ps`.
#
# Defaults can be pre-filled from /etc/linuxfixit/config.yaml:
#   followme_server:     "print.example.com"
#   followme_queue:      "FollowMe-Queue-Name"     (the name ON the server)
#   followme_local_name: "FollowMe-MFP-PCL"        (the name on this PC)
#   followme_domain:     "WIN"
# Requires: zenity, pkexec (both in the .deb Depends).

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT_HALF="$HERE/setup-followme-printer-root.sh"
CONFIG="/etc/linuxfixit/config.yaml"
TITLE="Set up the FollowMe printer"

have_zenity() { command -v zenity >/dev/null 2>&1; }

fail() {   # fail MESSAGE  -> error box + message in the output window, then stop
    if have_zenity; then zenity --error --width=440 --title="$TITLE" --text="$1"; fi
    echo "ERROR: $1"
    exit 1
}

cancelled() {   # the user pressed Cancel: stop quietly, nothing was changed
    echo "Cancelled. Nothing was changed."
    exit 0
}

# Read one simple "key: value" line from config.yaml (same style as print-label.sh).
cfg() {   # cfg KEY DEFAULT
    local v=""
    if [ -f "$CONFIG" ]; then
        v=$(grep -E "^\s*$1\s*:" "$CONFIG" 2>/dev/null \
            | head -1 | sed -E 's/^[^:]*:\s*//; s/["'"'"']//g; s/\s+$//')
    fi
    printf '%s' "${v:-$2}"
}

have_zenity || { echo "ERROR: zenity is not installed. Install with: sudo apt-get install -y zenity"; exit 1; }
[ -f "$ROOT_HALF" ] || fail "The helper script is missing:\n$ROOT_HALF\n\nReinstall LinuxFixIt."

DEF_SERVER="$(cfg followme_server "")"
DEF_QUEUE="$(cfg followme_queue "")"
LOCAL_NAME="$(cfg followme_local_name "FollowMe-MFP-PCL")"
DOMAIN="$(cfg followme_domain "WIN")"

# ---- 0. Destination ---------------------------------------------------------------
# The address of a printer is  smbspool-auth://SERVER/QUEUE  -- we ask for the two parts.
SERVER=$(zenity --entry --width=460 --title="$TITLE" \
    --text="Step 1 of 3: the print server\n\nThe host name of the FollowMe print server, for example print.sustain.dtu.dk.\nAsk IT if you are not sure. It is NOT the copier's own name." \
    --entry-text="$DEF_SERVER") || cancelled
SERVER="$(printf '%s' "$SERVER" | tr -d '[:space:]')"
[[ "$SERVER" =~ ^[A-Za-z0-9.-]+$ ]] || fail "\"$SERVER\" does not look like a host name (letters, digits, dots and dashes only)."

QUEUE=$(zenity --entry --width=460 --title="$TITLE" \
    --text="The queue name ON the print server, for example FollowMe-MFP-KM-PCL.\n\nTip: the script checks that this name exists before it changes anything." \
    --entry-text="$DEF_QUEUE") || cancelled
QUEUE="$(printf '%s' "$QUEUE" | tr -d '[:space:]')"
[[ "$QUEUE" =~ ^[A-Za-z0-9._-]+$ ]] || fail "\"$QUEUE\" does not look like a queue name (letters, digits, . _ - only)."

# ---- 1. Which old queues to remove? -----------------------------------------------
# A queue is a FollowMe candidate if its NAME starts with FollowMe- or its ADDRESS uses
# smbspool-auth:// or points at the new server. Plotters are always left alone.
CANDIDATES=()
while read -r _ _ name uri; do
    name="${name%:}"
    case "$name" in BYG-*|*Plot*|*plot*) continue ;; esac
    case "$uri"  in socket://*) continue ;; esac
    if [[ "$name" == FollowMe-* || "$uri" == smbspool-auth://* || "$uri" == *"$SERVER"* ]]; then
        CANDIDATES+=("$name" "$uri")
    fi
done < <(LC_ALL=C lpstat -v 2>/dev/null)

REMOVE=""
if [ ${#CANDIDATES[@]} -gt 0 ]; then
    LIST_ARGS=()
    for ((i=0; i<${#CANDIDATES[@]}; i+=2)); do
        LIST_ARGS+=(TRUE "${CANDIDATES[i]}" "${CANDIDATES[i+1]}")
    done
    REMOVE=$(zenity --list --checklist --width=720 --height=320 --title="$TITLE" \
        --text="Step 2 of 3: old FollowMe queues on this PC\n\nTicked queues are removed before the new one is created. Untick any you want to keep.\nPlotter queues are not listed and are never touched." \
        --column="Remove" --column="Queue on this PC" --column="Current address" \
        --separator="|" "${LIST_ARGS[@]}") || cancelled
else
    echo "No old FollowMe queues found on this PC."
fi

# ---- 2. Login for the login file ----------------------------------------------------
DEF_USER="${USER:-}"; DEF_USER="${DEF_USER##*\\}"; DEF_USER="${DEF_USER%%@*}"
U=$(zenity --entry --width=460 --title="$TITLE" \
    --text="Step 3 of 3: your DTU login\n\nThe copier shows your jobs when you swipe your card, so every job must carry your name.\nShort username only (for example abcd, not abcd@dtu.dk). The domain $DOMAIN is added for you." \
    --entry-text="$DEF_USER") || cancelled
U="${U##*\\}"; U="${U%%@*}"; U="$(printf '%s' "$U" | tr -d '[:space:]')"
[[ "$U" =~ ^[A-Za-z0-9._-]+$ ]] || fail "\"$U\" does not look like a DTU username."

P=$(zenity --password --title="$TITLE: password for $DOMAIN\\$U") || cancelled
[ -n "$P" ] || fail "No password entered. Nothing was changed."

# ---- 3. Summary, then hand over to the root half ---------------------------------
SUMMARY="This will:\n\n"
if [ -n "$REMOVE" ]; then SUMMARY+="  • remove: ${REMOVE//|/, }\n"; fi
SUMMARY+="  • create: $LOCAL_NAME\n      → smbspool-auth://$SERVER/$QUEUE\n"
SUMMARY+="  • save the login for $DOMAIN\\$U (readable only by the print system)\n\n"
SUMMARY+="An administrator password is asked for next."
zenity --question --width=520 --title="$TITLE" --ok-label="Set up printer" --text="$SUMMARY" || cancelled

echo "Handing over to the administrator part (pkexec)..."
# One value per line. pkexec keeps stdin, so the root half reads them with `read`.
printf '%s\n' "$SERVER" "$QUEUE" "$LOCAL_NAME" "$DOMAIN" "$U" "$REMOVE" "$P" \
    | pkexec /bin/bash "$ROOT_HALF"
RC=$?
unset P

case "$RC" in
    0)       zenity --info --width=440 --title="$TITLE" \
                 --text="The printer $LOCAL_NAME is ready.\n\nPrint something, then swipe your card at any FollowMe copier." ;;
    126|127) echo "Cancelled: the administrator password was not given. Nothing was changed." ;;
    *)       zenity --error --width=440 --title="$TITLE" \
                 --text="Setup did not finish. The output window shows which step failed." ;;
esac
exit "$RC"
