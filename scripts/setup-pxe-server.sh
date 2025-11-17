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
PRESEED_FILE="$PRESEED_DIR/pxe/btrfs-automated.cfg"

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
    
    # Show all interfaces for debugging
    log_info "Available interfaces with IP addresses:"
    ip -br addr show | grep -v "127.0.0.1" | grep -E "UP.*[0-9]+\.[0-9]+" | while read line; do
        echo "  $line"
    done
    echo ""
    
    # Check for ethernet first
    local eth_iface=$(ip -br addr show | grep -E "^(eth|enp|eno)" | grep "UP" | grep -oE "^[^ ]+" | head -n1)
    local eth_has_ip=""
    if [ -n "$eth_iface" ]; then
        eth_has_ip=$(ip -4 addr show "$eth_iface" | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    
    # Check for WiFi
    local wifi_iface=$(ip -br addr show | grep -E "^(wlan|wlp)" | grep "UP" | grep -oE "^[^ ]+" | head -n1)
    local wifi_has_ip=""
    if [ -n "$wifi_iface" ]; then
        wifi_has_ip=$(ip -4 addr show "$wifi_iface" | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    
    # Prefer ethernet with IP, otherwise use WiFi
    if [ -n "$eth_has_ip" ]; then
        NETWORK_INTERFACE="$eth_iface"
        SERVER_IP="$eth_has_ip"
        log_info "✓ Using Ethernet: $NETWORK_INTERFACE"
    elif [ -n "$wifi_has_ip" ]; then
        NETWORK_INTERFACE="$wifi_iface"
        SERVER_IP="$wifi_has_ip"
        log_info "✓ Using WiFi: $NETWORK_INTERFACE"
        log_warn "Note: WiFi PXE works fine for LAN, but ensure stable connection"
    else
        log_error "No network interface with IP address found"
        log_error "Please ensure your network interface has an IP assigned"
        exit 1
    fi
    
    log_info "✓ Server IP: $SERVER_IP"
    
    # Confirmation prompt
    echo ""
    log_warn "PXE Server Configuration (Proxy DHCP Mode):"
    echo "  Interface: $NETWORK_INTERFACE"
    echo "  Server IP: $SERVER_IP"
    echo "  Mode: Proxy DHCP (Router assigns IPs, PXE server provides boot info)"
    echo ""
    read -p "Continue with this configuration? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Setup cancelled by user"
        exit 0
    fi
}

install_dependencies() {
    log_step "Installing PXE server dependencies..."
    
    # Update package list
    if apt update 2>&1 | grep -q "Failed"; then
        log_warn "Some package sources failed, continuing with available sources"
    fi
    
    # Install dependencies
    local packages=(
        "dnsmasq"
        "pxelinux"
        "syslinux-common"
        "apache2"
        "nfs-kernel-server"
        "libarchive-tools"
        "rsync"
        "curl"
    )
    
    log_info "Installing: ${packages[*]}"
    
    if apt install -y "${packages[@]}"; then
        log_info "✓ Dependencies installed successfully"
    else
        log_error "Failed to install some dependencies"
        exit 1
    fi
    
    # Stop services for configuration
    systemctl stop dnsmasq apache2 nfs-server 2>/dev/null || true
    
    log_info "✓ Services stopped for configuration"
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
    APPEND initrd=debian-installer/initrd.gz auto=true priority=critical preseed/url=http://${SERVER_IP}/preseed.cfg netcfg/choose_interface=auto ---

LABEL manual
    MENU LABEL ^2. Manual Installation
    KERNEL debian-installer/vmlinuz
    APPEND initrd=debian-installer/initrd.gz ---

LABEL rescue
    MENU LABEL ^3. Rescue Mode
    KERNEL debian-installer/vmlinuz
    APPEND initrd=debian-installer/initrd.gz rescue/enable=true ---

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
    
    # Modify preseed to use local NFS mount for installation
    sed -i '/d-i mirror\/http\/hostname/d' "$HTTP_ROOT/preseed.cfg"
    sed -i '/d-i mirror\/http\/directory/d' "$HTTP_ROOT/preseed.cfg"
    sed -i '/d-i mirror\/http\/proxy/d' "$HTTP_ROOT/preseed.cfg"
    
    # Add NFS mount configuration after mirror section
    sed -i '/### Mirror/a\
d-i mirror/protocol string file\
d-i mirror/country string manual\
d-i mirror/file/hostname string\
d-i mirror/file/directory string /media/cdrom\
d-i apt-setup/cdrom/set-first boolean false\
d-i apt-setup/cdrom/set-next boolean false\
d-i apt-setup/cdrom/set-failed boolean false' "$HTTP_ROOT/preseed.cfg"
    
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
    log_step "Configuring dnsmasq (Proxy DHCP + TFTP)..."
    
    # Backup original config
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup 2>/dev/null || true
    
    cat > /etc/dnsmasq.conf << EOF
# PXE Server Configuration - Proxy DHCP Mode
# Router provides IP addresses, dnsmasq only provides PXE boot info

# Interface to listen on
interface=${NETWORK_INTERFACE}
bind-interfaces

# Proxy DHCP - Do NOT assign IP addresses
# Router DHCP handles IP assignment
dhcp-range=${SERVER_IP},proxy

# PXE Boot Configuration
dhcp-boot=pxelinux.0,${SERVER_IP},${SERVER_IP}

# Alternative: Use pxe-service for more explicit PXE
pxe-service=x86PC,"Network Boot",pxelinux

# TFTP Configuration
enable-tftp
tftp-root=${TFTP_ROOT}
tftp-secure

# Logging
log-dhcp
log-queries

# Do not provide DNS service
port=0
EOF
    
    log_info "dnsmasq configured in Proxy DHCP mode"
    log_info "Router will assign IP addresses, dnsmasq only provides PXE boot info"
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
    echo "  Mode:         Proxy DHCP (Router provides IPs)"
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