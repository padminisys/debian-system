# PXE Server Reset and Rebuild Guide

## 🚨 URGENT FIX FOR "couldn't mount installation media" ERROR

This guide provides a complete solution to reset and rebuild your PXE server with the **CD-ROM detection fix** properly applied.

---

## 📋 Problem Summary

**Error:** `couldn't mount installation media`

**Root Cause:** Debian installer defaults to CD-ROM detection even with netinst ISO, causing installation to fail before network configuration.

**Solution:** Add `hw-detect/load_media=false` to PXE boot parameters and verify it's actually applied.

---

## 🔧 Complete Workflow

### Step 1: Reset PXE Server (Clean Slate)

This completely removes all existing PXE configurations and provides a fresh start.

```bash
sudo ./scripts/reset-pxe-server.sh
```

**What it does:**
- ✓ Stops ALL services (dnsmasq, apache2, nfs-server)
- ✓ Kills any stuck processes
- ✓ Removes ALL old configurations
- ✓ Clears `/srv/tftp`, `/srv/http`, `/srv/nfs` completely
- ✓ Resets dnsmasq.conf to default
- ✓ Clears old logs
- ✓ Verifies clean state

**Output:** You'll see clear SUCCESS/FAIL for each step.

**Log file:** `/var/log/pxe-reset.log`

---

### Step 2: Setup PXE Server (With Validation)

This rebuilds the PXE server with the CD-ROM detection fix and validates every step.

```bash
sudo ./scripts/setup-pxe-server.sh
```

**What it does:**
- ✓ Detects network interface and server IP
- ✓ Installs required packages
- ✓ Sets up TFTP structure with validation
- ✓ Extracts netboot files from ISO with verification
- ✓ **Configures PXE menu with `hw-detect/load_media=false`**
- ✓ Sets up HTTP server for preseed
- ✓ Configures dnsmasq (Proxy DHCP mode)
- ✓ Starts services with health checks
- ✓ Verifies CD-ROM fix is applied
- ✓ Tests preseed accessibility

**Critical Feature:** The script now **VERIFIES** that `hw-detect/load_media=false` is in the boot configuration and will **FAIL** if it's not.

**Output:** You'll see detailed validation at every step, including:
- File existence checks
- Service status verification
- CD-ROM fix confirmation
- Exact boot parameters that will be used

**Log file:** `/var/log/pxe-setup.log`

---

### Step 3: Verify Configuration (GO/NO-GO Decision)

This provides a comprehensive verification and clear GO/NO-GO decision.

```bash
sudo ./scripts/verify-pxe-config.sh
```

**What it checks:**
- ✓ Service status (dnsmasq, apache2)
- ✓ TFTP files existence
- ✓ **CD-ROM detection fix presence (CRITICAL)**
- ✓ Preseed configuration
- ✓ Preseed HTTP accessibility
- ✓ Network configuration
- ✓ File permissions
- ✓ Shows EXACT boot parameters

**Output:**
```
╔══════════════════════════════════════════════════════════════╗
║  ✓ GO - PXE Server is Ready for Client Boot                 ║
╚══════════════════════════════════════════════════════════════╝
```

or

```
╔══════════════════════════════════════════════════════════════╗
║  ✗ NO-GO - Issues Found, Do Not Attempt PXE Boot            ║
╚══════════════════════════════════════════════════════════════╝
```

**Log file:** `/var/log/pxe-verify.log`

---

## 🎯 Quick Start (Complete Reset)

If you've been struggling with the CD-ROM error, follow these steps:

```bash
# 1. Complete reset
sudo ./scripts/reset-pxe-server.sh

# 2. Fresh setup with validation
sudo ./scripts/setup-pxe-server.sh

# 3. Verify everything is correct
sudo ./scripts/verify-pxe-config.sh

# 4. If verification passes, boot your client via PXE
```

---

## ✅ What to Look For

### In setup-pxe-server.sh output:

```
[STEP] Configuring PXE boot menu with CD-ROM detection fix...
[✓] PXE menu configured with CD-ROM detection fix
[✓] hw-detect/load_media=false added to boot parameters
```

### In verify-pxe-config.sh output:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CD-ROM DETECTION FIX VERIFICATION (CRITICAL)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[✓] hw-detect/load_media=false found in PXE config
```

### Exact boot parameters shown:

```
APPEND initrd=debian-installer/initrd.gz auto=true priority=critical
       preseed/url=http://192.168.1.100/preseed.cfg
       hw-detect/load_media=false  ← THIS IS CRITICAL
       netcfg/choose_interface=auto
       netcfg/get_hostname=debian-btrfs netcfg/get_domain=localdomain ---
```

---

## 🔍 Troubleshooting

### If reset fails:

```bash
# Manually stop services
sudo systemctl stop dnsmasq apache2 nfs-server

# Kill processes
sudo pkill -9 dnsmasq
sudo pkill -9 apache2

# Remove directories
sudo rm -rf /srv/tftp /srv/http /srv/nfs

# Try reset again
sudo ./scripts/reset-pxe-server.sh
```

### If setup fails:

Check the log file for specific errors:
```bash
sudo tail -50 /var/log/pxe-setup.log
```

Common issues:
- **ISO not found:** Ensure `debian-12.12.0-amd64-netinst.iso` is in `iso/` directory
- **Network interface:** Script will prompt you to confirm the detected interface
- **Package installation:** May need internet connection

### If verification fails:

The script will tell you exactly what's wrong. Common issues:

1. **Services not running:**
   ```bash
   sudo systemctl status dnsmasq apache2
   sudo journalctl -xeu dnsmasq
   ```

2. **CD-ROM fix not applied:**
   - Run reset and setup again
   - The setup script now GUARANTEES this fix is applied

3. **Preseed not accessible:**
   - Check Apache: `sudo systemctl status apache2`
   - Test manually: `curl http://localhost/preseed.cfg`

---

## 📊 Log Files

All scripts create detailed logs:

- **Reset:** `/var/log/pxe-reset.log`
- **Setup:** `/var/log/pxe-setup.log`
- **Verify:** `/var/log/pxe-verify.log`

View logs:
```bash
sudo tail -f /var/log/pxe-setup.log
sudo less /var/log/pxe-verify.log
```

---

## 🎓 Understanding the Fix

### Why `hw-detect/load_media=false`?

The Debian installer has a hardware detection phase that runs **BEFORE** network configuration. During this phase, it tries to detect and mount installation media (CD-ROM/DVD). 

With netinst ISO over PXE:
- ❌ **Without fix:** Installer tries to mount CD-ROM → fails → shows "couldn't mount installation media"
- ✅ **With fix:** Installer skips CD-ROM detection → proceeds to network configuration → downloads packages via HTTP

### Where is it applied?

1. **PXE boot parameters** (primary fix):
   - File: `/srv/tftp/pxelinux.cfg/default`
   - Line: `APPEND ... hw-detect/load_media=false ...`

2. **Preseed configuration** (reinforcement):
   - File: `/srv/http/preseed.cfg`
   - Lines: CD-ROM skip directives

---

## 🚀 After Successful Verification

Once you get the **GO** message:

1. **Boot client machine:**
   - Enable PXE/Network boot in BIOS
   - Connect to same network as PXE server
   - Ensure client has internet access
   - Boot from network

2. **Select installation:**
   - Choose: "Automated Btrfs Installation (Network)"
   - Installation will proceed automatically

3. **Monitor installation:**
   - Should proceed past hardware detection
   - Network configuration should succeed
   - Packages will download from deb.debian.org
   - Installation completes in 10-15 minutes

---

## 📞 Still Having Issues?

If you still see "couldn't mount installation media" after following this guide:

1. **Verify the fix is actually there:**
   ```bash
   sudo grep "hw-detect/load_media=false" /srv/tftp/pxelinux.cfg/default
   ```
   Should return a line with the parameter.

2. **Check client is getting correct boot parameters:**
   - Watch PXE boot screen on client
   - Should see the boot parameters displayed

3. **Review all logs:**
   ```bash
   sudo cat /var/log/pxe-verify.log
   ```

4. **Try manual verification:**
   ```bash
   # Check services
   sudo systemctl status dnsmasq apache2
   
   # Check preseed
   curl http://localhost/preseed.cfg
   
   # Check PXE config
   cat /srv/tftp/pxelinux.cfg/default
   ```

---

## 📝 Summary

This complete solution provides:

✅ **Complete reset** - Clean slate, no leftover configurations  
✅ **Validated setup** - Every step verified, CD-ROM fix guaranteed  
✅ **Clear verification** - GO/NO-GO decision before attempting boot  
✅ **Detailed logging** - Easy troubleshooting if issues arise  
✅ **User-friendly** - Clear output, no guessing  

**The CD-ROM detection fix is now GUARANTEED to be applied and verified.**