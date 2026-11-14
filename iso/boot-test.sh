#!/bin/bash
# Boot the live ISO in QEMU and report what happens: serial console output
# (including Vitrum's session log) and screenshots printed into the CI log as
# small base64 PNGs. Usage: boot-test.sh ISO VGA OUTDIR
set -uo pipefail
ISO=$1
VGA=${2:-virtio}
OUT=${3:-boot-shots}
mkdir -p "$OUT"
WORK=$(mktemp -d)

KERNEL=$(bsdtar -tf "$ISO" | grep -m1 '^live/vmlinuz')
INITRD=$(bsdtar -tf "$ISO" | grep -m1 '^live/initrd')
echo "Kernel: $KERNEL  initrd: $INITRD"
bsdtar -xf "$ISO" -C "$WORK" "$KERNEL" "$INITRD"
APPEND=$(bsdtar -xOf "$ISO" boot/grub/grub.cfg boot/grub/config.cfg 2>/dev/null | sed -n 's/^[[:space:]]*linux[[:space:]]\+[^ ]*vmlinuz[^ ]* \(.*\)$/\1/p' | head -n1)
# Drop GRUB-only parameters (e.g. findiso=${iso_path}, which GRUB expands).
APPEND=$(printf '%s\n' "$APPEND" | tr ' ' '\n' | grep -v '\${' | tr '\n' ' ')
[ -n "${APPEND// /}" ] || APPEND="boot=live components quiet splash"
APPEND="$APPEND console=tty0 console=ttyS0,115200 vitrum.serial-log systemd.mask=serial-getty@ttyS0.service"
echo "Kernel command line: $APPEND"

ACCEL="-accel tcg"
[ -w /dev/kvm ] && ACCEL="-enable-kvm -cpu host"

qemu-system-x86_64 $ACCEL -m 4096 -smp 2 -vga "$VGA" -display none \
    -device qemu-xhci -device usb-tablet \
    -cdrom "$ISO" -kernel "$WORK/$KERNEL" -initrd "$WORK/$INITRD" -append "$APPEND" \
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

for t in 45 90 150 210; do
    sleep $(( t - ${prev:-0} ))
    prev=$t
    shot "t${t}s"
done

echo "::group::serial console"
tr -cd '\11\12\15\40-\176' < "$OUT/serial.log" | tail -n 400
echo "::endgroup::"
echo "=== Vitrum session logs from serial ==="
tr -cd '\11\12\15\40-\176' < "$OUT/serial.log" | sed -n '/=== vitrum-session exited/,/=== end of log ===/p' | head -n 300

kill $QEMU 2>/dev/null
wait $QEMU 2>/dev/null
exit 0
