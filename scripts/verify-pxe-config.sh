#!/bin/bash
# PXE Configuration Verification Script
# Verifies that CD-ROM detection fix is properly applied
# Provides clear GO/NO-GO decision before attempting PXE boot

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
TFTP_ROOT="/srv/tftp"
HTTP_ROOT="/srv/http"
LOG_FILE="/var/log/pxe-verify.log"

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
    ((PASSED_CHECKS++))
}

log_fail() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
    ((FAILED_CHECKS++))
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
    ((WARNING_CHECKS++))
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}$1${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_fail "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

detect_server_ip() {
    # Detect server IP from dnsmasq config
    if [ -f /etc/dnsmasq.conf ]; then
        SERVER_IP=$(grep "^dhcp-range=" /etc/dnsmasq.conf | cut -d'=' -f2 | cut -d',' -f1)
        if [ -z "$SERVER_IP" ]; then
            # Try to get from interface
            local iface=$(grep "^interface=" /etc/dnsmasq.conf | cut -d'=' -f2)
            if [ -n "$iface" ]; then
                SERVER_IP=$(ip -4 addr show "$iface" | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1)
            fi
        fi
    fi
    
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="localhost"
    fi
}

verify_services() {
    log_section "SERVICE STATUS VERIFICATION"
    ((TOTAL_CHECKS++))
    
    local all_running=true
    
    # Check dnsmasq
    if systemctl is-active --quiet dnsmasq; then
        log_success "dnsmasq service is running"
    else
        log_fail "dnsmasq service is NOT running"
        all_running=false
    fi
    
    # Check apache2
    if systemctl is-active --quiet apache2; then
        log_success "apache2 service is running"
    else
        log_fail "apache2 service is NOT running"
        all_running=false
    fi
    
    if [ "$all_running" = false ]; then
        ((FAILED_CHECKS++))
    else
        ((PASSED_CHECKS++))
    fi
}

verify_tftp_files() {
    log_section "TFTP FILES VERIFICATION"
    
    local files=(
        "$TFTP_ROOT/pxelinux.0:PXE bootloader"
        "$TFTP_ROOT/menu.c32:Menu module"
        "$TFTP_ROOT/debian-installer/vmlinuz:Kernel"
        "$TFTP_ROOT/debian-installer/initrd.gz:Initial ramdisk"
        "$TFTP_ROOT/pxelinux.cfg/default:PXE configuration"
    )
    
    for file_info in "${files[@]}"; do
        ((TOTAL_CHECKS++))
        local file="${file_info%%:*}"
        local desc="${file_info##*:}"
        
        if [ -f "$file" ]; then
            log_success "$desc exists: $file"
            ((PASSED_CHECKS++))
        else
            log_fail "$desc missing: $file"
            ((FAILED_CHECKS++))
        fi
    done
}

verify_cdrom_fix() {
    log_section "CD-ROM DETECTION FIX VERIFICATION (CRITICAL)"
    
    ((TOTAL_CHECKS++))
    
    if [ ! -f "$TFTP_ROOT/pxelinux.cfg/default" ]; then
        log_fail "PXE config file not found"
        ((FAILED_CHECKS++))
        return
    fi
    
    # Check for hw-detect/load_media=false
    if grep -q "hw-detect/load_media=false" "$TFTP_ROOT/pxelinux.cfg/default"; then
        log_success "hw-detect/load_media=false found in PXE config"
        ((PASSED_CHECKS++))
        
        # Show the actual boot line
        echo "" | tee -a "$LOG_FILE"
        log_info "Boot parameters for automated install:"
        echo -e "${MAGENTA}" | tee -a "$LOG_FILE"
        grep -A 2 "LABEL auto-install" "$TFTP_ROOT/pxelinux.cfg/default" | grep "APPEND" | sed 's/^    /  /' | tee -a "$LOG_FILE"
        echo -e "${NC}" | tee -a "$LOG_FILE"
    else
        log_fail "hw-detect/load_media=false NOT found in PXE config"
        log_fail "This will cause 'couldn't mount installation media' error"
        ((FAILED_CHECKS++))
    fi
}

verify_preseed() {
    log_section "PRESEED CONFIGURATION VERIFICATION"
    
    # Check preseed file exists
    ((TOTAL_CHECKS++))
    if [ -f "$HTTP_ROOT/preseed.cfg" ]; then
        log_success "Preseed file exists: $HTTP_ROOT/preseed.cfg"
        ((PASSED_CHECKS++))
    else
        log_fail "Preseed file missing: $HTTP_ROOT/preseed.cfg"
        ((FAILED_CHECKS++))
        return
    fi
    
    # Check preseed has CD-ROM skip directives
    ((TOTAL_CHECKS++))
    if grep -q "apt-setup/cdrom/set-first" "$HTTP_ROOT/preseed.cfg"; then
        log_success "Preseed has CD-ROM skip directives"
        ((PASSED_CHECKS++))
    else
        log_warn "Preseed may be missing CD-ROM skip directives"
        ((WARNING_CHECKS++))
    fi
    
    # Check preseed accessibility via HTTP
    ((TOTAL_CHECKS++))
    if curl -s -f "http://localhost/preseed.cfg" > /dev/null 2>&1; then
        log_success "Preseed accessible via HTTP (localhost)"
        ((PASSED_CHECKS++))
    else
        log_fail "Preseed NOT accessible via HTTP"
        ((FAILED_CHECKS++))
    fi
    
    # Test from server IP
    ((TOTAL_CHECKS++))
    if [ "$SERVER_IP" != "localhost" ]; then
        if curl -s -f "http://${SERVER_IP}/preseed.cfg" > /dev/null 2>&1; then
            log_success "Preseed accessible via server IP: http://${SERVER_IP}/preseed.cfg"
            ((PASSED_CHECKS++))
        else
            log_warn "Preseed not accessible via server IP (may be firewall)"
            ((WARNING_CHECKS++))
        fi
    fi
}

verify_network_config() {
    log_section "NETWORK CONFIGURATION VERIFICATION"
    
    # Check dnsmasq config
    ((TOTAL_CHECKS++))
    if [ -f /etc/dnsmasq.conf ]; then
        log_success "dnsmasq configuration exists"
        ((PASSED_CHECKS++))
        
        # Show key configuration
        echo "" | tee -a "$LOG_FILE"
        log_info "dnsmasq configuration:"
        echo -e "${MAGENTA}" | tee -a "$LOG_FILE"
        grep -E "^(interface|dhcp-range|dhcp-boot|enable-tftp|tftp-root)" /etc/dnsmasq.conf | sed 's/^/  /' | tee -a "$LOG_FILE"
        echo -e "${NC}" | tee -a "$LOG_FILE"
    else
        log_fail "dnsmasq configuration missing"
        ((FAILED_CHECKS++))
    fi
    
    # Check TFTP is enabled
    ((TOTAL_CHECKS++))
    if grep -q "^enable-tftp" /etc/dnsmasq.conf; then
        log_success "TFTP enabled in dnsmasq"
        ((PASSED_CHECKS++))
    else
        log_fail "TFTP not enabled in dnsmasq"
        ((FAILED_CHECKS++))
    fi
}

verify_permissions() {
    log_section "FILE PERMISSIONS VERIFICATION"
    
    # Check TFTP root ownership
    ((TOTAL_CHECKS++))
    if [ -d "$TFTP_ROOT" ]; then
        local owner=$(stat -c '%U' "$TFTP_ROOT")
        if [ "$owner" = "dnsmasq" ]; then
            log_success "TFTP root owned by dnsmasq user"
            ((PASSED_CHECKS++))
        else
            log_warn "TFTP root owned by $owner (expected: dnsmasq)"
            ((WARNING_CHECKS++))
        fi
    fi
    
    # Check HTTP root is readable
    ((TOTAL_CHECKS++))
    if [ -r "$HTTP_ROOT/preseed.cfg" ]; then
        log_success "Preseed file is readable"
        ((PASSED_CHECKS++))
    else
        log_fail "Preseed file is not readable"
        ((FAILED_CHECKS++))
    fi
}

show_boot_parameters() {
    log_section "EXACT BOOT PARAMETERS THAT WILL BE USED"
    
    if [ -f "$TFTP_ROOT/pxelinux.cfg/default" ]; then
        echo "" | tee -a "$LOG_FILE"
        echo -e "${CYAN}When client boots via PXE and selects 'Automated Btrfs Installation',${NC}" | tee -a "$LOG_FILE"
        echo -e "${CYAN}these EXACT parameters will be used:${NC}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
        
        # Extract and format the APPEND line
        local append_line=$(grep -A 3 "LABEL auto-install" "$TFTP_ROOT/pxelinux.cfg/default" | grep "APPEND" | sed 's/^[[:space:]]*//')
        
        # Highlight the critical parameter
        echo "$append_line" | sed 's/hw-detect\/load_media=false/\\033[1;32mhw-detect\/load_media=false\\033[0;35m/g' | sed 's/^/║ /' | tee -a "$LOG_FILE"
        
        echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
    fi
}

print_summary() {
    log_section "VERIFICATION SUMMARY"
    
    echo "" | tee -a "$LOG_FILE"
    echo "Total Checks:    $TOTAL_CHECKS" | tee -a "$LOG_FILE"
    echo -e "${GREEN}Passed:          $PASSED_CHECKS${NC}" | tee -a "$LOG_FILE"
    echo -e "${RED}Failed:          $FAILED_CHECKS${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}Warnings:        $WARNING_CHECKS${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo "╔══════════════════════════════════════════════════════════════╗" | tee -a "$LOG_FILE"
        echo -e "║  ${GREEN}✓ GO - PXE Server is Ready for Client Boot${NC}              ║" | tee -a "$LOG_FILE"
        echo "╚══════════════════════════════════════════════════════════════╝" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        echo -e "${GREEN}All critical checks passed!${NC}" | tee -a "$LOG_FILE"
        echo "You can now boot your client machine via PXE." | tee -a "$LOG_FILE"
        
        if [ $WARNING_CHECKS -gt 0 ]; then
            echo "" | tee -a "$LOG_FILE"
            echo -e "${YELLOW}Note: There are $WARNING_CHECKS warnings, but they are not critical.${NC}" | tee -a "$LOG_FILE"
        fi
    else
        echo "╔══════════════════════════════════════════════════════════════╗" | tee -a "$LOG_FILE"
        echo -e "║  ${RED}✗ NO-GO - Issues Found, Do Not Attempt PXE Boot${NC}         ║" | tee -a "$LOG_FILE"
        echo "╚══════════════════════════════════════════════════════════════╝" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        echo -e "${RED}$FAILED_CHECKS critical check(s) failed!${NC}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        echo "Recommended actions:" | tee -a "$LOG_FILE"
        echo "  1. Review the failed checks above" | tee -a "$LOG_FILE"
        echo "  2. Run: sudo ./scripts/reset-pxe-server.sh" | tee -a "$LOG_FILE"
        echo "  3. Run: sudo ./scripts/setup-pxe-server.sh" | tee -a "$LOG_FILE"
        echo "  4. Run: sudo ./scripts/verify-pxe-config.sh (this script)" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}Log file: $LOG_FILE${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

main() {
    # Initialize log
    echo "=== PXE Configuration Verification - $(date) ===" > "$LOG_FILE"
    
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          PXE Configuration Verification                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_root
    detect_server_ip
    
    verify_services
    verify_tftp_files
    verify_cdrom_fix
    verify_preseed
    verify_network_config
    verify_permissions
    show_boot_parameters
    print_summary
    
    # Exit with appropriate code
    if [ $FAILED_CHECKS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"