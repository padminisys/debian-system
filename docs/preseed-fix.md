# Preseed Configuration Guide

## Overview

This project maintains **two separate preseed configurations** optimized for different installation methods:

1. **PXE Network Boot** - [`preseed/pxe/btrfs-automated.cfg`](../preseed/pxe/btrfs-automated.cfg)
2. **ISO/USB Boot** - [`preseed/iso/btrfs-automated.cfg`](../preseed/iso/btrfs-automated.cfg)

## Why Two Versions?

The preseed files require **different shell script syntax** depending on how they're delivered:

### PXE Version (HTTP-served)
- Uses **standard shell syntax**
- AWK: `awk {print\ \$1}`
- Heredocs: `<< EOF`
- Served via HTTP, parsed directly by installer

### ISO Version (Embedded)
- Uses **escaped shell syntax**
- AWK: `awk '"'"'{print $1}'"'"'`
- Heredocs: `<< '"'"'EOF'"'"'`
- Embedded in ISO, requires extra escaping for preseed parser

## Directory Structure

```
preseed/
├── pxe/
│   └── btrfs-automated.cfg    # For PXE network boot
└── iso/
    └── btrfs-automated.cfg    # For ISO/USB installation
```

## Installation Methods

### Method 1: PXE Network Boot

**Setup PXE Server:**
```bash
sudo ./scripts/setup-pxe-server.sh
```

**Features:**
- **Proxy DHCP mode** (Router assigns IPs, PXE server provides boot info only)
- TFTP boot files
- HTTP preseed delivery
- NFS installation files
- Uses: `preseed/pxe/btrfs-automated.cfg`

**How It Works:**
1. Router DHCP assigns IP to target machine
2. dnsmasq (Proxy DHCP) adds PXE boot information
3. Target downloads boot files via TFTP
4. Preseed downloaded via HTTP

**Stop PXE Server:**
```bash
sudo ./scripts/stop-pxe-server.sh
```

**Note:** Router continues to provide DHCP/IP addresses. PXE server only provides boot information.

### Method 2: USB/ISO Boot

**Build Custom ISO:**
```bash
./scripts/build-custom-iso.sh
```

**Flash to USB:**
```bash
sudo dd if=output/debian-12.12-btrfs-automated.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

**Features:**
- Bootable USB/DVD
- Embedded preseed
- Works offline
- Uses: `preseed/iso/btrfs-automated.cfg`

## Technical Details

### Shell Script Escaping

**PXE Version (Standard):**
```bash
ROOT_DEV=$(mount | grep "on /target " | awk {print\ \$1})
cat > /target/etc/fstab << EOF
```

**ISO Version (Escaped):**
```bash
ROOT_DEV=$(mount | grep "on /target " | awk '"'"'{print $1}'"'"')
cat > /target/etc/fstab << '"'"'EOF'"'"'
```

### Why Different Escaping?

- **ISO**: Preseed parser processes the entire `late_command` as a string, requiring double-escaping
- **PXE**: HTTP-served file is parsed directly, standard shell syntax works

## Verification

**Check PXE preseed:**
```bash
curl http://192.168.2.8/preseed.cfg | grep "ROOT_DEV="
```

**Check ISO preseed:**
```bash
bsdtar -xOf output/debian-12.12-btrfs-automated.iso preseed.cfg | grep "ROOT_DEV="
```

## Default Credentials

Both configurations use the same credentials:
- **Root:** `SecureRoot2024!`
- **User:** `sysadmin` / `Admin2024!Secure`

## Post-Installation

After successful installation:
```bash
system-info              # Display system details
btrfs subvolume list /   # List Btrfs subvolumes
snapper list             # List snapshots
```

## Troubleshooting

### PXE Installation Fails
1. Verify preseed is accessible: `curl http://SERVER_IP/preseed.cfg`
2. Check DHCP assignment on target machine
3. Ensure correct preseed syntax (no escaped quotes for PXE)

### ISO Installation Fails
1. Verify ISO was built with correct preseed
2. Check preseed has escaped syntax for embedded use
3. Rebuild ISO if needed: `./scripts/build-custom-iso.sh`

## Files Modified

- [`preseed/pxe/btrfs-automated.cfg`](../preseed/pxe/btrfs-automated.cfg) - PXE network boot
- [`preseed/iso/btrfs-automated.cfg`](../preseed/iso/btrfs-automated.cfg) - ISO/USB boot
- [`scripts/build-custom-iso.sh`](../scripts/build-custom-iso.sh) - Uses ISO preseed
- [`scripts/setup-pxe-server.sh`](../scripts/setup-pxe-server.sh) - Uses PXE preseed