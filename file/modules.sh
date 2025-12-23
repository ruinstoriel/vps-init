#!/bin/bash

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
        if systemctl restart ssh;then
            echo "SSH service restarted."
        else
            echo "Failed to restart SSH service."
        fi
    elif systemctl is-active --quiet sshd; then
        if systemctl restart sshd;then
            echo "SSHD service restarted."
        else
            echo "Failed to restart SSHD service."
        fi
    fi
    
    echo "SSH configured: Port $SSH_PORT, Key-only authentication enabled."
}

# Setup firewall (migrate from iptables to nftables)
setup_firewall() {
    print_step "Managing firewalls..."
    
    # Update package list
    wait_for_lock
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
    sysctl -w net.ipv6.conf.eth0.disable_ipv6=0
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

# Configure TCP BBR congestion control
configure_tcp_bbr() {
    print_step "Configuring TCP BBR congestion control..."
    
    # Check kernel version (BBR requires kernel 4.9+)
    local kernel_version=$(uname -r | cut -d. -f1)
    local kernel_minor=$(uname -r | cut -d. -f2)
    
    if [ "$kernel_version" -lt 4 ] || ([ "$kernel_version" -eq 4 ] && [ "$kernel_minor" -lt 9 ]); then
        echo "⚠ Warning: Kernel version $(uname -r) may not support BBR (requires 4.9+)"
        echo "Skipping BBR configuration..."
        return 0
    fi
    
    # Load TCP BBR module
    echo "Loading TCP BBR kernel module..."
    modprobe tcp_bbr
    
    # Verify module is loaded
    if ! lsmod | grep -q tcp_bbr; then
        echo "⚠ Warning: Failed to load tcp_bbr module"
        return 1
    fi
    
    # Configure sysctl settings for BBR
    echo "Configuring sysctl settings for BBR..."
    
    # Apply settings immediately
    sysctl -w net.core.default_qdisc=fq
    sysctl -w net.ipv4.tcp_congestion_control=bbr
    sysctl -w net.ipv4.tcp_fastopen=3
    tc qdisc replace dev eth0 root fq
    tc qdisc list dev eth0
    # Make changes persistent
    cat > /etc/sysctl.d/99-bbr.conf << EOF
# TCP BBR Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF
    
    echo "TCP BBR configuration file created: /etc/sysctl.d/99-bbr.conf"
    
    # Ensure module loads on boot
    if ! grep -q "tcp_bbr" /etc/modules-load.d/modules.conf 2>/dev/null && \
       ! grep -q "tcp_bbr" /etc/modules 2>/dev/null; then
        
        if [ -d /etc/modules-load.d ]; then
            echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
            echo "Module auto-load configured: /etc/modules-load.d/bbr.conf"
        else
            echo "tcp_bbr" >> /etc/modules
            echo "Module auto-load configured: /etc/modules"
        fi
    fi
    
    # Verify configuration
    local current_qdisc=$(sysctl -n net.core.default_qdisc)
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    
    if [ "$current_qdisc" = "fq" ] && [ "$current_cc" = "bbr" ]; then
        echo "✓ TCP BBR enabled successfully"
        echo "  - Queue discipline: $current_qdisc"
        echo "  - Congestion control: $current_cc"
    else
        echo "⚠ Warning: BBR configuration may not be active"
        echo "  - Current queue discipline: $current_qdisc (expected: fq)"
        echo "  - Current congestion control: $current_cc (expected: bbr)"
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
    
    chmod 600 "$NFT_CONF"
    
    # Update shebang in config file to match actual binary location
    sed -i "1s|^#!.*|#!$NFT_BIN -f|" "$NFT_CONF"
    mkdir -p /etc/nftables.d
    
    # Deploy SSH port configuration
    echo "Deploying SSH port configuration..."
    if [ ! -f "./ssh.nft" ]; then
        echo "Error: ssh.nft not found in current directory."
        exit 1
    fi
    
    # Copy and substitute SSH_PORT placeholder
    sed "s/SSH_PORT_PLACEHOLDER/$SSH_PORT/g" ./ssh.nft > /etc/nftables.d/ssh.nft
    chmod 644 /etc/nftables.d/ssh.nft
    echo "✓ SSH port $SSH_PORT configured in /etc/nftables.d/ssh.nft"
    
    # Enable and start nftables
    systemctl enable nftables
    systemctl restart nftables
    
    echo "nftables installed and configured successfully."
}

# Install and configure Fail2ban
setup_fail2ban() {
    print_step "Installing Fail2ban..."
    
    # Install Fail2ban
    wait_for_lock
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

    # Copy nftables-common.local if it exists
    if [ -f "./nftables-common.local" ]; then
        echo "Copying nftables-common.local..."
        mkdir -p /etc/fail2ban/action.d
        cp ./nftables-common.local /etc/fail2ban/action.d/nftables-common.local
        chmod 644 /etc/fail2ban/action.d/nftables-common.local
    fi

    # Enable and start Fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    echo "Fail2ban configured to use nftables."
}

# Setup SYN Flood Detection
setup_syn_flood_detection() {
    print_step "Setting up SYN Flood Detection..."
    
    # Install required dependencies
    echo "Installing dependencies (conntrack-tools, whois)..."
    wait_for_lock
    $PM $PM_INSTALL conntrack whois
    
    # Check if syn-flood-detect.sh exists
    if [ ! -f "./syn-flood-detect.sh" ]; then
        echo "Warning: syn-flood-detect.sh not found in current directory. Skipping..."
        return 0
    fi
    
    # Copy script to /usr/local/bin
    local script_path="/usr/local/bin/syn-flood-detect.sh"
    cp ./syn-flood-detect.sh "$script_path"
    chmod +x "$script_path"
    echo "Script copied to: $script_path"
    
    # Create log files
    touch /var/log/syn_flood_subnet.log
    touch /var/log/syn_flood_cron.log
    echo "Log files created."
    
    # Setup cron job (runs every 30 minutes)
    local cron_job="0,30 * * * * $script_path >> /var/log/syn_flood_cron.log 2>&1"
    
    # Remove existing cron jobs for this script
    crontab -l 2>/dev/null | grep -v "$script_path" | crontab - 2>/dev/null
    
    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    
    echo "Cron job configured: runs every 30 minutes (at :00 and :30)"
    echo "Cron log: /var/log/syn_flood_cron.log"
    echo "Detection log: /var/log/syn_flood_subnet.log"
    
    # Verify cron job
    if crontab -l 2>/dev/null | grep -q "$script_path"; then
        echo "✓ SYN Flood Detection setup complete"
    else
        echo "⚠ Warning: Failed to verify cron job installation"
    fi
}

# Setup KCPtun for SSH acceleration
setup_kcptun() {
    if [ "$ENABLE_KCPTUN" != "true" ]; then
        print_step "KCPtun installation skipped (ENABLE_KCPTUN=$ENABLE_KCPTUN)"
        return 0
    fi
    
    print_step "Setting up KCPtun for SSH acceleration..."
    
    # Detect system architecture
    local arch=$(uname -m)
    local start_dir=$(pwd)
    local kcptun_arch=""
    
    # Use utility function for architecture detection if available, or fallback
    if command -v get_system_arch &> /dev/null; then
        local detected_arch=$(get_system_arch)
        if [ -n "$detected_arch" ]; then
             # Map utility output to kcptun expectation
             case "$detected_arch" in
                amd64) kcptun_arch="amd64" ;;
                arm64) kcptun_arch="arm64" ;;
                arm7)  kcptun_arch="arm7" ;;
                *)     
                    echo "⚠ Warning: Unsupported architecture for KCPtun: $detected_arch"
                    return 0 
                    ;;
             esac
        fi
    else 
        # Fallback legacy detection
        case "$arch" in
            x86_64) kcptun_arch="amd64" ;;
            aarch64|arm64) kcptun_arch="arm64" ;;
            armv7l) kcptun_arch="arm7" ;;
            *) 
                echo "⚠ Warning: Unsupported architecture: $arch"
                return 0
                ;;
        esac
    fi
    
    echo "Detected architecture: $arch (kcptun: linux_$kcptun_arch)"
    
    # Download and install KCPtun
    echo "Downloading KCPtun..."
    cd /tmp
    
    # Download using the official script
    if ! curl -L https://raw.githubusercontent.com/xtaci/kcptun/master/download.sh | sh; then
        echo "⚠ Warning: Failed to download KCPtun"
        return 1
    fi
    
    # Find the downloaded tar.gz file
    local kcptun_file=$(ls -t kcptun-linux-${kcptun_arch}-*.tar.gz 2>/dev/null | head -n1)
    
    if [ -z "$kcptun_file" ]; then
        echo "⚠ Warning: KCPtun archive not found"
        return 1
    fi
    
    echo "Found KCPtun archive: $kcptun_file"
    
    # Extract the archive
    echo "Extracting KCPtun..."
    tar -xzf "$kcptun_file"
    
    # Install server binary
    if [ -f "server_linux_${kcptun_arch}" ]; then
        mv "server_linux_${kcptun_arch}" /usr/local/bin/kcptun-server
        chmod +x /usr/local/bin/kcptun-server
        echo "✓ KCPtun server installed to /usr/local/bin/kcptun-server"
    else
        echo "⚠ Warning: KCPtun server binary not found"
        return 1
    fi
    
    # Clean up
    rm -f "$kcptun_file" client_linux_${kcptun_arch}
    
    # Create systemd service
    echo "Creating systemd service..."
    cat > /etc/systemd/system/kcptun.service << EOF
[Unit]
Description=KCPtun Server for SSH Acceleration
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/kcptun-server \\
    -t "127.0.0.1:${SSH_PORT}" \\
    -l ":${KCPTUN_PORT}" \\
    -mode fast3 \\
    -nocomp \\
    -sockbuf 16777217 \\
    -dscp 46
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    echo "✓ Systemd service created: /etc/systemd/system/kcptun.service"
    
    # Restore original directory to find kcp.nft
    cd "$start_dir"

    # Add KCPtun port to nftables
    echo "Adding KCPtun port $KCPTUN_PORT (UDP) to firewall..."
    if command -v nft &> /dev/null && nft list table inet filter &> /dev/null 2>&1; then
        # Deploy KCP port configuration
        if [ ! -f "./kcp.nft" ]; then
            echo "⚠ Warning: kcp.nft not found in current directory, skipping firewall configuration"
        else
            # Copy and substitute KCPTUN_PORT placeholder
            sed "s/KCPTUN_PORT_PLACEHOLDER/$KCPTUN_PORT/g" ./kcp.nft > /etc/nftables.d/kcp.nft
            chmod 644 /etc/nftables.d/kcp.nft
            
            # Reload nftables to apply the new configuration
            systemctl reload nftables || systemctl restart nftables
            
            echo "✓ KCPtun port $KCPTUN_PORT configured in /etc/nftables.d/kcp.nft"
        fi
    else
        echo "⚠ Warning: nftables not available, skipping firewall configuration"
    fi
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable kcptun
    systemctl start kcptun
    
    # Verify service status
    if systemctl is-active --quiet kcptun; then
        echo "✓ KCPtun service started successfully"
        echo ""
        echo "KCPtun Configuration:"
        echo "  - Server Port (UDP): $KCPTUN_PORT"
        echo "  - Target SSH Port: $SSH_PORT"
        echo "  - Mode: fast3"
        echo ""
        echo "Client connection example:"
        echo "  ./client_linux_amd64 -r \"SERVER_IP:$KCPTUN_PORT\" -l \":$SSH_PORT\" -mode fast3 -nocomp -autoexpire 900 -sockbuf 16777217 -dscp 46"
        echo ""
    else
        echo "⚠ Warning: KCPtun service failed to start"
        echo "Check logs with: journalctl -u kcptun -n 50"
    fi
}

# Setup Cloudflare WARP using wgcf (Manual)
setup_warp() {
    if [ "$ENABLE_WARP" != "true" ]; then
        print_step "WARP installation skipped (ENABLE_WARP=$ENABLE_WARP)"
        return 0
    fi
    
    print_step "Installing Cloudflare WARP (via wgcf)..."
    
    # 1. Install WireGuard Tools
    echo "Installing WireGuard tools..."
    wait_for_lock
    
    if [ "$PM" = "apt-get" ]; then
        # Debian/Ubuntu
        $PM $PM_INSTALL wireguard-tools openresolv
    elif [ "$PM" = "dnf" ] || [ "$PM" = "yum" ]; then
         # CentOS/Fedora
         $PM $PM_INSTALL wireguard-tools
    fi
    
    # 2. Download wgcf
    echo "Downloading wgcf..."
    local wgcf_arch=$(get_system_arch)
    if [ -z "$wgcf_arch" ]; then
        echo "Error: Unsupported architecture for wgcf."
        return 1
    fi
    
    # Fix arch naming for wgcf if needed (utils uses amd64, arm64, which matches wgcf)
    version="2.2.29"
    local wgcf_url="https://github.com/ViRb3/wgcf/releases/download/v${version}/wgcf_${version}_linux_${wgcf_arch}"
    
    curl -fsSL -o /usr/local/bin/wgcf "$wgcf_url"
    chmod +x /usr/local/bin/wgcf
    
    if ! command -v wgcf &> /dev/null; then
        echo "Error: Failed to download/install wgcf."
        return 1
    fi
    
    echo "wgcf installed: $version"
    
    # 3. Configure WARP
    mkdir -p /etc/wireguard
    cd /etc/wireguard
    
    if [ -f "wgcf-account.toml" ]; then
        echo "Existing wgcf account found."
    else
        echo "Registering new wgcf account..."
        # Yes to TOS
        echo "yes" | wgcf register
    fi
    
    echo "Generating WireGuard profile..."
    wgcf generate
    
    if [ ! -f "wgcf-profile.conf" ]; then
        echo "Error: Failed to generate WireGuard profile."
        return 1
    fi
    
    # Rename to standard config name for wg-quick
    # User requested wgcf.conf as the name
    cp wgcf-profile.conf wgcf.conf
    chmod 600 wgcf.conf
    
    # Clean up generated profile to reduce clutter
    rm -f wgcf-profile.conf
    
    # --- Routing Fix ---
    # Allow incoming TCP traffic on the main interface to bypass WireGuard
    local primary_if=$(ip route | grep default | awk '{print $5}' | head -n1)
    # Get the main IP address
    local main_ip=$(ip -4 addr show "$primary_if" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    
    if [ -n "$primary_if" ] && [ -n "$main_ip" ]; then
        echo "Applying routing fix for $primary_if ($main_ip)..."
        # Insert PostUp and PostDown rules into the [Interface] section
        # sed -i '/^\[Interface\]/a PostUp = ip rule add from <IP> lookup main\nPostDown = ip rule delete from <IP> lookup main' wgcf.conf
        sed -i "/^\[Interface\]/a PostUp = ip rule add from $main_ip lookup main\nPostDown = ip rule delete from $main_ip lookup main" wgcf.conf
        
        # IPv6 Routing Fix
        # Get the main IPv6 address (global scope, excluding link-local)
        local main_ip6=$(ip -6 addr show "$primary_if" | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/.*scope global)' | head -n1)
        
        if [ -n "$main_ip6" ]; then
             echo "Applying IPv6 routing fix for $primary_if ($main_ip6)..."
             sed -i "/^\[Interface\]/a PostUp = ip -6 rule add from $main_ip6 lookup main\nPostDown = ip -6 rule delete from $main_ip6 lookup main" wgcf.conf
        else
             # Failback for non-IPv6 VPS (enable IPv6 via WARP)
             echo "No native IPv6 detected. Adding fallback routing rule (compatible with Table=off)..."
             # Add low priority rule to look up table 51820 AND explicitly add the route
             # This allows it to work even if 'Table = off' is set in wgcf.conf (user manual change)
             # We inject ip -6 route replace to ensure the route exists in table 51820
             sed -i "/^\[Interface\]/a PostUp = ip -6 rule add from all lookup 51820 prio 40000\nPostUp = ip -6 route replace default dev wgcf table 51820\nPostDown = ip -6 rule delete from all lookup 51820 prio 30000" wgcf.conf
        fi
    else
        echo "⚠ Warning: Could not detect primary interface IP. Routing fix skipped."
    fi
    # -------------------

    # --- Endpoint Fix (IPv4 Only Support) ---
    # If no global IPv6 address is found, force the endpoint to IPv4
    # to prevent connection issues on strict IPv4 systems.
    # Check for any global IPv6 address
    local has_ipv6=$(ip -6 addr show scope global 2>/dev/null | grep inet6)
    
    if [ -z "$has_ipv6" ]; then
        echo "No global IPv6 detected. Forcing WARP endpoint to IPv4..."
        # Default WARP IPv4 endpoint (Anycast)
        local warp_endpoint_ip="162.159.192.1"
        
        # Replace the domain with the IP in the config
        if grep -q "engage.cloudflareclient.com" wgcf.conf; then
            sed -i "s/engage.cloudflareclient.com/$warp_endpoint_ip/g" wgcf.conf
            echo "Endpoint updated to $warp_endpoint_ip"
        fi
    fi
    # ----------------------------------------
    
    # 4. Enable and Start
    echo "Enabling and starting WARP interface..."
    systemctl enable wg-quick@wgcf
    systemctl start wg-quick@wgcf
    
    # Verify
    if systemctl is-active --quiet wg-quick@wgcf; then
        echo "✓ WARP (WireGuard) service started successfully"
        echo "Interface: wgcf"
    else
        echo "⚠ Warning: WARP service failed to start"
        echo "Check logs with: journalctl -u wg-quick@wgcf -n 50"
    fi
}

# Setup ACME (Let's Encrypt)
setup_acme() {
    if [ "$ENABLE_ACME" != "true" ]; then
        print_step "Certificate setup skipped (ENABLE_ACME=$ENABLE_ACME)"
        return 0
    fi
    
    # Create certificate directory
    if [ ! -d "$ACME_CERT_PATH" ]; then
        echo "Creating certificate directory: $ACME_CERT_PATH"
        mkdir -p "$ACME_CERT_PATH"
        chmod 755 "$ACME_CERT_PATH"
    fi
    
    # Check if domain is configured
    if [ -z "$ACME_DOMAIN" ]; then
        echo "ACME_DOMAIN is not set. Skipping certificate issuance."
        return 0
    fi
    
    # Check if certificate files already exist
    if [ -f "$ACME_CERT_PATH/$ACME_DOMAIN.crt" ] && [ -f "$ACME_CERT_PATH/$ACME_DOMAIN.key" ]; then
        echo "Certificate for $ACME_DOMAIN already exists."
        echo "Certificate: $ACME_CERT_PATH/$ACME_DOMAIN.crt"
        echo "Key: $ACME_CERT_PATH/$ACME_DOMAIN.key"
        
        # Calculate and display pinSHA256 for existing certificate
        echo ""
        echo "Certificate pinSHA256:"
        openssl x509 -noout -fingerprint -sha256  -in "$ACME_CERT_PATH/$ACME_DOMAIN.crt"
        echo ""
        return 0
    fi
    
    # Self-signed certificate
    if [ "$ACME_USE_SELFSIGNED" = "true" ]; then
        print_step "Generating self-signed certificate for $ACME_DOMAIN..."
        
        # Generate private key
        echo "Generating private key..."
        openssl genrsa -out "$ACME_CERT_PATH/$ACME_DOMAIN.key" 2048
        
        # Generate self-signed certificate (valid for 10 years)
        echo "Generating self-signed certificate (valid for 10 years)..."
        openssl req -new -x509 -key "$ACME_CERT_PATH/$ACME_DOMAIN.key" \
            -out "$ACME_CERT_PATH/$ACME_DOMAIN.crt" \
            -days 3650 \
            -subj "/CN=$ACME_DOMAIN"
        
        if [ -f "$ACME_CERT_PATH/$ACME_DOMAIN.crt" ] && [ -f "$ACME_CERT_PATH/$ACME_DOMAIN.key" ]; then
            echo "✓ Self-signed certificate generated successfully"
            echo ""
            echo "Certificate: $ACME_CERT_PATH/$ACME_DOMAIN.crt"
            echo "Key: $ACME_CERT_PATH/$ACME_DOMAIN.key"
            echo ""
            
            # Calculate and display pinSHA256
            echo "=========================================="
            echo "Certificate pinSHA256 (for certificate pinning):"
            echo "=========================================="
            local pin_sha256=$(openssl x509 -noout -fingerprint -sha256  -in "$ACME_CERT_PATH/$ACME_DOMAIN.crt")
            echo "$pin_sha256"
            echo "=========================================="
            echo ""
            echo "Use this pinSHA256 value for certificate pinning in your applications."
            echo ""
        else
            echo "Error: Failed to generate self-signed certificate"
            return 1
        fi
    else
        # Let's Encrypt certificate
        print_step "Setting up Let's Encrypt certificate..."
        
        # Check email configuration
        if [ -z "$ACME_EMAIL" ] || [ "$ACME_EMAIL" = "admin@example.com" ]; then
            echo "⚠ Warning: ACME_EMAIL is not set or using default. Please configure a valid email."
            echo "Proceeding with installation strictly for acme.sh..."
        fi
        
        # Install dependencies
        echo "Installing dependencies (socat, cron)..."
        wait_for_lock
        $PM $PM_INSTALL socat cron
        
        # Install acme.sh
        if [ ! -d "$HOME/.acme.sh" ]; then
            echo "Installing acme.sh..."
            curl https://get.acme.sh | sh -s email="$ACME_EMAIL"
            
            # Verify installation
            if [ -f "$HOME/.acme.sh/acme.sh" ]; then
                echo "✓ acme.sh installed successfully"
                
                # Create alias manually for current session usage if needed
                alias acme.sh="$HOME/.acme.sh/acme.sh"
                
                echo "Use 'acme.sh' command to manage certificates."
                echo "Certificates will be stored in: $ACME_CERT_PATH (user configured location)" 
            else
                echo "Error: acme.sh installation failed."
                return 1
            fi
        else
            echo "acme.sh is already installed."
        fi
        
        print_step "Issuing certificate for $ACME_DOMAIN..."
        echo "Issuing certificate using standalone mode (Port 80)..."
        # Stop any service listening on port 80 if necessary (though usually init.sh runs on fresh VPS)
        # We assume port 80 is free or we might need to stop nginx/apache temporarily if they were installed.
        # For this init script, we assume no web server is running yet.
        
        if "$HOME/.acme.sh/acme.sh" --server letsencrypt --issue -d "$ACME_DOMAIN" --standalone --httpport 80; then
            echo "✓ Certificate issued successfully."
            
            # Install certificate
            echo "Installing certificate to $ACME_CERT_PATH..."
            "$HOME/.acme.sh/acme.sh"  --server letsencrypt --install-cert -d "$ACME_DOMAIN" \
                --key-file       "$ACME_CERT_PATH/$ACME_DOMAIN.key"  \
                --fullchain-file "$ACME_CERT_PATH/$ACME_DOMAIN.crt" \
                --reloadcmd     "echo 'Certificate updated.'"
                
            echo "Certificate installed: $ACME_CERT_PATH/$ACME_DOMAIN.crt"
            echo "Key installed: $ACME_CERT_PATH/$ACME_DOMAIN.key"
        else
            echo "Error: Failed to issue certificate for $ACME_DOMAIN"
            return 1
        fi
    fi
    
    chmod -R 755 "$ACME_CERT_PATH"
}

custome_hook(){
    local target_dir="${1:-.}"
    echo "Executing custom hooks from $target_dir..."
    
    local exec_fun_file="$target_dir/exec_fun.txt"
    local hook_script="$target_dir/custome_hook.sh"
    
    if [ ! -f "$exec_fun_file" ]; then
        echo "Warning: $exec_fun_file not found. Skipping hooks."
        return
    fi
    
    while IFS=" " read -r func_name args; do
        execute_if_exists "$hook_script" "$func_name" "$args"
        # echo "Executing $func_name with args: $args"
    done < "$exec_fun_file"
}
