# Quick Start Guide

Get your automated Debian 12.12 Btrfs system running in minutes.

## Prerequisites

- Debian-based build machine
- Debian 12.12 DVD ISO in [`iso/`](../iso/) directory
- 8GB+ USB drive OR network infrastructure for PXE

## Method 1: USB Installation (Fastest)

### Step 1: Build Custom ISO

```bash
cd /path/to/debian-system
./scripts/build-custom-iso.sh
```

**Expected Output**:
```
✅ SUCCESS!
Custom ISO created: output/debian-12.12-btrfs-automated.iso
```

**Time**: 5-10 minutes (depends on system)

### Step 2: Flash to USB

```bash
sudo ./scripts/flash-usb.sh
```

**Interactive prompts**:
1. Lists available USB devices
2. Select your USB device (e.g., `/dev/sdb`)
3. Confirms before flashing

**Alternative (manual)**:
```bash
sudo dd if=output/debian-12.12-btrfs-automated.iso \
        of=/dev/sdX \
        bs=4M \
        status=progress \
        conv=fsync
```

**Time**: 3-5 minutes

### Step 3: Boot and Install

1. Insert USB into target machine
2. Boot from USB (F12/F2/DEL for boot menu)
3. Select "Automated Btrfs Installation"
4. Wait 5-10 minutes
5. System reboots automatically

**Done!** Login with:
- User: `sysadmin`
- Password: `Admin2024!Secure`

## Method 2: PXE Network Installation

### Step 1: Setup PXE Server

```bash
sudo ./scripts/setup-pxe-server.sh
```

**What it does**:
- Installs dnsmasq, Apache, NFS
- Extracts netboot files
- Configures DHCP/TFTP
- Sets up HTTP preseed server

**Time**: 5-10 minutes

### Step 2: Boot Client from Network

1. Connect client to same network as PXE server
2. Enable network boot in BIOS (PXE/Network Boot)
3. Boot machine
4. Select "Automated Btrfs Installation"
5. Wait 5-10 minutes

**Done!** System ready to use.

## First Login

### Access System

```bash
# Local console
Username: sysadmin
Password: Admin2024!Secure

# SSH (if network configured)
ssh sysadmin@<ip-address>
```

### Verify Installation

```bash
# Display system information
system-info

# Run test suite
./scripts/test-installation.sh
```

**Expected output**:
```
✓ All tests passed! Installation is healthy.
```

## Basic Operations

### Create Snapshot

```bash
snapshot-create "Before testing"
```

### List Snapshots

```bash
snapshot-list
```

### Rollback System

```bash
snapshot-rollback
# System reboots to previous state
```

### View Btrfs Info

```bash
# List subvolumes
sudo btrfs subvolume list /

# Check disk usage
sudo btrfs filesystem usage /

# Show compression stats
sudo compsize /
```

## Testing Workflow Example

```bash
# 1. Create baseline snapshot
snapshot-create "Clean baseline"

# 2. Install test software
sudo apt install nginx
sudo systemctl start nginx

# 3. Test your changes
curl http://localhost

# 4. If something breaks, rollback
snapshot-rollback
# System reboots, nginx is gone

# 5. Try again with different approach
snapshot-create "Before nginx v2"
# ... repeat
```

## Common Tasks

### Change Password

```bash
# Change your password
passwd

# Change root password
sudo passwd root
```

### Configure Static IP

```bash
sudo nano /etc/network/interfaces

# Add:
auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 8.8.8.8

sudo systemctl restart networking
```

### Install Additional Software

```bash
sudo apt update
sudo apt install <package-name>
```

### Check System Status

```bash
# Disk usage
df -h

# Btrfs usage
sudo btrfs filesystem df /

# Snapshot count
sudo snapper -c root list | wc -l

# Service status
systemctl status grub-btrfsd
```

## Troubleshooting

### ISO Build Fails

```bash
# Install dependencies
sudo apt install -y xorriso libarchive-tools genisoimage isolinux

# Check ISO exists
ls -lh iso/debian-12.12.0-amd64-DVD-1.iso
```

### USB Not Detected

```bash
# List all block devices
lsblk

# Check USB connection
dmesg | tail -20
```

### PXE Boot Not Working

```bash
# Check services
sudo systemctl status dnsmasq apache2 nfs-server

# Test preseed accessibility
curl http://localhost/preseed.cfg

# Check network
ip addr show
```

### Installation Hangs

- Verify BIOS settings (UEFI vs Legacy)
- Check network cable connection
- Try different USB port
- Review logs: `/var/log/installer/syslog`

### Can't Login

**Default credentials**:
- Root: `SecureRoot2024!`
- User: `sysadmin` / `Admin2024!Secure`

If forgotten, boot from USB and reset password.

## Next Steps

1. **Change passwords**: Update default credentials
2. **Configure network**: Set static IP if needed
3. **Install software**: Add required packages
4. **Create snapshots**: Before major changes
5. **Test rollback**: Verify snapshot functionality

## Advanced Usage

### Boot from Specific Snapshot

1. Reboot system
2. In GRUB menu, select "System Snapshots"
3. Choose snapshot to boot
4. System boots in that state

### Cleanup Old Snapshots

```bash
# Manual cleanup
snapshot-cleanup

# Configure automatic cleanup
sudo nano /etc/snapper/configs/root
# Adjust TIMELINE_LIMIT_* values
```

### Monitor Disk Space

```bash
# Watch Btrfs usage
watch -n 5 'sudo btrfs filesystem usage /'

# Check snapshot sizes
sudo btrfs subvolume show /.snapshots/*
```

## Performance Tips

1. **SSD Recommended**: Btrfs performs best on SSD
2. **Compression**: Already enabled (zstd:1)
3. **Snapshots**: Keep count reasonable (<50)
4. **Cleanup**: Run `snapshot-cleanup` regularly

## Security Checklist

- [ ] Change default passwords
- [ ] Configure SSH keys
- [ ] Review firewall rules (`sudo ufw status`)
- [ ] Update system (`sudo apt update && sudo apt upgrade`)
- [ ] Disable root SSH (edit `/etc/ssh/sshd_config`)
- [ ] Configure fail2ban
- [ ] Setup monitoring

## Getting Help

### Check Logs

```bash
# Installation logs
sudo less /var/log/preseed-post-install.log

# System logs
sudo journalctl -xe

# Snapper logs
sudo snapper -c root list
```

### System Information

```bash
# Complete system info
system-info

# Btrfs info
sudo btrfs filesystem show

# Kernel version
uname -a
```

### Documentation

- [Main README](../README.md)
- [Architecture Guide](architecture.md)
- [Btrfs Documentation](https://btrfs.readthedocs.io/)
- [Snapper Manual](http://snapper.io/)

---

**You're now ready to use your automated Debian Btrfs system with snapshot capabilities!**