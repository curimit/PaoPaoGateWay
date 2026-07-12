#!/bin/bash
# Build (or re-build) the PaoPao Gateway seed ISO.
#
# The seed ISO is both the cloud-init NoCloud datasource and the offline
# package store. Layout:
#   user-data meta-data     cloud-init (static, never edited)
#   ppgw.conf               the ONLY file users edit
#   debs/*.deb              shared ppgw debs + dependency closure
#                           + the ppgw-config deb compiled from ppgw.conf
#   tools/                  this script + config-deb templates, so the
#                           ISO can be re-packed without cloning the repo
#
# Typical use after editing ppgw.conf extracted from a release ISO:
#   xorriso -osirrox on -indev ppgw-seed.iso -extract / seed/
#   vi seed/ppgw.conf
#   bash seed/tools/make-seed.sh -C seed/ -o my-seed.iso
#
# Every run compiles a fresh ppgw-config deb (new version) and writes a
# fresh instance-id, so cloud-init re-applies the configuration when the
# re-packed ISO is attached to an already-provisioned VM.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: make-seed.sh [options]
  -C <dir>          seed tree (default .): expects ppgw.conf, debs/,
                    user-data (falls back to user-data.yaml for repo use)
  -c <ppgw.conf>    config file (default <dir>/ppgw.conf)
  -d <debs dir>     debs directory (default <dir>/debs)
  -o <output.iso>   output path (default ./ppgw-seed.iso)
  --from-iso <iso>  extract <iso> first and use it as the seed tree
  --ssh-key "..."   override ssh_authorized_key
  --password "..."  override console password
  --hostname "..."  override hostname
EOF
    exit 1
}

scriptdir="$(cd "$(dirname "$0")" && pwd)"
tree="."
conf=""
debsdir=""
outiso="./ppgw-seed.iso"
fromiso=""
ov_key="" ov_pass="" ov_host=""

while [ $# -gt 0 ]; do
    case "$1" in
    -C) tree="$2"; shift 2 ;;
    -c) conf="$2"; shift 2 ;;
    -d) debsdir="$2"; shift 2 ;;
    -o) outiso="$2"; shift 2 ;;
    --from-iso) fromiso="$2"; shift 2 ;;
    --ssh-key) ov_key="$2"; shift 2 ;;
    --password) ov_pass="$2"; shift 2 ;;
    --hostname) ov_host="$2"; shift 2 ;;
    *) usage ;;
    esac
done

log() { echo -e "\033[32m[make-seed]\033[0m $*"; }
die() { echo -e "\033[31m[make-seed]\033[0m $*" >&2; exit 1; }

work="$(mktemp -d /tmp/ppgw-seed.XXXXXX)"
trap 'rm -rf "$work"' EXIT

if [ -n "$fromiso" ]; then
    log "Extracting $fromiso ..."
    command -v xorriso >/dev/null || die "xorriso is required for --from-iso."
    xorriso -osirrox on -indev "$fromiso" -extract / "$work/tree" >/dev/null 2>&1
    chmod -R u+w "$work/tree"
    tree="$work/tree"
fi

conf="${conf:-$tree/ppgw.conf}"
debsdir="${debsdir:-$tree/debs}"
[ -f "$conf" ] || die "ppgw.conf not found: $conf"
[ -d "$debsdir" ] || die "debs directory not found: $debsdir"

# user-data: ISO layout ships "user-data", the repo ships "user-data.yaml".
userdata=""
for c in "$tree/user-data" "$tree/user-data.yaml" "$scriptdir/../user-data.yaml" "$scriptdir/user-data.yaml"; do
    [ -f "$c" ] && userdata="$c" && break
done
[ -n "$userdata" ] || die "user-data template not found."

# config-deb templates: repo layout (pkg/ppgw-config) or ISO layout
# (tools/ppgw-config next to this script).
tpl=""
for c in "$scriptdir/pkg/ppgw-config" "$scriptdir/ppgw-config"; do
    [ -d "$c" ] && tpl="$c" && break
done
[ -n "$tpl" ] || die "ppgw-config templates not found next to make-seed.sh."

# ------------------------------------------------- compile ppgw-config
stamp="$(date +%Y%m%d%H%M%S)"
log "Compiling ppgw-config deb (version 0.$stamp)..."
stage="$work/stage"
mkdir -p "$stage/DEBIAN" "$stage/etc/ppgw"

# Sanitize: strip CRLF (Windows editors) and trailing whitespace, then
# append CLI overrides (sourced last, they win).
sed -e 's/\r$//' -e 's/[[:space:]]*$//' "$conf" >"$stage/etc/ppgw/seed.conf"
[ -n "$ov_key" ] && printf 'ssh_authorized_key="%s"\n' "$ov_key" >>"$stage/etc/ppgw/seed.conf"
[ -n "$ov_pass" ] && printf 'password="%s"\n' "$ov_pass" >>"$stage/etc/ppgw/seed.conf"
[ -n "$ov_host" ] && printf 'hostname="%s"\n' "$ov_host" >>"$stage/etc/ppgw/seed.conf"
chmod 600 "$stage/etc/ppgw/seed.conf"

bash -n "$stage/etc/ppgw/seed.conf" || die "ppgw.conf has shell syntax errors."

sed "s/@VERSION@/0.$stamp/" "$tpl/control" >"$stage/DEBIAN/control"
install -m 0755 "$tpl/postinst" "$stage/DEBIAN/postinst"
dpkg-deb --root-owner-group -Zxz -b "$stage" "$work/ppgw-config_0.${stamp}_all.deb" >/dev/null

# ---------------------------------------------------- assemble the ISO
iso="$work/iso"
mkdir -p "$iso/debs" "$iso/tools/ppgw-config"

cp "$userdata" "$iso/user-data"
printf 'instance-id: ppgw-%s\nlocal-hostname: PaoPaoGW\n' "$stamp" >"$iso/meta-data"
sed -e 's/\r$//' "$conf" >"$iso/ppgw.conf"

# Shared debs (drop any stale ppgw-config from a previous run).
find "$debsdir" -maxdepth 1 -name '*.deb' ! -name 'ppgw-config_*' \
    -exec cp {} "$iso/debs/" \;
cp "$work/ppgw-config_0.${stamp}_all.deb" "$iso/debs/"

# Self-contained re-pack toolkit.
cp "$scriptdir/$(basename "$0")" "$iso/tools/make-seed.sh" 2>/dev/null || cp "$0" "$iso/tools/make-seed.sh"
cp "$tpl/control" "$tpl/postinst" "$iso/tools/ppgw-config/"
chmod 755 "$iso/tools/make-seed.sh"

# ------------------------------------------------------------ mkisofs
log "Packing $outiso ..."
if command -v xorriso >/dev/null; then
    xorriso -as mkisofs -r -J -joliet-long -V cidata -o "$outiso" "$iso" >/dev/null 2>&1
elif command -v genisoimage >/dev/null; then
    genisoimage -quiet -r -J -joliet-long -V cidata -o "$outiso" "$iso"
else
    die "Need xorriso or genisoimage to build the ISO."
fi
log "Done: $outiso (config version 0.$stamp, instance-id ppgw-$stamp)"
