#!/bin/bash
# Debian 12.12 Custom ISO Builder with Btrfs + Snapper
# Extracts DVD ISO and embeds preseed for automated installation

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ISO_DIR="$PROJECT_ROOT/iso"
BUILD_DIR="$PROJECT_ROOT/build"
PRESEED_DIR="$PROJECT_ROOT/preseed"
OUTPUT_DIR="$PROJECT_ROOT/output"

SOURCE_ISO="$ISO_DIR/debian-12.12.0-amd64-DVD-1.iso"
PRESEED_FILE="$PRESEED_DIR/btrfs-automated.cfg"
OUTPUT_ISO="$OUTPUT_DIR/debian-12.12-btrfs-automated.iso"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log_info "Checking dependencies..."
    local missing_deps=()
    
    for cmd in xorriso bsdtar genisoimage isolinux; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Installing dependencies..."
        sudo apt update
        sudo apt install -y xorriso libarchive-tools genisoimage isolinux syslinux-utils
    else
        log_info "All dependencies satisfied"
    fi
}

verify_source_iso() {
    log_info "Verifying source ISO..."
    
    if [ ! -f "$SOURCE_ISO" ]; then
        log_error "Source ISO not found: $SOURCE_ISO"
        log_error "Please download Debian 12.12 DVD ISO to: $ISO_DIR/"
        exit 1
    fi
    
    local iso_size=$(stat -f%z "$SOURCE_ISO" 2>/dev/null || stat -c%s "$SOURCE_ISO" 2>/dev/null)
    log_info "Source ISO found: $(basename $SOURCE_ISO) ($(numfmt --to=iec-i --suffix=B $iso_size))"
}

verify_preseed() {
    log_info "Verifying preseed configuration..."
    
    if [ ! -f "$PRESEED_FILE" ]; then
        log_error "Preseed file not found: $PRESEED_FILE"
        exit 1
    fi
    
    log_info "Preseed configuration found: $(basename $PRESEED_FILE)"
}

prepare_build_directory() {
    log_info "Preparing build directory..."
    
    if [ -d "$BUILD_DIR/iso-extract" ]; then
        log_warn "Removing existing build directory..."
        rm -rf "$BUILD_DIR/iso-extract"
    fi
    
    mkdir -p "$BUILD_DIR/iso-extract"
    mkdir -p "$OUTPUT_DIR"
}

extract_iso() {
    log_info "Extracting source ISO (this may take several minutes)..."
    
    cd "$BUILD_DIR"
    bsdtar -C iso-extract -xf "$SOURCE_ISO"
    
    # Make extracted files writable
    chmod -R u+w iso-extract/
    
    log_info "ISO extraction complete"
}

embed_preseed() {
    log_info "Embedding preseed configuration..."
    
    cp "$PRESEED_FILE" "$BUILD_DIR/iso-extract/preseed.cfg"
    
    log_info "Preseed embedded successfully"
}

configure_isolinux() {
    log_info "Configuring ISOLINUX (BIOS boot)..."
    
    local isolinux_cfg="$BUILD_DIR/iso-extract/isolinux/isolinux.cfg"
    
    # Backup original
    cp "$isolinux_cfg" "$isolinux_cfg.orig"
    
    # Create new isolinux configuration
    cat > "$isolinux_cfg" << 'EOF'
default auto-install
timeout 50
prompt 0

label auto-install
    menu label ^Automated Btrfs Installation
    kernel /install.amd/vmlinuz
    append auto=true priority=critical vga=788 initrd=/install.amd/initrd.gz preseed/file=/cdrom/preseed.cfg quiet splash ---

label manual
    menu label ^Manual Installation
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/initrd.gz --- quiet

label rescue
    menu label ^Rescue Mode
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/initrd.gz rescue/enable=true --- quiet
EOF
    
    log_info "ISOLINUX configured for automated installation"
}

configure_grub() {
    log_info "Configuring GRUB (UEFI boot)..."
    
    local grub_cfg="$BUILD_DIR/iso-extract/boot/grub/grub.cfg"
    
    # Backup original
    if [ -f "$grub_cfg" ]; then
        cp "$grub_cfg" "$grub_cfg.orig"
    fi
    
    # Create new GRUB configuration
    cat > "$grub_cfg" << 'EOF'
set default=0
set timeout=5

menuentry "Automated Btrfs Installation" {
    set gfxpayload=keep
    linux   /install.amd/vmlinuz auto=true priority=critical preseed/file=/cdrom/preseed.cfg quiet splash ---
    initrd  /install.amd/initrd.gz
}

menuentry "Manual Installation" {
    set gfxpayload=keep
    linux   /install.amd/vmlinuz quiet ---
    initrd  /install.amd/initrd.gz
}

menuentry "Rescue Mode" {
    set gfxpayload=keep
    linux   /install.amd/vmlinuz rescue/enable=true quiet ---
    initrd  /install.amd/initrd.gz
}
EOF
    
    log_info "GRUB configured for automated installation"
}

update_md5sums() {
    log_info "Updating MD5 checksums..."
    
    cd "$BUILD_DIR/iso-extract"
    
    # Remove old checksums
    rm -f md5sum.txt
    
    # Generate new checksums
    find . -type f ! -name "md5sum.txt" ! -path "./isolinux/*" -exec md5sum {} \; > md5sum.txt
    
    log_info "MD5 checksums updated"
}

build_iso() {
    log_info "Building custom ISO..."
    
    cd "$BUILD_DIR"
    
    xorriso -as mkisofs \
        -r -V "Debian 12.12 Btrfs Auto" \
        -o "$OUTPUT_ISO" \
        -J -joliet-long \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -c isolinux/boot.cat \
        -b isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        iso-extract/
    
    log_info "ISO build complete"
}

verify_output() {
    log_info "Verifying output ISO..."
    
    if [ ! -f "$OUTPUT_ISO" ]; then
        log_error "Output ISO not found!"
        exit 1
    fi
    
    local iso_size=$(stat -f%z "$OUTPUT_ISO" 2>/dev/null || stat -c%s "$OUTPUT_ISO" 2>/dev/null)
    log_info "Output ISO: $(basename $OUTPUT_ISO)"
    log_info "Size: $(numfmt --to=iec-i --suffix=B $iso_size)"
    log_info "Location: $OUTPUT_ISO"
}

cleanup() {
    log_info "Cleaning up build directory..."
    rm -rf "$BUILD_DIR/iso-extract"
    log_info "Cleanup complete"
}

print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          Custom ISO Build Complete                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Output ISO: $OUTPUT_ISO"
    echo ""
    echo "Next Steps:"
    echo "  1. Flash to USB:"
    echo "     sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress conv=fsync"
    echo ""
    echo "  2. Boot from USB - Installation will start automatically"
    echo ""
    echo "  3. Default Credentials:"
    echo "     Root:     SecureRoot2024!"
    echo "     User:     sysadmin / Admin2024!Secure"
    echo ""
    echo "  4. After installation, run: system-info"
    echo ""
    echo "For PXE deployment, run: ./scripts/setup-pxe-server.sh"
    echo ""
}

main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Debian 12.12 Custom ISO Builder - Btrfs + Snapper       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_dependencies
    verify_source_iso
    verify_preseed
    prepare_build_directory
    extract_iso
    embed_preseed
    configure_isolinux
    configure_grub
    update_md5sums
    build_iso
    verify_output
    cleanup
    print_summary
}

main "$@"