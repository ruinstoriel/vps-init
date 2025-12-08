#!/bin/bash

# ============================================
# KCPtun Client Connection Script
# ============================================
# This script helps you connect to your VPS using KCPtun acceleration
# 
# Prerequisites:
# 1. Download KCPtun client for your platform from:
#    https://github.com/xtaci/kcptun/releases
# 2. Extract the client binary (e.g., client_linux_amd64, client_darwin_amd64, client_windows_amd64.exe)
# 3. Update the variables below with your VPS information
# ============================================

# ============================================
# Configuration
# ============================================

# Your VPS IP address
VPS_IP="YOUR_VPS_IP"

# KCPtun server port (default: SSH_PORT + 1)
KCPTUN_PORT="2201"

# Local port to listen on (you'll connect to localhost:LOCAL_PORT)
LOCAL_PORT="2200"

# Path to KCPtun client binary
# Linux/Mac examples:
#   ./client_linux_amd64
#   ./client_darwin_amd64
# Windows example:
#   ./client_windows_amd64.exe
KCPTUN_CLIENT="./client_linux_amd64"

# ============================================
# Main Script
# ============================================

echo "=================================================="
echo "KCPtun SSH Acceleration Client"
echo "=================================================="
echo ""
echo "Configuration:"
echo "  - VPS Server: $VPS_IP:$KCPTUN_PORT"
echo "  - Local Port: $LOCAL_PORT"
echo "  - Client Binary: $KCPTUN_CLIENT"
echo ""
echo "After KCPtun starts, connect to SSH using:"
echo "  ssh -p $LOCAL_PORT root@localhost"
echo ""
echo "=================================================="
echo ""

# Check if client binary exists
if [ ! -f "$KCPTUN_CLIENT" ]; then
    echo "Error: KCPtun client binary not found: $KCPTUN_CLIENT"
    echo ""
    echo "Please download KCPtun client from:"
    echo "  https://github.com/xtaci/kcptun/releases"
    echo ""
    echo "Or use the download script:"
    echo "  curl -L https://raw.githubusercontent.com/xtaci/kcptun/master/download.sh | sh"
    exit 1
fi

# Make sure it's executable
chmod +x "$KCPTUN_CLIENT"

# Start KCPtun client
echo "Starting KCPtun client..."
echo ""

"$KCPTUN_CLIENT" \
    -r "${VPS_IP}:${KCPTUN_PORT}" \
    -l ":${LOCAL_PORT}" \
    -mode fast3 \
    -nocomp \
    -autoexpire 900 \
    -sockbuf 16777217 \
    -dscp 46
