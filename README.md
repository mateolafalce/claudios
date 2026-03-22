# ClaudiOS

A minimalist OS based on Ubuntu 24.04 LTS whose sole purpose is to boot directly into **Claude Code** as the primary interface. No GUI — TUI only.

## Concept

ClaudiOS replaces the traditional shell with Claude Code. When the user logs in, they land directly in a Claude Code session. No desktop, no window manager, no extra apps — just the minimum system required for Claude to run and have internet access.

## Boot flow

```
BIOS/UEFI → GRUB → Linux → TTY login
  └─ user: claudios / password: claudios
       └─ claudios-shell (login shell)
            ├─ [if claude missing] auto-install via npm
            └─ Claude Code in loop
                 └─ Ctrl+C (3s) or type "bash" → emergency shell
```

## Build requirements

- A Linux system with `live-build` installed
- `curl` and `gnupg`
- Internet connection
- ~10 GB of free disk space

```bash
sudo apt install live-build curl gnupg
```

## Build

```bash
sudo ./build.sh
```

The process downloads Ubuntu packages and produces a bootable hybrid ISO. Expect 10–30 minutes depending on your connection.

## Test in QEMU

```bash
./test.sh
```

Requires `qemu-system-x86`:

```bash
sudo apt install qemu-system-x86
```

## Flash to USB

```bash
sudo dd if=live-image-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress
```

Replace `/dev/sdX` with the correct USB device (`lsblk` to identify it).

## Session persistence

On first boot from USB, ClaudiOS automatically detects the boot device and creates a persistence partition in the remaining free space. This means your Claude Code session (auth, config, history) survives reboots — no manual setup needed.

The persistence partition is an ext4 filesystem labeled `persistence` with a `/home` overlay. It is created by a systemd oneshot service (`claudios-persist.service`) that runs once and marks itself done.

## Default credentials

| Field    | Value                          |
|----------|-------------------------------|
| Username | `claudios`                    |
| Password | `claudios`                    |
| API key  | managed by Claude Code          |

## Project structure

```
claudios/
├── build.sh                    # Main build script (requires sudo)
├── clean.sh                    # Removes build artifacts
├── test.sh                     # Launches the ISO in QEMU
├── auto/
│   ├── config                  # live-build configuration
│   ├── build                   # Wrapper for lb build
│   └── clean                   # Wrapper for lb clean
└── config/
    ├── archives/               # Additional apt repositories (NodeSource)
    ├── package-lists/          # Packages to install in the ISO
    ├── hooks/live/             # Scripts that run inside the build chroot
    │   ├── 0050-locale-timezone.hook.chroot
    │   ├── 0100-install-nodejs.hook.chroot
    │   ├── 0200-install-claude-code.hook.chroot
    │   ├── 0300-create-user.hook.chroot
    │   └── 0350-enable-persist.hook.chroot
    └── includes.chroot/        # Files copied directly into the filesystem
        ├── etc/motd
        ├── etc/shells
        ├── etc/sudoers.d/claudios  # Passwordless sudo for reboot
        ├── etc/systemd/system/
        │   └── claudios-persist.service  # Auto-persistence on first boot
        ├── home/claudios/.claude/commands/
        │   ├── reset.md            # /reset slash command
        │   └── logout.md           # /logout slash command
        └── usr/local/bin/
            ├── claudios-shell      # Primary login shell
            └── claudios-persist    # Auto-persistence setup script
```

## Key components

### `claudios-shell`

The user's login shell (`/etc/passwd` points here). It handles:

1. Detecting whether `claude` is installed — if not, installs it automatically via npm
2. Launching `claude` in a loop (on exit, offers to restart or drop to bash)
3. Escape hatch: hold Ctrl+C for 3 seconds at startup → emergency bash

API key management is handled by Claude Code itself.

### Custom slash commands

ClaudiOS includes built-in slash commands for system management:

| Command | Description |
|---------|-------------|
| `/reset` | Reboots the system |
| `/logout` | Exits Claude Code and returns to claudios-shell |

These are defined in `~/.claude/commands/`.

## Emergency recovery

If `claudios-shell` fails and you lose access:

1. **From boot**: in GRUB, edit the kernel line and append `init=/bin/bash`
2. **From TTY**: if you reach the login prompt, the `claudios` user has sudo — another root user can change the shell with `chsh`

## Clean the build

```bash
sudo ./clean.sh
```
