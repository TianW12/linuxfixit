#!/usr/bin/env bash
# setup-followme-printer-root.sh  --  the ADMIN half of "Set up the FollowMe printer"
#
# Started by setup-followme-printer.sh through pkexec, so it runs as root.
# It reads its input from STDIN, one value per line, in this order:
#   SERVER  QUEUE  LOCAL_NAME  DOMAIN  USERNAME  QUEUES_TO_REMOVE("a|b|c")  PASSWORD
#
# Steps (each prints a [n/9] line so the user can see where it stopped):
#   1. packages      cups + smbclient + samba-common-bin
#   2. CUPS running
#   3. can we reach the server on port 445 (SMB)?
#   4. login test    smbclient checks the username/password AND that the queue exists.
#                    If this fails we stop here, BEFORE anything is changed.
#   5. find the driver (PPD) -- saved before step 6, because removing a queue deletes its PPD
#   6. remove the queues the user ticked
#   7. write the login file  /etc/cups/print-sustain.creds  (root:lp 640)
#   8. install the courier   /usr/lib/cups/backend/smbspool-auth
#   9. create the queue with auth-info-required=none, then check it
#
# Why auth-info-required=none: if CUPS thinks a queue "needs a username and password",
# the desktop pops up a login box for EVERY job. Our courier already reads the login
# file, so the queue must say it needs nothing.
#
# Compatible with the queue made by DTU Linux Setup (same file names and courier),
# so either tool can be run again on the same PC.

set -u

CONFIG="/etc/linuxfixit/config.yaml"
CREDS_FILE="/etc/cups/print-sustain.creds"
BACKEND="/usr/lib/cups/backend/smbspool-auth"

step() { printf '\n[%s] %s\n' "$1" "$2"; }
die()  { echo "ERROR: $1"; exit 1; }   # never 126/127: those mean "pkexec cancelled"

[ "$(id -u)" -eq 0 ] || die "This part must run as root (it is started through pkexec)."

# ---- Read the input ---------------------------------------------------------------
IFS= read -r SERVER     || die "No input received."
IFS= read -r QUEUE      || die "Input ended early (queue)."
IFS= read -r LOCAL_NAME || die "Input ended early (local name)."
IFS= read -r DOMAIN     || die "Input ended early (domain)."
IFS= read -r U          || die "Input ended early (username)."
IFS= read -r REMOVE     || die "Input ended early (queues to remove)."
IFS= read -r P          || [ -n "${P:-}" ] || die "Input ended early (password)."

# Check every value again here: never trust input just because our own GUI sent it.
[[ "$SERVER"     =~ ^[A-Za-z0-9.-]+$  ]] || die "Bad server name."
[[ "$QUEUE"      =~ ^[A-Za-z0-9._-]+$ ]] || die "Bad queue name."
[[ "$LOCAL_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "Bad local queue name."
[[ "$DOMAIN"     =~ ^[A-Za-z0-9._-]+$ ]] || die "Bad domain."
[[ "$U"          =~ ^[A-Za-z0-9._-]+$ ]] || die "Bad username."
[ -n "$P" ] || die "Empty password."

TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

# ---- 1. Packages --------------------------------------------------------------------
step 1/9 "Packages"
NEEDED=()
for pkg in cups smbclient samba-common-bin; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || NEEDED+=("$pkg")
done
if [ ${#NEEDED[@]} -eq 0 ]; then
    echo "      all installed"
else
    echo "      installing: ${NEEDED[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || echo "      (apt-get update reported an error; trying anyway)"
    apt-get install -y "${NEEDED[@]}" || die "Could not install ${NEEDED[*]}. Check the internet connection and try again."
fi

# ---- 2. CUPS ------------------------------------------------------------------------
step 2/9 "CUPS (the printing system)"
systemctl reset-failed cups.service cups.socket 2>/dev/null
systemctl enable --now cups >/dev/null 2>&1
for _ in $(seq 1 10); do lpstat -r >/dev/null 2>&1 && break; sleep 1; done
lpstat -r >/dev/null 2>&1 || die "CUPS is not responding. See: systemctl status cups"
echo "      running"

# ---- 3. Network ---------------------------------------------------------------------
step 3/9 "Can this PC reach $SERVER on port 445 (SMB)?"
if python3 -c 'import socket,sys; socket.create_connection((sys.argv[1],445),timeout=5).close()' "$SERVER" 2>/dev/null; then
    echo "      yes"
else
    die "No answer from $SERVER on port 445. Connect to the DTU network or VPN, then try again. Nothing was changed."
fi

# ---- 4. Login + queue test ----------------------------------------------------------
step 4/9 "Testing your login and the queue name (nothing is changed yet)"
AUTH="$TMP/auth"
( umask 077; printf 'username = %s\npassword = %s\ndomain = %s\n' "$U" "$P" "$DOMAIN" > "$AUTH" )
LIST="$(smbclient -L "//$SERVER" -A "$AUTH" -g 2>&1)"
rm -f "$AUTH"
if printf '%s' "$LIST" | grep -q "NT_STATUS_LOGON_FAILURE"; then
    die "The server refused $DOMAIN\\$U (NT_STATUS_LOGON_FAILURE). Check the password. Nothing was changed."
fi
if printf '%s' "$LIST" | grep -q "NT_STATUS_"; then
    die "The server answered: $(printf '%s' "$LIST" | grep -o 'NT_STATUS_[A-Z_]*' | head -1). Nothing was changed."
fi
if ! printf '%s\n' "$LIST" | grep -q "^Printer|$QUEUE|"; then
    echo "      The server has these printer queues:"
    printf '%s\n' "$LIST" | awk -F'|' '$1=="Printer"{print "        " $2}'
    die "There is no queue called \"$QUEUE\" on $SERVER. Run the card again with one of the names above."
fi
echo "      login accepted, and $QUEUE exists"

# ---- 5. Driver (PPD) ----------------------------------------------------------------
step 5/9 "Finding the driver (PPD)"
CFG_PPD=""
if [ -f "$CONFIG" ]; then
    CFG_PPD=$(grep -E '^\s*followme_ppd\s*:' "$CONFIG" | head -1 | sed -E 's/^[^:]*:\s*//; s/["'"'"']//g; s/\s+$//')
fi
IFS='|' read -r -a REMOVE_LIST <<< "$REMOVE"
SEARCH=()
[ -n "$CFG_PPD" ] && SEARCH+=("$CFG_PPD")
SEARCH+=("/etc/cups/ppd/$LOCAL_NAME.ppd")                  # the queue we are replacing
for q in "${REMOVE_LIST[@]}"; do [ -n "$q" ] && SEARCH+=("/etc/cups/ppd/$q.ppd"); done
SEARCH+=("/opt/dtu-sustain-setup/data/KOC751iUX.ppd"       # installed by DTU Linux Setup
         "$(dirname "$0")/drivers/KOC751iUX.ppd")
PPD=""
for f in "${SEARCH[@]}"; do
    if [ -f "$f" ]; then cp "$f" "$TMP/driver.ppd"; PPD="$TMP/driver.ppd"; echo "      using $f"; break; fi
done
[ -n "$PPD" ] || die "No driver found. Put the Konica PPD (KOC751iUX.ppd) somewhere and set followme_ppd: \"/path/to/KOC751iUX.ppd\" in $CONFIG. Nothing was changed."

# ---- 6. Remove old queues ---------------------------------------------------------
step 6/9 "Removing the queues you ticked"
EXISTING="$(lpstat -p 2>/dev/null | awk '/^printer /{print $2}')"
REMOVED=0
for q in "${REMOVE_LIST[@]}"; do
    [ -n "$q" ] || continue
    if ! printf '%s\n' "$EXISTING" | grep -qx -- "$q"; then echo "      skip $q (not found)"; continue; fi
    cupsreject "$q" >/dev/null 2>&1; cupsdisable "$q" >/dev/null 2>&1
    cancel -a "$q" >/dev/null 2>&1          # stuck jobs block removal
    if lpadmin -x "$q" 2>/dev/null; then echo "      removed $q"; REMOVED=$((REMOVED+1)); else echo "      WARNING: could not remove $q"; fi
done
[ "$REMOVED" -gt 0 ] || echo "      nothing removed"

# ---- 7. Login file ------------------------------------------------------------------
step 7/9 "Saving your login in $CREDS_FILE"
# umask BEFORE writing: the file must never exist readable by others, not even for a moment.
( umask 077
  printf 'username=%s\\%s\npassword=%s\n' "$DOMAIN" "$U" "$P" > "$CREDS_FILE" )
unset P
chown root:lp "$CREDS_FILE" && chmod 640 "$CREDS_FILE" || die "Could not set permissions on $CREDS_FILE."
echo "      saved (root:lp 640: only root and the print system can read it)"

# ---- 8. Courier (backend) ---------------------------------------------------------
step 8/9 "Installing the courier $BACKEND"
# Reads the login file, puts the login into the address, then hands over to smbspool.
# Same behaviour as the courier from DTU Linux Setup.
cat > "$BACKEND.new" <<BACKEND_EOF
#!/usr/bin/env bash
set -euo pipefail
CREDS="$CREDS_FILE"
if [ \$# -eq 0 ]; then exit 0; fi
USER_LINE=\$(grep -E "^username=" "\$CREDS" | head -n1 | cut -d= -f2-)
PASS_LINE=\$(grep -E "^password=" "\$CREDS" | head -n1 | cut -d= -f2-)
DOMAIN="\${USER_LINE%%\\\\*}"
UNAME="\${USER_LINE##*\\\\}"
URI="\${DEVICE_URI#smbspool-auth://}"
export DEVICE_URI="smb://\${DOMAIN}/\${UNAME}:\${PASS_LINE}@\${URI}"
exec /usr/bin/smbspool "\$@"
BACKEND_EOF
chown root:root "$BACKEND.new"; chmod 755 "$BACKEND.new"
mv -f "$BACKEND.new" "$BACKEND"       # move into place in one go: never a half-written file
[ -x /usr/bin/smbspool ] || die "/usr/bin/smbspool is missing. Install smbclient and run the card again."
echo "      installed"

# ---- 9. Create + verify the queue ---------------------------------------------------
step 9/9 "Creating $LOCAL_NAME"
lpadmin -p "$LOCAL_NAME" -E \
    -v "smbspool-auth://$SERVER/$QUEUE" \
    -P "$PPD" \
    -o auth-info-required=none \
    -o PageSize=A4 \
    -o job-sheets=none,none 2>"$TMP/err" \
    || die "Could not create $LOCAL_NAME: $(tr -d '\n' < "$TMP/err")"
cupsenable "$LOCAL_NAME"; cupsaccept "$LOCAL_NAME"
# Only become the default printer if this PC has none yet.
lpstat -d 2>/dev/null | grep -q "system default destination:" || lpadmin -d "$LOCAL_NAME"

URI_NOW="$(LC_ALL=C lpstat -v "$LOCAL_NAME" 2>/dev/null | sed 's/.*: //')"
[ "$URI_NOW" = "smbspool-auth://$SERVER/$QUEUE" ] || die "$LOCAL_NAME points to \"$URI_NOW\", not the new address."
# Look only inside this printer's <Printer NAME> ... </Printer> block.
AUTH_NOW="$(awk -v n="$LOCAL_NAME" '
    $0 ~ "^<(Default)?Printer " n ">$" {inside=1; next}
    inside && /^<\/(Default)?Printer>/ {exit}
    inside && /^AuthInfoRequired/ {print; exit}' /etc/cups/printers.conf 2>/dev/null)"
if [ -n "$AUTH_NOW" ] && [ "$AUTH_NOW" != "AuthInfoRequired none" ]; then
    die "$LOCAL_NAME still asks for a login ($AUTH_NOW)."
fi
echo "      $LOCAL_NAME → $URI_NOW"
echo
echo "Done. Test it with:"
echo "  echo \"test\" | lp -d $LOCAL_NAME"
echo "then swipe your card at a FollowMe copier."
exit 0
