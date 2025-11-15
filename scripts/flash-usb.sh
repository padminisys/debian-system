#!/bin/bash
# USB Flash Helper Script
# Safely flash custom ISO to USB drive

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

find_iso() {
    local iso_path="$1"
    
    if [ -z "$iso_path" ]; then
        # Try to find ISO in output directory
        local project_root="$(dirname "$(dirname "$(readlink -f "$0")")")"
        iso_path="$project_root/output/debian-12.12-btrfs-automated.iso"
    fi
    
    if [ ! -f "$iso_path" ]; then
        log_error "ISO file not found: $iso_path"
        log_info "Please build the ISO first: ./scripts/build-custom-iso.sh"
        exit 1
    fi
    
    echo "$iso_path"
}

list_usb_devices() {
    log_info "Available USB devices:"
    echo ""
    lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL | grep -E "usb|NAME"
    echo ""
}

confirm_device() {
    local device="$1"
    
    if [ ! -b "$device" ]; then
        log_error "Device $device does not exist"
        exit 1
    fi
    
    # Get device info
    local size=$(lsblk -d -n -o SIZE "$device")
    local model=$(lsblk -d -n -o MODEL "$device")
    
    echo ""
    log_warn "WARNING: This will ERASE all data on $device"
    echo "  Device: $device"
    echo "  Size:   $size"
    echo "  Model:  $model"
    echo ""
    
    # Check if device is mounted
    if mount | grep -q "^$device"; then
        log_warn "Device is currently mounted. Unmounting..."
        umount ${device}* 2>/dev/null || true
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Operation cancelled"
        exit 0
    fi
}

flash_iso() {
    local iso_path="$1"
    local device="$2"
    
    log_info "Flashing ISO to $device..."
    log_info "This may take several minutes..."
    
    dd if="$iso_path" of="$device" bs=4M status=progress conv=fsync
    
    sync
    
    log_info "Flash complete!"
}

print_usage() {
    echo "Usage: $0 [ISO_PATH] [DEVICE]"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive mode"
    echo "  $0 /path/to/iso.iso /dev/sdb          # Direct mode"
    echo ""
}

main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          USB Flash Helper - Debian Btrfs ISO                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_root
    
    local iso_path="${1:-}"
    local device="${2:-}"
    
    # Find ISO
    iso_path=$(find_iso "$iso_path")
    log_info "Using ISO: $iso_path"
    
    # Interactive device selection if not provided
    if [ -z "$device" ]; then
        list_usb_devices
        read -p "Enter device path (e.g., /dev/sdb): " device
    fi
    
    # Validate and confirm
    confirm_device "$device"
    
    # Flash
    flash_iso "$iso_path" "$device"
    
    echo ""
    log_info "USB drive ready for installation!"
    log_info "Boot from this USB to start automated installation"
    echo ""
}

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    print_usage
    exit 0
fi

main "$@"