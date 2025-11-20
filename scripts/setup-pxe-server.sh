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

SOURCE_ISO="$ISO_DIR/debian-12.12.0-amd64-netinst.iso"
PRESEED_FILE="$PRESEED_DIR/pxe/btrfs-automated.cfg"

# Logging
LOG_FILE="/var/log/pxe-setup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_fail() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
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
    systemctl stop dnsmasq apache2 2>/dev/null || true
    
    log_info "✓ Services stopped for configuration"
}

setup_tftp_structure() {
    log_step "Setting up TFTP directory structure..."
    
    mkdir -p "$TFTP_ROOT"/{pxelinux.cfg,debian-installer}
    
    # Copy PXE boot files
    if [ ! -f /usr/lib/PXELINUX/pxelinux.0 ]; then
        log_fail "pxelinux.0 not found"
        exit 1
    fi
    cp /usr/lib/PXELINUX/pxelinux.0 "$TFTP_ROOT/"
    log_success "pxelinux.0 copied"
    
    if [ ! -d /usr/lib/syslinux/modules/bios ]; then
        log_fail "syslinux modules not found"
        exit 1
    fi
    cp /usr/lib/syslinux/modules/bios/*.c32 "$TFTP_ROOT/"
    log_success "syslinux modules copied"
    
    # Set ownership to dnsmasq user for tftp-secure mode
    chown -R dnsmasq:nogroup "$TFTP_ROOT"
    
    # Verify files
    if [ ! -f "$TFTP_ROOT/pxelinux.0" ]; then
        log_fail "pxelinux.0 not in TFTP root"
        exit 1
    fi
    
    log_success "TFTP structure created with correct permissions"
}

extract_netboot_files() {
    log_step "Extracting netboot files from netinst ISO..."
    
    if [ ! -f "$SOURCE_ISO" ]; then
        log_fail "Source ISO not found: $SOURCE_ISO"
        log_error "Please ensure debian-12.12.0-amd64-netinst.iso is in $ISO_DIR"
        exit 1
    fi
    log_success "Source ISO found"
    
    # Mount ISO temporarily
    local mount_point="/mnt/debian-iso-temp"
    mkdir -p "$mount_point"
    
    if ! mount -o loop "$SOURCE_ISO" "$mount_point"; then
        log_fail "Failed to mount ISO"
        exit 1
    fi
    log_success "ISO mounted"
    
    # Verify kernel and initrd exist in ISO
    if [ ! -f "$mount_point/install.amd/vmlinuz" ]; then
        log_fail "vmlinuz not found in ISO"
        umount "$mount_point"
        exit 1
    fi
    
    if [ ! -f "$mount_point/install.amd/initrd.gz" ]; then
        log_fail "initrd.gz not found in ISO"
        umount "$mount_point"
        exit 1
    fi
    
    # Extract kernel and initrd from netinst ISO
    cp "$mount_point/install.amd/vmlinuz" "$TFTP_ROOT/debian-installer/"
    log_success "vmlinuz extracted"
    
    cp "$mount_point/install.amd/initrd.gz" "$TFTP_ROOT/debian-installer/"
    log_success "initrd.gz extracted"
    
    # Set ownership for TFTP files
    chown -R dnsmasq:nogroup "$TFTP_ROOT/debian-installer/"
    
    umount "$mount_point"
    rmdir "$mount_point"
    
    # Verify extracted files
    if [ ! -f "$TFTP_ROOT/debian-installer/vmlinuz" ]; then
        log_fail "vmlinuz not in TFTP root"
        exit 1
    fi
    
    if [ ! -f "$TFTP_ROOT/debian-installer/initrd.gz" ]; then
        log_fail "initrd.gz not in TFTP root"
        exit 1
    fi
    
    log_success "Netboot files extracted and verified"
    log_info "Installation will use HTTP mirror (deb.debian.org)"
}

configure_pxe_menu() {
    log_step "Configuring PXE boot menu with CD-ROM detection fix..."
    
    cat > "$TFTP_ROOT/pxelinux.cfg/default" << EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT 100
MENU TITLE Debian 12.12 Btrfs PXE Boot

LABEL auto-install
    MENU LABEL ^1. Automated Btrfs Installation (Network)
    MENU DEFAULT
    KERNEL debian-installer/vmlinuz
    APPEND initrd=debian-installer/initrd.gz auto=true priority=critical preseed/url=http://${SERVER_IP}/preseed.cfg hw-detect/load_media=false netcfg/choose_interface=auto netcfg/get_hostname=debian-btrfs netcfg/get_domain=localdomain ---

LABEL manual
    MENU LABEL ^2. Manual Installation
    KERNEL debian-installer/vmlinuz
    APPEND initrd=debian-installer/initrd.gz hw-detect/load_media=false ---

LABEL rescue
    MENU LABEL ^3. Rescue Mode
    KERNEL debian-installer/vmlinuz
    APPEND initrd=debian-installer/initrd.gz rescue/enable=true ---

LABEL local
    MENU LABEL ^4. Boot from Local Disk
    LOCALBOOT 0
EOF
    
    # Set ownership for PXE config files
    chown -R dnsmasq:nogroup "$TFTP_ROOT/pxelinux.cfg/"
    
    # Verify the configuration was written correctly
    if ! grep -q "hw-detect/load_media=false" "$TFTP_ROOT/pxelinux.cfg/default"; then
        log_fail "CD-ROM detection fix NOT applied to PXE config"
        exit 1
    fi
    
    log_success "PXE menu configured with CD-ROM detection fix"
    log_info "✓ hw-detect/load_media=false added to boot parameters"
}

setup_http_server() {
    log_step "Setting up HTTP server for preseed..."
    
    mkdir -p "$HTTP_ROOT"
    
    # Verify preseed file exists
    if [ ! -f "$PRESEED_FILE" ]; then
        log_fail "Preseed file not found: $PRESEED_FILE"
        exit 1
    fi
    log_success "Preseed file found"
    
    # Copy preseed file
    cp "$PRESEED_FILE" "$HTTP_ROOT/preseed.cfg"
    
    # Verify preseed was copied
    if [ ! -f "$HTTP_ROOT/preseed.cfg" ]; then
        log_fail "Preseed file not copied to HTTP root"
        exit 1
    fi
    log_success "Preseed file copied to HTTP root"
    
    # Verify preseed has CD-ROM skip directives
    if ! grep -q "apt-setup/cdrom/set-first" "$HTTP_ROOT/preseed.cfg"; then
        log_warn "Preseed may be missing CD-ROM skip directives"
    else
        log_success "Preseed has CD-ROM skip directives"
    fi
    
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
    
    # Verify Apache config was created
    if [ ! -f /etc/apache2/sites-available/pxe.conf ]; then
        log_fail "Apache PXE config not created"
        exit 1
    fi
    log_success "Apache PXE config created"
    
    a2ensite pxe.conf
    a2dissite 000-default.conf || true
    
    log_success "HTTP server configured"
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
    
    # Enable services
    systemctl enable dnsmasq apache2
    log_success "Services enabled"
    
    # Start dnsmasq
    if ! systemctl restart dnsmasq; then
        log_fail "Failed to start dnsmasq"
        log_error "Check: journalctl -xeu dnsmasq"
        exit 1
    fi
    
    # Verify dnsmasq is running
    sleep 2
    if ! systemctl is-active --quiet dnsmasq; then
        log_fail "dnsmasq failed to start"
        exit 1
    fi
    log_success "dnsmasq started and running"
    
    # Start apache2
    if ! systemctl restart apache2; then
        log_fail "Failed to start apache2"
        log_error "Check: journalctl -xeu apache2"
        exit 1
    fi
    
    # Verify apache2 is running
    sleep 2
    if ! systemctl is-active --quiet apache2; then
        log_fail "apache2 failed to start"
        exit 1
    fi
    log_success "apache2 started and running"
}

verify_setup() {
    log_step "Verifying PXE server setup..."
    
    local errors=0
    
    echo ""
    log_info "=== File Verification ==="
    
    # Check TFTP files
    if [ ! -f "$TFTP_ROOT/pxelinux.0" ]; then
        log_fail "TFTP boot file missing"
        ((errors++))
    else
        log_success "pxelinux.0 present"
    fi
    
    if [ ! -f "$TFTP_ROOT/debian-installer/vmlinuz" ]; then
        log_fail "vmlinuz missing"
        ((errors++))
    else
        log_success "vmlinuz present"
    fi
    
    if [ ! -f "$TFTP_ROOT/debian-installer/initrd.gz" ]; then
        log_fail "initrd.gz missing"
        ((errors++))
    else
        log_success "initrd.gz present"
    fi
    
    if [ ! -f "$TFTP_ROOT/pxelinux.cfg/default" ]; then
        log_fail "PXE config missing"
        ((errors++))
    else
        log_success "PXE config present"
    fi
    
    echo ""
    log_info "=== CD-ROM Detection Fix Verification ==="
    
    # CRITICAL: Verify CD-ROM detection fix
    if ! grep -q "hw-detect/load_media=false" "$TFTP_ROOT/pxelinux.cfg/default"; then
        log_fail "CD-ROM detection fix NOT in PXE config"
        ((errors++))
    else
        log_success "hw-detect/load_media=false present in PXE config"
    fi
    
    echo ""
    log_info "=== HTTP Preseed Verification ==="
    
    # Check HTTP preseed accessibility
    if ! curl -s "http://localhost/preseed.cfg" > /dev/null; then
        log_fail "HTTP preseed not accessible"
        ((errors++))
    else
        log_success "HTTP preseed accessible"
        
        # Test from server IP
        if curl -s "http://${SERVER_IP}/preseed.cfg" > /dev/null; then
            log_success "Preseed accessible via server IP"
        else
            log_warn "Preseed not accessible via server IP (may be firewall)"
        fi
    fi
    
    echo ""
    log_info "=== Service Verification ==="
    
    # Check services
    for service in dnsmasq apache2; do
        if ! systemctl is-active --quiet $service; then
            log_fail "Service $service is not running"
            ((errors++))
        else
            log_success "Service $service is running"
        fi
    done
    
    echo ""
    
    if [ $errors -eq 0 ]; then
        log_success "All verification checks passed"
        return 0
    else
        log_fail "Setup verification failed with $errors errors"
        return 1
    fi
}

configure_firewall() {
    log_step "Configuring firewall..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 67/udp  # DHCP
        ufw allow 69/udp  # TFTP
        ufw allow 80/tcp  # HTTP
        log_info "✓ Firewall rules added"
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
    echo "  ISO:          debian-12.12.0-amd64-netinst.iso"
    echo ""
    echo "Services Running:"
    echo "  TFTP:         $TFTP_ROOT (boot files)"
    echo "  HTTP:         http://$SERVER_IP/preseed.cfg"
    echo ""
    echo -e "${GREEN}CD-ROM Detection Fix Applied:${NC}"
    echo "  ✓ hw-detect/load_media=false in boot parameters"
    echo "  ✓ Preseed configured to skip CD-ROM detection"
    echo ""
    echo "Boot Parameters (Automated Install):"
    echo -e "${CYAN}  APPEND initrd=debian-installer/initrd.gz auto=true priority=critical"
    echo "         preseed/url=http://${SERVER_IP}/preseed.cfg"
    echo -e "         ${GREEN}hw-detect/load_media=false${CYAN}"
    echo "         netcfg/choose_interface=auto"
    echo -e "         netcfg/get_hostname=debian-btrfs netcfg/get_domain=localdomain ---${NC}"
    echo ""
    echo "Installation Method:"
    echo "  Type:         Network Installation (netinst)"
    echo "  Mirror:       deb.debian.org (HTTP)"
    echo "  Packages:     Downloaded from internet during installation"
    echo ""
    echo "Client Boot Instructions:"
    echo "  1. Connect client machine to same network"
    echo "  2. Ensure client has internet access"
    echo "  3. Enable PXE/Network boot in BIOS"
    echo "  4. Boot from network"
    echo "  5. Select 'Automated Btrfs Installation (Network)'"
    echo "  6. Installation completes in 10-15 minutes"
    echo ""
    echo "Default Credentials:"
    echo "  Root:     SecureRoot2024!"
    echo "  User:     sysadmin / Admin2024!Secure"
    echo ""
    echo "Verification:"
    echo "  Run: sudo ./scripts/verify-pxe-config.sh"
    echo ""
    echo "Testing:"
    echo "  curl http://$SERVER_IP/preseed.cfg"
    echo "  systemctl status dnsmasq apache2"
    echo ""
    echo -e "${YELLOW}Log file: $LOG_FILE${NC}"
    echo ""
}

main() {
    # Initialize log
    echo "=== PXE Server Setup - $(date) ===" > "$LOG_FILE"
    
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
    configure_dnsmasq
    configure_firewall
    start_services
    
    if verify_setup; then
        print_summary
    else
        echo ""
        log_error "Setup completed with errors - please review above"
        log_error "Check log file: $LOG_FILE"
        exit 1
    fi
}

main "$@"