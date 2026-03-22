#!/bin/bash
set -e
cd "$(dirname "$0")"
echo ">>> Cleaning build artifacts..."
sudo lb clean --purge
rm -f build.log
echo ">>> Done."
