#!/bin/bash
# create_apk.sh — build a netbird OpenWrt apk (apk-tools v3) for a given device or target.
#
# Usage:
#   ./create_apk.sh [DEVICE_OR_TARGET]
#
# Device aliases (GL-iNet and common):
#   mt6000                GL-iNet Flint 2           → aarch64_cortex-a53
#   mt3000                GL-iNet Beryl AX           → aarch64_cortex-a53
#   mt2500                GL-iNet Brume 2            → aarch64_cortex-a53
#   mt1300                GL-iNet Beryl              → mipsel_24kc
#   mt300n-v2             GL-iNet Mango              → mipsel_24kc
#   ar750s / x750s        GL-iNet Slate              → ath79 / mips_24kc  (*)
#   ax1800                GL-iNet Flint              → arm_cortex-a53 (ipq6018)
#   rpi4                  Raspberry Pi 4             → aarch64_cortex-a72
#   x86_64                Generic x86-64             → x86_64
#
# (*) ath79 targets use mips_24kc — netbird upstream doesn't ship a separate
#     MIPS big-endian build; use mipsel_24kc devices where possible.
#
# Raw OpenWrt arch targets (also accepted):
#   mipsel_24kc  aarch64_cortex-a53  aarch64_cortex-a72
#   arm_cortex-a7  arm_cortex-a9  x86_64
#
# Defaults to mipsel_24kc if no argument is given.

set -e

# ---------------------------------------------------------------------------
# Device alias → OpenWrt arch
# Edit or extend this table to add more devices.
# ---------------------------------------------------------------------------
resolve_device() {
    local input="${1,,}"   # lowercase
    case "$input" in
        # GL-iNet Filogic (MT7986 / MT7981) — aarch64 Cortex-A53
        mt6000|flint2|gl-mt6000)            echo "aarch64_cortex-a53" ;;
        mt3000|berylax|gl-mt3000)           echo "aarch64_cortex-a53" ;;
        mt2500|brume2|gl-mt2500)            echo "aarch64_cortex-a53" ;;
        mt6000*|mt3000*|mt2500*)            echo "aarch64_cortex-a53" ;;

        # GL-iNet ramips (MT7621) — mipsel 24kc
        mt1300|beryl|gl-mt1300)             echo "mipsel_24kc" ;;
        mt300n-v2|mango|gl-mt300n-v2)       echo "mipsel_24kc" ;;
        mt300a|mt300n|gl-mt300*)            echo "mipsel_24kc" ;;

        # GL-iNet IPQ (AX1800 / AXT1800) — ARM Cortex-A53
        ax1800|flint|gl-ax1800)             echo "arm_cortex-a53" ;;
        axt1800|slate-ax|gl-axt1800)        echo "arm_cortex-a53" ;;

        # Raspberry Pi
        rpi4|raspberrypi4|pi4)              echo "aarch64_cortex-a72" ;;
        rpi3|raspberrypi3|pi3)              echo "aarch64_cortex-a53" ;;

        # Generic
        x86_64|x86-64|amd64)               echo "x86_64" ;;

        # Pass-through: already a valid arch string
        mipsel_24kc|aarch64_cortex-a53|aarch64_cortex-a72|\
        arm_cortex-a53|arm_cortex-a7|arm_cortex-a9|x86_64)
                                            echo "$input" ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Map OpenWrt arch → netbird release arch token (linux_<token>.tar.gz)
# ---------------------------------------------------------------------------
nb_arch_for() {
    case "$1" in
        mipsel_24kc)            echo "mipsle" ;;
        aarch64_cortex-a53|\
        aarch64_cortex-a72|\
        arm_cortex-a53)         echo "arm64" ;;
        arm_cortex-a7|\
        arm_cortex-a9)          echo "armv6" ;;
        x86_64)                 echo "amd64" ;;
        *)                      echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# Parse argument
# ---------------------------------------------------------------------------
INPUT="${1:-mipsel_24kc}"
TARGET=$(resolve_device "$INPUT")

if [ "$TARGET" = "UNKNOWN" ]; then
    echo "ERROR: Unknown device or target: '$INPUT'"
    echo ""
    echo "Known device aliases:"
    echo "  mt6000, mt3000, mt2500        → aarch64_cortex-a53"
    echo "  mt1300, mt300n-v2             → mipsel_24kc"
    echo "  ax1800, axt1800               → arm_cortex-a53"
    echo "  rpi4                          → aarch64_cortex-a72"
    echo "  x86_64"
    echo ""
    echo "Or pass a raw OpenWrt arch string directly."
    exit 1
fi

NB_ARCH=$(nb_arch_for "$TARGET")

if [ -z "$NB_ARCH" ]; then
    echo "ERROR: No netbird binary mapping for OpenWrt arch '$TARGET'."
    echo "Add an entry to nb_arch_for() in this script."
    exit 1
fi

# ---------------------------------------------------------------------------
# Version + key — always fetch latest from GitHub
# ---------------------------------------------------------------------------
echo "Fetching latest netbird release version..."
VERSION=$(curl -fsSL "https://api.github.com/repos/netbirdio/netbird/releases/latest" \
    | grep '"tag_name"' \
    | sed 's/.*"tag_name": *"v\([^"]*\)".*/\1/')

if [ -z "$VERSION" ]; then
    echo "ERROR: Could not determine latest netbird version from GitHub API."
    exit 1
fi
echo "Latest version: ${VERSION}"


PRIVATE_KEY="private.pem"
PKG_NAME="netbird"
PKG_VERSION="${VERSION}-r1"
PKG_FILE="${PKG_NAME}_${VERSION}_${TARGET}.apk"

echo "========================================"
echo "  Input:    $INPUT"
echo "  Arch:     $TARGET"
echo "  netbird:  v${VERSION} (linux/${NB_ARCH})"
echo "  Output:   ${PKG_FILE}"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# 0. Ensure RSA private key exists
# ---------------------------------------------------------------------------
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Generating RSA-4096 private key -> ${PRIVATE_KEY}"
    openssl genrsa -out "$PRIVATE_KEY" 4096
fi

# ---------------------------------------------------------------------------
# 1. Locate apk-tools v3 ("apk mkpkg")
# ---------------------------------------------------------------------------
APK_BIN=$(command -v apk 2>/dev/null || true)

if [ -n "$APK_BIN" ]; then
    if ! "$APK_BIN" mkpkg --help >/dev/null 2>&1; then
        echo "WARNING: system 'apk' lacks 'mkpkg' (not v3). Falling back to container."
        APK_BIN=""
    fi
fi

if [ -z "$APK_BIN" ]; then
    CONTAINER_RUNTIME=$(command -v docker 2>/dev/null || command -v podman 2>/dev/null || true)
    if [ -z "$CONTAINER_RUNTIME" ]; then
        echo "ERROR: 'apk mkpkg' (apk-tools v3) not found and Docker/Podman not available."
        echo "Install options:"
        echo "  Fedora/RHEL:  dnf install apk-tools"
        echo "  Docker:       https://docs.docker.com/engine/install/"
        exit 1
    fi
    echo "Using ${CONTAINER_RUNTIME} + alpine:latest for apk-tools v3..."
    APK_BIN="${CONTAINER_RUNTIME} run --rm -v $(pwd):/work -w /work alpine:latest apk"
fi

# ---------------------------------------------------------------------------
# 2. Download netbird binary (cached per version+arch)
# ---------------------------------------------------------------------------
NB_TARBALL="netbird_${VERSION}_linux_${NB_ARCH}.tar.gz"
NB_URL="https://github.com/netbirdio/netbird/releases/download/v${VERSION}/${NB_TARBALL}"
NB_CACHED="netbird_bin_${VERSION}_${NB_ARCH}"

if [ ! -f "$NB_CACHED" ]; then
    echo "Downloading ${NB_TARBALL} ..."
    curl -fL --progress-bar -o "${NB_TARBALL}" "${NB_URL}"
    tar -xzf "${NB_TARBALL}" netbird
    rm -f "${NB_TARBALL}"

    echo "Compressing with UPX ..."
    if ! command -v upx >/dev/null 2>&1; then
        echo "ERROR: upx not found. Install it first (e.g. apt install upx-ucl / brew install upx)."
        rm -f netbird
        exit 1
    fi
    upx --lzma -9 netbird

    mv netbird "$NB_CACHED"
    echo "Cached: ${NB_CACHED}"
else
    echo "Using cached binary: ${NB_CACHED}"
fi

# ---------------------------------------------------------------------------
# 3. Build package root tree
# ---------------------------------------------------------------------------
ROOT_DIR="pkg_root_${TARGET}"
rm -rf "$ROOT_DIR"

mkdir -p "${ROOT_DIR}/usr/bin"
mkdir -p "${ROOT_DIR}/etc/init.d"
mkdir -p "${ROOT_DIR}/etc/netbird"

cp "$NB_CACHED"           "${ROOT_DIR}/usr/bin/netbird"
chmod 755                 "${ROOT_DIR}/usr/bin/netbird"

cp pkg/etc/init.d/netbird "${ROOT_DIR}/etc/init.d/netbird"
chmod 755                 "${ROOT_DIR}/etc/init.d/netbird"

# ---------------------------------------------------------------------------
# 4. .list file — required for "apk info -L" to show installed files
# ---------------------------------------------------------------------------
LIST_DIR="${ROOT_DIR}/lib/apk/packages"
mkdir -p "$LIST_DIR"

(cd "$ROOT_DIR" && \
    find . \( -type f -o -type l \) ! -path "./lib/apk/*" -printf "/%P\n" | sort) \
    > "${LIST_DIR}/${PKG_NAME}.list"

echo "Owned files:"
cat "${LIST_DIR}/${PKG_NAME}.list"
echo ""

# ---------------------------------------------------------------------------
# 5. Lifecycle hooks
# ---------------------------------------------------------------------------
SCRIPTS_DIR="apk_scripts_${TARGET}"
rm -rf "$SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"

cat > "${SCRIPTS_DIR}/post-install.sh" <<'HOOK'
#!/bin/sh
[ -x /etc/init.d/netbird ] && /etc/init.d/netbird enable || true
HOOK
chmod +x "${SCRIPTS_DIR}/post-install.sh"

cat > "${SCRIPTS_DIR}/pre-deinstall.sh" <<'HOOK'
#!/bin/sh
[ -x /etc/init.d/netbird ] && {
    /etc/init.d/netbird stop    || true
    /etc/init.d/netbird disable || true
}
HOOK
chmod +x "${SCRIPTS_DIR}/pre-deinstall.sh"

# ---------------------------------------------------------------------------
# 6. Build with apk mkpkg
# ---------------------------------------------------------------------------
echo "Running apk mkpkg ..."

$APK_BIN mkpkg \
    --info "name:${PKG_NAME}" \
    --info "version:${PKG_VERSION}" \
    --info "description:Connect devices into a secure private WireGuard mesh network" \
    --info "arch:${TARGET}" \
    --info "license:BSD-3-Clause" \
    --info "url:https://netbird.io" \
    --info "origin:${PKG_NAME}" \
    --info "depends:libc kmod-wireguard" \
    --script "post-install:${SCRIPTS_DIR}/post-install.sh" \
    --script "pre-deinstall:${SCRIPTS_DIR}/pre-deinstall.sh" \
    --files "${ROOT_DIR}" \
    --output "${PKG_FILE}" \
    --sign "${PRIVATE_KEY}"

# ---------------------------------------------------------------------------
# 7. Clean up
# ---------------------------------------------------------------------------
rm -rf "$ROOT_DIR" "$SCRIPTS_DIR"

echo ""
echo "Done: ${PKG_FILE}"
echo ""
echo "Install on router:"
echo "  scp ${PKG_FILE} root@<router>:/tmp/"
echo "  apk add --allow-untrusted /tmp/${PKG_FILE}"
echo ""
echo "Verify:"
echo "  apk info -L ${PKG_NAME}"