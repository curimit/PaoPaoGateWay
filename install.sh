#!/bin/bash
# PaoPao Gateway offline installer for bare-metal / existing Ubuntu.
#
# Ships inside ppgw-offline.tar.gz next to debs/. Fully offline: installs
# the bundled debs (ppgw packages + dependency closure) with apt and
# nothing else. Login and network settings of the host are not touched
# (the ppgw-config deb is seed-ISO-only). Safe to re-run to upgrade.
set -eu

cd "$(dirname "$0")"

[ "$(id -u)" = "0" ] || { echo "This installer must run as root." >&2; exit 1; }
grep -qi ubuntu /etc/os-release || { echo "This installer targets Ubuntu." >&2; exit 1; }
[ -d debs ] || { echo "debs/ directory not found next to install.sh." >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=600 install -y --no-install-recommends ./debs/*.deb

echo ""
echo "Install finished (ppgw.service is enabled)."
echo "Reboot to start the gateway: sudo reboot"
