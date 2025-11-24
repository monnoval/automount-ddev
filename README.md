# Automount DDEV

Systemd user service to automatically mount webserver directories after checking LXC DDEV availability.

## Features

- **automount.service**: Checks if LXC DDEV is reachable and automatically mounts the webserver directory on boot
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
   - `MOUNT_POINT`: Where to mount the webserver directory (must be configured in /etc/fstab)
   - `LXC_HOSTNAME`: Hostname of your LXC DDEV container

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

### Check service status
```bash
systemctl --user status automount.service
```

### View logs
```bash
journalctl --user -u automount.service
```

### Restart service
```bash
systemctl --user restart automount.service
```

### Stop service
```bash
systemctl --user stop automount.service
```

### Disable service
```bash
systemctl --user disable automount.service
```

## How It Works

1. When your system boots, `automount.service` starts after ZeroTier is ready
2. It pings the LXC DDEV container to check availability
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
Check if the LXC container is reachable:
```bash
ping -c 1 your-lxc-hostname
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
