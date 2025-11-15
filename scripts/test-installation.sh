#!/bin/bash
# Test and validate Btrfs installation
# Run this on the installed system to verify setup

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

test_btrfs_filesystem() {
    log_info "Testing Btrfs filesystem..."
    
    if mount | grep -q "type btrfs"; then
        log_pass "Btrfs filesystem mounted"
    else
        log_fail "Btrfs filesystem not found"
        return
    fi
    
    # Check compression
    if mount | grep -q "compress=zstd"; then
        log_pass "Btrfs compression enabled (zstd)"
    else
        log_fail "Btrfs compression not enabled"
    fi
}

test_subvolumes() {
    log_info "Testing Btrfs subvolumes..."
    
    local required_subvols=("@" "@home" "@var_log" "@snapshots" "@tmp")
    
    for subvol in "${required_subvols[@]}"; do
        if sudo btrfs subvolume list / | grep -q "$subvol"; then
            log_pass "Subvolume $subvol exists"
        else
            log_fail "Subvolume $subvol missing"
        fi
    done
}

test_snapper() {
    log_info "Testing Snapper configuration..."
    
    if command -v snapper &> /dev/null; then
        log_pass "Snapper installed"
    else
        log_fail "Snapper not installed"
        return
    fi
    
    if sudo snapper -c root list &> /dev/null; then
        log_pass "Snapper configuration exists"
        
        local snapshot_count=$(sudo snapper -c root list | tail -n +3 | wc -l)
        if [ "$snapshot_count" -gt 0 ]; then
            log_pass "Golden baseline snapshot exists ($snapshot_count snapshots)"
        else
            log_fail "No snapshots found"
        fi
    else
        log_fail "Snapper configuration missing"
    fi
}

test_grub_btrfs() {
    log_info "Testing GRUB-Btrfs integration..."
    
    if systemctl is-enabled grub-btrfsd.service &> /dev/null; then
        log_pass "grub-btrfsd service enabled"
    else
        log_fail "grub-btrfsd service not enabled"
    fi
    
    if systemctl is-active grub-btrfsd.service &> /dev/null; then
        log_pass "grub-btrfsd service running"
    else
        log_fail "grub-btrfsd service not running"
    fi
}

test_snapshot_scripts() {
    log_info "Testing snapshot management scripts..."
    
    local scripts=("snapshot-create" "snapshot-rollback" "snapshot-list" "snapshot-cleanup")
    
    for script in "${scripts[@]}"; do
        if [ -x "/usr/local/bin/$script" ]; then
            log_pass "Script $script exists and is executable"
        else
            log_fail "Script $script missing or not executable"
        fi
    done
}

test_fstab() {
    log_info "Testing fstab configuration..."
    
    if grep -q "subvol=@" /etc/fstab; then
        log_pass "Root subvolume in fstab"
    else
        log_fail "Root subvolume not in fstab"
    fi
    
    if grep -q "compress=zstd" /etc/fstab; then
        log_pass "Compression options in fstab"
    else
        log_fail "Compression options not in fstab"
    fi
}

test_network() {
    log_info "Testing network configuration..."
    
    if ip link show | grep -q "state UP"; then
        log_pass "Network interface is up"
    else
        log_fail "No active network interface"
    fi
    
    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_pass "Internet connectivity working"
    else
        log_fail "No internet connectivity"
    fi
}

test_packages() {
    log_info "Testing required packages..."
    
    local packages=("btrfs-progs" "snapper" "grub-btrfs" "vim" "htop" "curl")
    
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            log_pass "Package $pkg installed"
        else
            log_fail "Package $pkg not installed"
        fi
    done
}

test_credentials() {
    log_info "Testing user accounts..."
    
    if id sysadmin &> /dev/null; then
        log_pass "User sysadmin exists"
        
        if groups sysadmin | grep -q sudo; then
            log_pass "User sysadmin has sudo access"
        else
            log_fail "User sysadmin lacks sudo access"
        fi
    else
        log_fail "User sysadmin does not exist"
    fi
}

test_disk_space() {
    log_info "Testing disk space..."
    
    local root_usage=$(df -h / | tail -n 1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$root_usage" -lt 80 ]; then
        log_pass "Root filesystem usage: ${root_usage}%"
    else
        log_fail "Root filesystem usage high: ${root_usage}%"
    fi
}

print_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          Installation Test Summary                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "Tests Passed: ${GREEN}$PASSED${NC}"
    echo -e "Tests Failed: ${RED}$FAILED${NC}"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed! Installation is healthy.${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed. Please review the output above.${NC}"
        return 1
    fi
}

main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Debian 12.12 Btrfs Installation Test Suite              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    test_btrfs_filesystem
    test_subvolumes
    test_snapper
    test_grub_btrfs
    test_snapshot_scripts
    test_fstab
    test_network
    test_packages
    test_credentials
    test_disk_space
    
    print_summary
}

main "$@"