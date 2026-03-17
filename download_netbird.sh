#!/bin/bash
set -e

REPO="netbirdio/netbird"
ARCH="linux_mipsle_softfloat"

# Fetch latest release URL
echo "Fetching latest release information..."
RELEASE_DATA=$(curl -s https://api.github.com/repos/${REPO}/releases/latest)
DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep "browser_download_url" | grep "${ARCH}" | cut -d '"' -f 4)
VERSION=$(echo "$RELEASE_DATA" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: Could not find download URL for ${ARCH}"
    exit 1
fi

echo "$VERSION" > VERSION
FILENAME=$(basename "$DOWNLOAD_URL")
echo "Downloading $FILENAME..."
curl -LO "$DOWNLOAD_URL"

echo "Extracting netbird binary..."
tar -xzf "$FILENAME" netbird

echo "Compressing netbird with UPX..."
upx --best netbird

echo "Cleaning up..."
rm "$FILENAME"

echo "Done! Final netbird binary size:"
ls -lh netbird
