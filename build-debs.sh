#!/bin/bash
# Build the four shared ppgw debs (core / geodata / dashboard / system).
#
# Everything that would normally require GitHub access at deploy time
# (ppgw binary, mihomo cores, sing-box, geodata, dashboard) is fetched
# here and packed into debs, so target machines never touch the network.
#
# Requirements: docker, curl, git, dpkg-deb.
# Output: dist/debs/ppgw-{core,geodata,dashboard,system}_*.deb
#
# PPGW_DEV_FAKE=1 skips all downloads/builds and packs placeholder
# binaries instead - only for local packaging/layout smoke tests.
set -euo pipefail

builddir="$(cd "$(dirname "$0")" && pwd)"
out="$builddir/dist"
debs="$out/debs"
work="$out/build"
VERSION="${PPGW_DEB_VERSION:-$(date +%Y%m%d)+g$(git -C "$builddir" rev-parse --short HEAD 2>/dev/null || echo dev)}"
rm -rf "$work"
mkdir -p "$debs" "$work/bin" "$work/geodata"

log() { echo -e "\033[32m[build-debs]\033[0m $*"; }

# ------------------------------------------------------------ artifacts
if [ "${PPGW_DEV_FAKE:-0}" = "1" ]; then
    log "DEV FAKE mode: packing placeholder binaries."
    for f in ppgw sing-box mihomo_compatible mihomo_v3; do
        printf '#!/bin/sh\necho fake %s\n' "$f" >"$work/bin/$f"
        chmod 755 "$work/bin/$f"
    done
    for f in geoip.metadb ASN.mmdb GeoIP.dat GeoSite.dat; do
        echo fake >"$work/geodata/$f"
    done
    echo "dev-fake" >"$out/mihomo_version.txt"
else
    log "Building ppgw binary (golang:alpine, same chain as the ISO)..."
    docker pull -q golang:alpine
    docker run --rm --name ppgw-gobuilder \
        -v "$builddir"/ppgw/ppgw.go:/go/main.go \
        -v "$work"/bin/:/go/ppgw/ \
        -v "$builddir"/ppgw/buildppgw.sh:/go/build/buildppgw.sh \
        golang:alpine sh /go/build/buildppgw.sh
    [ -f "$work/bin/ppgw" ] || { echo "ppgw compilation failed." >&2; exit 1; }

    log "Downloading mihomo (Meta kernel) compatible + v3..."
    ver=$(curl -s https://github.com/MetaCubeX/mihomo/releases |
        grep mihomo-android- | grep MetaCubeX/mihomo/releases |
        grep -Eo "download/[^/]+" | cut -d"/" -f2 | head -1)
    [ -n "$ver" ] || { echo "Unable to resolve mihomo version." >&2; exit 1; }
    log "mihomo version: $ver"
    for flavor in compatible v3; do
        curl -fsSL "https://github.com/MetaCubeX/mihomo/releases/download/${ver}/mihomo-linux-amd64-${flavor}-${ver}.gz" \
            -o "$work/bin/mihomo_${flavor}.gz"
        gunzip "$work/bin/mihomo_${flavor}.gz"
        chmod +x "$work/bin/mihomo_${flavor}"
    done
    "$work/bin/mihomo_compatible" -v | grep Mihomo
    echo "$ver" >"$out/mihomo_version.txt"

    log "Downloading geodata (meta-rules-dat, release branch)..."
    git clone --single-branch --branch release --depth 1 \
        https://github.com/MetaCubeX/meta-rules-dat "$work/meta_rules"
    (
        cd "$work/meta_rules"
        sha256sum -c geoip.metadb.sha256sum
        sha256sum -c GeoLite2-ASN.mmdb.sha256sum
        sha256sum -c geoip.dat.sha256sum
        sha256sum -c geosite.dat.sha256sum
    )
    mv "$work/meta_rules/geoip.metadb" "$work/geodata/geoip.metadb"
    mv "$work/meta_rules/GeoLite2-ASN.mmdb" "$work/geodata/ASN.mmdb"
    mv "$work/meta_rules/geoip.dat" "$work/geodata/GeoIP.dat"
    mv "$work/meta_rules/geosite.dat" "$work/geodata/GeoSite.dat"
    rm -rf "$work/meta_rules"

    log "Building sing-box (kkkgo/box, same as the ISO Dockerfile)..."
    docker run --rm --name ppgw-singbuilder -v "$work"/bin/:/out/ golang:alpine sh -c '
        set -e
        apk add --no-cache git >/dev/null
        git clone https://github.com/kkkgo/box.git /data/box --depth 1
        cd /data/box
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
            -ldflags "-X '"'"'github.com/sagernet/sing-box/constant.Version=$(git describe --tags --always)'"'"' -s -w" \
            -trimpath -tags "with_clash_api" -buildvcs=false \
            -o /out/sing-box ./cmd/sing-box
    '
    [ -f "$work/bin/sing-box" ] || { echo "sing-box build failed." >&2; exit 1; }
fi

# ------------------------------------------------------------- packing
pack_deb() {
    # pack_deb <name> <staging_dir>
    local name="$1" staging="$2" arch
    mkdir -p "$staging/DEBIAN"
    sed "s/@VERSION@/$VERSION/" "$builddir/pkg/$name/control" >"$staging/DEBIAN/control"
    if [ -f "$builddir/pkg/$name/postinst" ]; then
        install -m 0755 "$builddir/pkg/$name/postinst" "$staging/DEBIAN/postinst"
    fi
    arch=$(grep '^Architecture:' "$staging/DEBIAN/control" | awk '{print $2}')
    dpkg-deb --root-owner-group -Zxz -b "$staging" \
        "$debs/${name}_${VERSION}_${arch}.deb" >/dev/null
    log "packed ${name}_${VERSION}_${arch}.deb"
}

log "Assembling ppgw-core..."
S="$work/stage-core"
mkdir -p "$S/usr/lib/ppgw"
cp -a "$builddir/pkg/ppgw-core/files/." "$S/"
install -m 0755 "$work/bin/ppgw" "$S/usr/bin/ppgw"
install -m 0755 "$work/bin/sing-box" "$S/usr/bin/sing-box"
install -m 0755 "$work/bin/mihomo_compatible" "$S/usr/lib/ppgw/mihomo_compatible"
install -m 0755 "$work/bin/mihomo_v3" "$S/usr/lib/ppgw/mihomo_v3"
chmod 755 "$S"/usr/bin/*.sh "$S/usr/bin/reload"
chmod 644 "$S/usr/lib/systemd/system/ppgw.service"
pack_deb ppgw-core "$S"

log "Assembling ppgw-geodata..."
S="$work/stage-geodata"
mkdir -p "$S/etc/config/clash"
cp -a "$work/geodata/." "$S/etc/config/clash/"
chmod 644 "$S"/etc/config/clash/*
pack_deb ppgw-geodata "$S"

log "Assembling ppgw-dashboard..."
S="$work/stage-dashboard"
mkdir -p "$S/etc/config/clash"
cp -a "$builddir/ppgw/FILES/etc/config/clash/clash-dashboard" \
    "$S/etc/config/clash/clash-dashboard"
pack_deb ppgw-dashboard "$S"

log "Assembling ppgw-system..."
S="$work/stage-system"
mkdir -p "$S"
cp -a "$builddir/pkg/ppgw-system/files/." "$S/"
chmod 600 "$S/etc/netplan/99-ppgw.yaml"
pack_deb ppgw-system "$S"

rm -rf "$work"
ls -lah "$debs"
log "Done. version=$VERSION"
