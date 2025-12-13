#!/bin/bash

# ============================================
# VPS Initialization Script
# ============================================
# This script automates VPS initialization including:
# - Timezone configuration
# - SSH key setup and hardening
# - Firewall migration from iptables to nftables
# - Fail2ban installation (configuration required separately)
# - Optional IPv6 configuration
# - Automatic ACME installation (optional)
# ============================================

# ============================================
# Import Modules
# ============================================

# Get the directory of the current script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Source configuration variables
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Source utility functions
if [ -f "$SCRIPT_DIR/utils.sh" ]; then
    source "$SCRIPT_DIR/utils.sh"
else
    echo "Error: utils.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Source setup modules
if [ -f "$SCRIPT_DIR/modules.sh" ]; then
    source "$SCRIPT_DIR/modules.sh"
else
    echo "Error: modules.sh not found in $SCRIPT_DIR"
    exit 1
fi

# ============================================
# Main Execution
# ============================================

main() {
    print_section "VPS Initialization Script"
    
    # Pre-flight checks
    check_root
    validate_public_key
    
    # Detect system package manager
    detect_package_manager
    
    # Execute configuration steps
    setup_timezone
    setup_ssh_key
    configure_ssh_hardening
    setup_firewall
    configure_ipv6
    configure_tcp_bbr
    configure_nftables
    setup_fail2ban
    setup_syn_flood_detection
    setup_kcptun
    setup_warp
    setup_acme
    custome_hook "$SCRIPT_DIR"
    # Final message
    print_section "VPS Initialization Complete"
    echo ""
    echo "Configuration Summary:"
    echo "  - Timezone: $TIMEZONE"
    echo "  - SSH Port: $SSH_PORT"
    echo "  - SSH Authentication: Key-only (password disabled)"
    echo "  - Firewall: nftables (iptables removed)"
    echo "  - IPv6 Configuration: $ENABLE_IPV6"
    echo "  - TCP BBR: Enabled (congestion control optimized)"
    echo "  - Fail2ban: Configured (using nftables)"
    echo "  - SYN Flood Detection: Enabled (runs every 30 minutes)"
    echo "  - KCPtun SSH Acceleration: $ENABLE_KCPTUN (Port: $KCPTUN_PORT UDP)"
    echo "  - Cloudflare WARP: $ENABLE_WARP"
    echo "  - ACME (SSL): $ENABLE_ACME (Email: $ACME_EMAIL)"
    echo ""
    echo "⚠️  IMPORTANT: VERIFY SSH ACCESS BEFORE CLOSING THIS SESSION!"
    echo ""
    echo "Test connection with:"
    echo "  ssh -p $SSH_PORT -i ~/.ssh/id_ed25519 root@your_vps_ip"
    echo ""
    print_section ""
}

# Run main function
main
