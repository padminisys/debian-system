# Preseed Configuration Directory

This directory contains two separate preseed configurations optimized for different installation methods.

## Directory Structure

```
preseed/
├── pxe/
│   └── btrfs-automated.cfg    # PXE network boot (HTTP-served)
├── iso/
│   └── btrfs-automated.cfg    # ISO/USB boot (embedded)
└── README.md                   # This file
```

## Key Differences

### PXE Version (`pxe/btrfs-automated.cfg`)
- **Delivery:** HTTP server (`http://SERVER_IP/preseed.cfg`)
- **Syntax:** Standard shell syntax
- **Usage:** Network boot installations
- **Script:** `scripts/setup-pxe-server.sh`

**Example syntax:**
```bash
ROOT_DEV=$(mount | grep "on /target " | awk {print\ \$1})
cat > /target/etc/fstab << EOF
```

### ISO Version (`iso/btrfs-automated.cfg`)
- **Delivery:** Embedded in ISO file
- **Syntax:** Escaped shell syntax (for preseed parser)
- **Usage:** USB/DVD installations
- **Script:** `scripts/build-custom-iso.sh`

**Example syntax:**
```bash
ROOT_DEV=$(mount | grep "on /target " | awk '"'"'{print $1}'"'"')
cat > /target/etc/fstab << '"'"'EOF'"'"'
```

## Usage

### For PXE Installation
```bash
sudo ./scripts/setup-pxe-server.sh
# Preseed served from: http://SERVER_IP/preseed.cfg
```

### For USB Installation
```bash
./scripts/build-custom-iso.sh
# Preseed embedded in: output/debian-12.12-btrfs-automated.iso
```

## Important Notes

⚠️ **Do not mix the preseed files!**
- PXE preseed will fail if used in ISO (syntax errors)
- ISO preseed will fail if used in PXE (incorrect escaping)

✅ **Always use the correct preseed for your installation method**

## Verification

**Check PXE preseed syntax:**
```bash
curl http://192.168.2.8/preseed.cfg | grep "ROOT_DEV="
# Should show: awk {print\ \$1}
```

**Check ISO preseed syntax:**
```bash
bsdtar -xOf output/debian-12.12-btrfs-automated.iso preseed.cfg | grep "ROOT_DEV="
# Should show: awk '"'"'{print $1}'"'"'
```

## Common Features

Both preseed files provide:
- Automated Btrfs installation with subvolumes (@, @home, @var_log, @snapshots, @tmp)
- Snapper snapshot management
- GRUB integration for snapshot booting
- Indian locale (en_IN.UTF-8, Asia/Kolkata)
- Default credentials (Root: SecureRoot2024!, User: sysadmin/Admin2024!Secure)
- Security hardening (UFW, fail2ban, SSH configuration)

## Maintenance

When updating preseed configuration:
1. Make changes to **both** files
2. Ensure correct syntax for each version
3. Test both PXE and ISO installations
4. Update documentation if needed

See [`docs/preseed-fix.md`](../docs/preseed-fix.md) for detailed technical explanation.