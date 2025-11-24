#!/bin/bash
#
# Pre-unmount warning notification
# Warns user 5 minutes before auto-unmount
#

TIMESTAMP=$(date '+%H:%M:%S')

# Desktop notification
NOTIFICATION_SENT=false

# KDE Plasma - use kdialog
if [ -n "$DISPLAY" ] && command -v kdialog &> /dev/null; then
    kdialog --title "Auto-unmount Warning" \
            --passivepopup "⏰ Webserver will auto-unmount in 5 minutes

Please save your work and close any open files." 10 2>/dev/null && NOTIFICATION_SENT=true
fi

# Fallback to notify-send
if [ "$NOTIFICATION_SENT" = false ] && [ -n "$DISPLAY" ] && command -v notify-send &> /dev/null; then
    notify-send -u normal -t 10000 \
        "⏰ Auto-unmount Warning" \
        "Webserver will auto-unmount in 5 minutes\nPlease save your work and close any open files." && NOTIFICATION_SENT=true
fi

# Try with DBUS if not in active session
if [ "$NOTIFICATION_SENT" = false ]; then
    USER_UID=$(id -u)
    
    if command -v kdialog &> /dev/null; then
        for session in /run/user/$USER_UID/bus; do
            if [ -S "$session" ]; then
                DBUS_SESSION_BUS_ADDRESS="unix:path=$session" \
                kdialog --title "Auto-unmount Warning" \
                        --passivepopup "⏰ Webserver will auto-unmount in 5 minutes" 10 2>/dev/null && break
            fi
        done
    fi
fi

exit 0
