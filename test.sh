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

echo "Starting $ISO in QEMU..."
echo "(Ctrl+A, X to quit QEMU)"
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
    -cdrom "$ISO" \
    -boot d \
    -net nic \
    -net user \
    -nographic \
    -serial mon:stdio
