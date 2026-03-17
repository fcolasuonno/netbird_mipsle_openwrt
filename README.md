# Netbird OpenWrt (APK)

This repository contains a script to download the latest Netbird binary, compress it with UPX, and package it into a signed `.apk` for OpenWrt 25.12+ (apk-tools v3).

Multiple devices and architectures are supported.

## Prerequisites

- `curl`
- `upx`
- `openssl`
- `apk` (apk-tools v3 with `apk mkpkg` support) **or** Docker / Podman as a fallback

> **apk-tools v3 note:** OpenWrt 25.12+ uses a new binary package format (ADB) that cannot be hand-crafted — `apk mkpkg` is required. If your build host doesn't have apk-tools v3 natively (e.g. Fedora: `dnf install apk-tools`), the script will automatically use an Alpine container via Docker or Podman.

## Files

- `create_apk.sh`: Fetches the latest Netbird release from GitHub, compresses it with UPX, and packages it into a signed `.apk`.
- `pkg/etc/init.d/netbird`: OpenWrt init script included in the package.
- `private.pem`: RSA private key used to sign the package (auto-generated on first run — **never commit this**).

## Usage

### Build for a specific device

```bash
chmod +x create_apk.sh
./create_apk.sh mt6000    # GL-iNet Flint 2
./create_apk.sh mt1300    # GL-iNet Beryl
```

The script auto-detects the correct architecture for each device and fetches the matching Netbird binary.

### Supported devices

| Argument | Device | Architecture |
|---|---|---|
| `mt6000`, `flint2` | GL-iNet Flint 2 | `aarch64_cortex-a53` |
| `mt3000`, `berylax` | GL-iNet Beryl AX | `aarch64_cortex-a53` |
| `mt2500`, `brume2` | GL-iNet Brume 2 | `aarch64_cortex-a53` |
| `mt1300`, `beryl` | GL-iNet Beryl | `mipsel_24kc` |
| `mt300n-v2`, `mango` | GL-iNet Mango | `mipsel_24kc` |
| `ax1800`, `flint` | GL-iNet Flint | `arm_cortex-a53` |
| `rpi4` | Raspberry Pi 4 | `aarch64_cortex-a72` |
| `x86_64` | Generic x86-64 | `x86_64` |

Raw OpenWrt arch strings (e.g. `aarch64_cortex-a53`) are also accepted directly.
Defaults to `mipsel_24kc` if no argument is given.

### Install on OpenWrt

```bash
scp netbird_<version>_<arch>.apk root@<router>:/tmp/
apk add --allow-untrusted /tmp/netbird_<version>_<arch>.apk
```

Verify the installed files:
```bash
apk info -L netbird
```

### Signed installs (optional)

To install without `--allow-untrusted`, copy the public key to the router once:

```bash
openssl rsa -in private.pem -pubout -out netbird.pub
scp netbird.pub root@<router>:/etc/apk/keys/
```

Then install normally:
```bash
apk add /tmp/netbird_<version>_<arch>.apk
```

## Binary caching

Downloaded and UPX-compressed binaries are cached locally as `netbird_bin_<version>_<arch>`. Re-running the script for the same version reuses the cache — the GitHub download and UPX compression only happen once per version.

## Security Note

**Do not commit `private.pem`.** If you lose it, generate a new key pair and replace the public key on all your routers:

```bash
rm private.pem
./create_apk.sh mt6000   # generates a new private.pem automatically
openssl rsa -in private.pem -pubout -out netbird.pub
scp netbird.pub root@<router>:/etc/apk/keys/
```