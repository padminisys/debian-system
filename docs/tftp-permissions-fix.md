# TFTP Permission Fix for PXE Boot

## Problem
PXE clients were getting permission denied errors when trying to access TFTP files:
```
PXE-T02: cannot access /srv/tftp/pxelinux.0 Permission denied
PXE-E3C: TFTP Error - Access Violation
```

## Root Cause
The dnsmasq configuration uses `tftp-secure` mode, which restricts TFTP file access to files owned by the dnsmasq user. However, the TFTP files in [`/srv/tftp/`](../scripts/setup-pxe-server.sh:14) were owned by `root:root`, preventing the dnsmasq user from reading them.

## Solution
Changed ownership of all TFTP files to `dnsmasq:nogroup`:
```bash
sudo chown -R dnsmasq:nogroup /srv/tftp/
sudo systemctl restart dnsmasq
```

## Verification
Test TFTP access:
```bash
# Test from localhost
curl -s tftp://localhost/pxelinux.0 > /dev/null && echo "Success" || echo "Failed"

# Test from server IP
curl -s tftp://192.168.2.12/pxelinux.0 > /dev/null && echo "Success" || echo "Failed"
```

## Script Updates
Updated [`setup-pxe-server.sh`](../scripts/setup-pxe-server.sh) to automatically set correct ownership:
- [`setup_tftp_structure()`](../scripts/setup-pxe-server.sh:144) - Sets ownership after copying boot files
- [`extract_netboot_files()`](../scripts/setup-pxe-server.sh:156) - Sets ownership for kernel/initrd
- [`configure_pxe_menu()`](../scripts/setup-pxe-server.sh:183) - Sets ownership for PXE config

## Why tftp-secure?
The `tftp-secure` option in dnsmasq.conf provides security by:
- Preventing directory traversal attacks
- Restricting access to files outside TFTP root
- Ensuring only authorized files can be served

## Alternative Solution (Not Recommended)
You could remove `tftp-secure` from dnsmasq.conf, but this reduces security. The ownership fix is the proper solution.

## Status
✅ Fixed - TFTP files now accessible with proper permissions
✅ Script updated to prevent future issues
✅ Proxy DHCP mode working correctly (router assigns IPs)