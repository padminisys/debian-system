# NFS URL Format Fix for PXE Installation

## Problem
After restarting the PXE server, target machines were getting "couldn't mount installation media" error during network boot installation.

## Root Cause
The Debian installer was using an incorrect NFS URL format in the boot parameters. The original configuration used:
```
url=nfs://192.168.2.12/srv/nfs/debian
```

However, the Debian installer expects the NFS mount to be specified using different parameters:
```
method=nfs nfsroot=192.168.2.12:/srv/nfs/debian
```

## Investigation Steps Performed

1. **Verified PXE boot configuration** - Checked [`/srv/tftp/pxelinux.cfg/default`](/srv/tftp/pxelinux.cfg/default:10)
2. **Verified NFS server status** - Confirmed NFS server was running
3. **Verified NFS exports** - Confirmed `/srv/nfs/debian` was properly exported
4. **Tested NFS mount** - Successfully mounted NFS share locally
5. **Verified ISO content** - Confirmed `/srv/nfs/debian` contains full Debian ISO content
6. **Identified format issue** - Found incorrect NFS URL format in boot parameters

## Solution Applied

### 1. Fixed PXE Boot Configuration
Updated [`/srv/tftp/pxelinux.cfg/default`](/srv/tftp/pxelinux.cfg/default:10) line 10:

**Before:**
```
APPEND initrd=debian-installer/initrd.gz auto=true priority=critical preseed/url=http://192.168.2.12/preseed.cfg netcfg/choose_interface=auto netcfg/get_hostname=debian-btrfs netcfg/get_domain=localdomain url=nfs://192.168.2.12/srv/nfs/debian ---
```

**After:**
```
APPEND initrd=debian-installer/initrd.gz auto=true priority=critical preseed/url=http://192.168.2.12/preseed.cfg netcfg/choose_interface=auto netcfg/get_hostname=debian-btrfs netcfg/get_domain=localdomain method=nfs nfsroot=192.168.2.12:/srv/nfs/debian ---
```

### 2. Updated Setup Script
Modified [`scripts/setup-pxe-server.sh`](scripts/setup-pxe-server.sh:202) line 202 to use correct format for future installations.

### 3. Restarted Services
```bash
sudo chown -R dnsmasq:nogroup /srv/tftp/pxelinux.cfg/
sudo systemctl restart dnsmasq
```

## Verification Steps

Run these commands to verify the fix:

```bash
# 1. Check the boot configuration has correct NFS format
sudo cat /srv/tftp/pxelinux.cfg/default | grep "method=nfs"

# 2. Verify NFS server is running
systemctl status nfs-server

# 3. Verify NFS exports
showmount -e localhost

# 4. Verify dnsmasq is running
systemctl status dnsmasq

# 5. Test NFS mount manually
sudo mount -t nfs localhost:/srv/nfs/debian /mnt
ls /mnt
sudo umount /mnt
```

## Testing the Fix

1. **Boot target machine** - Power on the target machine (192.168.2.6)
2. **Select PXE boot** - Choose network boot from BIOS
3. **Select automated installation** - Choose "Automated Btrfs Installation" from menu
4. **Verify installation starts** - Installation should proceed without "couldn't mount installation media" error

## Technical Details

### Debian Installer NFS Parameters

The Debian installer uses these parameters for NFS-based installation:

- `method=nfs` - Specifies NFS as the installation method
- `nfsroot=<server>:<path>` - Specifies the NFS server and export path
  - Format: `IP:/absolute/path`
  - Example: `192.168.2.12:/srv/nfs/debian`

### Why the Old Format Failed

The `url=nfs://` format is not recognized by the Debian installer's initramfs. The installer specifically looks for:
1. `method=nfs` to enable NFS installation mode
2. `nfsroot=` to specify the NFS mount point

Without these parameters, the installer cannot mount the installation media from NFS.

## Related Files

- [`/srv/tftp/pxelinux.cfg/default`](/srv/tftp/pxelinux.cfg/default) - PXE boot menu configuration
- [`scripts/setup-pxe-server.sh`](scripts/setup-pxe-server.sh) - PXE server setup script
- `/etc/exports` - NFS export configuration
- `/etc/dnsmasq.conf` - DHCP/TFTP server configuration

## References

- Debian Installation Guide: Network Boot Parameters
- NFS Installation Method Documentation
- PXE Boot Configuration Guide