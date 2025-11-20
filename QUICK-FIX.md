# 🚨 QUICK FIX - PXE Server CD-ROM Error

## Problem
Getting `couldn't mount installation media` error during PXE boot installation.

## Solution (3 Commands)

```bash
# 1. Complete reset (removes all old configs)
sudo ./scripts/reset-pxe-server.sh

# 2. Fresh setup with CD-ROM fix (validates everything)
sudo ./scripts/setup-pxe-server.sh

# 3. Verify it's correct (GO/NO-GO decision)
sudo ./scripts/verify-pxe-config.sh
```

## What to Expect

### After Step 1 (Reset):
```
✓ All services stopped
✓ All processes killed
✓ All configurations removed
✓ All directories cleaned
✓ Clean state verified
```

### After Step 2 (Setup):
```
✓ TFTP structure created
✓ Netboot files extracted
✓ PXE menu configured with CD-ROM detection fix
✓ hw-detect/load_media=false added to boot parameters  ← CRITICAL
✓ HTTP server configured
✓ Services started and running
```

### After Step 3 (Verify):
```
╔══════════════════════════════════════════════════════════════╗
║  ✓ GO - PXE Server is Ready for Client Boot                 ║
╚══════════════════════════════════════════════════════════════╝

All critical checks passed!
You can now boot your client machine via PXE.
```

## If You Get "NO-GO"

The verify script will tell you exactly what's wrong. Most common fix:

```bash
# Run the complete workflow again
sudo ./scripts/reset-pxe-server.sh
sudo ./scripts/setup-pxe-server.sh
sudo ./scripts/verify-pxe-config.sh
```

## Verify the Fix is Applied

```bash
# Check PXE config has the fix
sudo grep "hw-detect/load_media=false" /srv/tftp/pxelinux.cfg/default

# Should output a line containing: hw-detect/load_media=false
```

## Boot Client

Once you get **GO** from verification:

1. Enable PXE/Network boot in client BIOS
2. Connect client to same network
3. Boot from network
4. Select "Automated Btrfs Installation (Network)"
5. Installation should proceed without CD-ROM error

## Logs

If something fails, check logs:
```bash
sudo tail -50 /var/log/pxe-setup.log
sudo tail -50 /var/log/pxe-verify.log
```

## Full Documentation

See [`docs/pxe-server-reset-guide.md`](docs/pxe-server-reset-guide.md) for complete details.

---

**Key Point:** The setup script now **GUARANTEES** the CD-ROM fix is applied and **VERIFIES** it before completing. If setup succeeds, the fix is there.