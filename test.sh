#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ISO="${1:-$(ls -1t *.iso 2>/dev/null | head -1)}"

if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
    echo "Usage: $0 [path-to-iso]"
    echo "No ISO found. Run ./build.sh first."
    exit 1
fi

# Check dependencies
if ! command -v qemu-system-x86_64 &>/dev/null; then
    echo "ERROR: qemu-system-x86_64 not found."
    echo "  sudo apt install qemu-system-x86"
    exit 1
fi

# Create a virtual USB disk image with the ISO dd'd onto it
# This simulates a real USB stick and allows persistence testing
USB_IMG="test-usb.img"

if [ -f "$USB_IMG" ] && [ "${FRESH:-}" != "1" ]; then
    echo "Re-using existing virtual USB disk (set FRESH=1 to recreate)..."
else
    ISO_SIZE=$(stat -c%s "$ISO")
    # Disk = ISO size + 512MB for persistence partition
    DISK_SIZE=$(( ISO_SIZE + 512 * 1024 * 1024 ))

    echo "Creating virtual USB disk ($((DISK_SIZE / 1024 / 1024))MB)..."
    qemu-img create -f raw "$USB_IMG" "$DISK_SIZE"
    dd if="$ISO" of="$USB_IMG" bs=4M conv=notrunc status=none

    # Create persistence partition in remaining space (no root needed)
    echo "Creating persistence partition on virtual disk..."
    FREE_INFO=$(parted -s "$USB_IMG" unit B print free 2>/dev/null | grep 'Free Space' | tail -1 || true)
    if [ -n "$FREE_INFO" ]; then
        FREE_START=$(echo "$FREE_INFO" | awk '{print $1}' | tr -d 'B')
        FREE_END=$(echo "$FREE_INFO" | awk '{print $2}' | tr -d 'B')
        ALIGN=$((1024 * 1024))
        ALIGNED_START=$(( (FREE_START + ALIGN - 1) / ALIGN * ALIGN ))
        PART_SIZE_KB=$(( (FREE_END - ALIGNED_START) / 1024 ))

        parted -s -a optimal "$USB_IMG" mkpart primary ext4 "${ALIGNED_START}B" "${FREE_END}B"

        # Build ext4 partition image with persistence.conf (no root/losetup needed)
        PERSIST_DIR=$(mktemp -d)
        echo "/ union" > "$PERSIST_DIR/persistence.conf"
        PART_FILE=$(mktemp)
        mke2fs -t ext4 -L persistence -d "$PERSIST_DIR" "$PART_FILE" "${PART_SIZE_KB}k" >/dev/null 2>&1
        rm -rf "$PERSIST_DIR"

        # Write partition image into the virtual disk at the correct offset
        dd if="$PART_FILE" of="$USB_IMG" bs=1M seek=$((ALIGNED_START / 1048576)) conv=notrunc status=none
        rm "$PART_FILE"
        echo "Persistence partition created."
    else
        echo "WARNING: could not create persistence partition on virtual disk."
    fi
fi

echo "Starting ClaudiOS from virtual USB disk..."
echo "(Ctrl+A, X to quit QEMU)"
echo "(Re-run without FRESH=1 to test persistence across reboots)"
echo ""

# Optional KVM flags (if available)
KVM_FLAG=""
if [ -w /dev/kvm ]; then
    KVM_FLAG="-enable-kvm"
fi

qemu-system-x86_64 \
    -m 2048 \
    -smp 2 \
    $KVM_FLAG \
    -usb \
    -drive file="$USB_IMG",format=raw,if=none,id=usbdisk \
    -device usb-storage,drive=usbdisk \
    -boot c \
    -net nic \
    -net user \
    -nographic \
    -serial mon:stdio
