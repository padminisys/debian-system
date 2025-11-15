# System Architecture

## Overview

This document describes the technical architecture of the Debian 12.12 Btrfs automated installation system.

## Components

### 1. Preseed Configuration

**File**: [`preseed/btrfs-automated.cfg`](../preseed/btrfs-automated.cfg:1)

**Purpose**: Debian installer automation configuration

**Key Sections**:
- Localization (India/English)
- Network configuration (Ethernet priority)
- Disk partitioning (Btrfs with subvolumes)
- Package selection
- Post-installation scripts

**Critical Features**:
- Automatic disk detection
- Btrfs subvolume creation
- Snapper configuration
- GRUB-Btrfs setup

### 2. ISO Builder

**File**: [`scripts/build-custom-iso.sh`](../scripts/build-custom-iso.sh:1)

**Purpose**: Create bootable ISO with embedded preseed

**Process Flow**:
```
Source ISO → Extract → Embed Preseed → Configure Boot → Build ISO
```

**Key Operations**:
1. Extract Debian DVD ISO
2. Embed preseed configuration
3. Configure ISOLINUX (BIOS boot)
4. Configure GRUB (UEFI boot)
5. Update checksums
6. Build hybrid ISO

### 3. PXE Server

**File**: [`scripts/setup-pxe-server.sh`](../scripts/setup-pxe-server.sh:1)

**Purpose**: Network-based installation server

**Services**:
- **dnsmasq**: DHCP + TFTP server
- **Apache2**: HTTP server for preseed
- **NFS**: Network filesystem for installation files

**Network Flow**:
```
Client Boot → DHCP Request → IP + Boot File
           → TFTP Download → Kernel + Initrd
           → HTTP Fetch → Preseed Config
           → NFS Mount → Installation Files
```

## Btrfs Architecture

### Subvolume Structure

```
/dev/sda4 (Btrfs root)
├── @ (/)                    # Root filesystem
├── @home (/home)            # User data
├── @var_log (/var/log)      # System logs
├── @snapshots (/.snapshots) # Snapshot storage
└── @tmp (/tmp)              # Temporary files
```

### Why This Structure?

1. **@ (root)**: Main system, can be snapshotted independently
2. **@home**: User data persists across root snapshots
3. **@var_log**: Logs don't consume snapshot space
4. **@snapshots**: Dedicated space for Snapper
5. **@tmp**: Temporary files excluded from snapshots

### Mount Options

```bash
compress=zstd:1    # Fast compression, good ratio
noatime            # Don't update access times (performance)
space_cache=v2     # Improved free space tracking
```

## Snapshot System

### Snapper Integration

**Configuration**: `/etc/snapper/configs/root`

**Snapshot Types**:
1. **Timeline**: Automatic hourly/daily/weekly
2. **Pre/Post**: Before/after package operations
3. **Manual**: User-created snapshots

### GRUB-Btrfs Integration

**Service**: `grub-btrfsd.service`

**Function**: Monitors `.snapshots` directory and updates GRUB menu

**Boot Process**:
```
GRUB Menu → Select Snapshot → Boot Kernel
         → Mount @snapshots/X/snapshot as /
         → System boots in snapshot state
```

## Installation Flow

### USB Boot Installation

```
1. BIOS/UEFI Boot
   ↓
2. GRUB/ISOLINUX Menu
   ↓
3. Load Kernel + Initrd
   ↓
4. Debian Installer Starts
   ↓
5. Read Preseed Config
   ↓
6. Automatic Partitioning
   ↓
7. Install Base System
   ↓
8. Post-Install Script
   ├── Create Btrfs Subvolumes
   ├── Configure Snapper
   ├── Setup GRUB-Btrfs
   └── Create Golden Snapshot
   ↓
9. Reboot to Installed System
```

### PXE Boot Installation

```
1. Network Boot (PXE)
   ↓
2. DHCP Request
   ↓
3. Receive IP + Boot File
   ↓
4. TFTP Download Kernel/Initrd
   ↓
5. HTTP Fetch Preseed
   ↓
6. NFS Mount Installation Files
   ↓
7. [Same as USB from step 6]
```

## Post-Installation Scripts

### Btrfs Setup Process

**Location**: Preseed `late_command` section

**Steps**:
1. Mount Btrfs root volume
2. Create subvolumes (@, @home, etc.)
3. Copy existing data to subvolumes
4. Remount with proper subvolume structure
5. Generate new fstab
6. Configure Snapper
7. Update initramfs and GRUB

### Snapshot Management Scripts

**Created in**: `/usr/local/bin/`

1. **snapshot-create**: Create pre-change snapshot
2. **snapshot-rollback**: Rollback to last snapshot
3. **snapshot-list**: Display all snapshots
4. **snapshot-cleanup**: Remove old snapshots

## Security Architecture

### Default Security Measures

1. **Firewall**: UFW enabled, SSH allowed
2. **Fail2ban**: Brute-force protection
3. **SSH**: Configured for remote access
4. **Sudo**: Passwordless for sysadmin user

### Network Security

- PXE server should run on trusted network
- DHCP range isolated from production
- HTTP preseed accessible only during installation

## Performance Considerations

### Btrfs Compression

**Algorithm**: zstd:1 (level 1)

**Benefits**:
- 30-50% space savings
- Minimal CPU overhead
- Faster than no compression (less I/O)

**Trade-offs**:
- Slight CPU usage increase
- Not suitable for already-compressed data

### Snapshot Performance

**Copy-on-Write (CoW)**:
- Snapshots are instant (metadata only)
- Only changed blocks consume space
- No performance penalty for snapshots

**Space Usage**:
- Initial snapshot: ~10-50 MB
- Grows with changes
- Shared blocks not duplicated

## Disk Layout Strategy

### Partition Scheme

```
/dev/sda1  512MB   EFI (FAT32)
/dev/sda2  1GB     /boot (ext4)
/dev/sda3  8GB     swap
/dev/sda4  Rest    Btrfs (all subvolumes)
```

### Why Separate /boot?

1. **GRUB Compatibility**: Not all GRUB versions support Btrfs fully
2. **Recovery**: Easier to recover if Btrfs issues occur
3. **Simplicity**: Standard ext4 for bootloader

### Why Separate EFI?

1. **UEFI Requirement**: Must be FAT32
2. **Firmware Access**: UEFI firmware reads this directly
3. **Standard**: Universal across all UEFI systems

## Testing Architecture

### Test Suite Components

**File**: [`scripts/test-installation.sh`](../scripts/test-installation.sh:1)

**Tests**:
1. Btrfs filesystem verification
2. Subvolume structure validation
3. Snapper configuration check
4. GRUB-Btrfs integration
5. Network connectivity
6. Package installation
7. User account verification
8. Disk space analysis

### Testing Workflow

```
Install System → Run Tests → Create Snapshot
              → Make Changes → Test Changes
              → Rollback if Failed → Repeat
```

## Scalability

### Single Machine

- USB boot: Manual per machine
- Time: 5-10 minutes per installation

### Multiple Machines (PXE)

- Network boot: Parallel installations
- Time: 5-10 minutes regardless of count
- Limitation: Network bandwidth

### Production Scale

**Recommended**:
- Dedicated PXE server per subnet
- Gigabit network minimum
- NFS server with SSD storage

## Maintenance

### Regular Tasks

1. **Snapshot Cleanup**: Automatic via Snapper
2. **System Updates**: Standard apt upgrade
3. **Disk Space**: Monitor Btrfs usage
4. **Logs**: Rotate via logrotate

### Monitoring Points

- Btrfs filesystem health
- Snapshot count and size
- Disk space usage
- Service status (grub-btrfsd)

## Disaster Recovery

### Rollback Scenarios

1. **Boot from Snapshot**: Select in GRUB menu
2. **Snapper Rollback**: `snapshot-rollback` command
3. **Manual Recovery**: Boot from USB, mount subvolumes

### Backup Strategy

**What to Backup**:
- @home subvolume (user data)
- Configuration files
- Application data

**What NOT to Backup**:
- @ subvolume (can be reinstalled)
- @tmp (temporary files)
- Snapshots (local recovery only)

## Future Enhancements

### Potential Improvements

1. **Multi-disk Support**: RAID configurations
2. **Encryption**: LUKS integration
3. **Cloud Integration**: Cloud-init support
4. **Monitoring**: Prometheus exporters
5. **Automation**: Ansible playbooks

### Extensibility Points

- Preseed customization
- Post-install hooks
- Custom package lists
- Network configurations
- Security policies

---

**This architecture provides a robust, production-ready foundation for automated Debian installations with advanced filesystem features and rapid rollback capabilities.**