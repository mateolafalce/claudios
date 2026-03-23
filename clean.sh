#!/bin/bash
set -e
cd "$(dirname "$0")"
echo ">>> Cleaning build artifacts..."
sudo lb clean --purge
# lb clean --purge may leave the bootstrap cache and stage markers behind
sudo rm -rf .build cache
rm -f build.log
echo ">>> Done."
