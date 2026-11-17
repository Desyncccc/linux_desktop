#!/bin/bash
# Boot the live ISO in QEMU and report what happens: serial console output
# (including Vitrum's session log) and screenshots printed into the CI log as
# small base64 PNGs.
# Usage: boot-test.sh ISO VGA OUTDIR [FIRMWARE] [BOOT] [EXTRA_APPEND]
#   FIRMWARE: bios (default) or uefi (OVMF, q35 machine with a SATA CD-ROM,
#             like VMware's UEFI virtual machines)
#   BOOT:     kernel (default; direct kernel boot with serial logging) or
#             grub (the ISO's own boot menu, as a user would boot it)
set -uo pipefail
ISO=$1
VGA=${2:-virtio}
OUT=${3:-boot-shots}
FIRMWARE=${4:-bios}
BOOT=${5:-kernel}
EXTRA=${6:-}
mkdir -p "$OUT"
WORK=$(mktemp -d)

MACHINE=""
FW=""
if [ "$FIRMWARE" = uefi ]; then
    MACHINE="-machine q35"
    CODE=$(ls /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd 2>/dev/null | head -n1)
    VARS=$(ls /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd 2>/dev/null | head -n1)
    cp "$VARS" "$WORK/vars.fd"
    FW="-drive if=pflash,format=raw,readonly=on,file=$CODE -drive if=pflash,format=raw,file=$WORK/vars.fd"
fi

KERNEL_ARGS=()
if [ "$BOOT" = kernel ]; then
    KERNEL=$(bsdtar -tf "$ISO" | grep -m1 '^live/vmlinuz')
    INITRD=$(bsdtar -tf "$ISO" | grep -m1 '^live/initrd')
    echo "Kernel: $KERNEL  initrd: $INITRD"
    bsdtar -xf "$ISO" -C "$WORK" "$KERNEL" "$INITRD"
    APPEND=$(bsdtar -xOf "$ISO" boot/grub/grub.cfg boot/grub/config.cfg 2>/dev/null | sed -n 's/^[[:space:]]*linux[[:space:]]\+[^ ]*vmlinuz[^ ]* \(.*\)$/\1/p' | head -n1)
    # Drop GRUB-only parameters (e.g. findiso=${iso_path}, which GRUB expands).
    APPEND=$(printf '%s\n' "$APPEND" | tr ' ' '\n' | grep -v '\${' | tr '\n' ' ')
    [ -n "${APPEND// /}" ] || APPEND="boot=live components quiet splash"
    APPEND="$APPEND console=tty0 console=ttyS0,115200 vitrum.serial-log systemd.mask=serial-getty@ttyS0.service $EXTRA"
    echo "Kernel command line: $APPEND"
    KERNEL_ARGS=(-kernel "$WORK/$KERNEL" -initrd "$WORK/$INITRD" -append "$APPEND")
else
    echo "Booting through the ISO's boot menu ($FIRMWARE)"
fi

ACCEL="-accel tcg"
[ -w /dev/kvm ] && ACCEL="-enable-kvm -cpu host"

qemu-system-x86_64 $ACCEL $MACHINE $FW -m 4096 -smp 2 -vga "$VGA" -display none \
    -device qemu-xhci -device usb-tablet \
    -cdrom "$ISO" -boot d "${KERNEL_ARGS[@]}" \
    -serial "file:$OUT/serial.log" -monitor "unix:$WORK/mon.sock,server,nowait" &
QEMU=$!

shot() {
    echo "screendump $WORK/$1.ppm" | socat - "UNIX-CONNECT:$WORK/mon.sock" >/dev/null 2>&1
    sleep 1
    if [ -f "$WORK/$1.ppm" ]; then
        convert "$WORK/$1.ppm" "$OUT/$1.png"
        convert "$WORK/$1.ppm" -resize 640x "$WORK/$1-small.png"
        echo "::group::screenshot $1 (base64 PNG)"
        echo "BEGIN-SCREENSHOT $1"
        base64 -w0 "$WORK/$1-small.png"; echo
        echo "END-SCREENSHOT $1"
        echo "::endgroup::"
    fi
}

key() { echo "sendkey $1" | socat - "UNIX-CONNECT:$WORK/mon.sock" >/dev/null 2>&1; sleep 0.15; }
type_text() { local t=$1 i; for ((i = 0; i < ${#t}; i++)); do key "${t:i:1}"; done; }

sleep 60
shot "1-desktop"
key meta_l; sleep 2
shot "2-start-menu"
type_text firefox; sleep 1
shot "3-search"
key ret; sleep 40
shot "4-firefox"
key ctrl-alt-t; sleep 12
shot "5-terminal"
key meta_l-e; sleep 5
shot "6-explorer"

echo "::group::serial console"
tr -cd '\11\12\15\40-\176' < "$OUT/serial.log" | tail -n 400
echo "::endgroup::"
echo "=== Vitrum session logs from serial ==="
tr -cd '\11\12\15\40-\176' < "$OUT/serial.log" | sed -n '/=== vitrum-session exited/,/=== end of log ===/p' | head -n 300

kill $QEMU 2>/dev/null
wait $QEMU 2>/dev/null
exit 0
