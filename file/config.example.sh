#!/bin/bash

# ============================================
# Configuration Variables (Example)
# Rename this file to config.sh and update values
# ============================================

# Set to "true" to enable timezone configuration, "false" to skip
ENABLE_TIMEZONE="true"

# Timezone setting
TIMEZONE="Asia/Shanghai"

# Set to "true" to enable SSH key setup, "false" to skip
ENABLE_SSH_KEY="true"

# Set to "true" to enable SSH hardening, "false" to skip
ENABLE_SSH_HARDENING="true"

# SSH Port
SSH_PORT="2200"

# Set to "true" to enable firewall setup, "false" to skip
ENABLE_FIREWALL="true"

# Set to "true" to enable IPv6 configuration, "false" to skip
ENABLE_IPV6="false"

# Set to "true" to enable TCP BBR, "false" to skip
ENABLE_TCP_BBR="true"

# Set to "true" to enable nftables configuration, "false" to skip
ENABLE_NFTABLES="true"

# Set to "true" to enable Fail2ban, "false" to skip
ENABLE_FAIL2BAN="true"

# Set to "true" to enable SYN flood detection, "false" to skip
ENABLE_SYN_FLOOD_DETECTION="true"

# Set to "true" to enable KCPtun SSH acceleration, "false" to skip
ENABLE_KCPTUN="true"

# KCPtun port (SSH_PORT + 1 by default)
KCPTUN_PORT=$((SSH_PORT + 1))

# Set to "true" to enable Cloudflare WARP, "false" to skip
ENABLE_WARP="true"

# Public key file
# Ensure this file exists in the same directory or provide content directly
PUB_KEY=$(<id_ed25519.pub)

# Set to "true" to enable ACME (Let's Encrypt) setup, "false" to skip
ENABLE_ACME="true"

# Set to "true" to use self-signed certificate, "false" to use Let's Encrypt
ACME_USE_SELFSIGNED="false"

# Email for ACME registration (only used for Let's Encrypt)
ACME_EMAIL="admin@example.com"

# Directory to store certificates
ACME_CERT_PATH="/etc/ssl/acme"

# Domain for certificate (leave empty to skip issuance)
ACME_DOMAIN="example.com"
