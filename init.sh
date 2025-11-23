#!/bin/bash

# VPS Initialization Script
# Usage: ./init.sh "YOUR_PUBLIC_KEY"
# Example: ./init.sh "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."

PUB_KEY=$(<id_ed25519.pub)

if [ -z "$PUB_KEY" ]; then
    echo "Error: No public key provided."
    echo "Usage: $0 \"ssh-rsa ...\""
    exit 1
fi

# Ensure running as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

echo "Starting VPS Initialization..."

# 1. Setup SSH Key
echo "Setting up SSH key..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Check if key already exists to avoid duplicates
AUTH_KEYS="$HOME/.ssh/authorized_keys"
if [ ! -f "$AUTH_KEYS" ]; then
    echo "$PUB_KEY" > "$AUTH_KEYS"
else
    grep -qF "$PUB_KEY" "$AUTH_KEYS" || echo "$PUB_KEY" >> "$AUTH_KEYS"
fi
chmod 600 ~/.ssh/authorized_keys
echo "SSH key added."

# 2. SSH Hardening
echo "Configuring SSH..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp $SSHD_CONFIG "${SSHD_CONFIG}.bak"

# Disable Password Authentication
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' $SSHD_CONFIG
sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' $SSHD_CONFIG
sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' $SSHD_CONFIG
# Disable PAM 
# WARNING: 'UsePAM no' is not supported in RHEL and may cause several problems.
# sed -i 's/^#\?UsePAM.*/UsePAM no/' $SSHD_CONFIG

# Disable Root Password Login (Allow keys)
# 'prohibit-password' is the default in many modern distros but let's enforce it
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' $SSHD_CONFIG

# Restart SSH to apply changes
if systemctl is-active --quiet ssh; then
    systemctl restart ssh
elif systemctl is-active --quiet sshd; then
    systemctl restart sshd
fi
echo "SSH configured and restarted."

# 3. Remove iptables / Install nftables
echo "Managing firewalls..."

# Detect Package Manager
if command -v apt-get &> /dev/null; then
    PM="apt-get"
    PM_INSTALL="install -y"
    PM_REMOVE="remove -y --purge"
    PM_UPDATE="update"
elif command -v dnf &> /dev/null; then
    PM="dnf"
    PM_INSTALL="install -y"
    PM_REMOVE="remove -y"
    PM_UPDATE="makecache"
elif command -v yum &> /dev/null; then
    PM="yum"
    PM_INSTALL="install -y"
    PM_REMOVE="remove -y"
    PM_UPDATE="makecache"
else
    echo "Error: Unsupported package manager. Cannot install nftables."
    exit 1
fi

# Update package list
$PM $PM_UPDATE

# Install nftables
$PM $PM_INSTALL nftables

# Verify installation and fix path if needed
if ! command -v nft &> /dev/null; then
    echo "Error: nftables installation failed. 'nft' command not found."
    exit 1
fi

NFT_BIN=$(command -v nft)
echo "nft found at: $NFT_BIN"

# Fix for systemd units that hardcode /sbin/nft (common on some RHEL/CentOS versions)
if [ ! -x /sbin/nft ] && [ -x "$NFT_BIN" ]; then
    echo "Symlinking $NFT_BIN to /sbin/nft to satisfy systemd..."
    ln -s "$NFT_BIN" /sbin/nft
fi

# Stop and disable other firewalls if present
systemctl stop ufw 2>/dev/null
systemctl disable ufw 2>/dev/null
systemctl stop firewalld 2>/dev/null
systemctl disable firewalld 2>/dev/null

# Flush iptables rules
iptables -F 2>/dev/null
iptables -X 2>/dev/null
ip6tables -F 2>/dev/null
ip6tables -X 2>/dev/null

# Try to remove iptables-persistent or ufw if desired, but removing 'iptables' package 
# can be risky if other tools depend on it. 
# The user asked to "delete iptables", we will try to purge the package if it's not essential for system.
# SAFE MODE: Just disable it and let nftables take over.
# AGGRESSIVE MODE (User Request):
# Note: On RHEL/CentOS, 'iptables' might be a dependency for other things or base system, 
# but 'iptables-services' is the service. We'll try to remove the firewall managers.
if [ "$PM" = "apt-get" ]; then
    $PM $PM_REMOVE iptables ufw firewalld
    NFT_CONF="/etc/nftables.conf"
else
    $PM $PM_REMOVE iptables-services firewalld ufw
    # RHEL/AlmaLinux usually uses /etc/sysconfig/nftables.conf
    NFT_CONF="/etc/sysconfig/nftables.conf"
    # Ensure the directory exists
    mkdir -p /etc/sysconfig
fi

# 3.5. Diable IPv6 autoconfig and router advertisements
echo "Configuring IPv6..."
sysctl -w net.ipv6.conf.all.autoconf=0
sysctl -w net.ipv6.conf.all.accept_ra=0
sysctl -w net.ipv6.conf.eth0.autoconf=0
sysctl -w net.ipv6.conf.eth0.accept_ra=0

# Find the primary network interface (usually eth0, ens3, etc.)
PRIMARY_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -n "$PRIMARY_IF" ]; then
    echo "Enabling IPv6 on interface: $PRIMARY_IF"
    sysctl -w net.ipv6.conf.$PRIMARY_IF.autoconf=0
    sysctl -w net.ipv6.conf.$PRIMARY_IF.accept_ra=0
fi

# Make changes persistent
cat >> /etc/sysctl.d/99-ipv6.conf << EOF
# Disable IPv6 autoconfig and router advertisements
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.eth0.autoconf = 0
net.ipv6.conf.eth0.accept_ra = 0
EOF

if [ -n "$PRIMARY_IF" ]; then
    cat >> /etc/sysctl.d/99-ipv6.conf << EOF
net.ipv6.conf.$PRIMARY_IF.autoconf = 0
net.ipv6.conf.$PRIMARY_IF.accept_ra = 0
EOF
fi

echo "IPv6 autoconfig and router advertisements disabled."

# Check and fix IPv6 disable settings in sysctl.conf
echo "Checking IPv6 disable settings..."
SYSCTL_CONF="/etc/sysctl.conf"

# Ensure IPv6 is NOT disabled (disable_ipv6 should be 0)
if grep -q "net.ipv6.conf.all.disable_ipv6" "$SYSCTL_CONF" 2>/dev/null; then
    sed -i 's/^net.ipv6.conf.all.disable_ipv6.*/net.ipv6.conf.all.disable_ipv6 = 0/' "$SYSCTL_CONF"
else
    echo "net.ipv6.conf.all.disable_ipv6 = 0" >> "$SYSCTL_CONF"
fi

if grep -q "net.ipv6.conf.default.disable_ipv6" "$SYSCTL_CONF" 2>/dev/null; then
    sed -i 's/^net.ipv6.conf.default.disable_ipv6.*/net.ipv6.conf.default.disable_ipv6 = 0/' "$SYSCTL_CONF"
else
    echo "net.ipv6.conf.default.disable_ipv6 = 0" >> "$SYSCTL_CONF"
fi

if grep -q "net.ipv6.conf.lo.disable_ipv6" "$SYSCTL_CONF" 2>/dev/null; then
    sed -i 's/^net.ipv6.conf.lo.disable_ipv6.*/net.ipv6.conf.lo.disable_ipv6 = 0/' "$SYSCTL_CONF"
else
    echo "net.ipv6.conf.lo.disable_ipv6 = 0" >> "$SYSCTL_CONF"
fi

# Apply the settings immediately
sysctl -w net.ipv6.conf.all.disable_ipv6=0
sysctl -w net.ipv6.conf.default.disable_ipv6=0
sysctl -w net.ipv6.conf.lo.disable_ipv6=0

echo "IPv6 disable settings fixed."

systemctl restart network 
# 4. Configure nftables
echo "Applying nftables configuration to $NFT_CONF..."
cp ./nftables.conf "$NFT_CONF"

# Fix Windows line endings (CRLF) which cause syntax errors in nft
sed -i 's/\r$//' "$NFT_CONF"

chmod 600 "$NFT_CONF"

# Update shebang in config file to match actual binary location
sed -i "1s|^#!.*|#!$NFT_BIN -f|" "$NFT_CONF"

# Enable and start nftables
systemctl enable nftables
systemctl restart nftables

echo "nftables installed and configured."

echo "==================================================="
echo "VPS Initialization Complete."
echo "PLEASE VERIFY you can SSH in with your key BEFORE closing this session!"
echo "==================================================="
