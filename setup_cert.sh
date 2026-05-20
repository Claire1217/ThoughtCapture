#!/bin/bash
# One-time setup: create a self-signed code signing certificate
# so ThoughtCapture's Accessibility permission survives rebuilds.
set -e

CERT_NAME="ThoughtCapture Dev"

# Check if already exists
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✓ Certificate '$CERT_NAME' already exists."
    security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME"
    exit 0
fi

echo "Creating self-signed code signing certificate: '$CERT_NAME'"

TMPDIR=$(mktemp -d)

cat > "$TMPDIR/cert.conf" << 'EOF'
[req]
distinguished_name = req_dn
x509_extensions = codesign_ext
prompt = no

[req_dn]
CN = ThoughtCapture Dev

[codesign_ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

# Generate key + cert
openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMPDIR/key.pem" -out "$TMPDIR/cert.pem" \
    -days 3650 -nodes -config "$TMPDIR/cert.conf" 2>/dev/null

# Create p12 (use -legacy for macOS compatibility)
openssl pkcs12 -export -out "$TMPDIR/tc.p12" \
    -inkey "$TMPDIR/key.pem" -in "$TMPDIR/cert.pem" \
    -passout pass:tc123 -legacy 2>/dev/null

# Import to login keychain
echo "Importing to login keychain..."
security import "$TMPDIR/tc.p12" -k ~/Library/Keychains/login.keychain-db \
    -P tc123 -T /usr/bin/codesign

# Trust the certificate (will prompt for password)
echo "Trusting certificate (enter your password if prompted)..."
security add-trusted-cert -d -r trustRoot \
    -k ~/Library/Keychains/login.keychain-db "$TMPDIR/cert.pem"

# Verify
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo ""
    echo "✓ Certificate created and trusted."
    security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME"
else
    echo "✗ Certificate not valid. Check Keychain Access."
    exit 1
fi

rm -rf "$TMPDIR"
