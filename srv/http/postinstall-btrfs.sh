#!/bin/bash
# Debian 12.12 Btrfs Post-Installation Script
# Automated Btrfs subvolume setup with Snapper integration

set -e
exec > >(tee -a /var/log/preseed-post-install.log) 2>&1

echo "=== [$(date)] Starting Btrfs Post-Installation Setup ==="

# Detect root device and UUID
ROOT_DEV=$(mount | grep "on / " | awk '{print $1}')
BTRFS_UUID=$(blkid -s UUID -o value $ROOT_DEV)
echo "Root device: $ROOT_DEV"
echo "Btrfs UUID: $BTRFS_UUID"

# Mount Btrfs root
mkdir -p /mnt/btrfs-root
mount -t btrfs $ROOT_DEV /mnt/btrfs-root

echo "Creating Btrfs subvolumes..."
cd /mnt/btrfs-root

# Create @ subvolume and copy root filesystem
btrfs subvolume create @
echo "Copying root filesystem to @ subvolume..."
rsync -aAXHv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / /mnt/btrfs-root/@/

# Create additional subvolumes
btrfs subvolume create @home
btrfs subvolume create @var_log
btrfs subvolume create @snapshots
btrfs subvolume create @tmp

# Copy existing data to subvolumes
if [ -d /home ] && [ "$(ls -A /home)" ]; then
    rsync -aAXHv /home/ /mnt/btrfs-root/@home/
fi

if [ -d /var/log ] && [ "$(ls -A /var/log)" ]; then
    rsync -aAXHv /var/log/ /mnt/btrfs-root/@var_log/
fi

# Remount with subvolumes
cd /
umount /mnt/btrfs-root
umount /boot/efi || true
umount /boot || true

mount -o subvol=@,compress=zstd:1,noatime $ROOT_DEV /mnt
mkdir -p /mnt/{home,var/log,.snapshots,tmp}
mount -o subvol=@home,compress=zstd:1,noatime $ROOT_DEV /mnt/home
mount -o subvol=@var_log,compress=zstd:1,noatime $ROOT_DEV /mnt/var/log
mount -o subvol=@snapshots,noatime $ROOT_DEV /mnt/.snapshots
mount -o subvol=@tmp,compress=zstd:1,noatime $ROOT_DEV /mnt/tmp

# Remount boot partitions
BOOT_DEV=$(blkid | grep -E 'LABEL="boot"' | cut -d: -f1 || echo "")
if [ -n "$BOOT_DEV" ]; then
    mount $BOOT_DEV /mnt/boot
fi

EFI_DEV=$(blkid | grep -E 'TYPE="vfat"' | head -n1 | cut -d: -f1 || echo "")
if [ -n "$EFI_DEV" ]; then
    mkdir -p /mnt/boot/efi
    mount $EFI_DEV /mnt/boot/efi
fi

# Generate fstab
echo "Generating fstab..."
cat > /mnt/etc/fstab << EOF
# Btrfs Production Environment - Auto-configured
UUID=$BTRFS_UUID  /            btrfs  defaults,subvol=@,compress=zstd:1,noatime,space_cache=v2  0  1
UUID=$BTRFS_UUID  /home        btrfs  defaults,subvol=@home,compress=zstd:1,noatime  0  2
UUID=$BTRFS_UUID  /var/log     btrfs  defaults,subvol=@var_log,compress=zstd:1,noatime  0  2
UUID=$BTRFS_UUID  /.snapshots  btrfs  defaults,subvol=@snapshots,noatime  0  2
UUID=$BTRFS_UUID  /tmp         btrfs  defaults,subvol=@tmp,compress=zstd:1,noatime  0  2
EOF

if [ -n "$BOOT_DEV" ]; then
    BOOT_UUID=$(blkid -s UUID -o value $BOOT_DEV)
    echo "UUID=$BOOT_UUID  /boot  ext4  defaults  0  2" >> /mnt/etc/fstab
fi

if [ -n "$EFI_DEV" ]; then
    EFI_UUID=$(blkid -s UUID -o value $EFI_DEV)
    echo "UUID=$EFI_UUID  /boot/efi  vfat  umask=0077  0  1" >> /mnt/etc/fstab
fi

SWAP_DEV=$(blkid | grep -E 'TYPE="swap"' | cut -d: -f1 || echo "")
if [ -n "$SWAP_DEV" ]; then
    SWAP_UUID=$(blkid -s UUID -o value $SWAP_DEV)
    echo "UUID=$SWAP_UUID  none  swap  sw  0  0" >> /mnt/etc/fstab
fi

# Configure Snapper
echo "Configuring Snapper..."
chroot /mnt snapper -c root create-config /

chroot /mnt btrfs subvolume delete /.snapshots 2>/dev/null || true
mkdir -p /mnt/.snapshots
mount -o subvol=@snapshots,noatime $ROOT_DEV /mnt/.snapshots

cat > /mnt/etc/snapper/configs/root << 'SNAPEOF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="20"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="6"
TIMELINE_LIMIT_YEARLY="2"
TIMELINE_CREATE="yes"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
SNAPEOF

chroot /mnt chmod 750 /.snapshots
chroot /mnt systemctl enable grub-btrfsd.service

# Configure GRUB
echo "Configuring GRUB..."
cat >> /mnt/etc/default/grub << 'GRUBEOF'

# Btrfs Snapshot Configuration
GRUB_TIMEOUT=10
GRUB_BTRFS_SUBMENUNAME="System Snapshots"
GRUB_BTRFS_SNAPSHOT_BOOTING="true"
GRUB_BTRFS_SNAPSHOT_BOOTING_SORT="descending"
GRUB_BTRFS_LIMIT="10"
GRUBEOF

# Create snapshot management scripts
echo "Creating snapshot management scripts..."

cat > /mnt/usr/local/bin/snapshot-create << 'SCRIPTEOF'
#!/bin/bash
DESC="${1:-Manual snapshot $(date +%Y%m%d_%H%M%S)}"
echo "Creating snapshot: $DESC"
sudo snapper -c root create --description "$DESC" --cleanup-algorithm number
SNAP_NUM=$(sudo snapper -c root list | tail -n 1 | awk '{print $1}')
echo "$SNAP_NUM" > /tmp/last_snapshot_num
echo "✓ Snapshot #$SNAP_NUM created successfully"
sudo snapper -c root list | tail -n 5
SCRIPTEOF

cat > /mnt/usr/local/bin/snapshot-rollback << 'SCRIPTEOF'
#!/bin/bash
if [ -f /tmp/last_snapshot_num ]; then
    SNAP_NUM=$(cat /tmp/last_snapshot_num)
    echo "Rolling back to snapshot #$SNAP_NUM"
    sudo snapper -c root undochange $SNAP_NUM..0
else
    echo "No recent snapshot found. Using Snapper rollback..."
    sudo snapper rollback
fi
echo "✓ Rollback prepared. Rebooting in 5 seconds..."
sleep 5
sudo systemctl reboot
SCRIPTEOF

cat > /mnt/usr/local/bin/snapshot-list << 'SCRIPTEOF'
#!/bin/bash
sudo snapper -c root list
SCRIPTEOF

cat > /mnt/usr/local/bin/snapshot-cleanup << 'SCRIPTEOF'
#!/bin/bash
echo "Cleaning up old snapshots..."
sudo snapper -c root cleanup number
echo "✓ Cleanup complete"
sudo snapper -c root list
SCRIPTEOF

chmod +x /mnt/usr/local/bin/snapshot-*

# Create system-info script
cat > /mnt/usr/local/bin/system-info << 'INFOEOF'
#!/bin/bash
echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo ""
echo "=== Credentials (Default) ==="
echo "Root Password: SecureRoot2024!"
echo "User: sysadmin"
echo "Password: Admin2024!Secure"
echo ""
echo "=== Network ==="
ip -br addr show
echo ""
echo "=== Btrfs Subvolumes ==="
sudo btrfs subvolume list /
echo ""
echo "=== Snapshots ==="
sudo snapper -c root list
echo ""
echo "=== Disk Usage ==="
df -h | grep -E "Filesystem|/dev/"
INFOEOF

chmod +x /mnt/usr/local/bin/system-info

# Configure sudo for sysadmin
echo "sysadmin ALL=(ALL:ALL) NOPASSWD:ALL" > /mnt/etc/sudoers.d/sysadmin
chmod 440 /mnt/etc/sudoers.d/sysadmin

# Enable SSH root login
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /mnt/etc/ssh/sshd_config

# Configure firewall
chroot /mnt ufw allow 22/tcp
chroot /mnt ufw --force enable

# Update initramfs and GRUB
echo "Updating initramfs and GRUB..."
chroot /mnt update-initramfs -u -k all
chroot /mnt update-grub

# Create golden baseline snapshot
echo "Creating golden baseline snapshot..."
chroot /mnt snapper -c root create --description "Golden Baseline - Fresh Install $(date +%Y-%m-%d)" --cleanup-algorithm number

# Create MOTD
cat > /mnt/etc/motd << 'MOTDEOF'
╔══════════════════════════════════════════════════════════════╗
║          Debian 12.12 Btrfs Production System                ║
║          Automated Installation Complete                     ║
╚══════════════════════════════════════════════════════════════╝

Default Credentials:
  Root:     SecureRoot2024!
  User:     sysadmin / Admin2024!Secure

Snapshot Management:
  snapshot-create [description]  - Create new snapshot
  snapshot-rollback              - Rollback to last snapshot
  snapshot-list                  - List all snapshots
  snapshot-cleanup               - Clean old snapshots
  system-info                    - Display system information

Run system-info for complete system details.

MOTDEOF

echo "=== [$(date)] Btrfs Post-Installation Complete ==="
echo "Installation log: /var/log/preseed-post-install.log"