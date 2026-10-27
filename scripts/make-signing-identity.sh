#!/bin/bash
# Creates the free, self-signed "Amiga-View Dev" code-signing identity that scripts/bundle.sh
# signs with. No Apple developer account is needed. A stable signature keeps the Accessibility
# grant and the Keychain item for the wasabid key working across rebuilds; an ad-hoc signature
# changes with every build, so macOS would ask again each time.
# Run once per Mac. AMIGA_VIEW_IDENTITY names the identity, AMIGA_VIEW_KEYCHAIN the keychain
# (default: the login keychain).
set -euo pipefail
NAME="${AMIGA_VIEW_IDENTITY:-Amiga-View Dev}"
KEYCHAIN="${AMIGA_VIEW_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "\"$NAME\" already exists in $KEYCHAIN"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
# /usr/bin/openssl is LibreSSL; its PKCS#12 format is one `security import` can read.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/identity.p12" -passout "pass:$PASS"
# -T lets codesign use the private key without asking.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\" in $KEYCHAIN. Build with scripts/bundle.sh."
