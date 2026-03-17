#!/bin/bash
set -e

# Configuration
KEY_NAME="my.rsa.pub"
PRIVATE_KEY="private.pem"
PUBLIC_KEY="$KEY_NAME"

# 0. Ensure keys exist
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Generating NEW RSA keys..."
    openssl genrsa -out "$PRIVATE_KEY" 4096
    openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY"
fi

if [ -f VERSION ]; then
    VERSION=$(cat VERSION)
else
    VERSION="0.66.4"
fi

ARCH="mipsel_24kc"
PKG_FILE="netbird_${VERSION}_${ARCH}.apk"

# Temporary directories
DATA_DIR="pkg_data"
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR/usr/bin" "$DATA_DIR/etc/init.d" "$DATA_DIR/etc/netbird"

echo "Preparing package structure..."
cp netbird "$DATA_DIR/usr/bin/netbird"
chmod +x "$DATA_DIR/usr/bin/netbird"
cp pkg/etc/init.d/netbird "$DATA_DIR/etc/init.d/netbird"
chmod +x "$DATA_DIR/etc/init.d/netbird"

# Helper to strip exactly the last two 512-byte null blocks from a tar
strip_tar_nulls() {
    python3 -c "
import sys
data = sys.stdin.buffer.read()
if data.endswith(b'\x00' * 1024):
    sys.stdout.buffer.write(data[:-1024])
else:
    sys.stdout.buffer.write(data)
"
}

echo "Creating Data Stream..."
(cd "$DATA_DIR" && tar -c --format=posix --numeric-owner --owner=0 --group=0 .) | gzip -n -9 > data.tar.gz

echo "Creating Control Stream..."
DATA_HASH=$(sha256sum data.tar.gz | cut -d' ' -f1)
SIZE=$(find "$DATA_DIR" -type f -printf "%s\n" | awk '{s+=$1} END {print s}')
DATE=$(date +%s)

cat > .PKGINFO <<EOF
pkgname = netbird
pkgver = ${VERSION}-r1
pkgdesc = Connect your devices into a single secure private WireGuard mesh network
url = https://netbird.io
builddate = $DATE
packager = Gemini CLI
size = $SIZE
arch = $ARCH
license = BSD-3-Clause
depend = libc
depend = kmod-wireguard
datahash = $DATA_HASH
EOF

# Create control.tar.gz (Tar segment)
tar -c -b 1 --format=posix --numeric-owner --owner=0 --group=0 .PKGINFO | \
    strip_tar_nulls | gzip -n -9 > control.tar.gz

echo "Signing Control Stream (SHA1 Legacy Method)..."
# Legacy naming: .SIGN.RSA.<keyname> (no algorithm prefix)
# This is the most reliable way to match /etc/apk/keys/<keyname>
SIG_FILENAME=".SIGN.RSA.$KEY_NAME"
openssl dgst -sha1 -sign "$PRIVATE_KEY" -out "$SIG_FILENAME" control.tar.gz

echo "Creating Signature Stream..."
tar -c -b 1 --format=posix --numeric-owner --owner=0 --group=0 "$SIG_FILENAME" | \
    strip_tar_nulls | gzip -n -9 > signature.tar.gz

echo "Assembling APK..."
cat signature.tar.gz control.tar.gz data.tar.gz > "$PKG_FILE"

# Clean up
rm -rf "$DATA_DIR" .PKGINFO "$SIG_FILENAME" control.tar.gz signature.tar.gz data.tar.gz

echo "Done! Final signed package created: $PKG_FILE"
echo ""
echo "INSTALLATION STEPS:"
echo "1. Copy $PUBLIC_KEY to /etc/apk/keys/ on target."
echo "   (Make sure it's named exactly $KEY_NAME)"
echo "2. Run: apk add ./$PKG_FILE"
echo ""
echo "Note: The public key is a standard PEM file (-----BEGIN PUBLIC KEY-----)."
