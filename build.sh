#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== ClaudiOS Build ==="
echo "Date: $(date)"
echo ""

# Check dependencies
for cmd in lb curl gpg xorriso; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' not found."
        echo "  sudo apt install live-build curl gnupg xorriso grub-pc-bin"
        exit 1
    fi
done

# GRUB MBR image needed to make the ISO hybrid-bootable (BIOS USB boot)
GRUB_MBR="/usr/lib/grub/i386-pc/boot_hybrid.img"
if [ ! -f "$GRUB_MBR" ]; then
    echo "ERROR: GRUB i386-pc boot_hybrid.img not found."
    echo "  sudo apt install grub-pc-bin"
    exit 1
fi

# Download NodeSource GPG key if not present
if [ ! -f config/archives/nodesource.key.chroot ]; then
    echo ">>> Downloading NodeSource GPG key..."
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor > config/archives/nodesource.key.chroot
    echo ">>> Key downloaded."
fi

# lb config (reads auto/config)
echo ">>> Running lb config..."
lb config

# lb build (reads auto/build) — must run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: lb build requires root privileges."
    echo "  Run: sudo ./build.sh"
    exit 1
fi
echo ">>> Running lb build (this may take several minutes)..."
lb build

echo ""
echo "=== Build complete ==="
ISO=$(ls -1 *.iso 2>/dev/null | head -1 || echo "")
# live-build 3.0 may leave the ISO inside chroot/
if [ -z "$ISO" ] && [ -f chroot/binary.hybrid.iso ]; then
    mv chroot/binary.hybrid.iso binary.hybrid.iso
    ISO="binary.hybrid.iso"
fi

if [ -n "$ISO" ] && [ -d "binary" ]; then
    echo ">>> Recreating ISO with xorrisofs for proper USB hybrid boot..."
    xorrisofs \
        -J -l \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -r -b boot/grub/grub_eltorito \
        -c boot.catalog \
        --grub2-mbr "$GRUB_MBR" \
        --grub2-boot-info \
        -V "ClaudiOS" \
        -o "${ISO}.new" \
        binary/
    mv "${ISO}.new" "$ISO"
    echo ">>> Hybrid ISO created (USB bootable)."

    echo ""
    echo "ISO generated: $ISO"
    echo "Size: $(du -sh "$ISO" | cut -f1)"
    echo ""
    echo "To test: ./test.sh"
    echo "To flash to USB: sudo dd if=$ISO of=/dev/sdX bs=4M status=progress"
elif [ -n "$ISO" ]; then
    echo "WARNING: binary/ directory not found, skipping USB hybrid remaster."
    echo "ISO generated: $ISO (CD boot only)"
else
    echo "WARNING: No ISO found. Check build.log"
fi
