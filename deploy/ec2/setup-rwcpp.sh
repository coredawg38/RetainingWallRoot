#!/bin/bash
# =============================================================================
# setup-rwcpp.sh - Manual rwcpp Server Setup
# =============================================================================
# This script manually builds and deploys the rwcpp server.
# Typically, this is handled by GitHub Actions, but this script
# can be used for initial setup or troubleshooting.
#
# Prerequisites:
#   - provision.sh has been run
#   - rwcpp source code is available
#
# Usage:
#   ./setup-rwcpp.sh [source-path]
# =============================================================================

set -euo pipefail

SOURCE_PATH="${1:-/tmp/rwcpp}"
APP_DIR="/opt/rwcpp"
DEPLOY_USER="github-deploy"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=============================================="
echo "rwcpp Server Manual Setup"
echo "=============================================="
echo ""

# Check if source exists
if [[ ! -d "${SOURCE_PATH}" ]]; then
    log_error "Source directory not found: ${SOURCE_PATH}"
    echo ""
    echo "Options:"
    echo "1. Clone from GitHub:"
    echo "   git clone https://github.com/your-org/rwcpp.git ${SOURCE_PATH}"
    echo ""
    echo "2. Copy from local machine:"
    echo "   scp -r ./rwcpp ubuntu@server:${SOURCE_PATH}"
    exit 1
fi

# Check for required files
if [[ ! -f "${SOURCE_PATH}/Makefile" ]]; then
    log_error "Makefile not found in ${SOURCE_PATH}"
    exit 1
fi

log_info "Building from: ${SOURCE_PATH}"
echo ""

# =============================================================================
# 1. Build mailio (email library)
# =============================================================================
log_info "[1/4] Building mailio library..."

MAILIO_PATH="${SOURCE_PATH}/../mailio"
if [[ -d "${MAILIO_PATH}" ]]; then
    cd "${MAILIO_PATH}"

    if [[ ! -d "build" ]]; then
        mkdir build
    fi

    cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc)
    sudo make install
    sudo ldconfig

    log_info "mailio built and installed"
else
    log_warn "mailio directory not found at ${MAILIO_PATH}"
    log_warn "Email functionality may not work"
fi

# =============================================================================
# 2. Build rwcpp server
# =============================================================================
log_info "[2/4] Building rwcpp server..."

cd "${SOURCE_PATH}"

# Clean previous build
make clean 2>/dev/null || true

# Build server
make retainingwall-server

if [[ ! -f "retainingwall-server" ]]; then
    log_error "Build failed - retainingwall-server not created"
    exit 1
fi

log_info "Server built successfully"

# =============================================================================
# 3. Deploy binary
# =============================================================================
log_info "[3/4] Deploying server binary..."

# Stop service if running
sudo systemctl stop rwcpp 2>/dev/null || true

# Copy binary
sudo cp retainingwall-server "${APP_DIR}/retainingwall-server.new"
sudo chmod +x "${APP_DIR}/retainingwall-server.new"

# Backup old binary if exists
if [[ -f "${APP_DIR}/retainingwall-server" ]]; then
    sudo mv "${APP_DIR}/retainingwall-server" "${APP_DIR}/retainingwall-server.old"
fi

# Activate new binary
sudo mv "${APP_DIR}/retainingwall-server.new" "${APP_DIR}/retainingwall-server"

# Copy images if they exist
if [[ -d "${SOURCE_PATH}/images" ]]; then
    sudo cp -r "${SOURCE_PATH}/images/"* "${APP_DIR}/images/" 2>/dev/null || true
fi

# Set ownership
sudo chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}"

log_info "Binary deployed to ${APP_DIR}"

# =============================================================================
# 4. Start service
# =============================================================================
log_info "[4/4] Starting rwcpp service..."

# Check if .env exists
if [[ ! -f "${APP_DIR}/.env" ]]; then
    log_warn "Environment file ${APP_DIR}/.env not found"
    log_warn "Server may not function correctly without configuration"
fi

# Start service
sudo systemctl start rwcpp

# Wait and check status
sleep 2

if sudo systemctl is-active --quiet rwcpp; then
    log_info "Service started successfully"
else
    log_error "Service failed to start"
    log_error "Check logs: journalctl -u rwcpp -n 50"
    exit 1
fi

# Test health endpoint
sleep 2
if curl -sf http://localhost:8080/health > /dev/null; then
    log_info "Health check passed"
else
    log_warn "Health check failed - server may still be starting"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
echo "rwcpp Setup Complete!"
echo "=============================================="
echo ""
echo "Server Status:"
sudo systemctl status rwcpp --no-pager | head -10
echo ""
echo "Test commands:"
echo "  curl http://localhost:8080/health"
echo "  curl http://localhost:8080/api/v1/docs"
echo ""
echo "View logs:"
echo "  sudo journalctl -u rwcpp -f"
echo "  tail -f /var/log/rwcpp/server.log"
echo ""
echo "Manage service:"
echo "  sudo systemctl start rwcpp"
echo "  sudo systemctl stop rwcpp"
echo "  sudo systemctl restart rwcpp"
