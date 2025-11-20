# Immediate Fix for CD-ROM Detection Error

## Problem
After running `setup-pxe-server.sh`, the CD-ROM detection error returned because the script extracted files from the netinst ISO, which contains CD-ROM detection code.

## Quick Fix (For Current Setup)

Run the switch-to-netboot script to replace netinst files with pure netboot files:

```bash
sudo ./scripts/switch-to-netboot.sh
```

This will:
1. Download official Debian netboot.tar.gz (~40MB initrd)
2. Replace the netinst initrd (~22MB) with netboot initrd
3. Backup your current files
4. Restart dnsmasq service

Then restart dnsmasq:
```bash
sudo systemctl restart dnsmasq
```

## Permanent Fix (Already Applied)

The `setup-pxe-server.sh` script has been **updated** to automatically download and use official Debian netboot files instead of extracting from the netinst ISO.

### What Changed

**Before:**
- Extracted kernel/initrd from netinst ISO
- netinst initrd contains CD-ROM detection code
- Required manual switch-to-netboot.sh after setup

**After:**
- Downloads official netboot.tar.gz directly
- Pure network boot files (NO CD-ROM code)
- No manual intervention needed

### For Fresh Setup

If you run `setup-pxe-server.sh` now, it will:
1. Download netboot.tar.gz from deb.debian.org
2. Extract pure network boot files
3. Install them directly to TFTP root
4. No CD-ROM detection issues

## Verification

After running either fix, verify:

```bash
# Check initrd size (should be ~40MB for netboot)
ls -lh /srv/tftp/debian-installer/initrd.gz

# Test PXE boot
# Should see NO CD-ROM errors
```

## Why This Happened

1. **netinst ISO** = Designed for CD-ROM boot + network fallback
   - Contains CD-ROM detection code
   - Smaller initrd (~22MB)
   - Expects installation media

2. **netboot files** = Pure network boot
   - NO CD-ROM detection code
   - Larger initrd (~40MB)
   - Pure network installation

## Next Steps

1. **If you already ran setup:** Run `sudo ./scripts/switch-to-netboot.sh`
2. **For fresh setup:** Just run `sudo ./scripts/setup-pxe-server.sh` (already fixed)
3. **Test PXE boot:** CD-ROM error should be gone

## Related Files

- [`scripts/setup-pxe-server.sh`](scripts/setup-pxe-server.sh) - Now uses netboot directly
- [`scripts/switch-to-netboot.sh`](scripts/switch-to-netboot.sh) - Manual fix for existing setups
- [`docs/pxe-installation-media-fix.md`](docs/pxe-installation-media-fix.md) - Technical details