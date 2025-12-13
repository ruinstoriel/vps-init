#!/bin/bash

# ============================================
# Configuration Variables (Example)
# Rename this file to config.sh and update values
# ============================================

# Set to "true" to enable IPv6 configuration, "false" to skip
ENABLE_IPV6="false"

# Timezone setting
TIMEZONE="Asia/Shanghai"

# SSH Port
SSH_PORT="2200"

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

# Email for ACME registration
ACME_EMAIL="admin@example.com"

# Directory to store certificates
ACME_CERT_PATH="/etc/ssl/acme"

# Domain for ACME certificate (leave empty to skip issuance)
ACME_DOMAIN="example.com"
