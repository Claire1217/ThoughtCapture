#!/bin/bash
# Developer-only: create a self-signed code signing certificate
# so Eureka's Accessibility permission survives rebuilds.
# NOT needed for end users — just run deploy.sh instead.
set -e

CERT_NAME="Eureka Dev"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✓ Certificate '$CERT_NAME' already exists."
    security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME"
    exit 0
fi

echo "Creating self-signed code signing certificate: '$CERT_NAME'"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/cert.conf" << 'EOF'
[req]
distinguished_name = req_dn
x509_extensions = codesign_ext
prompt = no

[req_dn]
CN = Eureka Dev

[codesign_ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

echo "Generating certificate..."
openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMPDIR/key.pem" -out "$TMPDIR/cert.pem" \
    -days 3650 -nodes -config "$TMPDIR/cert.conf" || {
    echo "✗ Failed to generate certificate. Check openssl output above."
    exit 1
}

echo "Creating PKCS12 bundle..."
if ! openssl pkcs12 -export -out "$TMPDIR/tc.p12" \
    -inkey "$TMPDIR/key.pem" -in "$TMPDIR/cert.pem" \
    -passout pass:tc123 -legacy 2>/dev/null; then
    openssl pkcs12 -export -out "$TMPDIR/tc.p12" \
        -inkey "$TMPDIR/key.pem" -in "$TMPDIR/cert.pem" \
        -passout pass:tc123 || {
        echo "✗ Failed to create PKCS12 bundle. Check openssl output above."
        exit 1
    }
fi

echo "Importing to login keychain..."
security import "$TMPDIR/tc.p12" -k ~/Library/Keychains/login.keychain-db \
    -P tc123 -T /usr/bin/codesign || {
    echo "✗ Failed to import certificate to keychain."
    exit 1
}

echo "Trusting certificate (enter your password if prompted)..."
security add-trusted-cert -d -r trustRoot \
    -k ~/Library/Keychains/login.keychain-db "$TMPDIR/cert.pem" || {
    echo "✗ Failed to trust certificate. You may need to trust it manually in Keychain Access."
    exit 1
}

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo ""
    echo "✓ Certificate created and trusted."
    security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME"
else
    echo "✗ Certificate not found after import. Check Keychain Access."
    exit 1
fi
