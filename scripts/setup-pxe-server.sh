#!/bin/bash
# PXE Server Setup for Debian 12.12 Btrfs Automated Installation
# Configures TFTP, DHCP, and HTTP services for network boot

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PXE_DIR="$PROJECT_ROOT/pxe"
PRESEED_DIR="$PROJECT_ROOT/preseed"
ISO_DIR="$PROJECT_ROOT/iso"

TFTP_ROOT="/srv/tftp"
HTTP_ROOT="/srv/http"
NFS_ROOT="/srv/nfs"

SOURCE_ISO="$ISO_DIR/debian-12.12.0-amd64-DVD-1.iso"
PRESEED_FILE="$PRESEED_DIR/btrfs-automated.cfg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

detect_network_interface() {
    log_step "Detecting network interface..."
    
    # Prefer ethernet over wifi
    local eth_iface=$(ip -br link show | grep -E "^(eth|enp|eno)" | grep "UP" | head -n1 | awk '{print $1}')
    
    if [ -n "$eth_iface" ]; then
        NETWORK_INTERFACE="$eth_iface"
        log_info "Using ethernet interface: $NETWORK_INTERFACE"
    else
        local wifi_iface=$(ip -br link show | grep -E "^(wlan|wlp)" | grep "UP" | head -n1 | awk '{print $1}')
        if [ -n "$wifi_iface" ]; then
            NETWORK_INTERFACE="$wifi_iface"
            log_warn "Using WiFi interface: $NETWORK_INTERFACE"
        else
            log_error "No active network interface found"
            exit 1
        fi
    fi
    
    # Get IP address
    SERVER_IP=$(ip -4 addr show "$NETWORK_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    
    if [ -z "$SERVER_IP" ]; then
        log_error "Could not determine server IP address"
        exit 1
    fi
    
    log_info "Server IP: $SERVER_IP"
    
    # Calculate network range
    NETWORK_PREFIX=$(echo "$SERVER_IP" | cut -d. -f1-3)
    DHCP_RANGE_START="${NETWORK_PREFIX}.100"
    DHCP_RANGE_END="${NETWORK_PREFIX}.200"
    
    log_info "DHCP Range: $DHCP_RANGE_START - $DHCP_RANGE_END"
}

install_dependencies() {
    log_step "Installing PXE server dependencies..."
    
    apt update
    apt install -y \
        dnsmasq \
        pxelinux \
        syslinux-common \
        apache2 \
        nfs-kernel-server \
        bsdtar
    
    # Stop services for configuration
    systemctl stop dnsmasq apache2 nfs-server || true
    
    log_info "Dependencies installed"
}

setup_tftp_structure() {
    log_step "Setting up TFTP directory structure..."
    
    mkdir -p "$TFTP_ROOT"/{pxelinux.cfg,debian-installer}
    
    # Copy PXE boot files
    cp /usr/lib/PXELINUX/pxelinux.0 "$TFTP_ROOT/"
    cp /usr/lib/syslinux/modules/bios/*.c32 "$TFTP_ROOT/"
    
    log_info "TFTP structure created"
}

extract_netboot_files() {
    log_step "Extracting netboot files from ISO..."
    
    if [ ! -f "$SOURCE_ISO" ]; then
        log_error "Source ISO not found: $SOURCE_ISO"
        exit 1
    fi
    
    # Mount ISO temporarily
    local mount_point="/mnt/debian-iso-temp"
    mkdir -p "$mount_point"
    mount -o loop "$SOURCE_ISO" "$mount_point"
    
    # Extract kernel and initrd
    cp "$mount_point/install.amd/vmlinuz" "$TFTP_ROOT/debian-installer/"
    cp "$mount_point/install.amd/initrd.gz" "$TFTP_ROOT/debian-installer/"
    
    # Setup NFS export for ISO content
    mkdir -p "$NFS_ROOT/debian"
    rsync -av "$mount_point/" "$NFS_ROOT/debian/"
    
    umount "$mount_point"
    rmdir "$mount_point"
    
    log_info "Netboot files extracted"
}

configure_pxe_menu() {
    log_step "Configuring PXE boot menu..."
    
    cat > "$TFTP_ROOT/pxelinux.cfg/default" << EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT 100
MENU TITLE Debian 12.12 Btrfs PXE Boot

LABEL auto-install
    MENU LABEL ^1. Automated Btrfs Installation
    MENU DEFAULT
    KERNEL debian-installer/vmlinuz
    APPEND initrd=debian-installer/initrd.gz auto=true priority=critical url=http://${SERVER_IP}/preseed.cfg netcfg/choose_interface=${NETWORK_INTERFACE} quiet splash ---

LABEL manual
    MENU LABEL ^2. Manual Installation
    KERNEL debian-installer/vmlinuz
    APPEND initrd=debian-installer/initrd.gz quiet ---

LABEL rescue
    MENU LABEL ^3. Rescue Mode
    KERNEL debian-installer/vmlinuz
    APPEND initrd=debian-installer/initrd.gz rescue/enable=true quiet ---

LABEL local
    MENU LABEL ^4. Boot from Local Disk
    LOCALBOOT 0
EOF
    
    log_info "PXE menu configured"
}

setup_http_server() {
    log_step "Setting up HTTP server for preseed..."
    
    mkdir -p "$HTTP_ROOT"
    
    # Copy preseed file
    cp "$PRESEED_FILE" "$HTTP_ROOT/preseed.cfg"
    
    # Modify preseed to use NFS for installation
    sed -i "s|d-i mirror/http/hostname string deb.debian.org|d-i mirror/protocol string nfs\nd-i mirror/nfs/server string ${SERVER_IP}\nd-i mirror/nfs/directory string /srv/nfs/debian|" "$HTTP_ROOT/preseed.cfg"
    
    # Configure Apache
    cat > /etc/apache2/sites-available/pxe.conf << EOF
<VirtualHost *:80>
    DocumentRoot $HTTP_ROOT
    <Directory $HTTP_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF
    
    a2ensite pxe.conf
    a2dissite 000-default.conf || true
    
    log_info "HTTP server configured"
}

setup_nfs_server() {
    log_step "Setting up NFS server..."
    
    # Configure NFS exports
    cat > /etc/exports << EOF
$NFS_ROOT/debian *(ro,sync,no_subtree_check,no_root_squash)
EOF
    
    exportfs -ra
    
    log_info "NFS server configured"
}

configure_dnsmasq() {
    log_step "Configuring dnsmasq (DHCP + TFTP)..."
    
    # Backup original config
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
    
    cat > /etc/dnsmasq.conf << EOF
# PXE Server Configuration for Debian Btrfs Installation

# Interface to listen on
interface=${NETWORK_INTERFACE}
bind-interfaces

# DHCP Configuration
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},12h
dhcp-option=3,${SERVER_IP}
dhcp-option=6,${SERVER_IP}

# PXE Boot Configuration
dhcp-boot=pxelinux.0

# TFTP Configuration
enable-tftp
tftp-root=${TFTP_ROOT}

# Logging
log-dhcp
log-queries

# DNS
no-resolv
server=8.8.8.8
server=8.8.4.4
EOF
    
    log_info "dnsmasq configured"
}

start_services() {
    log_step "Starting PXE services..."
    
    systemctl enable dnsmasq apache2 nfs-server
    systemctl restart dnsmasq apache2 nfs-server
    
    log_info "Services started"
}

verify_setup() {
    log_step "Verifying PXE server setup..."
    
    local errors=0
    
    # Check TFTP files
    if [ ! -f "$TFTP_ROOT/pxelinux.0" ]; then
        log_error "TFTP boot file missing"
        ((errors++))
    fi
    
    # Check HTTP preseed
    if ! curl -s "http://localhost/preseed.cfg" > /dev/null; then
        log_error "HTTP preseed not accessible"
        ((errors++))
    fi
    
    # Check services
    for service in dnsmasq apache2 nfs-server; do
        if ! systemctl is-active --quiet $service; then
            log_error "Service $service is not running"
            ((errors++))
        fi
    done
    
    if [ $errors -eq 0 ]; then
        log_info "All checks passed"
        return 0
    else
        log_error "Setup verification failed with $errors errors"
        return 1
    fi
}

configure_firewall() {
    log_step "Configuring firewall..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 67/udp  # DHCP
        ufw allow 69/udp  # TFTP
        ufw allow 80/tcp  # HTTP
        ufw allow 2049/tcp # NFS
        ufw allow 111/tcp  # RPC
        log_info "Firewall rules added"
    else
        log_warn "UFW not installed, skipping firewall configuration"
    fi
}

print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          PXE Server Setup Complete                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Server Configuration:"
    echo "  Interface:    $NETWORK_INTERFACE"
    echo "  Server IP:    $SERVER_IP"
    echo "  DHCP Range:   $DHCP_RANGE_START - $DHCP_RANGE_END"
    echo ""
    echo "Services Running:"
    echo "  TFTP:         $TFTP_ROOT"
    echo "  HTTP:         http://$SERVER_IP/preseed.cfg"
    echo "  NFS:          $NFS_ROOT/debian"
    echo ""
    echo "Client Boot Instructions:"
    echo "  1. Connect client machine to same network"
    echo "  2. Enable PXE/Network boot in BIOS"
    echo "  3. Boot from network"
    echo "  4. Select 'Automated Btrfs Installation'"
    echo "  5. Installation completes in 5-10 minutes"
    echo ""
    echo "Default Credentials:"
    echo "  Root:     SecureRoot2024!"
    echo "  User:     sysadmin / Admin2024!Secure"
    echo ""
    echo "Testing:"
    echo "  curl http://$SERVER_IP/preseed.cfg"
    echo "  systemctl status dnsmasq apache2 nfs-server"
    echo ""
}

main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     PXE Server Setup - Debian 12.12 Btrfs Installation      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_root
    detect_network_interface
    install_dependencies
    setup_tftp_structure
    extract_netboot_files
    configure_pxe_menu
    setup_http_server
    setup_nfs_server
    configure_dnsmasq
    configure_firewall
    start_services
    verify_setup
    print_summary
}

main "$@"