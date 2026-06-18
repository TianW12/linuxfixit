#!/bin/bash
# Install gLabels - a label designer for Linux. Brother's own P-touch Editor is
# Windows-only, so gLabels is the usual way to design and print labels (e.g. to
# a Brother PT-P950NW) on Ubuntu. Runs as root via pkexec.
set -u

echo "== Installing gLabels (label editor) =="

if command -v glabels-3 >/dev/null 2>&1 || command -v glabels >/dev/null 2>&1; then
    echo "gLabels is already installed; nothing to do."
    exit 0
fi

# Make sure we can actually reach the package mirrors before trying.
if command -v getent >/dev/null 2>&1; then
    getent hosts archive.ubuntu.com >/dev/null 2>&1 \
        || echo "Warning: could not resolve archive.ubuntu.com (continuing anyway)."
fi

echo "-- Updating package lists..."
apt-get update || echo "Warning: apt-get update failed (continuing with cached lists)."

echo "-- Installing gLabels..."
if ! DEBIAN_FRONTEND=noninteractive apt-get install -y glabels; then
    echo "ERROR: failed to install gLabels. Check the internet connection and try again." >&2
    exit 1
fi

echo ""
echo "Done. Open 'Show Applications' and search: gLabels"
echo ""
echo "To print to the Brother PT-P950NW: design your label, then File -> Print"
echo "and pick the Brother printer queue. Set the correct tape width in the"
echo "print dialog before printing."
