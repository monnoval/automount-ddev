# Automount DDEV

Systemd user service to automatically mount remote directories after checking server availability.

## Compatibility

**Cross-platform compatible**: Works on Debian-based and RHEL-based distributions.

All commands use portable paths (no hardcoded `/usr/bin` or `/usr/sbin`), allowing systemd to automatically resolve the correct locations across different Linux distributions.

**Tested on:**
- Debian-based: Debian, Ubuntu, Linux Mint, Pop!_OS
- RHEL-based: AlmaLinux, Rocky Linux, RHEL, CentOS Stream, Fedora
- Other: openSUSE, Arch Linux (likely compatible)

**Requirements:**
- systemd with user services support
- Standard mount utilities (mount, umount, findmnt)
- Optional: ZeroTier for VPN functionality
- Optional: libnotify or kdialog for desktop notifications

## Features

- **automount.service**: Checks if remote server is reachable and automatically mounts the directory on boot
- **Failure notifications**: Desktop notifications if mount fails
- **ZeroTier aware**: Waits for ZeroTier to be ready before attempting mount

## Installation

1. **Copy the configuration template:**
   ```bash
   cp config.sh.example config.sh
   ```

2. **Edit `config.sh` to match your setup:**
   ```bash
   nano config.sh
   ```
   
   Customize these variables:
   - `MOUNT_POINT`: Where to mount the remote directory (must be configured in /etc/fstab)
   - `REMOTE_HOST`: Hostname or IP of your remote server

3. **Run the installation script:**
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

4. **Enable user lingering (optional but recommended):**
   
   This keeps your services running even when you log out:
   ```bash
   sudo loginctl enable-linger $USER
   ```

## Usage

```bash
# Check service status
systemctl --user status automount.service

# View logs
journalctl --user -u automount.service

# Restart service
systemctl --user restart automount.service

# Stop service
systemctl --user stop automount.service

# Disable service
systemctl --user disable automount.service
```

## How It Works

1. When your system boots, `automount.service` starts after ZeroTier is ready
2. It pings the remote server to check availability
3. If reachable and not already mounted, it mounts the directory
4. If mount fails, you get a desktop notification
5. The mount remains active until you log out (or permanently if lingering is enabled)

## Uninstallation

```bash
systemctl --user stop automount.service
systemctl --user disable automount.service
rm ~/.config/systemd/user/automount.service
rm ~/.config/systemd/user/automount-failure-notify@.service
systemctl --user daemon-reload
```

## Configuration Files

- `config.sh.example` - Template configuration file
- `config.sh` - Your local configuration (git-ignored)
- `automount.service` - Systemd service template
- `automount-failure-notify@.service` - Failure notification service template
- `notify-mount-failure.sh` - Notification script
- `install.sh` - Installation script

## Troubleshooting

### Service won't start
Check if the remote server is reachable:
```bash
ping -c 1 your-server-hostname
```

### Mount fails
Ensure your mount point is configured in `/etc/fstab`:
```bash
grep your-mount-point /etc/fstab
```

Check the failure log:
```bash
cat automount-failures.log
```

### Service stops when you log out
Enable user lingering:
```bash
sudo loginctl enable-linger $USER
```
