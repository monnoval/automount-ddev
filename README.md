# Automount DDEV

Systemd user services to automatically mount webserver directories after checking LXC DDEV availability.

## Features

- **ping-lxcddev.service**: Checks if the LXC DDEV container is reachable before proceeding
- **automount.service**: Automatically mounts webserver directories when the system starts

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
   - `AUTOMOUNT_SCRIPT_DIR`: Path to your automount.sh script
   - `MOUNT_POINT`: Where to mount the webserver directories
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
systemctl --user status ping-lxcddev.service
```

### View logs
```bash
journalctl --user -u automount.service
journalctl --user -u ping-lxcddev.service
```

### Restart services
```bash
systemctl --user restart automount.service
```

### Stop services
```bash
systemctl --user stop automount.service
```

### Disable services
```bash
systemctl --user disable automount.service
systemctl --user disable ping-lxcddev.service
```

## How It Works

1. When your system boots, `ping-lxcddev.service` starts and pings the LXC DDEV container
2. If the container is reachable, `automount.service` runs your automount script
3. The mount remains active until you log out (or permanently if lingering is enabled)

## Uninstallation

```bash
systemctl --user stop automount.service ping-lxcddev.service
systemctl --user disable automount.service ping-lxcddev.service
rm ~/.config/systemd/user/automount.service
rm ~/.config/systemd/user/ping-lxcddev.service
systemctl --user daemon-reload
```

## Configuration Files

- `config.sh.example` - Template configuration file
- `config.sh` - Your local configuration (git-ignored)
- `automount.service` - Systemd service template for mounting
- `ping-lxcddev.service` - Systemd service template for network check
- `install.sh` - Installation script

## Troubleshooting

### Services won't start
Check if the LXC container is reachable:
```bash
ping -c 1 lxcddev
```

### Mount fails
Check the automount script exists and is executable:
```bash
ls -la ~/Projects/_config/automount.sh
```

### Services stop when you log out
Enable user lingering:
```bash
sudo loginctl enable-linger $USER
```
