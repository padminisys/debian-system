# PXE Installation Media Fix

## Problem

During PXE installation, the Debian installer displayed:
```
[!!!] Detect and mount installation media
Your installation media couldn't be mounted.
```

## Root Cause Analysis

The issue occurred because:

1. **PXE boot worked correctly** ✅
   - TFTP server delivered boot files
   - Kernel and initrd loaded successfully
   - Installer started

2. **Installation media was not accessible** ❌
   - NFS server was running and exporting `/srv/nfs/debian`
   - ISO content was properly extracted to NFS directory
   - BUT: Installer didn't know HOW to mount the NFS share

3. **Missing NFS mount instruction**
   - The kernel boot parameters didn't include the NFS mount URL
   - Preseed configuration expected `/media/cdrom` but it wasn't mounted
   - Installer had no way to access the installation files

## Solution

### What Was Fixed

Added NFS mount URL to the kernel boot parameters in the PXE menu configuration:

**Before:**
```
APPEND initrd=debian-installer/initrd.gz auto=true priority=critical preseed/url=http://192.168.2.12/preseed.cfg netcfg/choose_interface=auto ---
```

**After:**
```
APPEND initrd=debian-installer/initrd.gz auto=true priority=critical preseed/url=http://192.168.2.12/preseed.cfg netcfg/choose_interface=auto netcfg/get_hostname=debian-btrfs netcfg/get_domain=localdomain url=nfs://192.168.2.12/srv/nfs/debian ---
```

### Key Changes

1. **Added `url=nfs://SERVER_IP/srv/nfs/debian`**
   - Tells the installer where to find installation media
   - Mounts NFS share automatically during boot
   - Makes ISO content available at `/media/cdrom`

2. **Simplified preseed HTTP setup**
   - Removed complex mirror modifications
   - Kept original `deb.debian.org` configuration
   - NFS handles base system, HTTP handles packages

3. **Updated documentation**
   - Added installation method details
   - Included NFS testing commands
   - Clarified two-stage installation process

## Installation Flow

### Stage 1: Base System (NFS)
```
Client → TFTP (boot files) → Kernel loads → NFS mounts → Base system installs
```

### Stage 2: Packages (HTTP)
```
Base system → APT configured → deb.debian.org → Additional packages install
```

## Verification

### Check NFS Server
```bash
# Verify NFS is running
systemctl status nfs-server

# Check exports
showmount -e localhost
# Should show: /srv/nfs/debian *

# Verify ISO content
ls -la /srv/nfs/debian/
# Should show: dists/, pool/, install.amd/, etc.
```

### Check PXE Configuration
```bash
# View PXE menu
cat /srv/tftp/pxelinux.cfg/default | grep "url=nfs"
# Should show: url=nfs://192.168.2.12/srv/nfs/debian

# Test preseed accessibility
curl http://192.168.2.12/preseed.cfg | grep mirror
# Should show: d-i mirror/http/hostname string deb.debian.org
```

### Test NFS Mount (from another machine)
```bash
# Install NFS client
sudo apt install nfs-common

# Test mount
sudo mkdir -p /mnt/test
sudo mount -t nfs 192.168.2.12:/srv/nfs/debian /mnt/test
ls /mnt/test
# Should show ISO content

# Unmount
sudo umount /mnt/test
```

## Files Modified

1. [`scripts/setup-pxe-server.sh`](../scripts/setup-pxe-server.sh)
   - Line 202: Added NFS URL to kernel boot parameters
   - Lines 225-235: Simplified HTTP preseed setup
   - Lines 378-410: Updated summary with installation method details

## Technical Details

### Why NFS for Base System?

**Advantages:**
- Fast local network transfer
- No internet dependency for base system
- Consistent installation source
- Reduced bandwidth usage

**How it works:**
1. Kernel boot parameter `url=nfs://...` triggers NFS mount
2. Debian installer mounts NFS share to `/media/cdrom`
3. Base system packages installed from local NFS
4. After base system, APT uses HTTP mirror for additional packages

### Why HTTP for Packages?

**Advantages:**
- Always up-to-date packages
- Security updates available immediately
- No need to maintain local package mirror
- Smaller NFS export (only DVD-1 needed)

## Troubleshooting

### Issue: "Couldn't mount installation media"

**Check:**
```bash
# 1. NFS server running?
systemctl status nfs-server

# 2. Exports configured?
cat /etc/exports
# Should show: /srv/nfs/debian *(ro,sync,no_subtree_check,no_root_squash)

# 3. ISO content present?
ls /srv/nfs/debian/dists/

# 4. PXE menu has NFS URL?
grep "url=nfs" /srv/tftp/pxelinux.cfg/default
```

**Fix:**
```bash
# Restart NFS server
sudo systemctl restart nfs-server

# Re-export NFS shares
sudo exportfs -ra

# Verify
showmount -e localhost
```

### Issue: Packages fail to download

**Check:**
```bash
# 1. Internet connectivity on target machine
# 2. Preseed mirror configuration
curl http://192.168.2.12/preseed.cfg | grep mirror

# Should show:
# d-i mirror/http/hostname string deb.debian.org
# d-i mirror/http/directory string /debian
```

### Issue: NFS mount timeout

**Possible causes:**
- Firewall blocking NFS ports
- Network connectivity issues
- NFS server not responding

**Fix:**
```bash
# Check firewall
sudo ufw status
# Should allow: 2049/tcp (NFS), 111/tcp (RPC)

# Add rules if needed
sudo ufw allow 2049/tcp
sudo ufw allow 111/tcp
sudo systemctl restart nfs-server
```

## Testing the Fix

### Quick Test
```bash
# 1. Verify all services
systemctl status dnsmasq apache2 nfs-server

# 2. Check NFS export
showmount -e localhost

# 3. Verify PXE menu
cat /srv/tftp/pxelinux.cfg/default | grep url=nfs

# 4. Test preseed
curl http://192.168.2.12/preseed.cfg | head -30
```

### Full Installation Test
1. Boot target machine via PXE
2. Select "Automated Btrfs Installation"
3. Watch for NFS mount messages in installer
4. Installation should proceed without "couldn't mount" error
5. Verify installation completes successfully

## Related Documentation

- [PXE Server Setup](../scripts/setup-pxe-server.sh)
- [Preseed Configuration](../preseed/pxe/btrfs-automated.cfg)
- [TFTP Permissions Fix](./tftp-permissions-fix.md)
- [Architecture Overview](./architecture.md)

## Summary

The fix adds the NFS mount URL (`url=nfs://SERVER_IP/srv/nfs/debian`) to the kernel boot parameters, allowing the Debian installer to automatically mount the installation media from the NFS server. This provides a fast, reliable local installation source while still using internet mirrors for package updates.

**Result:** PXE installation now works end-to-end without manual intervention.