#!/usr/bin/env bash
set -euo pipefail

CONF="/etc/sssd/sssd.conf"

# must be root
if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo or as root"
    exit 1
fi

# backup first
cp "$CONF" "${CONF}.bak.$(date +%F-%H%M%S)"

# detect domain section
DOMAIN_SECTION=$(grep -oP '^\[domain/.*\]' "$CONF" | head -n1)

if [[ -z "$DOMAIN_SECTION" ]]; then
    echo "No domain section found in $CONF"
    exit 1
fi

echo "Using domain section: $DOMAIN_SECTION"

# apply settings (idempotent-ish)
sed -i "/$DOMAIN_SECTION/,/^\[/ {
    s/^ad_gpo_access_control.*/ad_gpo_access_control = disabled/;
    s/^ignore_group_members.*/ignore_group_members = true/;
    s/^ldap_referrals.*/ldap_referrals = false/;
    s/^enumerate.*/enumerate = false/;
}" "$CONF"

# add if missing
grep -q "ad_gpo_access_control" "$CONF" || sed -i "/$DOMAIN_SECTION/a ad_gpo_access_control = disabled" "$CONF"
grep -q "ignore_group_members" "$CONF" || sed -i "/$DOMAIN_SECTION/a ignore_group_members = true" "$CONF"
grep -q "ldap_referrals" "$CONF" || sed -i "/$DOMAIN_SECTION/a ldap_referrals = false" "$CONF"
grep -q "enumerate" "$CONF" || sed -i "/$DOMAIN_SECTION/a enumerate = false" "$CONF"

# permissions
chmod 600 "$CONF"
chown root:root "$CONF"

# clear cache + restart
sss_cache -E || true
systemctl restart sssd

echo "Done. Test with:"
echo "time id 'youruser@yourdomain'"