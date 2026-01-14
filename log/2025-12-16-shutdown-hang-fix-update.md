# Shutdown Hang Issue - Update and Refinement

**Date:** December 16-17, 2025  
**Issue:** Shutdown hanging again despite December 8 fixes  
**Status:** Fixed with refined configuration

**Note:** A subsequent issue was discovered on Dec 17 - see [2025-12-17-unmountnfs-service-conflict.md](./2025-12-17-unmountnfs-service-conflict.md) for the final resolution.

## Related Documentation
- Original fix: [2025-12-08-shutdown-hang-fix.md](./2025-12-08-shutdown-hang-fix.md)
- Final resolution: [2025-12-17-unmountnfs-service-conflict.md](./2025-12-17-unmountnfs-service-conflict.md)

## Problem Recurrence

Shutdown hung again on December 16, requiring hard power-off. Investigation revealed the issue was with the `mnt-sites.mount` override configuration.

## Root Cause

The original fix used `DefaultDependencies=no`, which had an unintended consequence:
- The mount unit was **never being stopped during normal shutdown sequence**
- It was only unmounted in the final `systemd-shutdown` phase (after journald stops logging)
- At that late stage, any hang is invisible in logs and requires hard reset
- Journal logs showed: "Reached target Unmount All Filesystems" but `mnt-sites.mount` was never explicitly stopped

## Investigation

### Evidence from Logs
```bash
journalctl -b -1 --no-pager | tail -100
```

The logs showed:
- Shutdown proceeded normally through all stages
- User services stopped successfully (automount.service with `/bin/true` worked fine)
- System reached "Unmount All Filesystems" target
- journald stopped at 19:37:45
- **No evidence of mnt-sites.mount being stopped/unmounted**
- System hung after journald stopped (in the "black hole" phase)

### The Problem with DefaultDependencies=no

When `DefaultDependencies=no` is set:
- The unit opts out of standard systemd dependency chains
- This means it doesn't automatically get stopped during `umount.target`
- The mount persists until the final `systemd-shutdown` phase
- At that point, if NFS server is unreachable, even lazy unmount can hang
- Since journald is already stopped, there's no logging of the hang

## The Fix - Updated override.conf

**File:** `/etc/systemd/system/mnt-sites.mount.d/override.conf`

### OLD Configuration (INCOMPLETE)
```ini
[Unit]
# Don't wait for this during shutdown
DefaultDependencies=no

[Mount]
# Force lazy unmount on stop
LazyUnmount=yes
# Only wait 5 seconds max during shutdown
TimeoutSec=5
```

**Problem:** Never gets stopped during normal shutdown sequence.

### NEW Configuration (COMPLETE FIX)
```ini
[Unit]
# Stop this mount before umount.target during shutdown
Conflicts=umount.target
Before=umount.target

[Mount]
# Force lazy unmount on stop
LazyUnmount=yes
# Only wait 5 seconds max during shutdown
TimeoutSec=5s
```

**Solution:** Explicitly tied to umount.target for proper shutdown ordering.

## What Changed and Why

### Removed:
- `DefaultDependencies=no` - This prevented the mount from being stopped during normal shutdown

### Added:
- `Conflicts=umount.target` - Forces the mount to stop when shutdown reaches umount.target
- `Before=umount.target` - Ensures unmount happens early in shutdown (while logging still works)

### Kept:
- `LazyUnmount=yes` - Still needed for immediate detach if NFS server unreachable
- `TimeoutSec=5s` - Still needed as safety timeout

## Why This Is Better

1. **Mount stops during logged phase** - We can see what happens in journal logs
2. **Proper shutdown ordering** - umount.target is the correct place for filesystem unmounts
3. **Won't reach "black hole" phase** - Happens before systemd-shutdown takes over
4. **Still has safety mechanisms** - Lazy unmount + timeout prevents indefinite hangs

## Deployment Instructions

1. Edit the system mount override (requires sudo):
```bash
sudo nano /etc/systemd/system/mnt-sites.mount.d/override.conf
```

2. Replace content with the NEW configuration above

3. Reload systemd:
```bash
sudo systemctl daemon-reload
```

4. Verify configuration is loaded:
```bash
systemctl cat mnt-sites.mount
```

Expected output should include:
```
# /etc/systemd/system/mnt-sites.mount.d/override.conf
[Unit]
# Stop this mount before umount.target during shutdown
Conflicts=umount.target
Before=umount.target

[Mount]
# Force lazy unmount on stop
LazyUnmount=yes
# Only wait 5 seconds max during shutdown
TimeoutSec=5s
```

## Verification After Fix

To verify the fix works:

```bash
# Monitor during next shutdown (from another machine via SSH if possible)
journalctl -f -u mnt-sites.mount

# After reboot, check previous shutdown logs
journalctl -b -1 | grep "mnt-sites"
```

You should now see explicit log entries for `mnt-sites.mount` being stopped during shutdown.

## Complete Solution Summary

The complete fix for shutdown hangs involves TWO components:

### 1. User Service (automount.service)
- Uses `ExecStop=/bin/true` (does nothing on stop)
- Stops quickly, doesn't attempt any NFS operations
- File: `~/.config/systemd/user/automount.service`

### 2. System Mount Unit (mnt-sites.mount)
- Uses `Conflicts=umount.target` + `Before=umount.target`
- Stops during proper shutdown phase (while logging works)
- Has lazy unmount + timeout as safety
- File: `/etc/systemd/system/mnt-sites.mount.d/override.conf`

This separation of concerns ensures:
- User service exits immediately
- System mount unit handles unmounting at the right time
- Both have safety mechanisms to prevent hangs
- All activity is logged for troubleshooting

## References

- Systemd mount unit documentation: `man systemd.mount`
- Systemd unit dependencies: `man systemd.unit` (see "Conflicts=", "Before=")
- Systemd special targets: `man systemd.special` (see "umount.target")
- Systemd shutdown sequence: `man bootup` (read bottom-up for shutdown)
- LazyUnmount documentation: `man systemd.mount` (see "LazyUnmount=")

## Key Lessons Learned

1. `DefaultDependencies=no` is powerful but can prevent units from participating in shutdown
2. Always verify units are actually stopping during shutdown (check logs)
3. The phase after journald stops is a "black hole" for debugging
4. Explicit ordering with `Conflicts=` and `Before=` is better than disabling dependencies
5. umount.target is the proper place for filesystem unmounts during shutdown

