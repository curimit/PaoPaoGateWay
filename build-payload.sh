#!/bin/bash
# Build payload.tar.gz for the cloud-init edition.
#
# Everything that would normally require GitHub access at deploy time
# (ppgw binary, mihomo cores, sing-box, geodata, dashboard) is fetched
# and packed here, so target machines only ever download one archive.
#
# Requirements: docker, curl, git. Output: dist/payload.tar.gz{,.sha256}
set -euo pipefail

builddir="$(cd "$(dirname "$0")" && pwd)"
out="$builddir/dist"
stage="$out/payload"
rm -rf "$out"
mkdir -p "$stage/bin" "$stage/geodata"

log() { echo -e "\033[32m[payload]\033[0m $*"; }

# ------------------------------------------------------------------ ppgw
log "Building ppgw binary (golang:alpine, same chain as the ISO)..."
docker pull -q golang:alpine
docker run --rm --name ppgw-gobuilder \
    -v "$builddir"/ppgw/ppgw.go:/go/main.go \
    -v "$stage"/bin/:/go/ppgw/ \
    -v "$builddir"/ppgw/buildppgw.sh:/go/build/buildppgw.sh \
    golang:alpine sh /go/build/buildppgw.sh
[ -f "$stage/bin/ppgw" ] || { echo "ppgw compilation failed." >&2; exit 1; }

# ---------------------------------------------------------------- mihomo
log "Downloading mihomo (Meta kernel) compatible + v3..."
ver=$(curl -s https://github.com/MetaCubeX/mihomo/releases |
    grep mihomo-android- | grep MetaCubeX/mihomo/releases |
    grep -Eo "download/[^/]+" | cut -d"/" -f2 | head -1)
[ -n "$ver" ] || { echo "Unable to resolve mihomo version." >&2; exit 1; }
log "mihomo version: $ver"
for flavor in compatible v3; do
    curl -fsSL "https://github.com/MetaCubeX/mihomo/releases/download/${ver}/mihomo-linux-amd64-${flavor}-${ver}.gz" \
        -o "$stage/bin/mihomo_${flavor}.gz"
    gunzip "$stage/bin/mihomo_${flavor}.gz"
    chmod +x "$stage/bin/mihomo_${flavor}"
done
"$stage/bin/mihomo_compatible" -v | grep Mihomo
echo "$ver" >"$out/mihomo_version.txt"

# --------------------------------------------------------------- geodata
log "Downloading geodata (meta-rules-dat, release branch)..."
git clone --single-branch --branch release --depth 1 \
    https://github.com/MetaCubeX/meta-rules-dat "$out/meta_rules"
(
    cd "$out/meta_rules"
    sha256sum -c geoip.metadb.sha256sum
    sha256sum -c GeoLite2-ASN.mmdb.sha256sum
    sha256sum -c geoip.dat.sha256sum
    sha256sum -c geosite.dat.sha256sum
)
mv "$out/meta_rules/geoip.metadb" "$stage/geodata/geoip.metadb"
mv "$out/meta_rules/GeoLite2-ASN.mmdb" "$stage/geodata/ASN.mmdb"
mv "$out/meta_rules/geoip.dat" "$stage/geodata/GeoIP.dat"
mv "$out/meta_rules/geosite.dat" "$stage/geodata/GeoSite.dat"
rm -rf "$out/meta_rules"

# --------------------------------------------------------------- sing-box
log "Building sing-box (kkkgo/box, same as the ISO Dockerfile)..."
docker run --rm --name ppgw-singbuilder -v "$stage"/bin/:/out/ golang:alpine sh -c '
    set -e
    apk add --no-cache git >/dev/null
    git clone https://github.com/kkkgo/box.git /data/box --depth 1
    cd /data/box
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
        -ldflags "-X '"'"'github.com/sagernet/sing-box/constant.Version=$(git describe --tags --always)'"'"' -s -w" \
        -trimpath -tags "with_clash_api" -buildvcs=false \
        -o /out/sing-box ./cmd/sing-box
'
[ -f "$stage/bin/sing-box" ] || { echo "sing-box build failed." >&2; exit 1; }

# ------------------------------------------------------------- dashboard
log "Packing dashboard and adaptation files..."
cp -a "$builddir/ppgw/FILES/etc/config/clash/clash-dashboard" "$stage/clash-dashboard"
cp -a "$builddir/files" "$stage/files"

# ----------------------------------------------------------------- pack
log "Creating payload.tar.gz..."
tar -czf "$out/payload.tar.gz" -C "$stage" .
rm -rf "$stage"
(cd "$out" && sha256sum payload.tar.gz >payload.tar.gz.sha256)
ls -lah "$out"
log "Done. mihomo=$ver"
