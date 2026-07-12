#!/bin/bash
# PaoPao Gateway (cloud-init edition) bootstrap installer for Ubuntu.
#
# Usually invoked automatically from cloud-init user-data on first boot,
# but it is safe to run manually on a fresh Ubuntu 22.04/24.04 server,
# and safe to re-run to upgrade the runtime payload.
#
# Environment variables:
#   PPGW_BASE_URL  Preferred download base for payload.tar.gz, e.g. a LAN
#                  HTTP server: http://192.168.1.2:8080/ppgw
#   PPGW_REPO      GitHub repository (default: curimit/PaoPaoGateWay)
#   PPGW_MIRRORS   Space separated gh-proxy style prefixes tried before
#                  hitting GitHub directly.
#   PPGW_SHA256    Pin the payload sha256 instead of trusting the
#                  .sha256 file next to the payload.
#   PPGW_SNIFF     yes|no, enable the sing-box sniffer chain (default yes,
#                  same as the official ISO docker image).
set -u

PPGW_REPO="${PPGW_REPO:-curimit/PaoPaoGateWay}"
PPGW_MIRRORS="${PPGW_MIRRORS:-https://ghfast.top/ https://gh-proxy.com/}"
PPGW_SNIFF="${PPGW_SNIFF:-yes}"
GITHUB_BASE="https://github.com/${PPGW_REPO}/releases/latest/download"
PAYLOAD_NAME="payload.tar.gz"
WORKDIR="$(mktemp -d /tmp/ppgw-install.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

log() { echo -e "\033[32m[PPGW-INSTALL]\033[0m $*"; }
warn() { echo -e "\033[31m[PPGW-INSTALL]\033[0m $*" >&2; }
die() { warn "$*"; exit 1; }

[ "$(id -u)" = "0" ] || die "This installer must run as root."
grep -qi ubuntu /etc/os-release || die "This installer targets Ubuntu."

# ---------------------------------------------------------------- packages
log "Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=600 update -q || warn "apt update failed, trying to continue with cached lists."
apt-get -o DPkg::Lock::Timeout=600 install -q -y \
    nftables inotify-tools chrony psmisc openvpn curl ca-certificates \
    || die "Failed to install required packages."

# ---------------------------------------------------------------- payload
fetch() {
    # fetch <url> <output>
    curl -fsSL --connect-timeout 15 --retry 2 -o "$2" "$1"
}

try_source() {
    # try_source <base_url> -> downloads and verifies payload into WORKDIR
    local base="$1"
    log "Trying payload source: $base"
    fetch "$base/$PAYLOAD_NAME" "$WORKDIR/$PAYLOAD_NAME" || return 1
    local want=""
    if [ -n "${PPGW_SHA256:-}" ]; then
        want="$PPGW_SHA256"
    else
        fetch "$base/$PAYLOAD_NAME.sha256" "$WORKDIR/$PAYLOAD_NAME.sha256" || return 1
        want="$(cut -d' ' -f1 <"$WORKDIR/$PAYLOAD_NAME.sha256" | head -1)"
    fi
    local got
    got="$(sha256sum "$WORKDIR/$PAYLOAD_NAME" | cut -d' ' -f1)"
    if [ -z "$want" ] || [ "$got" != "$want" ]; then
        warn "sha256 mismatch from $base (got $got, want $want)"
        rm -f "$WORKDIR/$PAYLOAD_NAME"
        return 1
    fi
    return 0
}

payload_ok=0
if [ -n "${PPGW_BASE_URL:-}" ]; then
    try_source "${PPGW_BASE_URL%/}" && payload_ok=1
fi
if [ "$payload_ok" = "0" ]; then
    for mirror in $PPGW_MIRRORS; do
        try_source "${mirror%/}/${GITHUB_BASE}" && payload_ok=1 && break
    done
fi
if [ "$payload_ok" = "0" ]; then
    try_source "$GITHUB_BASE" && payload_ok=1
fi
[ "$payload_ok" = "1" ] || die "Unable to download a verified $PAYLOAD_NAME from any source."

log "Extracting payload..."
mkdir -p "$WORKDIR/payload"
tar -xzf "$WORKDIR/$PAYLOAD_NAME" -C "$WORKDIR/payload" || die "Payload extraction failed."
P="$WORKDIR/payload"
for need in bin/ppgw bin/mihomo_compatible bin/sing-box files/usr/bin/ppg.sh clash-dashboard/index_base.html; do
    [ -e "$P/$need" ] || die "Payload is missing $need"
done

# ---------------------------------------------------------------- files
log "Installing runtime files..."
cp -a "$P/files/." /
chmod 600 /etc/netplan/99-ppgw.yaml

# Select the mihomo build for this CPU (same idea as the ISO's MI switch).
CLASH_BIN="$P/bin/mihomo_compatible"
if [ -x "$P/bin/mihomo_v3" ] && /lib64/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q "x86-64-v3 (supported"; then
    CLASH_BIN="$P/bin/mihomo_v3"
fi
install -m 0755 "$CLASH_BIN" /usr/bin/clash
install -m 0755 "$P/bin/ppgw" /usr/bin/ppgw
install -m 0755 "$P/bin/sing-box" /usr/bin/sing-box
log "clash core: $(/usr/bin/clash -v | head -1)"

mkdir -p /etc/config/clash /www /etc/ppgw
rm -rf /etc/config/clash/clash-dashboard
cp -a "$P/clash-dashboard" /etc/config/clash/clash-dashboard
cp -a "$P/geodata/." /etc/config/clash/
# Flags read by ppg.sh/ppgw: mihomo core + bundled geodata (see ISO patcher).
touch /www/clash_core /www/clash_geo

# ---------------------------------------------------------------- sniffer
if [ "$PPGW_SNIFF" = "yes" ]; then
    log "Enabling sing-box sniffer chain..."
    sed -i 's/1082/1081/g' /usr/bin/nft.sh /usr/bin/nft_tcp.sh
    sed -i 's/#forsniff//g' /usr/bin/nft.sh
else
    rm -f /usr/bin/sing-box
fi

# ---------------------------------------------------------------- system
log "Configuring system..."
# cloud-init must stop managing netplan (see 99-ppgw-network.cfg); drop the
# generated per-interface config: 99-ppgw.yaml runs DHCP on every e* port.
rm -f /etc/netplan/50-cloud-init.yaml /etc/netplan/90-default.yaml

# Free port 53 and expose real upstream DNS in /etc/resolv.conf.
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved 2>/dev/null || true

# Pick up the ppgw NTP sources (chrony replaces systemd-timesyncd).
systemctl restart chrony 2>/dev/null || true

sysctl --system >/dev/null 2>&1

systemctl daemon-reload
systemctl enable ppgw.service >/dev/null 2>&1

log "Install finished. Reboot to start the gateway (ppgw.service is enabled)."
