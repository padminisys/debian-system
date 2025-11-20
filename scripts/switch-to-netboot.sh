#!/bin/bash
# Switch from netinst ISO extraction to official Debian netboot files
# This fixes the "couldn't mount installation media" error

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Switch to Official Debian Netboot Files                 ║"
echo "║     Fixes: 'couldn't mount installation media' error        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

check_root

log_step "Downloading official Debian netboot files..."
NETBOOT_URL="http://deb.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/netboot.tar.gz"
TEMP_DIR="/tmp/debian-netboot-$$"
mkdir -p "$TEMP_DIR"

if ! wget -q --show-progress "$NETBOOT_URL" -O "$TEMP_DIR/netboot.tar.gz"; then
    log_error "Failed to download netboot.tar.gz"
    rm -rf "$TEMP_DIR"
    exit 1
fi
log_success "Downloaded netboot.tar.gz"

log_step "Extracting netboot files..."
cd "$TEMP_DIR"
tar -xzf netboot.tar.gz
log_success "Extracted netboot files"

log_step "Backing up current files..."
TFTP_ROOT="/srv/tftp"
BACKUP_DIR="/srv/tftp-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r "$TFTP_ROOT/debian-installer" "$BACKUP_DIR/" 2>/dev/null || true
log_success "Backup created at $BACKUP_DIR"

log_step "Installing official netboot kernel and initrd..."
# The netboot files use 'linux' instead of 'vmlinuz'
cp "$TEMP_DIR/debian-installer/amd64/linux" "$TFTP_ROOT/debian-installer/vmlinuz"
cp "$TEMP_DIR/debian-installer/amd64/initrd.gz" "$TFTP_ROOT/debian-installer/initrd.gz"

# Set correct ownership
chown -R dnsmasq:nogroup "$TFTP_ROOT/debian-installer/"
log_success "Netboot files installed"

log_step "Verifying installation..."
if [ ! -f "$TFTP_ROOT/debian-installer/vmlinuz" ]; then
    log_error "vmlinuz not found after installation"
    exit 1
fi

if [ ! -f "$TFTP_ROOT/debian-installer/initrd.gz" ]; then
    log_error "initrd.gz not found after installation"
    exit 1
fi

# Check file sizes
INITRD_SIZE=$(stat -c%s "$TFTP_ROOT/debian-installer/initrd.gz")
if [ "$INITRD_SIZE" -lt 30000000 ]; then
    log_error "initrd.gz seems too small ($INITRD_SIZE bytes)"
    log_error "Expected ~40MB for netboot initrd"
    exit 1
fi

log_success "Files verified (initrd.gz: $(numfmt --to=iec-i --suffix=B $INITRD_SIZE))"

log_step "Cleaning up..."
rm -rf "$TEMP_DIR"
log_success "Cleanup complete"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    SUCCESS                                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
log_info "Official Debian netboot files installed"
log_info "Backup location: $BACKUP_DIR"
echo ""
log_info "Key Differences:"
echo "  • Netboot initrd: ~40MB (pure network boot)"
echo "  • Netinst initrd: ~22MB (CD-ROM boot + network)"
echo ""
log_info "The netboot initrd has NO CD-ROM detection code"
log_info "This should resolve the 'couldn't mount installation media' error"
echo ""
log_info "Next steps:"
echo "  1. Restart dnsmasq: systemctl restart dnsmasq"
echo "  2. Test PXE boot on client machine"
echo "  3. Installation should proceed without CD-ROM errors"
echo ""