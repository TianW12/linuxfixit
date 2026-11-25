#!/bin/bash
# print-label.sh  --  LinuxFixIt card: "Print a label"
#
# Flow:
#   1. Remind the IT user the PC must be on the SAME subnet as the printer.
#   2. Preflight: ping the printer + check the LPR port (515) is open.
#   3. Pop up a form (text / tape width / copies / bold).
#   4. Call print_label_engine.py to send the label over LPR.
#
# Printing needs NO admin password, so this card is privilege: none.
# Requires: zenity, python3, python3-pil  (declared in the .deb Depends).

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$HERE/print_label_engine.py"

have_zenity() { command -v zenity >/dev/null 2>&1; }

fail() {
    # $1 = message
    if have_zenity; then
        zenity --error --width=420 --title="Print a label" --text="$1"
    fi
    echo "ERROR: $1"
    exit 1
}

# ---- Settings: read from /etc/linuxfixit/config.yaml (no hardcoded defaults) ----
CONFIG="/etc/linuxfixit/config.yaml"

# cfg <key>  ->  prints the value of "key: value" from config.yaml (quotes removed)
cfg() {
    [ -f "$CONFIG" ] || return 0
    grep -E "^\s*$1\s*:" "$CONFIG" 2>/dev/null \
        | head -1 | sed -E 's/^[^:]*:\s*//; s/["'"'"']//g; s/\s+$//'
}

PRINTER_IP=$(cfg printer_ip)
ESP32_IP=$(cfg esp32_ip)          # optional: ESP32 power-on helper. Empty = feature off.
ESP32_TOKEN=$(cfg esp32_token)    # must be the same as TOKEN in b2_press_api.ino

if [ -z "$PRINTER_IP" ]; then
    fail "No printer IP is configured.\n\nAdd a line like:\n  printer_ip: \"<printer-ip>\"\nto ${CONFIG}, then try again."
fi
# ---- 0. zenity present? ----
if ! have_zenity; then
    echo "ERROR: 'zenity' is not installed.  Install with: sudo apt-get install -y zenity"
    exit 1
fi

# ---- 1. Subnet reminder (skippable: "don't remind me again") ----
REMIND_FLAG="${HOME}/.config/linuxfixit/skip-print-subnet-reminder"
if [ ! -f "$REMIND_FLAG" ]; then
    ANSWER=$(zenity --question --width=460 --title="Print a label" \
        --ok-label="Yes, continue" --cancel-label="Cancel" \
        --extra-button="Yes, don't remind me again" \
        --text="Before printing:\n\nThis computer must be on the SAME network (subnet) as the label printer (${PRINTER_IP}).\n\nThis usually means a wired connection in the IT office. WiFi on a different subnet will not reach the printer.\n\nIs this computer connected to the printer's network?")
    RC=$?
    if [ "$ANSWER" = "Yes, don't remind me again" ]; then
        mkdir -p "$(dirname "$REMIND_FLAG")"
        touch "$REMIND_FLAG"
        echo "Subnet reminder disabled (created $REMIND_FLAG)."
    elif [ "$RC" -ne 0 ]; then
        echo "Cancelled by user at subnet check."
        exit 0
    fi
fi

# ---- 2. Preflight: ping + LPR port 515 ----
echo "Preflight: checking ${PRINTER_IP} ..."

port_515_open() { timeout "${1:-5}" bash -c "echo > /dev/tcp/${PRINTER_IP}/515" 2>/dev/null; }

# ---- 2b. NEW: printer off? Ask the ESP32 to press the power button, then wait ----
if ! ping -c 1 -W 2 "$PRINTER_IP" >/dev/null 2>&1; then
    [ -n "$ESP32_IP" ] \
        || fail "Cannot reach the printer at ${PRINTER_IP} (ping failed).\n\nCheck that the printer is on and this PC is on the same subnet, then try again."

    echo "Printer doesn't answer. Asking the ESP32 (${ESP32_IP}) to switch it on..."
    curl -s -m 5 -X POST -H "Authorization: Bearer ${ESP32_TOKEN}" "http://${ESP32_IP}/press" \
        || fail "Cannot reach the printer or the ESP32 (${ESP32_IP}).\n\nPlease go to the label printer and check it."
    echo ""                                   # the line above prints the ESP32's answer

    echo -n "Waiting for the printer to start (max 40 s)"
    for _ in $(seq 1 20); do sleep 2; echo -n "."; port_515_open 2 && break; done
    echo ""
fi

if ! port_515_open; then
    fail "The printer at ${PRINTER_IP} is not ready to print (port 515 is closed).\n\nPlease go to the label printer and check it: is it on, showing an error, out of tape, or still starting up? Then try again."
fi

echo "Preflight OK: printer reachable and LPR port open."

# ---- 3. Input form ----
FORM=$(zenity --forms --width=420 --title="Print a label" \
    --ok-label="Print label" --cancel-label="Cancel" \
    --text="Printer: ${PRINTER_IP}   (LPR / binary_p1)" \
    --separator="^" \
    --add-entry="Text to print" \
    --add-combo="Tape width (mm)" --combo-values="12|3.5|6|9|18|24|36" \
    --add-entry="Copies" \
    --add-combo="Bold" --combo-values="No|Yes" \
    --add-combo="Half-cut" --combo-values="Yes|No" \
    --add-combo="Chain print" --combo-values="No|Yes") \
    || { echo "Cancelled by user at form."; exit 0; }

TEXT=$(echo "$FORM"     | cut -d'^' -f1)
TAPE=$(echo "$FORM"     | cut -d'^' -f2)
COPIES=$(echo "$FORM"   | cut -d'^' -f3)
BOLD=$(echo "$FORM"     | cut -d'^' -f4)
HALFCUT=$(echo "$FORM"  | cut -d'^' -f5)
CHAIN=$(echo "$FORM"    | cut -d'^' -f6)

# ---- 4. Validate ----
[ -n "$TEXT" ] || fail "No text was entered. Please run again and type the label text."
[ -n "$TAPE" ] || TAPE="12"          # empty choice -> 12 mm (also the first item in the list)
case "$COPIES" in
    ''|*[!0-9]*) COPIES=1 ;;
esac
[ "$COPIES" -ge 1 ] 2>/dev/null || COPIES=1

BOLD_FLAG=""
[ "$BOLD" = "Yes" ] && BOLD_FLAG="--bold"

# Half-cut defaults ON; only turn OFF if user explicitly chose No.
HALFCUT_FLAG=""
[ "$HALFCUT" = "No" ] && HALFCUT_FLAG="--no-half-cut"

# Chain print defaults OFF; only turn ON if user explicitly chose Yes.
CHAIN_FLAG=""
[ "$CHAIN" = "Yes" ] && CHAIN_FLAG="--chain"

# ---- 5. Print ----
echo "Printing: '$TEXT'  tape=${TAPE}mm  copies=${COPIES}  bold=${BOLD:-No}  half-cut=${HALFCUT:-Yes}  chain=${CHAIN:-No}"
echo ""

python3 "$ENGINE" \
    --ip "$PRINTER_IP" \
    --tape "$TAPE" \
    --text "$TEXT" \
    --copies "$COPIES" \
    $BOLD_FLAG $HALFCUT_FLAG $CHAIN_FLAG
RC=$?

if [ "$RC" -ne 0 ]; then
    fail "The label did not print (engine exit code ${RC}). See the output window for details."
fi

echo ""
echo "Done. ${COPIES} label(s) sent to ${PRINTER_IP}."
exit 0
