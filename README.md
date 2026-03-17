# Netbird OpenWrt (APK)

This repository contains scripts to download the latest Netbird binary for MIPS Little Endian (`mipsel_24kc`), compress it with UPX, and package it into a signed `.apk` for OpenWrt 25.12+.

## Prerequisites

- `upx`
- `openssl`
- `tar`, `gzip`, `python3` (for packaging)

## Files

- `download_netbird.sh`: Fetches the latest `linux_mipsle_softfloat` release from GitHub, extracts it, and compresses it with UPX.
- `create_apk.sh`: Packages the binary into a signed `.apk` file compatible with OpenWrt's new APK-based system.
- `my.rsa.pub`: The public key used to verify the package signature.

## Usage

1. **Download and Prepare:**
   ```bash
   chmod +x download_netbird.sh
   ./download_netbird.sh
   ```

2. **Build the APK:**
   ```bash
   chmod +x create_apk.sh
   ./create_apk.sh
   ```

3. **Install on OpenWrt:**
   - Copy `my.rsa.pub` to `/etc/apk/keys/` on the router.
   - Copy the generated `.apk` to the router.
   - Run: `apk add ./netbird_<version>_mipsel_24kc.apk`

## Security Note

**DO NOT** commit your `private.pem` file. If you lose it, you will need to generate a new key pair and update the public key on your devices.
