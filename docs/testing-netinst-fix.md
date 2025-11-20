# Testing the Netinst Fix

## Overview

This document provides step-by-step instructions to test the netinst ISO fix for the "couldn't mount installation media" error.

## Pre-Test Verification

Before running the PXE server setup, verify the configuration:

### 1. Check ISO Files

```bash
ls -lh iso/
```

**Expected output:**
```
debian-12.12.0-amd64-netinst.iso  (~400MB)
debian-12.12.0-amd64-DVD-1.iso    (~4.7GB, optional)
```

### 2. Verify Script Configuration

```bash
grep "SOURCE_ISO" scripts/setup-pxe-server.sh
```

**Expected output:**
```bash
SOURCE_ISO="$ISO_DIR/debian-12.12.0-amd64-netinst.iso"
```

### 3. Check for NFS References (Should be REMOVED)

```bash
grep -i "nfs" scripts/setup-pxe-server.sh | grep -v "^#" | head -5
```

**Expected:** No active NFS configuration (only comments if any)

---

## Running the Setup

### Step 1: Clean Previous Installation (if exists)

```bash
# Stop old services
sudo systemctl stop dnsmasq apache2 nfs-server 2>/dev/null || true

# Remove old NFS exports
sudo rm -f /etc/exports
sudo exportfs -ra

# Clean old TFTP/HTTP directories
sudo rm -rf /srv/tftp/* /srv/http/* /srv/nfs/*
```

### Step 2: Run PXE Server Setup

```bash
sudo ./scripts/setup-pxe-server.sh
```

**What to watch for:**
- ✅ Detects network interface correctly
- ✅ Installs dependencies (no nfs-kernel-server)
- ✅ Extracts netboot files from netinst ISO
- ✅ Creates PXE menu without NFS parameters
- ✅ Starts dnsmasq and apache2 (NOT nfs-server)

**Expected summary output:**
```
╔══════════════════════════════════════════════════════════════╗
║          PXE Server Setup Complete                          ║
╚══════════════════════════════════════════════════════════════╝

Server Configuration:
  Interface:    wlp2s0 (or your interface)
  Server IP:    192.168.2.12 (or your IP)
  Mode:         Proxy DHCP (Router provides IPs)
  ISO:          debian-12.12.0-amd64-netinst.iso

Services Running:
  TFTP:         /srv/tftp (boot files)
  HTTP:         http://192.168.2.12/preseed.cfg

Installation Method:
  Type:         Network Installation (netinst)
  Mirror:       deb.debian.org (HTTP)
  Packages:     Downloaded from internet during installation
```

---

## Post-Setup Verification

### 1. Check Services

```bash
systemctl status dnsmasq apache2
```

**Expected:** Both services active (running)

**NFS should NOT be running:**
```bash
systemctl status nfs-server
# Expected: inactive (dead) or "Unit nfs-server.service could not be found"
```

### 2. Verify TFTP Files

```bash
ls -lh /srv/tftp/debian-installer/
```

**Expected output:**
```
-rw-r--r-- 1 dnsmasq nogroup 6.2M vmlinuz
-rw-r--r-- 1 dnsmasq nogroup  28M initrd.gz
```

### 3. Check PXE Boot Menu

```bash
cat /srv/tftp/pxelinux.cfg/default
```

**Verify:**
- ✅ Menu title shows "Debian 12.12 Btrfs PXE Boot"
- ✅ APPEND line does NOT contain `method=nfs` or `nfsroot=`
- ✅ APPEND line contains `preseed/url=http://...`

**Correct APPEND line:**
```
APPEND initrd=debian-installer/initrd.gz auto=true priority=critical preseed/url=http://192.168.2.12/preseed.cfg netcfg/choose_interface=auto netcfg/get_hostname=debian-btrfs netcfg/get_domain=localdomain ---
```

### 4. Test Preseed Accessibility

```bash
curl -s http://localhost/preseed.cfg | head -20
```

**Expected:** Should show preseed configuration starting with:
```
#### Debian 12.12 Preseed - Automated Btrfs + Snapper Installation ####
#### PXE Network Boot Version ####
```

### 5. Test TFTP Access

```bash
# Install tftp client if needed
sudo apt install tftp-hpa

# Test TFTP download
tftp localhost -c get pxelinux.0 /tmp/test-pxelinux.0
ls -lh /tmp/test-pxelinux.0
rm /tmp/test-pxelinux.0
```

**Expected:** File downloads successfully (~26KB)

---

## Client Machine Testing

### Preparation

1. **Ensure client machine:**
   - Is on same network as PXE server
   - Has internet connectivity (can reach deb.debian.org)
   - Has PXE/Network boot enabled in BIOS

2. **Network requirements:**
   - DHCP server running (router or PXE server)
   - No firewall blocking ports 67, 69, 80
   - Internet access for package downloads

### Boot Process

1. **Power on client machine**
2. **Enter BIOS/Boot menu** (usually F12, F2, or Del)
3. **Select Network Boot / PXE Boot**
4. **Watch for:**
   ```
   PXE-E51: No DHCP or proxyDHCP offers were received
   ```
   If you see this, check network connectivity

5. **Expected boot sequence:**
   ```
   Searching for server (DHCP)...
   CLIENT IP: 192.168.2.x
   SERVER IP: 192.168.2.12
   TFTP: pxelinux.0
   Loading kernel...
   Loading initrd...
   ```

### Installation Phase

**What to watch for:**

1. **PXE Menu appears:**
   ```
   Debian 12.12 Btrfs PXE Boot
   
   1. Automated Btrfs Installation (Network)
   2. Manual Installation
   3. Rescue Mode
   4. Boot from Local Disk
   ```

2. **Select option 1** (or wait for auto-selection)

3. **Installer starts:**
   - Network configuration
   - Downloading preseed
   - Configuring network

4. **Critical check - NO "couldn't mount installation media" error**
   - If you see this error, the fix didn't work
   - Check logs in next section

5. **Package download phase:**
   ```
   Retrieving file 1 of 150...
   Downloading packages from deb.debian.org...
   ```
   This confirms netinst is working correctly

6. **Installation continues:**
   - Partitioning disk
   - Installing base system
   - Installing packages
   - Configuring system
   - Installing GRUB

7. **Completion:**
   ```
   Installation complete
   Rebooting...
   ```

### Expected Timeline

- **Network configuration:** 1-2 minutes
- **Base system installation:** 3-5 minutes
- **Package downloads:** 5-10 minutes (depends on internet speed)
- **System configuration:** 1-2 minutes
- **Total:** 10-15 minutes

---

## Troubleshooting During Test

### Issue: "Couldn't mount installation media"

**This means the fix didn't work. Check:**

```bash
# 1. Verify netinst ISO is being used
grep SOURCE_ISO scripts/setup-pxe-server.sh

# 2. Check boot parameters
cat /srv/tftp/pxelinux.cfg/default | grep APPEND

# 3. Verify no NFS parameters
cat /srv/tftp/pxelinux.cfg/default | grep -i nfs
# Should return nothing
```

### Issue: "No DHCP offers received"

**Network connectivity problem:**

```bash
# Check dnsmasq is running
systemctl status dnsmasq

# Check dnsmasq logs
sudo journalctl -u dnsmasq -f

# Verify network interface
ip addr show
```

### Issue: "Package download failed"

**Internet connectivity problem:**

```bash
# Test from PXE server
curl -I http://deb.debian.org/debian/

# Check client can reach internet
# (requires console access to installer)
```

### Issue: Installation hangs

**Check installer logs on client machine:**

1. Press `Alt+F2` to switch to shell
2. View logs:
   ```bash
   tail -f /var/log/syslog
   ```
3. Look for errors related to:
   - Network configuration
   - Package downloads
   - Disk partitioning

---

## Success Criteria

✅ **PXE server setup completes without errors**
✅ **No NFS service running**
✅ **Boot menu shows netinst configuration**
✅ **Client boots from network successfully**
✅ **NO "couldn't mount installation media" error**
✅ **Packages download from deb.debian.org**
✅ **Installation completes successfully**
✅ **System boots into installed Debian**

---

## Post-Installation Verification

After successful installation, login and verify:

```bash
# 1. Check system info
system-info

# 2. Verify Btrfs subvolumes
sudo btrfs subvolume list /

# 3. Check snapshots
sudo snapper -c root list

# 4. Verify GRUB-Btrfs
sudo update-grub | grep snapshot

# 5. Test snapshot creation
snapshot-create "Post-installation test"
snapshot-list
```

---

## Comparison: Before vs After

### Before (Broken - DVD ISO)

```
❌ Used debian-12.12.0-amd64-DVD-1.iso
❌ NFS server configured
❌ Boot parameters: method=nfs nfsroot=...
❌ Error: "Couldn't mount installation media"
❌ Installation failed
```

### After (Fixed - Netinst ISO)

```
✅ Uses debian-12.12.0-amd64-netinst.iso
✅ No NFS server needed
✅ Boot parameters: preseed/url=http://...
✅ No mounting errors
✅ Packages download from deb.debian.org
✅ Installation succeeds
```

---

## Next Steps After Successful Test

1. **Document your network configuration**
2. **Change default passwords**
3. **Configure firewall rules**
4. **Setup monitoring**
5. **Test snapshot/rollback functionality**
6. **Deploy to production machines**

---

## Rollback Plan (If Test Fails)

If the fix doesn't work:

1. **Capture logs:**
   ```bash
   sudo journalctl -u dnsmasq > dnsmasq.log
   sudo journalctl -u apache2 > apache2.log
   cat /srv/tftp/pxelinux.cfg/default > pxe-config.txt
   ```

2. **Check configuration:**
   ```bash
   grep -r "nfs" /srv/tftp/
   grep -r "DVD" scripts/
   ```

3. **Report issue with:**
   - PXE server IP and interface
   - Client machine details
   - Error messages
   - Log files

---

## Summary

This test validates that:
- Netinst ISO is correctly configured
- NFS is completely removed
- HTTP mirror approach works
- PXE installation succeeds end-to-end

**Expected result:** Clean, automated Debian installation in 10-15 minutes without any "couldn't mount installation media" errors.