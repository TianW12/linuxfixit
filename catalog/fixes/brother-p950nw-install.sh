#!/bin/bash
# Brother PT-P950NW label printer - finishes the install AFTER the user has
# downloaded the LPR + CUPS-wrapper .deb drivers from support.brother.com.
# Runs as root via pkexec.
#
# Brother ships these as 32-bit (i386) packages, so on 64-bit Ubuntu 24.04 we
# must enable the i386 architecture and pull in libc6:i386 first. We also have
# to relax AppArmor for cupsd and create /usr/share/cups/model, which Brother's
# installer scripts expect to exist.
set -u

REAL_UID="${PKEXEC_UID:-$(id -u)}"
USER_HOME=$(getent passwd "$REAL_UID" | cut -d: -f6)
DL="$USER_HOME/Downloads"

# Brother's driver filenames look like:
#   ptp950nwlpr-1.0.2-0.i386.deb
#   ptp950nwcupswrapper-1.0.2-0.i386.deb
LPR=$(ls "$DL"/ptp950nwlpr-*.deb 2>/dev/null | sort -V | tail -1)
CUPS=$(ls "$DL"/ptp950nwcupswrapper-*.deb 2>/dev/null | sort -V | tail -1)

if [ -z "$LPR" ] || [ -z "$CUPS" ]; then
    echo "Could not find both Brother PT-P950NW drivers in $DL"
    echo ""
    echo "Found LPR driver:          ${LPR:-(missing)}"
    echo "Found CUPS-wrapper driver: ${CUPS:-(missing)}"
    echo ""
    echo "Please download BOTH .deb files first:"
    echo "  1. Open the PT-P950NW Linux download page (see the steps in the app)"
    echo "  2. Download the 'LPR driver' (deb) AND the 'CUPS wrapper driver' (deb)"
    echo "  3. Leave them in your Downloads folder, then click 'Fix it' again."
    exit 1
fi

echo "Found LPR driver:          $LPR"
echo "Found CUPS-wrapper driver: $CUPS"
echo ""

echo "== 1/4: Enabling 32-bit (i386) support for the Brother drivers =="
dpkg --add-architecture i386
apt-get update || echo "Warning: apt-get update failed (continuing with cached lists)."
DEBIAN_FRONTEND=noninteractive apt-get install -y libc6:i386 csh \
    || echo "Warning: could not install i386 dependencies; install may still work."

echo ""
echo "== 2/4: Preparing CUPS (AppArmor + model directory) =="
command -v aa-complain >/dev/null 2>&1 && aa-complain cupsd 2>/dev/null || true
mkdir -p /usr/share/cups/model

echo ""
echo "== 3/4: Installing the Brother drivers =="
dpkg -i --force-all "$LPR"
dpkg -i --force-all "$CUPS"
# Pull in anything dpkg --force-all skipped.
DEBIAN_FRONTEND=noninteractive apt-get -f install -y || true

echo ""
echo "== 4/4: Restarting the printing service =="
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart cups 2>/dev/null || systemctl restart cupsd 2>/dev/null || true
else
    service cups restart 2>/dev/null || true
fi

echo ""
echo "Drivers installed."
echo ""
echo "Now add the printer (the PT-P950NW is a NETWORK printer):"
echo "  1. Find the printer's IP address (printed on its network status sheet,"
echo "     or from your label printer's screen / Brother iPrint&Label app)."
echo "  2. Open Settings -> Printers -> Add, or go to http://localhost:631"
echo "     (Administration -> Add Printer), and add it as an"
echo "     'AppSocket/HP JetDirect' printer using:  socket://<printer-ip>:9100"
echo "  3. When asked for the driver/model, choose 'Brother PT-P950NW'."
echo "  4. Print a test label to confirm it works."
