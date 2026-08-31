#!/bin/bash
# Creates a dedicated code-signing certificate for RELEASE builds and stores it in the
# repository secrets, so every published release carries the same code identity and
# users grant Accessibility only once instead of after every update.
#
# The key is generated here and uploaded straight to GitHub; it is never imported into
# the local keychain. Local development keeps its own identity (make signing-cert), so
# running this does not invalidate a permission you already granted locally.
#
# Re-running replaces the secrets with a fresh certificate, which means the next
# release changes identity and users have to grant Accessibility once more.

set -euo pipefail

NAME="${1:-2cmd Release Signing}"
REPO="${REPO:-tonatoz/2cmd}"

command -v gh >/dev/null || { echo "gh is required"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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

# security import rejects an empty password, so the bundle gets a random one and the
# password travels next to it as a second secret.
PASSWORD="$(openssl rand -hex 24)"
openssl pkcs12 -export \
	-inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-out "$WORK/identity.p12" -passout "pass:$PASSWORD"

echo "Uploading secrets to ${REPO}…"
base64 < "$WORK/identity.p12" | gh secret set SIGNING_CERT_P12 --repo "$REPO"
printf '%s' "$PASSWORD" | gh secret set SIGNING_CERT_PASSWORD --repo "$REPO"

echo
echo "Certificate SHA-1 fingerprint (matches 'certificate leaf' in the release's"
echo "designated requirement, so you can verify a downloaded build):"
openssl x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | sed 's/^/  /'
echo
echo "Done. Releases built by the workflow will now use this identity."
