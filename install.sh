#!/bin/bash
#
# Install Automount DDEV systemd services
# Run this script to set up and configure the services
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
    echo "✓ Loaded configuration from config.sh"
else
    echo "⚠️  No config.sh found, using defaults"
    MOUNT_POINT="/mnt/sites"
    LXC_HOSTNAME="lxcddev"
fi

# Systemd user directory (respects XDG_CONFIG_HOME)
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

echo ""
echo "Installing Automount DDEV systemd service..."
echo "  Mount point: $MOUNT_POINT"
echo "  LXC hostname: $LXC_HOSTNAME"
echo ""

# Create systemd user directory if it doesn't exist
mkdir -p "$SYSTEMD_USER_DIR"

# Remove old service files if they exist
echo "Cleaning up old service files..."
rm -f "$SYSTEMD_USER_DIR/automount.service"
rm -f "$SYSTEMD_USER_DIR/automount-failure-notify@.service"
rm -f "$SYSTEMD_USER_DIR/ping-lxcddev.service"

# Generate service file with configured paths
echo "Generating service files from templates..."

# automount.service
sed -e "s|%MOUNT_POINT%|$MOUNT_POINT|g" \
    -e "s|%LXC_HOSTNAME%|$LXC_HOSTNAME|g" \
    "$SCRIPT_DIR/automount.service" > "$SYSTEMD_USER_DIR/automount.service"

# automount-failure-notify@.service
sed "s|%SCRIPT_DIR%|$SCRIPT_DIR|g" \
    "$SCRIPT_DIR/automount-failure-notify@.service" > "$SYSTEMD_USER_DIR/automount-failure-notify@.service"

echo "✓ Service files generated"
echo ""

# Make scripts executable
echo "Making scripts executable..."
chmod +x "$SCRIPT_DIR/notify-mount-failure.sh"
echo "✓ Scripts are executable"
echo ""

# Reload systemd
echo "Reloading systemd..."
systemctl --user daemon-reload
echo "✓ Systemd reloaded"
echo ""

# Enable and start service
echo "Enabling service..."
systemctl --user enable automount.service
echo "✓ Service enabled"
echo ""

# Start service
echo "Starting service..."
systemctl --user start automount.service
echo "✓ Service started"
echo ""

# Show status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Installation complete! Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
systemctl --user status automount.service --no-pager | head -10
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation complete!"
echo ""
echo "Your automount service is now running with:"
echo "  • Automatic mount on boot after $LXC_HOSTNAME is reachable"
echo "  • Mount point: $MOUNT_POINT"
echo "  • Desktop notifications on failure"
echo ""
echo "⚠️  Note: Make sure $MOUNT_POINT is configured in /etc/fstab"
echo ""

# Check for lingering
LINGER_STATUS=$(loginctl show-user $USER 2>/dev/null | grep "Linger=" | cut -d= -f2)
if [ "$LINGER_STATUS" != "yes" ]; then
    echo "⚠️  IMPORTANT: User lingering is NOT enabled!"
    echo "   Your service will STOP when you log out."
    echo ""
    echo "   To keep the service running when logged out, run:"
    echo "   sudo loginctl enable-linger $USER"
    echo ""
fi

echo "Configuration: $SCRIPT_DIR/config.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
