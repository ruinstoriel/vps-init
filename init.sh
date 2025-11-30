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
# ============================================

# ============================================
# Configuration Variables
# ============================================

# Set to "true" to enable IPv6 configuration, "false" to skip
ENABLE_IPV6="true"

# Timezone setting
TIMEZONE="Asia/Shanghai"

# SSH Port
SSH_PORT="2200"

# Public key file
PUB_KEY=$(<id_ed25519.pub)

# ============================================
# Utility Functions
# ============================================

# Print section header
print_section() {
    echo ""
    echo "==================================================="
    echo "$1"
    echo "==================================================="
}

# Print step message
print_step() {
    echo ""
    echo ">>> $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo "Error: Please run as root"
        exit 1
    fi
}

# Validate public key
validate_public_key() {
    if [ -z "$PUB_KEY" ]; then
        echo "Error: No public key provided."
        echo "Usage: $0 \"ssh-rsa ...\""
        exit 1
    fi
}

# ============================================
# Core Functions
# ============================================

# Set system timezone
setup_timezone() {
    print_step "Setting timezone to $TIMEZONE..."
    
    if command -v timedatectl &> /dev/null; then
        timedatectl set-timezone "$TIMEZONE"
        echo "Timezone set to: $(timedatectl | grep 'Time zone' | awk '{print $3}')"
    else
        # Fallback method for systems without timedatectl
        ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
        echo "$TIMEZONE" > /etc/timezone
        echo "Timezone set to $TIMEZONE (fallback method)"
    fi
    
    echo "Current time: $(date)"
}

# Setup SSH public key authentication
setup_ssh_key() {
    print_step "Setting up SSH key..."
    
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    local auth_keys="$HOME/.ssh/authorized_keys"
    
    # Check if key already exists to avoid duplicates
    if [ ! -f "$auth_keys" ]; then
        echo "$PUB_KEY" > "$auth_keys"
    else
        grep -qF "$PUB_KEY" "$auth_keys" || echo "$PUB_KEY" >> "$auth_keys"
    fi
    
    chmod 600 "$auth_keys"
    echo "SSH key added successfully."
}

# Configure SSH hardening settings
configure_ssh_hardening() {
    print_step "Configuring SSH hardening..."
    
    local sshd_config="/etc/ssh/sshd_config"
    
    # Backup original config
    cp "$sshd_config" "${sshd_config}.bak"
    echo "Backup created: ${sshd_config}.bak"
    
    # Change SSH Port
    sed -i "s/^#\?Port.*/Port $SSH_PORT/" "$sshd_config"
    grep -q "^Port" "$sshd_config" || echo "Port $SSH_PORT" >> "$sshd_config"
    
    # Disable Password Authentication
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
    sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$sshd_config"
    sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$sshd_config"
    
    # Disable Root Password Login (Allow keys only)
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' "$sshd_config"
    
    # Restart SSH service
    if systemctl is-active --quiet ssh; then
        systemctl restart ssh
        echo "SSH service restarted."
    elif systemctl is-active --quiet sshd; then
        systemctl restart sshd
        echo "SSHD service restarted."
    fi
    
    echo "SSH configured: Port $SSH_PORT, Key-only authentication enabled."
}

# Detect and set package manager variables
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PM="apt-get"
        PM_INSTALL="install -y"
        PM_REMOVE="remove -y --purge"
        PM_UPDATE="update"
        NFT_CONF="/etc/nftables.conf"
    elif command -v dnf &> /dev/null; then
        PM="dnf"
        PM_INSTALL="install -y"
        PM_REMOVE="remove -y"
        PM_UPDATE="makecache"
        NFT_CONF="/etc/sysconfig/nftables.conf"
        mkdir -p /etc/sysconfig
    elif command -v yum &> /dev/null; then
        PM="yum"
        PM_INSTALL="install -y"
        PM_REMOVE="remove -y"
        PM_UPDATE="makecache"
        NFT_CONF="/etc/sysconfig/nftables.conf"
        mkdir -p /etc/sysconfig
    else
        echo "Error: Unsupported package manager. Cannot install nftables."
        exit 1
    fi
    
    echo "Detected package manager: $PM"
}

# Setup firewall (migrate from iptables to nftables)
setup_firewall() {
    print_step "Managing firewalls..."
    
    # Update package list
    $PM $PM_UPDATE
    
    # Stop and disable other firewalls FIRST
    echo "Stopping and disabling conflicting firewalls..."
    systemctl stop ufw 2>/dev/null
    systemctl disable ufw 2>/dev/null
    systemctl stop firewalld 2>/dev/null
    systemctl disable firewalld 2>/dev/null
    
    
    # Remove old firewall packages BEFORE installing nftables
    echo "Removing old firewall packages..."
    if [ "$PM" = "apt-get" ]; then
        $PM $PM_REMOVE ufw firewalld 2>/dev/null
    else
        $PM $PM_REMOVE firewalld ufw 2>/dev/null
    fi
    
    # NOW install nftables (won't be affected by removal above)
    echo "Installing nftables..."
    $PM $PM_INSTALL nftables
    
    # Verify installation
    if ! command -v nft &> /dev/null; then
        echo "Error: nftables installation failed. 'nft' command not found."
        exit 1
    fi
    
    NFT_BIN=$(command -v nft)
    echo "nft found at: $NFT_BIN"
    
    # Fix for systemd units that hardcode /sbin/nft
    if [ ! -x /sbin/nft ] && [ -x "$NFT_BIN" ]; then
        echo "Symlinking $NFT_BIN to /sbin/nft to satisfy systemd..."
        ln -s "$NFT_BIN" /sbin/nft
    fi
    
    echo "Firewall migration completed."
}

# Configure IPv6 settings
configure_ipv6() {
    if [ "$ENABLE_IPV6" != "true" ]; then
        print_step "IPv6 configuration skipped (ENABLE_IPV6=$ENABLE_IPV6)"
        return 0
    fi
    
    print_step "Configuring IPv6..."
    
    # Disable IPv6 autoconfig and router advertisements
    echo "Disabling IPv6 autoconfig and router advertisements..."
    sysctl -w net.ipv6.conf.all.autoconf=0
    sysctl -w net.ipv6.conf.all.accept_ra=0
    sysctl -w net.ipv6.conf.eth0.autoconf=0
    sysctl -w net.ipv6.conf.eth0.accept_ra=0
    
    # Find the primary network interface
    local primary_if=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -n "$primary_if" ]; then
        echo "Configuring IPv6 on interface: $primary_if"
        sysctl -w net.ipv6.conf.$primary_if.autoconf=0
        sysctl -w net.ipv6.conf.$primary_if.accept_ra=0
    fi
    
    # Make changes persistent
    cat > /etc/sysctl.d/99-ipv6.conf << EOF
# Disable IPv6 autoconfig and router advertisements
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.eth0.autoconf = 0
net.ipv6.conf.eth0.accept_ra = 0
EOF
    
    if [ -n "$primary_if" ]; then
        cat >> /etc/sysctl.d/99-ipv6.conf << EOF
net.ipv6.conf.$primary_if.autoconf = 0
net.ipv6.conf.$primary_if.accept_ra = 0
EOF
    fi
    
    echo "IPv6 autoconfig and router advertisements disabled."
    
    # Ensure IPv6 is NOT completely disabled
    echo "Ensuring IPv6 is enabled..."
    local sysctl_conf="/etc/sysctl.conf"
    
    # Update or add disable_ipv6 settings
    if grep -q "net.ipv6.conf.all.disable_ipv6" "$sysctl_conf" 2>/dev/null; then
        sed -i 's/^net.ipv6.conf.all.disable_ipv6.*/net.ipv6.conf.all.disable_ipv6 = 0/' "$sysctl_conf"
    else
        echo "net.ipv6.conf.all.disable_ipv6 = 0" >> "$sysctl_conf"
    fi
    
    if grep -q "net.ipv6.conf.default.disable_ipv6" "$sysctl_conf" 2>/dev/null; then
        sed -i 's/^net.ipv6.conf.default.disable_ipv6.*/net.ipv6.conf.default.disable_ipv6 = 0/' "$sysctl_conf"
    else
        echo "net.ipv6.conf.default.disable_ipv6 = 0" >> "$sysctl_conf"
    fi
    
    if grep -q "net.ipv6.conf.lo.disable_ipv6" "$sysctl_conf" 2>/dev/null; then
        sed -i 's/^net.ipv6.conf.lo.disable_ipv6.*/net.ipv6.conf.lo.disable_ipv6 = 0/' "$sysctl_conf"
    else
        echo "net.ipv6.conf.lo.disable_ipv6 = 0" >> "$sysctl_conf"
    fi
    
    # Apply the settings immediately
    sysctl -w net.ipv6.conf.all.disable_ipv6=0
    sysctl -w net.ipv6.conf.default.disable_ipv6=0
    sysctl -w net.ipv6.conf.lo.disable_ipv6=0
    
    echo "IPv6 enabled with custom configuration."
    
    # Restart network service if available
    if systemctl list-units --type=service | grep -q "network.service"; then
        systemctl restart network 2>/dev/null
        echo "Network service restarted."
    elif systemctl list-units --type=service | grep -q "networking.service"; then
        systemctl restart networking 2>/dev/null
        echo "Networking service restarted."
    fi
}

# Configure nftables
configure_nftables() {
    print_step "Configuring nftables..."
    
    # Copy nftables configuration
    if [ ! -f "./nftables.conf" ]; then
        echo "Error: nftables.conf not found in current directory."
        exit 1
    fi
    
    cp ./nftables.conf "$NFT_CONF"
    echo "Configuration copied to: $NFT_CONF"
    
    # Fix Windows line endings (CRLF) which cause syntax errors
    sed -i 's/\r$//' "$NFT_CONF"
    
    # Replace SSH_PORT placeholder with actual port
    sed -i "s/{{SSH_PORT}}/$SSH_PORT/g" "$NFT_CONF"
    echo "SSH port configured: $SSH_PORT"
    
    chmod 600 "$NFT_CONF"
    
    # Update shebang in config file to match actual binary location
    sed -i "1s|^#!.*|#!$NFT_BIN -f|" "$NFT_CONF"
    mkdir -p /etc/nftables.d
    # Enable and start nftables
    systemctl enable nftables
    systemctl restart nftables
    
    echo "nftables installed and configured successfully."
}

# Install and configure Fail2ban
setup_fail2ban() {
    print_step "Installing Fail2ban..."
    
    # Install Fail2ban
    $PM $PM_INSTALL fail2ban
    
    # Verify installation
    if ! command -v fail2ban-client &> /dev/null; then
        echo "Error: Fail2ban installation failed."
        exit 1
    fi
    
    echo "Fail2ban installed successfully."
    
    # Remove default configuration in jail.d to prevent startup errors
    # (Debian/Ubuntu creates defaults-debian.conf which enables sshd by default, 
    # causing "No file(s) found" error if auth.log is missing)
    if [ -d /etc/fail2ban/jail.d ]; then
        rm -f /etc/fail2ban/jail.d/*
        echo "Cleaned up default configurations in /etc/fail2ban/jail.d/"
    fi
    
    # Configure fail2ban to use nftables
    echo "Configuring Fail2ban to use nftables..."
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
banaction = nftables-multiport
banaction_allports = nftables-allports
EOF

    # Enable and start Fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    echo "Fail2ban configured to use nftables."
}



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
    configure_nftables
    setup_fail2ban
    
    # Final message
    print_section "VPS Initialization Complete"
    echo ""
    echo "Configuration Summary:"
    echo "  - Timezone: $TIMEZONE"
    echo "  - SSH Port: $SSH_PORT"
    echo "  - SSH Authentication: Key-only (password disabled)"
    echo "  - Firewall: nftables (iptables removed)"
    echo "  - IPv6 Configuration: $ENABLE_IPV6"
    echo "  - Fail2ban: Configured (using nftables)"
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
