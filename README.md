# Debian 12.12 Btrfs Automated Installation System

Complete automated installation system for Debian 12.12 with Btrfs filesystem, Snapper snapshots, and production-ready configuration. Supports both USB boot and PXE network installation.

## 🎯 Features

- **Zero-Touch Installation**: Fully automated Debian 12.12 installation
- **Btrfs Filesystem**: Advanced filesystem with compression and snapshots
- **Snapper Integration**: Automatic snapshot management and rollback capability
- **GRUB-Btrfs**: Boot from any snapshot directly from GRUB menu
- **PXE Support**: Network-based installation for bare metal provisioning
- **Production Ready**: Secure defaults, firewall configured, optimized for India locale
- **Testing Friendly**: 10-second rollback for rapid testing iterations

## 📋 Prerequisites

- Debian-based system for building ISO/PXE server
- **For USB Installation:**
  - Debian 12.12 netinst or DVD ISO (placed in [`iso/`](iso/) directory)
  - Download: `debian-12.12.0-amd64-netinst.iso` (~400MB) or DVD (~4.7GB)
  - 8GB+ USB drive
- **For PXE Installation:**
  - Internet connection (downloads official netboot files automatically)
  - No ISO required - setup script downloads netboot.tar.gz directly
  - Network infrastructure with internet access

## 🚀 Quick Start

### 🚨 PXE Installation Issues?

If you're getting `couldn't mount installation media` error, see **[QUICK-FIX.md](QUICK-FIX.md)** for immediate solution.

### Option 1: USB Installation

```bash
# 1. Build custom ISO
./scripts/build-custom-iso.sh

# 2. Flash to USB
sudo ./scripts/flash-usb.sh

# 3. Boot from USB
# Installation completes automatically in 5-10 minutes
```

### Option 2: PXE Network Installation

```bash
# 1. Setup PXE server (downloads official netboot files)
sudo ./scripts/setup-pxe-server.sh

# 2. Verify configuration (recommended)
sudo ./scripts/verify-pxe-config.sh

# 3. Boot client machine from network
# 4. Ensure client has internet access
# Installation completes automatically in 10-15 minutes
```

**Note:**
- PXE setup automatically downloads official Debian netboot files (~40MB)
- No ISO required - pure network boot installation
- Client machine needs internet connectivity to download packages

**Having Issues?** See [IMMEDIATE-FIX.md](IMMEDIATE-FIX.md) for CD-ROM detection error fix.

## 📁 Project Structure

```
debian-system/
├── iso/                          # Source ISO location
│   ├── debian-12.12.0-amd64-netinst.iso  # For USB (optional)
│   └── debian-12.12.0-amd64-DVD-1.iso    # For USB (optional)
├── preseed/                      # Preseed configurations
│   ├── pxe/
│   │   └── btrfs-automated.cfg   # PXE preseed
│   └── iso/
│       └── btrfs-automated.cfg   # ISO preseed
├── scripts/                      # Automation scripts
│   ├── build-custom-iso.sh       # Build bootable ISO
│   ├── setup-pxe-server.sh       # Setup PXE server (downloads netboot)
│   ├── switch-to-netboot.sh      # Switch existing setup to netboot
│   ├── reset-pxe-server.sh       # Complete PXE server reset
│   ├── verify-pxe-config.sh      # Verify PXE configuration
│   ├── flash-usb.sh              # Flash ISO to USB
│   └── test-installation.sh      # Validate installation
├── build/                        # Build artifacts (auto-created)
├── output/                       # Generated ISOs (auto-created)
├── pxe/                          # PXE server files (auto-created)
└── docs/                         # Documentation
```

## 🔧 Configuration

### Default Credentials

**Root Account:**
- Username: `root`
- Password: `SecureRoot2024!`

**Admin Account:**
- Username: `sysadmin`
- Password: `Admin2024!Secure`
- Sudo: Full access (passwordless)

### Locale Settings

- **Country**: India (IN)
- **Language**: English (en_IN.UTF-8)
- **Keyboard**: US Layout
- **Timezone**: Asia/Kolkata
- **NTP Server**: in.pool.ntp.org

### Disk Layout

The system automatically creates the following Btrfs subvolume structure:

```
/dev/sda1  512MB   EFI System Partition
/dev/sda2  1GB     /boot (ext4)
/dev/sda3  8GB     swap
/dev/sda4  Rest    Btrfs with subvolumes:
                   ├── @           (/)
                   ├── @home       (/home)
                   ├── @var_log    (/var/log)
                   ├── @snapshots  (/.snapshots)
                   └── @tmp        (/tmp)
```

All Btrfs subvolumes use:
- **Compression**: zstd:1
- **Mount options**: noatime, space_cache=v2

## 📖 Usage Guide

### After Installation

1. **Login** with default credentials
2. **View system info**:
   ```bash
   system-info
   ```

3. **Check installation**:
   ```bash
   ./scripts/test-installation.sh
   ```

### Snapshot Management

The system includes convenient snapshot management commands:

```bash
# Create snapshot before making changes
snapshot-create "Before OVN testing"

# List all snapshots
snapshot-list

# Rollback to last snapshot (reboots system)
snapshot-rollback

# Cleanup old snapshots
snapshot-cleanup
```

### Testing Workflow

Perfect for rapid testing iterations:

```bash
# 1. Create pre-test snapshot
snapshot-create "Before test run"

# 2. Run your tests
./run-your-tests.sh

# 3. If system breaks, rollback in 10 seconds
snapshot-rollback
# System reboots to clean state

# 4. Repeat testing
```

### Boot from Snapshot

1. Reboot system
2. In GRUB menu, select "System Snapshots"
3. Choose any snapshot to boot from
4. System boots into that snapshot state

## 🛠️ Advanced Configuration

### Customizing Preseed

Edit [`preseed/btrfs-automated.cfg`](preseed/btrfs-automated.cfg:1) to customize:

- Partitioning scheme
- Package selection
- Network configuration
- User accounts
- Post-installation scripts

### Modifying ISO Build

Edit [`scripts/build-custom-iso.sh`](scripts/build-custom-iso.sh:1) to:

- Change boot menu options
- Adjust timeout values
- Add custom boot parameters

### PXE Server Configuration

Edit [`scripts/setup-pxe-server.sh`](scripts/setup-pxe-server.sh:1) to:

- Change DHCP range
- Modify network interface
- Adjust NFS/TFTP paths

## 🧪 Testing

### Validate Installation

Run the test suite on installed system:

```bash
./scripts/test-installation.sh
```

Tests include:
- Btrfs filesystem verification
- Subvolume structure
- Snapper configuration
- GRUB-Btrfs integration
- Network connectivity
- Package installation
- User accounts

### Manual Verification

```bash
# Check Btrfs subvolumes
sudo btrfs subvolume list /

# Check mount options
mount | grep btrfs

# Check snapshots
sudo snapper -c root list

# Check GRUB entries
sudo update-grub
```

## 📊 Performance Characteristics

### Installation Time

- **USB Boot**: 5-10 minutes (depends on hardware)
- **PXE Boot**: 10-15 minutes (depends on internet speed)
  - Uses official netboot files: pure network installation
  - Downloads packages from deb.debian.org during installation

### Snapshot Operations

- **Create snapshot**: < 1 second
- **Rollback**: 10 seconds + reboot time
- **Boot from snapshot**: Same as normal boot

### Disk Space

- **Base installation**: ~3-4 GB
- **Per snapshot**: ~10-50 MB (only changed data)
- **Recommended**: 20GB+ for root partition

## 🔒 Security Features

- **Firewall**: UFW enabled with SSH allowed
- **Fail2ban**: Installed and configured
- **SSH**: Root login enabled (change in production)
- **Sudo**: Configured for sysadmin user
- **Updates**: Security updates enabled

## 🌐 Network Configuration

### Ethernet Priority

System prefers ethernet over WiFi:
1. Detects active ethernet interface
2. Falls back to WiFi if no ethernet
3. Configures DHCP automatically

### Static IP (Optional)

Edit [`/etc/network/interfaces`](file:///etc/network/interfaces) after installation:

```bash
auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 8.8.8.8 8.8.4.4
```

## 🐛 Troubleshooting

### ISO Build Fails

```bash
# Check dependencies
sudo apt install -y xorriso libarchive-tools genisoimage isolinux

# Verify source ISO exists
ls -lh iso/debian-12.12.0-amd64-DVD-1.iso

# Check disk space
df -h
```

### PXE Boot Issues

**"Couldn't mount installation media" error:**

This error occurred in older versions when using netinst ISO extraction. **Now fixed automatically.**

**Current Solution (v2.0):**
- Setup script now downloads official Debian netboot files directly
- No CD-ROM detection code in netboot files
- Pure network boot installation

**If you have an existing setup with this error:**
```bash
# Quick fix for existing installations
sudo ./scripts/switch-to-netboot.sh
sudo systemctl restart dnsmasq
```

**For fresh setup:**
```bash
# Just run setup - it now uses netboot automatically
sudo ./scripts/setup-pxe-server.sh
```

**Detailed Documentation:**
- [IMMEDIATE-FIX.md](IMMEDIATE-FIX.md) - Fix for existing setups
- [docs/pxe-installation-media-fix.md](docs/pxe-installation-media-fix.md) - Technical details

**Common Issues:**
- No internet connectivity on PXE server (needed to download netboot files)
- No internet connectivity on client machine (needed to download packages)
- Firewall blocking HTTP/TFTP ports
- Services not running properly

### Installation Hangs

- Check BIOS settings (UEFI vs Legacy)
- Verify network connectivity
- Check preseed syntax
- Review installation logs: `/var/log/installer/syslog`

### Snapshot Issues

```bash
# Check Snapper status
sudo snapper -c root list

# Verify subvolume
sudo btrfs subvolume show /.snapshots

# Check GRUB configuration
sudo update-grub
```

## 📚 Additional Resources

- [Btrfs Documentation](https://btrfs.readthedocs.io/)
- [Snapper Documentation](http://snapper.io/)
- [Debian Preseed](https://wiki.debian.org/DebianInstaller/Preseed)
- [PXE Boot Guide](https://wiki.debian.org/PXEBootInstall)

## 🤝 Contributing

This is a production-ready system. Contributions welcome:

1. Test on different hardware
2. Report issues
3. Suggest improvements
4. Add documentation

## 📝 License

This project is provided as-is for automated Debian installation with Btrfs.

## ⚠️ Important Notes

1. **Backup Data**: Installation erases target disk
2. **Test First**: Validate on test hardware before production
3. **Change Passwords**: Update default credentials after installation
4. **Network Security**: Secure PXE server on trusted networks only
5. **Snapshot Cleanup**: Configure retention policies for production

## 🎓 Learning Resources

### Understanding Btrfs

- Subvolumes are like directories but can be snapshotted independently
- Snapshots are instant and space-efficient (copy-on-write)
- Compression reduces disk usage without performance penalty

### Snapper Workflow

1. **Pre-snapshot**: Before making changes
2. **Make changes**: Install packages, modify configs
3. **Post-snapshot**: After changes complete
4. **Compare**: See what changed between snapshots
5. **Rollback**: Undo changes if needed

### PXE Boot Process

1. Client requests IP via DHCP
2. DHCP server provides IP + boot file location
3. Client downloads boot files via TFTP (official netboot kernel/initrd)
4. Kernel boots and fetches preseed via HTTP
5. Installer downloads packages from deb.debian.org
6. Installation proceeds automatically

**Key Difference from netinst:**
- **Netboot**: Pure network boot (~40MB initrd, NO CD-ROM code)
- **Netinst**: CD-ROM boot + network fallback (~22MB initrd, has CD-ROM detection)

## 🚀 Production Deployment

### Checklist

- [ ] Change default passwords
- [ ] Configure static IP (if needed)
- [ ] Setup SSH keys
- [ ] Configure firewall rules
- [ ] Setup monitoring
- [ ] Configure backup strategy
- [ ] Document snapshot retention policy
- [ ] Test rollback procedure
- [ ] Verify network security
- [ ] Update system packages

### Recommended Snapshot Policy

```bash
# Edit /etc/snapper/configs/root
TIMELINE_CREATE="yes"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="6"
```

---

**Built for production-grade bare metal provisioning with testing-friendly rollback capabilities.**