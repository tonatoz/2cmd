#!/bin/bash
# Creates a local self-signed code-signing certificate and imports it into the login
# keychain, so every build can be signed with a STABLE identity.
#
# Why this matters: TCC stores an Accessibility grant together with a code signing
# requirement. Ad-hoc signing has no certificate, so that requirement collapses to the
# exact cdhash of one build and the grant stops applying after every rebuild. Signing
# with a certificate pins the requirement to the certificate instead, which stays the
# same across rebuilds, so the grant survives.
#
# No Apple Developer account needed: TCC only requires the identity to be stable, not
# globally trusted. The certificate cannot be used to distribute the app.

set -euo pipefail

NAME="${1:-2cmd Local Signing}"

if security find-identity -p codesigning | grep -q "$NAME"; then
	echo "Identity '$NAME' already exists — nothing to do."
	exit 0
fi

KEYCHAIN="$(security default-keychain -d user | tr -d ' "')"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Extensions go through a config file: `openssl req -addext` is not available on the
# LibreSSL build that ships with macOS.
cat >"$WORK/openssl.cnf" <<CONF
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[dn]
CN = $NAME

[v3]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
CONF

echo "Generating certificate '$NAME'…"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
	-keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
	-config "$WORK/openssl.cnf" 2>/dev/null

# LibreSSL (the openssl on macOS) has no -legacy flag; its default PKCS#12 encryption
# is what the keychain expects anyway. The bundle needs a non-empty password —
# `security import` fails MAC verification on an empty one — so use a throwaway.
TRANSIT_PASSWORD="$(openssl rand -hex 16)"
openssl pkcs12 -export \
	-inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-out "$WORK/identity.p12" -passout "pass:$TRANSIT_PASSWORD"

# -T pre-authorises just codesign, so signing does not need the keychain password.
# macOS may still ask once on first use; choose "Always Allow".
echo "Importing into ${KEYCHAIN}"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$TRANSIT_PASSWORD" \
	-T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo
security find-identity -p codesigning | grep "$NAME"
echo
echo "Done. 'make install' now signs with this identity."
echo "Grant Accessibility once more; after that it survives rebuilds."
