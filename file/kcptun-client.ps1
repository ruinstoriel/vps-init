# ============================================
# KCPtun Client Connection Script (PowerShell)
# ============================================
# This script helps you connect to your VPS using KCPtun acceleration
# 
# Prerequisites:
# 1. Download KCPtun client for Windows from:
#    https://github.com/xtaci/kcptun/releases
# 2. Extract client_windows_amd64.exe
# 3. Update the variables below with your VPS information
# ============================================

# ============================================
# Configuration
# ============================================

# Your VPS IP address
$VPS_IP = "YOUR_VPS_IP"

# KCPtun server port (default: SSH_PORT + 1)
$KCPTUN_PORT = "2201"

# Local port to listen on (you'll connect to localhost:LOCAL_PORT)
$LOCAL_PORT = "2200"

# Path to KCPtun client binary
$KCPTUN_CLIENT = ".\client_windows_amd64.exe"

# ============================================
# Main Script
# ============================================

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "KCPtun SSH Acceleration Client" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:"
Write-Host "  - VPS Server: $VPS_IP`:$KCPTUN_PORT"
Write-Host "  - Local Port: $LOCAL_PORT"
Write-Host "  - Client Binary: $KCPTUN_CLIENT"
Write-Host ""
Write-Host "After KCPtun starts, connect to SSH using:" -ForegroundColor Yellow
Write-Host "  ssh -p $LOCAL_PORT root@localhost" -ForegroundColor Green
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Check if client binary exists
if (-not (Test-Path $KCPTUN_CLIENT)) {
    Write-Host "Error: KCPtun client binary not found: $KCPTUN_CLIENT" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please download KCPtun client from:"
    Write-Host "  https://github.com/xtaci/kcptun/releases" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Look for: kcptun-windows-amd64-YYYYMMDD.tar.gz"
    exit 1
}

# Start KCPtun client
Write-Host "Starting KCPtun client..." -ForegroundColor Green
Write-Host ""

& $KCPTUN_CLIENT `
    -r "${VPS_IP}:${KCPTUN_PORT}" `
    -l ":${LOCAL_PORT}" `
    -mode fast3 `
    -nocomp `
    -autoexpire 900 `
    -sockbuf 16777217 `
    -dscp 46
