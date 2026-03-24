#!/bin/bash
# Flash ClaudiOS ISO to a USB drive and create the persistence partition.
# Usage: sudo ./flash.sh /dev/sdX [path-to-iso]

set -euo pipefail

DEVICE="${1:-}"
ISO="${2:-$(ls -1t *.iso 2>/dev/null | head -1 || true)}"

if [ -z "$DEVICE" ]; then
    echo "Usage: sudo $0 /dev/sdX [path-to-iso]"
    echo ""
    echo "Available removable devices:"
    lsblk -d -o NAME,SIZE,RM,TYPE,MOUNTPOINTS | grep -E '^\S+\s+\S+\s+1\s+disk' || echo "  (none found)"
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    echo "ERROR: $DEVICE is not a block device"
    exit 1
fi

if [ -z "$ISO" ] || [ ! -f "$ISO" ]; then
    echo "ERROR: no ISO found. Run ./build.sh first."
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo ./flash.sh $DEVICE)"
    exit 1
fi

# Safety check: refuse to flash to non-removable devices
REMOVABLE=$(lsblk -d -n -o RM "$DEVICE" 2>/dev/null | xargs || echo "0")
if [ "$REMOVABLE" != "1" ]; then
    echo "ERROR: $DEVICE is not a removable device. Refusing to flash."
    echo "       If you're sure, use: dd if=$ISO of=$DEVICE bs=4M status=progress"
    exit 1
fi

# Check for mounted partitions on the device
if mount | grep -q "^${DEVICE}"; then
    echo "ERROR: $DEVICE has mounted partitions. Unmount them first:"
    mount | grep "^${DEVICE}" | awk '{print "  sudo umount " $1}'
    exit 1
fi

echo "=== ClaudiOS Flash ==="
echo "ISO:    $ISO ($(du -sh "$ISO" | cut -f1))"
echo "Device: $DEVICE ($(lsblk -d -n -o SIZE "$DEVICE"))"
echo ""
echo "WARNING: ALL data on $DEVICE will be destroyed!"
read -rp "Continue? [y/N] " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

# Step 1: Write ISO to device
echo ""
echo ">>> Writing ISO to $DEVICE..."
dd if="$ISO" of="$DEVICE" bs=4M status=progress conv=fsync
sync

# Step 2: Re-read partition table
partprobe "$DEVICE" 2>/dev/null || true
udevadm settle --timeout=10 2>/dev/null || true
sleep 1

# Step 3: Create persistence partition in remaining space
echo ""
echo ">>> Creating persistence partition..."

FREE_INFO=$(parted -s "$DEVICE" unit B print free 2>/dev/null | grep 'Free Space' | tail -1 || true)
if [ -z "$FREE_INFO" ]; then
    echo "WARNING: no free space found on $DEVICE. Persistence partition not created."
    echo "         The ISO will still boot, but changes won't persist across reboots."
    exit 0
fi

FREE_START=$(echo "$FREE_INFO" | awk '{print $1}' | tr -d 'B')
FREE_END=$(echo "$FREE_INFO" | awk '{print $2}' | tr -d 'B')

# Align start to 1MiB boundary for optimal performance
ALIGN=$((1024 * 1024))
ALIGNED_START=$(( (FREE_START + ALIGN - 1) / ALIGN * ALIGN ))

parted -s -a optimal "$DEVICE" mkpart primary ext4 "${ALIGNED_START}B" "${FREE_END}B"
partprobe "$DEVICE" 2>/dev/null || true
udevadm settle --timeout=10 2>/dev/null || true
sleep 1

# Determine new partition name
if echo "$DEVICE" | grep -qE 'nvme|loop|mmcblk'; then
    NEW_PART="${DEVICE}p2"
else
    NEW_PART="${DEVICE}2"
fi

# Wait for device node
for i in $(seq 1 10); do
    [ -b "$NEW_PART" ] && break
    sleep 1
done

if [ ! -b "$NEW_PART" ]; then
    echo "WARNING: partition device $NEW_PART not found. Persistence not configured."
    exit 1
fi

# Step 4: Format and configure persistence
echo ">>> Formatting $NEW_PART..."
mkfs.ext4 -q -L persistence "$NEW_PART"

MOUNT_DIR=$(mktemp -d)
mount "$NEW_PART" "$MOUNT_DIR"
echo "/ union" > "$MOUNT_DIR/persistence.conf"
sync
umount -l "$MOUNT_DIR" || umount "$MOUNT_DIR"
rmdir "$MOUNT_DIR" 2>/dev/null || true

echo ""
echo "=== Done ==="
echo "USB is ready. Persistence partition: $NEW_PART ($(lsblk -n -o SIZE "$NEW_PART" | xargs))"
echo "Boot from $DEVICE and all changes will persist across reboots."
