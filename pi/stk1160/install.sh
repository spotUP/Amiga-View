#!/bin/sh
# Install the patched stk1160 module for the running kernel and reload it.
set -e
K=$(uname -r)
cd "$(dirname "$0")"
make
systemctl --user stop amiga-cam
sudo mkdir -p /lib/modules/$K/updates
sudo cp stk1160.ko /lib/modules/$K/updates/
sudo depmod -a
sudo modprobe -r stk1160
sudo modprobe stk1160
/sbin/modinfo stk1160 | head -3
systemctl --user start amiga-cam
echo INSTALL_OK
