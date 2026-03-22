# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

ClaudiOS is a custom Ubuntu 24.04 LTS live ISO that boots directly into Claude Code as the sole user interface. There is no desktop or window manager — only a TTY login that drops the user straight into a Claude Code session via a custom login shell.

## Build and test

```bash
# Build the ISO (requires root — live-build needs it)
sudo ./build.sh

# Test the ISO in QEMU (no display needed — runs in the terminal)
./test.sh

# Clean all build artifacts
sudo ./clean.sh
```

Build output goes to `build.log` (piped there by `auto/build`). The generated ISO appears in the project root as `*.iso`.

The build requires `live-build`, `curl`, `gnupg`, `grub-pc-bin`, and `xorriso`:
```bash
sudo apt install live-build curl gnupg grub-pc-bin xorriso qemu-system-x86
```

## Architecture

The project uses **Debian live-build** to produce an `iso-hybrid` image. live-build reads configuration from the `auto/` and `config/` directories and assembles a chroot, then wraps it into a bootable ISO.

### Build pipeline

1. `auto/config` — passes flags to `lb config` (Ubuntu Noble, amd64, grub bootloader, no apt recommends)
2. `auto/build` — runs `lb build` and tees output to `build.log`
3. `config/archives/nodesource.list.chroot` — adds the NodeSource Node.js 22 apt repo
4. `config/package-lists/claudios.list.chroot` — declares all packages installed in the image (networking, sudo, nodejs, git, etc.)
5. `config/hooks/live/*.hook.chroot` — shell scripts executed **inside the chroot** during build, in numeric order:
   - `0050` — sets locale (`en_US.UTF-8`) and timezone (UTC)
   - `0100` — verifies Node.js/npm and places the NodeSource GPG key
   - `0200` — runs `npm install -g @anthropic-ai/claude-code`
   - `0300` — creates the `claudios` user with `claudios-shell` as its login shell
   - `0350` — enables the `claudios-persist` systemd service
6. `config/includes.chroot/` — files copied verbatim into the ISO filesystem at their respective paths

### Runtime components

**`/usr/local/bin/claudios-shell`** — the login shell set in `/etc/passwd`. On every login it:
- Auto-installs Claude Code via npm if `claude` is not in PATH
- Shows a 3-second countdown; Ctrl+C during it drops to bash
- Launches `claude` in an infinite loop; on exit prompts to restart or drop to bash

API key management is handled by Claude Code itself (via `claude` login flow).

### Custom slash commands

ClaudiOS ships two slash commands in `config/includes.chroot/home/claudios/.claude/commands/`:
- `/reboot` — reboots the system (`sudo reboot`)
- `/shut-down` — exits Claude Code and returns to claudios-shell

Passwordless sudo for `/reboot` is granted via `config/includes.chroot/etc/sudoers.d/claudios`.

### Persistence

On first boot from USB, a systemd oneshot service (`claudios-persist.service`) automatically detects the boot device and creates a persistence partition in the remaining free space. The ISO boots with `persistence persistence-media=removable-usb` kernel parameters, so on subsequent boots `/home` is overlaid and all Claude Code session data (auth, config, history) is preserved automatically.

### Key constraint: login shell in `/etc/passwd`

`claudios-shell` is registered in `/etc/shells` and set directly as the user's shell — it is not a `.bashrc` redirect. Any change to the startup sequence must be made in `claudios-shell` itself, not in shell profile files.

### NodeSource GPG key

`build.sh` downloads the NodeSource GPG key at build time and writes it to `config/archives/nodesource.key.chroot` (excluded from git). live-build picks it up automatically alongside the `.list.chroot` file.
