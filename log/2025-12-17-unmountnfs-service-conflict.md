# Shutdown Hang - unmountnfs.service Conflict

**Date:** December 17, 2025  
**Issue:** Shutdown hanging despite previous fixes  
**Status:** Fixed - disabled conflicting service  

## Related Documentation
- Original fix: [2025-12-08-shutdown-hang-fix.md](./2025-12-08-shutdown-hang-fix.md)
- Configuration refinement: [2025-12-16-shutdown-hang-fix-update.md](./2025-12-16-shutdown-hang-fix-update.md)

## Problem Description

Shutdown hung again, requiring hard power-off. This occurred even after:
1. Fixed `automount.service` to use `ExecStop=/bin/true` (Dec 8)
2. Fixed `mnt-sites.mount` override with proper `Conflicts=umount.target` (Dec 16-17)

## Investigation

### What the Logs Showed

```bash
journalctl -b -1 --no-pager | tail -200
```

Key findings:
1. `automount.service` (user service) stopped successfully
2. **No evidence of `mnt-sites.mount` being stopped at all**
3. Logs stopped at 19:32:44 (before journald shutdown)
4. The NFS mount was still active after reboot

### The Real Culprit

Found this in the shutdown logs:

```
Dec 17 19:32:12 nitro5 systemd[1]: Stopping Unmount all nfs...
Dec 17 19:32:12 nitro5 systemd[34901]: unmountnfs.service: Failed to locate executable /home/nitro5/Projects/_config/unmountnfs.sh: Permission denied
Dec 17 19:32:12 nitro5 systemd[34901]: unmountnfs.service: Failed at step EXEC spawning /home/nitro5/Projects/_config/unmountnfs.sh: Permission denied
Dec 17 19:32:13 nitro5 systemd[1]: unmountnfs.service: Control process exited, code=exited, status=203/EXEC
Dec 17 19:32:13 nitro5 systemd[1]: unmountnfs.service: Failed with result 'exit-code'.
Dec 17 19:32:13 nitro5 systemd[1]: Stopped Unmount all nfs.
```

## Root Cause

There were **TWO competing systems** trying to manage NFS unmounting:

### System 1: Old Custom Service (unmountnfs.service)
**Created:** May 26, 2025  
**Location:** `/etc/systemd/system/unmountnfs.service`

```ini
[Unit]
Description=Unmount all nfs
Requires=zerotier-one.service
After=network-online.target network.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/bin/true
ExecStop=/home/nitro5/Projects/_config/unmountnfs.sh
 
[Install]
WantedBy=multi-user.target
```

**Script:** `/home/nitro5/Projects/_config/unmountnfs.sh`

```bash
#!/bin/bash

ME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

DIRLISTX=(
	/mnt/sites
	/mnt/webdev
)

for DIR in "${DIRLISTX[@]}"; do
	if [[ $(findmnt -M $DIR) ]]; then
		echo "$ME: umount -f $DIR"
		umount -f $DIR
	fi
done
```

**Problems:**
- Failing with "Permission denied" error during shutdown
- Using `umount -f` which can hang on unreachable NFS servers
- Redundant with the newer automount-ddev system
- Blocking/delaying shutdown when it fails

### System 2: automount-ddev Project
**Created:** November 24, 2025 (first commit)  
**Components:**
- `automount.service` (user service) - handles mounting
- `mnt-sites.mount` (system mount unit) - handles unmounting
- Proper timeout configuration
- Lazy unmount with safety mechanisms

**This is the correct, modern approach.**

## Why Both Systems Existed

**Timeline:**
1. **May 2025** - Created custom `unmountnfs.service` as initial solution
2. **November 2025** - Developed proper `automount-ddev` project to replace it
3. **December 2025** - Refined automount-ddev through multiple iterations
4. **Problem:** Forgot to disable the old `unmountnfs.service`

Result: Both systems were trying to unmount during shutdown, causing conflicts and failures.

## The Fix

Disabled the old, conflicting service:

```bash
sudo systemctl disable unmountnfs.service
sudo systemctl stop unmountnfs.service
```

This leaves only the automount-ddev system active, which is:
- More robust
- Properly designed for systemd
- Has appropriate timeouts and lazy unmount
- Separates concerns (user service for mounting, system unit for unmounting)

## Verification

After disabling `unmountnfs.service`:

```bash
# Verify it's disabled
systemctl status unmountnfs.service

# Should show:
#   Loaded: loaded (/etc/systemd/system/unmountnfs.service; disabled; ...)
#   Active: inactive (dead)

# Test shutdown
shutdown -h now
```

**Result:** Shutdown completed cleanly without requiring hard power-off.

## Complete Solution Summary

The complete fix for shutdown hangs requires:

### 1. User Service (automount.service)
**File:** `~/.config/systemd/user/automount.service`
- `ExecStop=/bin/true` - Does nothing on stop, exits immediately
- Handles mounting on startup
- No NFS operations during shutdown

### 2. System Mount Unit (mnt-sites.mount)
**File:** `/etc/systemd/system/mnt-sites.mount.d/override.conf`
```ini
[Unit]
Conflicts=umount.target
Before=umount.target

[Mount]
LazyUnmount=yes
TimeoutSec=5s
```
- Handles unmounting during proper shutdown phase
- Has timeout and lazy unmount protection

### 3. No Conflicting Services
**Disabled:** `unmountnfs.service`
- Prevents conflicts with modern systemd mount units
- Eliminates permission issues and script failures
- Removes redundant unmount attempts

## Key Lessons Learned

1. **Always disable old solutions when implementing new ones** - Legacy services can interfere with new systems
2. **Check for competing services** - Multiple services managing the same resources causes conflicts
3. **Monitor for permission errors** - "Permission denied" during shutdown indicates configuration problems
4. **Custom scripts are less reliable than systemd mount units** - Systemd's built-in mount management is more robust
5. **umount.target wasn't reached** - The old service was failing BEFORE the proper unmount phase

## Related Files

- `/etc/systemd/system/unmountnfs.service` - Old conflicting service (now disabled)
- `/home/nitro5/Projects/_config/unmountnfs.sh` - Old unmount script (no longer used)
- `/etc/systemd/system/mnt-sites.mount.d/override.conf` - Current working configuration
- `~/.config/systemd/user/automount.service` - User service for mounting

## Future Maintenance

If adding or modifying mount points:

1. **Use the automount-ddev system** - Run `install.sh` to deploy changes
2. **Check for old services** - `systemctl list-units --all | grep -i mount`
3. **Verify no conflicts** - Ensure only one system manages each mount point
4. **Test shutdown** - Always verify shutdown completes cleanly

## Troubleshooting

If shutdown hangs again:

1. **Check for competing services:**
```bash
systemctl list-units --type=service --all | grep -i "mount\|nfs"
journalctl -b -1 | grep -i "permission denied\|failed"
```

2. **Verify service states:**
```bash
systemctl status unmountnfs.service  # Should be disabled
systemctl status automount.service   # User service
systemctl status mnt-sites.mount     # System mount
```

3. **Check shutdown logs for failures:**
```bash
journalctl -b -1 | grep -i "failed\|permission\|error" | tail -50
```

## References

- Systemd service conflicts: `man systemd.unit` (see "Conflicts=")
- Permission errors in services: Usually indicates script execution issues or SELinux denials
- Managing systemd services: `man systemctl`
- Debugging shutdown: `journalctl -b -1` to view previous boot logs


