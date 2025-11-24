#!/bin/bash
#
# Automount Failure Notification Script
# This script is called when automount.service fails
#

SERVICE_NAME="${1:-automount.service}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)

# Base directory (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration for mount point info
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

# Log file for tracking failures
LOG_FILE="$SCRIPT_DIR/automount-failures.log"

# Get failure reason from systemd
FAILURE_REASON=$(systemctl --user status "$SERVICE_NAME" 2>&1 | tail -20)

# Log the failure
echo "[$TIMESTAMP] Automount failed" >> "$LOG_FILE"
echo "$FAILURE_REASON" >> "$LOG_FILE"
echo "----------------------------------------" >> "$LOG_FILE"

# Desktop notification
NOTIFICATION_SENT=false

# KDE Plasma - use kdialog (native KDE notification)
if [ -n "$DISPLAY" ] && command -v kdialog &> /dev/null; then
    kdialog --title "Automount Failed" \
            --error "⚠️ Failed to mount ${MOUNT_POINT:-webserver} at $TIMESTAMP

Your webserver files are NOT accessible!

Common fix: Restart the LXC server
  ssh ${LXC_HOSTNAME} 'sudo reboot'

Check logs with:
journalctl --user -u automount.service" 2>/dev/null && NOTIFICATION_SENT=true
fi

# Fallback to notify-send (works on most desktops)
if [ "$NOTIFICATION_SENT" = false ] && [ -n "$DISPLAY" ] && command -v notify-send &> /dev/null; then
    notify-send -u critical \
        "⚠️ Automount Failed" \
        "Failed to mount ${MOUNT_POINT:-webserver} at $TIMESTAMP\nCommon fix: ssh ${LXC_HOSTNAME} 'sudo reboot'\nCheck logs: journalctl --user -u automount.service" && NOTIFICATION_SENT=true
fi

# Try to find the DBUS session for notification (even if not in active session)
# This is useful for boot-time failures
if [ "$NOTIFICATION_SENT" = false ]; then
    # Get the user's UID
    USER_UID=$(id -u)
    
    # Try kdialog with DBUS
    if command -v kdialog &> /dev/null; then
        for session in /run/user/$USER_UID/bus; do
            if [ -S "$session" ]; then
                DBUS_SESSION_BUS_ADDRESS="unix:path=$session" \
                kdialog --title "Automount Failed" \
                        --error "⚠️ Failed to mount ${MOUNT_POINT:-webserver} at $TIMESTAMP" 2>/dev/null && NOTIFICATION_SENT=true && break
            fi
        done
    fi
    
    # Try notify-send with DBUS
    if [ "$NOTIFICATION_SENT" = false ] && command -v notify-send &> /dev/null; then
        for session in /run/user/$USER_UID/bus; do
            if [ -S "$session" ]; then
                DBUS_SESSION_BUS_ADDRESS="unix:path=$session" \
                notify-send -u critical \
                    "⚠️ Automount Failed" \
                    "Failed to mount ${MOUNT_POINT:-webserver} at $TIMESTAMP" 2>/dev/null && NOTIFICATION_SENT=true && break
            fi
        done
    fi
fi

# Create a visible flag file
FLAG_FILE="$SCRIPT_DIR/.automount-failed"
echo "Automount failed at $TIMESTAMP" > "$FLAG_FILE"
echo "Mount point: ${MOUNT_POINT:-unknown}" >> "$FLAG_FILE"
echo "Check: journalctl --user -u automount.service" >> "$FLAG_FILE"

exit 0
