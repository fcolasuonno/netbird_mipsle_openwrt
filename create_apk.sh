#!/bin/bash
# create_apk.sh — builds an OpenWrt apk-tools v3 package using "apk mkpkg".
#
# OpenWrt (25.xx / main branch) uses apk-tools v3, whose package format (ADB)
# is a custom binary format — NOT the concatenated-gzip-tars of Alpine v2.
# You cannot hand-craft v3 packages; you must use "apk mkpkg" from
# apk-tools >= 3.x.  This script will use apk from Docker/Podman (Alpine)
# if "apk mkpkg" is not already available on the host.

set -e

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PRIVATE_KEY="private.pem"

if [ -f VERSION ]; then
    VERSION=$(cat VERSION)
else
    VERSION="0.66.4"
fi

ARCH="mipsel_24kc"
PKG_NAME="netbird"
PKG_VERSION="${VERSION}-r1"
PKG_FILE="${PKG_NAME}_${VERSION}_${ARCH}.apk"

# ---------------------------------------------------------------------------
# 0. Ensure RSA key exists
# ---------------------------------------------------------------------------
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Generating RSA private key..."
    openssl genrsa -out "$PRIVATE_KEY" 4096
fi

# ---------------------------------------------------------------------------
# 1. Locate or obtain apk-tools v3
#
#    OpenWrt uses apk-tools v3. The package format (ADB) is a custom binary
#    structure — NOT the Alpine v2 "concatenated gzipped tars" format.
#    It cannot be hand-crafted; "apk mkpkg" is the only supported way.
# ---------------------------------------------------------------------------
APK_BIN=$(command -v apk 2>/dev/null || true)

# Verify it actually supports mkpkg (v3 feature; absent in old Alpine v2 tools)
if [ -n "$APK_BIN" ]; then
    if ! "$APK_BIN" mkpkg --help >/dev/null 2>&1; then
        echo "WARNING: 'apk' found but does not support 'mkpkg' (not v3 tools). Will use Docker."
        APK_BIN=""
    fi
fi

if [ -z "$APK_BIN" ]; then
    CONTAINER_RUNTIME=$(command -v docker 2>/dev/null || command -v podman 2>/dev/null || true)
    if [ -z "$CONTAINER_RUNTIME" ]; then
        echo "ERROR: 'apk mkpkg' not found and no Docker/Podman available."
        echo "Options:"
        echo "  - Fedora/RHEL:  dnf install apk-tools"
        echo "  - Docker/Podman: install either one and re-run this script"
        exit 1
    fi
    echo "Using $CONTAINER_RUNTIME to access apk-tools v3 from Alpine..."
    APK_BIN="${CONTAINER_RUNTIME} run --rm -v $(pwd):/work -w /work alpine:latest apk"
fi

echo "apk binary: $APK_BIN"

# ---------------------------------------------------------------------------
# 2. Prepare the package root file tree
# ---------------------------------------------------------------------------
ROOT_APK_DIR="pkg_root_apk"
rm -rf "$ROOT_APK_DIR"

mkdir -p "$ROOT_APK_DIR/usr/bin"
mkdir -p "$ROOT_APK_DIR/etc/init.d"
mkdir -p "$ROOT_APK_DIR/etc/netbird"

echo "Copying package files..."
cp netbird "$ROOT_APK_DIR/usr/bin/netbird"
chmod 755 "$ROOT_APK_DIR/usr/bin/netbird"

cp pkg/etc/init.d/netbird "$ROOT_APK_DIR/etc/init.d/netbird"
chmod 755 "$ROOT_APK_DIR/etc/init.d/netbird"

# ---------------------------------------------------------------------------
# 3. Create the .list file — required by apk-tools v3 installed-db.
#    Must list every file the package owns (with leading slash), one per line.
#    This is what "apk info -L <pkg>" reads back after installation.
# ---------------------------------------------------------------------------
LIST_DIR="$ROOT_APK_DIR/lib/apk/packages"
mkdir -p "$LIST_DIR"

(cd "$ROOT_APK_DIR" && find . \( -type f -o -type l \) ! -path "./lib/apk/*" -printf "/%P\n" | sort) \
    > "$LIST_DIR/${PKG_NAME}.list"

echo "Package will own:"
cat "$LIST_DIR/${PKG_NAME}.list"

# ---------------------------------------------------------------------------
# 4. init script hooks (post-install / pre-deinstall)
# ---------------------------------------------------------------------------
APK_SCRIPTS_DIR="apk_scripts"
rm -rf "$APK_SCRIPTS_DIR"
mkdir -p "$APK_SCRIPTS_DIR"

cat > "$APK_SCRIPTS_DIR/post-install.sh" <<'HOOK'
#!/bin/sh
[ -x /etc/init.d/netbird ] && /etc/init.d/netbird enable || true
HOOK
chmod +x "$APK_SCRIPTS_DIR/post-install.sh"

cat > "$APK_SCRIPTS_DIR/pre-deinstall.sh" <<'HOOK'
#!/bin/sh
[ -x /etc/init.d/netbird ] && {
    /etc/init.d/netbird stop   || true
    /etc/init.d/netbird disable || true
}
HOOK
chmod +x "$APK_SCRIPTS_DIR/pre-deinstall.sh"

# ---------------------------------------------------------------------------
# 5. Build the package with apk mkpkg
# ---------------------------------------------------------------------------
echo ""
echo "Building ${PKG_FILE} ..."

$APK_BIN mkpkg \
    --info "name:${PKG_NAME}" \
    --info "version:${PKG_VERSION}" \
    --info "description:Connect devices into a secure private WireGuard mesh network" \
    --info "arch:${ARCH}" \
    --info "license:BSD-3-Clause" \
    --info "url:https://netbird.io" \
    --info "origin:${PKG_NAME}" \
    --info "depends:libc kmod-wireguard" \
    --script "post-install:${APK_SCRIPTS_DIR}/post-install.sh" \
    --script "pre-deinstall:${APK_SCRIPTS_DIR}/pre-deinstall.sh" \
    --files "${ROOT_APK_DIR}" \
    --output "${PKG_FILE}" \
    --sign "${PRIVATE_KEY}"

# ---------------------------------------------------------------------------
# 6. Clean up temporaries
# ---------------------------------------------------------------------------
rm -rf "$ROOT_APK_DIR" "$APK_SCRIPTS_DIR"

echo ""
echo "Done: ${PKG_FILE}"
echo ""
echo "INSTALLATION (OpenWrt 25.xx / apk-tools v3):"
echo "  scp ${PKG_FILE} root@<router>:/tmp/"
echo "  apk add --allow-untrusted /tmp/${PKG_FILE}"
echo ""
echo "  # Verify after install:"
echo "  apk info -L ${PKG_NAME}"
echo ""
echo "To install with full signature verification instead of --allow-untrusted,"
echo "extract the public key from ${PRIVATE_KEY} and place it in /etc/apk/keys/ on the router:"
echo "  openssl rsa -in ${PRIVATE_KEY} -pubout -out netbird.pub"
echo "  scp netbird.pub root@<router>:/etc/apk/keys/"