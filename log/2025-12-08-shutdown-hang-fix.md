# Shutdown Hang Issue - Fix Summary

**Date:** December 8, 2025  
**Issue:** System shutdown getting stuck during NFS unmount  
**Status:** Fixed (multiple iterations required)  
**Update:** See [2025-12-16-shutdown-hang-fix-update.md](./2025-12-16-shutdown-hang-fix-update.md) for Dec 16-17 refinement

## Problem Description

The system was hanging during shutdown, failing to complete the shutdown sequence properly. This required manual intervention (hard reset/power button) to power off the machine. The issue persisted through multiple attempted fixes.

## Root Causes (Multiple Issues Found)

### Issue #1: mnt-sites.mount (System Mount) - FIXED
The `/mnt/sites` NFS mount (mounting `lxcddev:/mnt/sites`) initially had:
- No timeout configured in the systemd-generated mount unit
- When the remote NFS server (`lxcddev`) was unreachable during shutdown, unmount would wait indefinitely
- Default dependencies were blocking the shutdown sequence

**Solution Applied:** Created systemd drop-in override at `/etc/systemd/system/mnt-sites.mount.d/override.conf`

### Issue #2: automount.service - fuser hanging - FAILED APPROACH
After fixing the system mount, shutdown still hung. The `automount.service` user service was timing out.

**First attempted fix:** Added `fuser -km` to kill processes before unmount
```ini
ExecStop=-/usr/sbin/fuser -km /mnt/sites
ExecStop=-umount -l /mnt/sites
```

**Result:** FAILED - `fuser` itself hung trying to check NFS mount

**Log Evidence:**
```
Dec 08 19:56:20 nitro5 systemd[1664]: automount.service: Stopping timed out. Terminating.
Dec 08 19:56:20 nitro5 systemd[1664]: automount.service: Unit process 7314 (fuser) remains running after unit stopped.
```

### Issue #3: Fundamental Design Problem - FINAL FIX
The core issue was **architectural**:
- User services shut down LATE in the shutdown sequence
- By the time `automount.service` (user service) tries to unmount, the system is already in final shutdown
- Any command that touches NFS (including `fuser`, `umount`, even `umount -f -l`) can hang
- User services are in the wrong place in the shutdown sequence to handle NFS unmounts

**Final Solution:** 
- User service (`automount.service`) does **NOTHING** on stop - just exits immediately with `/bin/true`
- System mount unit (`mnt-sites.mount`) handles all unmounting with proper timeout and lazy unmount
- This separates concerns: user service manages mounting, system manages unmounting

## Investigation Timeline

### 1. Initial Investigation
```bash
mount | grep -i ddev
# Result: lxcddev:/mnt/sites on /mnt/sites type nfs4 (rw,nosuid,nodev,noexec,...)
```

### 2. Examined fstab Configuration
```bash
cat /etc/fstab | grep sites
# Result: lxcddev:/mnt/sites	/mnt/sites	nfs   rw,suid,dev,noexec,noauto,user,async
```

### 3. Reviewed Shutdown Logs (Multiple Boots)
```bash
journalctl -b -1 --no-pager | tail -300 | grep -i "timeout\|stopping"
journalctl --user -u automount.service -b -1
```

### 4. Discovered User Service Timing Out
```
Dec 08 19:50:14 systemd[1674]: automount.service: Stopping timed out. Terminating.
```

### 5. Tried fuser Approach - Failed
```
Dec 08 19:56:20 systemd[1664]: automount.service: Unit process 7314 (fuser) remains running after unit stopped.
```

### 6. Realized Architectural Problem
- User services stop too late
- NFS operations are unreliable during late shutdown
- System mount units are the proper place for unmounting

## Final Solution

### Solution #1: mnt-sites.mount Override (System Level)

**File:** `/etc/systemd/system/mnt-sites.mount.d/override.conf`

**⚠️ NOTE:** This configuration was refined on Dec 16-17, 2025. See [2025-12-16-shutdown-hang-fix-update.md](./2025-12-16-shutdown-hang-fix-update.md) for the current working configuration and detailed explanation of the changes.

### Solution #2: automount.service Fix (User Level)

**File:** `~/.config/systemd/user/automount.service` (and template in this repo)

**Key Changes:**

1. **Removed all unmount logic from user service:**
```ini
# Don't try to unmount during shutdown - let the system mount unit handle it
# Just exit immediately
ExecStop=/bin/true
```

2. **Added shutdown ordering hints:**
```ini
# Stop BEFORE network goes down
Before=network-pre.target
Conflicts=shutdown.target
```

3. **Reduced timeout to minimum:**
```ini
TimeoutStopSec=1
KillMode=none
```

**Why This Works:**
- `/bin/true` exits instantly (success, does nothing)
- No NFS operations attempted in user service during shutdown
- System mount unit handles unmounting at the proper time in shutdown sequence
- User service just manages the initial mounting, not unmounting

## Complete automount.service Configuration

```ini
[Unit]
Description=Automount webservers
After=zerotier-one.service network-online.target
Wants=network-online.target
# Stop BEFORE network goes down
Before=network-pre.target
Conflicts=shutdown.target
OnFailure=automount-failure-notify@%n.service

[Service]
Type=oneshot
RemainAfterExit=true
StandardOutput=journal
StandardError=journal
TimeoutStopSec=1
KillMode=none
# Wait up to 30 seconds for host to become reachable (15 attempts × 2 second intervals)
# Useful for WiFi connections that take time to establish
ExecStartPre=/bin/bash -c 'for i in {1..15}; do ping -c 1 -W 2 %REMOTE_HOST% >/dev/null 2>&1 && exit 0; echo "Waiting for network... attempt $i/15"; sleep 2; done; echo "Gave up: host unreachable after 30s"; exit 1'
# Check if already mounted, if not then mount
ExecStart=/bin/bash -c 'if findmnt -M %MOUNT_POINT% >/dev/null; then echo "Already mounted"; exit 0; fi; mount %MOUNT_POINT% && echo "Mount successful" || { echo "Mount failed"; exit 1; }'
# Don't try to unmount during shutdown - let the system mount unit handle it
# Just exit immediately
ExecStop=/bin/true

[Install]
WantedBy=default.target
```

## Deployment Instructions

### For System Mount (mnt-sites.mount)
```bash
sudo mkdir -p /etc/systemd/system/mnt-sites.mount.d
# Create override.conf with the content above
sudo systemctl daemon-reload
```

**Note:** The filename inside `.mount.d/` can be anything ending with `.conf` (e.g., `10-timeout.conf`, `shutdown-fix.conf`). Systemd reads all `.conf` files in lexical order.

### For User Service (automount.service)
```bash
# After running install.sh, reload the user service
systemctl --user daemon-reload
systemctl --user restart automount.service
```

## Expected Behavior After Fix

1. During normal operation:
   - User service mounts `/mnt/sites` on login/startup
   - Mount is available for use

2. During shutdown:
   - User service stops quickly (runs `/bin/true`, exits in <1 second)
   - System mount unit (`mnt-sites.mount`) unmounts the filesystem
   - If NFS server unreachable, lazy unmount happens after 5-second timeout
   - Shutdown proceeds without hanging

## Why Previous Approaches Failed

### Attempt 1: Just lazy unmount in user service
```ini
ExecStop=-umount -l /mnt/sites
```
**Failed:** `umount -l` can still hang on NFS mounts during shutdown

### Attempt 2: Kill processes first with fuser
```ini
ExecStop=-/usr/sbin/fuser -km /mnt/sites
ExecStop=-umount -l /mnt/sites
```
**Failed:** `fuser` itself hangs when checking NFS mount points

### Attempt 3: Force + lazy unmount
```ini
ExecStop=-/bin/bash -c 'umount -f -l /mnt/sites 2>/dev/null || true'
```
**Failed:** Even `umount -f -l` can hang on NFS during late shutdown

### Final Approach: Don't unmount in user service at all
```ini
ExecStop=/bin/true
```
**SUCCESS:** User service exits immediately, system mount unit handles unmounting at proper time

## Verification

To verify the fixes are working:

```bash
# Check system mount override is applied
systemctl cat mnt-sites.mount

# Check user service configuration
systemctl --user cat automount.service

# Test user service stop (should be instant)
time systemctl --user stop automount.service
# Should complete in <1 second

# Monitor next shutdown (from another machine via SSH if possible)
journalctl -f -u mnt-sites.mount
journalctl --user -f -u automount.service
```

## Related Files

- `/etc/fstab` - Contains the NFS mount definition
- `/run/systemd/generator/mnt-sites.mount` - Auto-generated base unit
- `/etc/systemd/system/mnt-sites.mount.d/override.conf` - System mount override (handles unmounting)
- `~/.config/systemd/user/automount.service` - User service (handles mounting only)
- `automount.service` (in this repo) - Template for user service

## Key Lessons Learned

1. **User services are the wrong place for NFS unmounting** - they run too late in shutdown
2. **Any NFS operation can hang during shutdown** - even `fuser`, `umount -f`, etc.
3. **System mount units are designed for shutdown unmounting** - use them
4. **Separation of concerns** - user service mounts, system unit unmounts
5. **`/bin/true` is your friend** - when you need a service to exit instantly

## Additional Notes

- The other NFS mount in fstab (`webdev:/var/www`) was not mounted during investigation
- If it becomes mounted regularly, apply the same pattern: system mount override, user service does nothing on stop
- User services have a default 90-second stop timeout, but service-specific timeouts take precedence
- The `user` option in fstab creates a user-owned mount, which is why the system mount unit exists
- These fixes are safe and don't affect normal mount/unmount operations

## Troubleshooting

If shutdown still hangs:

1. **Check which service is timing out:**
```bash
journalctl -b -1 --no-pager | grep -i "timeout\|timed out"
```

2. **Check what processes are using the mount:**
```bash
lsof +f -- /mnt/sites
fuser -v /mnt/sites
```

3. **Test user service stop (should be instant):**
```bash
time systemctl --user stop automount.service
# Should complete in <1 second
```

4. **Verify system mount override is loaded:**
```bash
systemctl show mnt-sites.mount | grep -E "TimeoutUSec|LazyUnmount"
# Should show: TimeoutUSec=5s, LazyUnmount=yes
```

5. **Check if mount is actually managed by systemd:**
```bash
systemctl status mnt-sites.mount
mount | grep sites
```

## Updates

**December 16-17, 2025:** The configuration required further refinement. The `DefaultDependencies=no` setting prevented the mount from being stopped during normal shutdown, causing hangs in the final systemd-shutdown phase (after journald stops logging). See [2025-12-16-shutdown-hang-fix-update.md](./2025-12-16-shutdown-hang-fix-update.md) for complete details on the updated configuration.

**December 17, 2025:** A conflicting legacy service (`unmountnfs.service`) was discovered that was also trying to manage NFS unmounting and causing permission errors during shutdown. See [2025-12-17-unmountnfs-service-conflict.md](./2025-12-17-unmountnfs-service-conflict.md) for the final resolution.

## References

- Systemd mount unit documentation: `man systemd.mount`
- Systemd service documentation: `man systemd.service`
- Systemd unit dependencies: `man systemd.unit` (see "Before=", "After=", "Conflicts=")
- Lazy unmount: `man umount` (see `-l` option)
- Drop-in overrides: `man systemd.unit` (see "Example 2" for drop-in directories)
- Systemd shutdown sequence: `man bootup` (read bottom-up for shutdown)
