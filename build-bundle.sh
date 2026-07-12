#!/bin/bash
# Build every release artifact:
#   dist/ppgw-seed.iso        seed ISO (cloud-init datasource + offline store)
#   dist/ppgw-offline.tar.gz  bare-metal offline bundle (no ppgw-config deb)
#   dist/sha256sum.txt
#
# Steps: build the four shared debs (build-debs.sh), grab the Ubuntu
# dependency closure in a minimal ubuntu:24.04 container, assemble the
# offline tree, then compile the default seed ISO with make-seed.sh.
#
# Requirements: docker, curl, git, dpkg-deb, xorriso.
# PPGW_DEV_FAKE=1 propagates to build-debs.sh and skips the closure
# download - local layout smoke tests only.
set -euo pipefail

builddir="$(cd "$(dirname "$0")" && pwd)"
out="$builddir/dist"
log() { echo -e "\033[32m[build-bundle]\033[0m $*"; }

rm -rf "$out"
bash "$builddir/build-debs.sh"

# --------------------------------------------------- dependency closure
# ubuntu:24.04 is a subset of the 24.04 cloud image, so downloading from
# the minimal container over-fetches rather than under-fetches.
offline="$out/ppgw-offline"
mkdir -p "$offline/debs"
if [ "${PPGW_DEV_FAKE:-0}" = "1" ]; then
    log "DEV FAKE mode: skipping dependency closure download."
else
    log "Fetching Ubuntu dependency closure (ubuntu:24.04)..."
    docker run --rm -v "$offline/debs":/out ubuntu:24.04 bash -c '
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -q
        apt-get install -y -q --no-install-recommends --download-only \
            chrony nftables inotify-tools openvpn ca-certificates \
            procps iproute2
        cp /var/cache/apt/archives/*.deb /out/
        chmod 644 /out/*.deb
    '
fi
cp "$out"/debs/ppgw-*.deb "$offline/debs/"

# ------------------------------------------------------- offline bundle
log "Packing ppgw-offline.tar.gz..."
cp "$builddir/install.sh" "$offline/install.sh"
chmod 755 "$offline/install.sh"
tar -czf "$out/ppgw-offline.tar.gz" -C "$out" ppgw-offline

# ------------------------------------------------------------- seed ISO
log "Building the default seed ISO..."
bash "$builddir/make-seed.sh" \
    -C "$builddir" \
    -c "$builddir/ppgw.conf" \
    -d "$offline/debs" \
    -o "$out/ppgw-seed.iso"

# ------------------------------------------------------------ checksums
(cd "$out" && sha256sum ppgw-seed.iso ppgw-offline.tar.gz >sha256sum.txt)
rm -rf "$offline" "$out/debs"
ls -lah "$out"
log "Done."
