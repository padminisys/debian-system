#!/bin/bash
# Stop PXE Server Services
# Stops dnsmasq (Proxy DHCP + TFTP), Apache2 (HTTP), and NFS services
# Note: Router continues to provide DHCP/IP addresses

# Removed set -e to allow script to continue if services aren't running

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

stop_services() {
    log_info "Stopping PXE server services..."
    
    local services=("dnsmasq" "apache2" "nfs-server")
    local stopped=0
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_info "Stopping $service..."
            systemctl stop "$service" 2>/dev/null || log_warn "Failed to stop $service"
            systemctl disable "$service" 2>/dev/null || true
            ((stopped++))
        else
            log_warn "$service is not running"
        fi
    done
    
    if [ $stopped -gt 0 ]; then
        log_info "✓ Stopped $stopped service(s)"
    else
        log_warn "No PXE services were running"
    fi
}

verify_stopped() {
    log_info "Verifying services are stopped..."
    
    local still_running=0
    local services=("dnsmasq" "apache2" "nfs-server")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_error "$service is still running"
            ((still_running++))
        fi
    done
    
    if [ $still_running -eq 0 ]; then
        log_info "✓ All PXE services stopped successfully"
    else
        log_warn "$still_running service(s) still running (may need manual intervention)"
    fi
}

cleanup_ports() {
    log_info "Checking for processes on PXE ports..."
    
    # Check PXE-specific ports (not DHCP 67 since router handles that)
    local ports=(69 80 2049 111)
    local port_names=("TFTP" "HTTP" "NFS" "RPC")
    local found=0
    
    for i in "${!ports[@]}"; do
        local port="${ports[$i]}"
        local name="${port_names[$i]}"
        if lsof -i ":$port" &>/dev/null; then
            log_warn "Port $port ($name) still in use:"
            lsof -i ":$port" | tail -n +2
            ((found++))
        fi
    done
    
    if [ $found -eq 0 ]; then
        log_info "✓ All PXE ports are free"
    fi
}

print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          PXE Server Stopped                                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Stopped Services:"
    echo "  • dnsmasq (Proxy DHCP + TFTP)"
    echo "  • apache2 (HTTP - preseed files)"
    echo "  • nfs-server (NFS - installation files)"
    echo ""
    echo "Note: Router DHCP continues to assign IP addresses"
    echo ""
    echo "To restart PXE server:"
    echo "  sudo ./scripts/setup-pxe-server.sh"
    echo ""
    echo "To check service status:"
    echo "  systemctl status dnsmasq apache2 nfs-server"
    echo ""
}

main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          Stopping PXE Server                                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_root
    stop_services
    verify_stopped
    cleanup_ports
    print_summary
}

main "$@"