#!/bin/bash
# Build the Vitrum live ISO with Debian live-build. Run as root inside a
# Debian 13 environment (the CI runs it in a privileged debian:trixie
# container). Expects the Vitrum .deb in iso/packages/. Output: out/*.iso
set -euo pipefail

SRC=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-/tmp/vitrum-iso}
VERSION=$(sed -n 's/^project(vitrum VERSION \([0-9.]*\).*/\1/p' "$SRC/CMakeLists.txt")

apt-get update
apt-get install -y --no-install-recommends live-build debootstrap squashfs-tools xorriso \
    grub-pc-bin grub-efi-amd64-bin mtools dosfstools ca-certificates cpio

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

lb config \
    --mode debian \
    --distribution trixie \
    --architectures amd64 \
    --archive-areas "main contrib non-free non-free-firmware" \
    --binary-images iso-hybrid \
    --bootloaders "grub-efi,grub-pc" \
    --debian-installer none \
    --memtest none \
    --apt-recommends false \
    --iso-application "Vitrum" \
    --iso-volume "VITRUM_LIVE" \
    --iso-publisher "Vitrum" \
    --bootappend-live "boot=live components quiet splash loglevel=3 vt.global_cursor_default=0 hostname=vitrum username=user live-config.noautologin user-fullname=User locales=en_US.UTF-8 keyboard-layouts=us live-config.user-default-groups=audio,cdrom,dip,floppy,video,plugdev,netdev,input,render,sudo"

# Packages for the live system
mkdir -p config/package-lists
cat > config/package-lists/vitrum.list.chroot <<'LIST'
plymouth
plymouth-label
live-boot
live-config
live-config-systemd
systemd-sysv
libpam-systemd
dbus
dbus-user-session
sudo
polkitd
locales
console-setup
keyboard-configuration
network-manager
pipewire
pipewire-pulse
wireplumber
libgl1-mesa-dri
libegl-mesa0
libgbm1
qt6-qpa-plugins
qt6-wayland
xserver-xorg-core
xserver-xorg-input-libinput
xinit
foot
firefox-esr
xdg-utils
icoutils
wine
wine64
fonts-noto-core
fonts-open-sans
adwaita-icon-theme
hicolor-icon-theme
spice-vdagent
open-vm-tools
LIST

# Our package
mkdir -p config/packages.chroot
cp "$SRC"/iso/packages/*.deb config/packages.chroot/

# Files and hooks
cp -r "$SRC/iso/includes.chroot" config/
mkdir -p config/hooks/normal
cp "$SRC"/iso/hooks/*.hook.chroot config/hooks/normal/

lb build

mkdir -p "$SRC/out"
mv live-image-amd64.hybrid.iso "$SRC/out/vitrum-${VERSION}-live-amd64.iso"
