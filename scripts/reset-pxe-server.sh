#!/bin/bash
# Complete PXE Server Reset Script
# Stops all services, kills stuck processes, removes all configurations
# Provides a clean slate for fresh PXE server setup

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
LOG_FILE="/var/log/pxe-reset.log"

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

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

stop_services() {
    log_step "Stopping all PXE-related services..."
    
    local services=("dnsmasq" "apache2" "nfs-server" "nfs-kernel-server")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Stopping $service..."
            systemctl stop "$service" 2>/dev/null || true
            log_success "$service stopped"
        else
            log_info "$service not running"
        fi
    done
    
    # Disable services to prevent auto-start
    for service in "${services[@]}"; do
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            systemctl disable "$service" 2>/dev/null || true
        fi
    done
    
    log_success "All services stopped and disabled"
}

kill_stuck_processes() {
    log_step "Killing any stuck processes..."
    
    # Kill dnsmasq processes
    if pgrep -x dnsmasq > /dev/null; then
        log_info "Killing dnsmasq processes..."
        pkill -9 dnsmasq 2>/dev/null || true
        sleep 1
        log_success "dnsmasq processes killed"
    fi
    
    # Kill apache2 processes
    if pgrep -x apache2 > /dev/null; then
        log_info "Killing apache2 processes..."
        pkill -9 apache2 2>/dev/null || true
        sleep 1
        log_success "apache2 processes killed"
    fi
    
    # Kill any NFS processes
    if pgrep -x nfsd > /dev/null; then
        log_info "Killing NFS processes..."
        pkill -9 nfsd 2>/dev/null || true
        sleep 1
        log_success "NFS processes killed"
    fi
    
    log_success "All stuck processes killed"
}

remove_configurations() {
    log_step "Removing all PXE configurations..."
    
    # Backup dnsmasq config if it exists
    if [ -f /etc/dnsmasq.conf ]; then
        log_info "Backing up dnsmasq.conf to /etc/dnsmasq.conf.pre-reset"
        cp /etc/dnsmasq.conf /etc/dnsmasq.conf.pre-reset
    fi
    
    # Reset dnsmasq to default
    if [ -f /etc/dnsmasq.conf ]; then
        log_info "Resetting dnsmasq.conf to default..."
        cat > /etc/dnsmasq.conf << 'EOF'
# Configuration file for dnsmasq.
# See http://www.thekelleys.org.uk/dnsmasq/doc.html for options.

# Uncomment to enable DHCP
#dhcp-range=192.168.1.50,192.168.1.150,12h

# Uncomment to enable TFTP
#enable-tftp
#tftp-root=/srv/tftp
EOF
        log_success "dnsmasq.conf reset to default"
    fi
    
    # Remove Apache PXE site config
    if [ -f /etc/apache2/sites-available/pxe.conf ]; then
        log_info "Removing Apache PXE site configuration..."
        a2dissite pxe.conf 2>/dev/null || true
        rm -f /etc/apache2/sites-available/pxe.conf
        log_success "Apache PXE site removed"
    fi
    
    # Re-enable default Apache site
    if [ -f /etc/apache2/sites-available/000-default.conf ]; then
        a2ensite 000-default.conf 2>/dev/null || true
        log_success "Apache default site re-enabled"
    fi
    
    log_success "All configurations removed"
}

clean_directories() {
    log_step "Cleaning PXE directories..."
    
    local dirs=("/srv/tftp" "/srv/http" "/srv/nfs")
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Removing $dir..."
            rm -rf "$dir"
            log_success "$dir removed"
        else
            log_info "$dir does not exist"
        fi
    done
    
    # Remove any mounted ISOs
    if mount | grep -q "/mnt/debian-iso"; then
        log_info "Unmounting ISO..."
        umount /mnt/debian-iso 2>/dev/null || true
        log_success "ISO unmounted"
    fi
    
    log_success "All directories cleaned"
}

clear_logs() {
    log_step "Clearing old PXE logs..."
    
    # Clear dnsmasq logs
    if [ -f /var/log/dnsmasq.log ]; then
        > /var/log/dnsmasq.log
        log_success "dnsmasq logs cleared"
    fi
    
    # Clear apache logs
    if [ -f /var/log/apache2/access.log ]; then
        > /var/log/apache2/access.log
        log_success "Apache access logs cleared"
    fi
    
    if [ -f /var/log/apache2/error.log ]; then
        > /var/log/apache2/error.log
        log_success "Apache error logs cleared"
    fi
    
    log_success "All logs cleared"
}

verify_clean_state() {
    log_step "Verifying clean state..."
    
    local issues=0
    
    # Check services are stopped
    for service in dnsmasq apache2 nfs-server; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_error "$service is still running"
            ((issues++))
        fi
    done
    
    # Check directories are removed
    for dir in /srv/tftp /srv/http /srv/nfs; do
        if [ -d "$dir" ]; then
            log_error "$dir still exists"
            ((issues++))
        fi
    done
    
    # Check processes
    if pgrep -x dnsmasq > /dev/null; then
        log_error "dnsmasq processes still running"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "Clean state verified - ready for fresh setup"
        return 0
    else
        log_error "Clean state verification failed with $issues issues"
        return 1
    fi
}

print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          PXE Server Reset Complete                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${GREEN}✓ All services stopped${NC}"
    echo -e "${GREEN}✓ All processes killed${NC}"
    echo -e "${GREEN}✓ All configurations removed${NC}"
    echo -e "${GREEN}✓ All directories cleaned${NC}"
    echo -e "${GREEN}✓ All logs cleared${NC}"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Run: sudo ./scripts/setup-pxe-server.sh"
    echo "  2. Run: sudo ./scripts/verify-pxe-config.sh"
    echo "  3. Boot client machine via PXE"
    echo ""
    echo -e "${YELLOW}Log file: $LOG_FILE${NC}"
    echo ""
}

main() {
    # Initialize log
    echo "=== PXE Server Reset - $(date) ===" > "$LOG_FILE"
    
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          PXE Server Complete Reset                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    log_warn "This will completely reset your PXE server configuration!"
    log_warn "All services will be stopped and configurations removed."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Reset cancelled by user"
        exit 0
    fi
    
    echo ""
    
    check_root
    stop_services
    kill_stuck_processes
    remove_configurations
    clean_directories
    clear_logs
    verify_clean_state
    print_summary
}

main "$@"