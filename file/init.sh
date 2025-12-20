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
    [ "$ENABLE_TIMEZONE" = "true" ] && setup_timezone
    [ "$ENABLE_SSH_KEY" = "true" ] && setup_ssh_key
    [ "$ENABLE_SSH_HARDENING" = "true" ] && configure_ssh_hardening
    [ "$ENABLE_FIREWALL" = "true" ] && setup_firewall
    [ "$ENABLE_IPV6" = "true" ] && configure_ipv6
    [ "$ENABLE_TCP_BBR" = "true" ] && configure_tcp_bbr
    [ "$ENABLE_NFTABLES" = "true" ] && configure_nftables
    [ "$ENABLE_FAIL2BAN" = "true" ] && setup_fail2ban
    [ "$ENABLE_SYN_FLOOD_DETECTION" = "true" ] && setup_syn_flood_detection
    [ "$ENABLE_KCPTUN" = "true" ] && setup_kcptun
    [ "$ENABLE_WARP" = "true" ] && setup_warp
    [ "$ENABLE_ACME" = "true" ] && setup_acme
    custome_hook "$SCRIPT_DIR"
    # Final message
    print_section "VPS Initialization Complete"
    echo ""
    echo "Configuration Summary:"
    echo "  - Timezone: ${ENABLE_TIMEZONE:-Disabled} ($TIMEZONE)"
    echo "  - SSH Key Setup: ${ENABLE_SSH_KEY:-Disabled}"
    echo "  - SSH Port: $SSH_PORT"
    echo "  - SSH Hardening: ${ENABLE_SSH_HARDENING:-Disabled} (Key-only authentication)"
    echo "  - Firewall: ${ENABLE_FIREWALL:-Disabled} (nftables, iptables removed)"
    echo "  - IPv6 Configuration: ${ENABLE_IPV6:-Disabled}"
    echo "  - TCP BBR: ${ENABLE_TCP_BBR:-Disabled} (congestion control)"
    echo "  - NFTables Configuration: ${ENABLE_NFTABLES:-Disabled}"
    echo "  - Fail2ban: ${ENABLE_FAIL2BAN:-Disabled} (using nftables)"
    echo "  - SYN Flood Detection: ${ENABLE_SYN_FLOOD_DETECTION:-Disabled} (runs every 30 minutes)"
    echo "  - KCPtun SSH Acceleration: ${ENABLE_KCPTUN:-Disabled} (Port: $KCPTUN_PORT UDP)"
    echo "  - Cloudflare WARP: ${ENABLE_WARP:-Disabled}"
    if [ "$ENABLE_ACME" = "true" ]; then
        if [ "$ACME_USE_SELFSIGNED" = "true" ]; then
            echo "  - Certificate: ${ENABLE_ACME:-Disabled} (Self-signed for $ACME_DOMAIN)"
        else
            echo "  - Certificate: ${ENABLE_ACME:-Disabled} (Let's Encrypt, Email: $ACME_EMAIL)"
        fi
    else
        echo "  - Certificate: Disabled"
    fi
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
