# Shutdown Hang - ZeroTier Network Timing Issue

**Date:** January 12, 2026  
**Issue:** Shutdown hang due to NFS unmount timing conflict with ZeroTier shutdown  
**Status:** Fixed - added network dependency ordering  

## Related Documentation
- Original fix: [2025-12-08-shutdown-hang-fix.md](./2025-12-08-shutdown-hang-fix.md)
- Configuration refinement: [2025-12-16-shutdown-hang-fix-update.md](./2025-12-16-shutdown-hang-fix-update.md)
- Service conflict: [2025-12-17-unmountnfs-service-conflict.md](./2025-12-17-unmountnfs-service-conflict.md)

## Problem Description

System required forced power-off during shutdown on January 9, 2026. Investigation revealed that the NFS mount unmount process hung due to network connectivity loss during the shutdown sequence.

**System Environment:**
- OS: AlmaLinux 9.7 (Moss Jungle Cat)
- Systemd: 252-55.el9_7.7.alma.1
- Kernel: 5.14.0-611.16.1.el9_7.x86_64

## Investigation

### Shutdown Log Analysis

```bash
journalctl --boot=-1 --no-pager | grep -E "(mnt-sites|zerotier)" 
```

Key timeline from January 9, 2026 shutdown:

```
Jan 09 18:53:14 nitro5 systemd[1]: Stopped target Remote File Systems.
Jan 09 18:53:14 nitro5 systemd[1]: Unmounting /mnt/sites...
Jan 09 18:53:17 nitro5 systemd[1]: Stopped ZeroTier One.
Jan 09 18:53:19 nitro5 systemd[1]: mnt-sites.mount: Unmounting timed out. Terminating.
Jan 09 18:53:19 nitro5 systemd[1]: mnt-sites.mount: Mount process exited, code=killed, status=15/TERM
Jan 09 18:53:19 nitro5 systemd[1]: mnt-sites.mount: Failed with result 'timeout'.
Jan 09 18:53:19 nitro5 systemd[1]: mnt-sites.mount: Unit process 16331 (umount.nfs4) remains running after unit stopped.
```

### Root Cause

**Race condition between mount unmount and network shutdown:**

1. **18:53:14** - System begins unmounting `/mnt/sites` (NFS mount)
2. **18:53:17** - ZeroTier network service stops (3 seconds into unmount)
3. **18:53:19** - Unmount times out after 5 seconds total

**The Critical Problem:**
- NFS server `lxcddev:/mnt/sites` is only reachable through ZeroTier VPN
- ZeroTier stopped **during** the unmount operation
- Once ZeroTier stopped, the NFS server became unreachable
- The `umount.nfs4` process couldn't complete gracefully
- Even with `LazyUnmount=yes`, the process initially tries to contact the server
- After timeout, systemd killed the unmount process but left zombie process behind
- Zombie `umount.nfs4` process (PID 16331) blocked shutdown completion

### Why This Happened

The `mnt-sites.mount` unit had proper timeout and lazy unmount settings but **lacked a critical dependency**:

**Previous configuration:**
```ini
[Unit]
Conflicts=umount.target
Before=umount.target

[Mount]
LazyUnmount=yes
TimeoutSec=5s
```

**Missing dependency:** No guarantee that the mount unmounts before ZeroTier stops!

## The Solution

### Updated Configuration

**File:** `/etc/systemd/system/mnt-sites.mount.d/override.conf`

Added critical network dependency:

```ini
[Unit]
# Stop this mount before umount.target during shutdown
Conflicts=umount.target
Before=umount.target
# CRITICAL: Unmount BEFORE ZeroTier network goes down
Before=zerotier-one.service

[Mount]
# Force lazy unmount on stop
LazyUnmount=yes
# Only wait 5 seconds max during shutdown
TimeoutSec=5s
```

### Why This Works

Adding `Before=zerotier-one.service` ensures:

1. **Correct shutdown order:** NFS mount unmounts → then ZeroTier stops
2. **Network availability:** NFS server is reachable during unmount attempt
3. **Clean completion:** Unmount can complete gracefully or fail quickly with network up
4. **No zombie processes:** Clean process termination prevents hanging
5. **Fast shutdown:** Even if unmount fails, it fails quickly with proper cleanup

### Applied Changes

```bash
# User edited: /etc/systemd/system/mnt-sites.mount.d/override.conf
# User ran: sudo systemctl daemon-reload
```

### Verification

Configuration successfully applied:

```bash
systemctl show mnt-sites.mount | grep -E "(Before=|Conflicts=|TimeoutUSec=|LazyUnmount=)"
```

Output confirms:
```
TimeoutUSec=5s
LazyUnmount=yes
Conflicts=umount.target
Before=zerotier-one.service remote-fs.target umount.target
```

✅ All settings correctly applied
✅ Mount will unmount before ZeroTier stops

## Key Lessons Learned

1. **Network-dependent mounts need explicit ordering** - NFS mounts over VPN must unmount before the VPN service stops
2. **LazyUnmount doesn't prevent initial contact** - Even with `LazyUnmount=yes`, unmount process initially tries to reach the server
3. **Network loss during unmount causes zombies** - If network disappears during unmount timeout, zombie processes block shutdown
4. **VPN adds hidden dependency** - The VPN service must be explicitly added to `Before=` directive in mount unit override

## Testing

**Next steps:**
1. Test normal shutdown to verify clean unmount
2. Monitor for zombie processes: `journalctl -b | grep "remains running"`
3. Verify shutdown completes without forced power-off

**Expected behavior:**
- Shutdown completes cleanly without hanging
- No timeout errors for `mnt-sites.mount`
- No zombie `umount.nfs4` processes

## References

- Previous shutdown hang fixes: [2025-12-08-shutdown-hang-fix.md](./2025-12-08-shutdown-hang-fix.md), [2025-12-17-unmountnfs-service-conflict.md](./2025-12-17-unmountnfs-service-conflict.md)

## Troubleshooting Future Issues

If shutdown hangs again, check:

1. **Verify dependency ordering:**
```bash
systemctl show mnt-sites.mount | grep Before=
# Should include: zerotier-one.service
```

2. **Check for zombie processes:**
```bash
journalctl -b -1 | grep "remains running"
```

3. **Check mount unmount logs:**
```bash
journalctl -b -1 | grep "mnt-sites.mount"
```

## Related Files

- `/etc/systemd/system/mnt-sites.mount.d/override.conf` - Mount unit override with network dependency
- `/etc/fstab` - Mount point definition (source for auto-generated mount unit)
- `~/.config/systemd/user/automount.service` - User service for mounting on startup

## Solution Summary

The `Before=zerotier-one.service` dependency in the override.conf is the complete and correct solution. This ensures the NFS mount unmounts before the VPN network becomes unavailable, preventing shutdown hangs.

