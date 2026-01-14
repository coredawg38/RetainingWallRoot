#!/bin/bash
# =============================================================================
# provision.sh - Full EC2 Instance Provisioning for Retaining Wall
# =============================================================================
# This script installs all dependencies and configures the server:
#   - System packages (build tools, nginx, certbot)
#   - C++ build dependencies (Cairo, Boost, OpenSSL, etc.)
#   - Application directories and users
#   - Systemd service for rwcpp
#   - Nginx configuration
#
# Prerequisites:
#   - Running on Ubuntu 22.04 EC2 instance
#   - Run as root or with sudo
#
# Usage:
#   sudo ./provision.sh [domain-name]
#
# Example:
#   sudo ./provision.sh retainingwall.example.com
# =============================================================================

set -euo pipefail

# Configuration
DOMAIN_NAME="${1:-}"
APP_DIR="/opt/rwcpp"
WEB_DIR="/var/www/retainingwall"
LOG_DIR="/var/log/rwcpp"
DEPLOY_USER="github-deploy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=============================================="
echo "Retaining Wall Server Provisioning"
echo "=============================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Prompt for domain if not provided
if [[ -z "${DOMAIN_NAME}" ]]; then
    read -p "Enter domain name (e.g., retainingwall.example.com): " DOMAIN_NAME
    if [[ -z "${DOMAIN_NAME}" ]]; then
        log_error "Domain name is required"
        exit 1
    fi
fi

log_info "Domain: ${DOMAIN_NAME}"
echo ""

# =============================================================================
# 1. System Update and Essential Packages
# =============================================================================
log_info "[1/8] Updating system and installing essential packages..."

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

apt-get install -y \
    curl \
    git \
    htop \
    jq \
    unzip \
    wget \
    vim \
    tmux \
    fail2ban \
    ufw

log_info "Essential packages installed"

# =============================================================================
# 2. Install Build Dependencies for rwcpp
# =============================================================================
log_info "[2/8] Installing C++ build dependencies..."

apt-get install -y \
    build-essential \
    g++ \
    make \
    cmake \
    pkg-config \
    libcairo2-dev \
    libcurl4-openssl-dev \
    libsqlite3-dev \
    libssl-dev \
    libboost-all-dev

log_info "C++ build dependencies installed"

# =============================================================================
# 3. Install Nginx
# =============================================================================
log_info "[3/8] Installing Nginx..."

apt-get install -y nginx

# Remove default site
rm -f /etc/nginx/sites-enabled/default

log_info "Nginx installed"

# =============================================================================
# 4. Install Certbot
# =============================================================================
log_info "[4/8] Installing Certbot for SSL certificates..."

apt-get install -y certbot python3-certbot-nginx

log_info "Certbot installed"

# =============================================================================
# 5. Create Directories
# =============================================================================
log_info "[5/8] Creating application directories..."

mkdir -p "${APP_DIR}"/{outputs,data,images,inputs}
mkdir -p "${WEB_DIR}"
mkdir -p "${LOG_DIR}"
mkdir -p /var/www/certbot

log_info "Directories created:"
log_info "  App: ${APP_DIR}"
log_info "  Web: ${WEB_DIR}"
log_info "  Logs: ${LOG_DIR}"

# =============================================================================
# 6. Create Deploy User
# =============================================================================
log_info "[6/8] Creating deployment user..."

if ! id "${DEPLOY_USER}" &>/dev/null; then
    useradd -m -s /bin/bash "${DEPLOY_USER}"
    log_info "User '${DEPLOY_USER}' created"
else
    log_info "User '${DEPLOY_USER}' already exists"
fi

# Setup SSH directory for deploy user
mkdir -p "/home/${DEPLOY_USER}/.ssh"
chmod 700 "/home/${DEPLOY_USER}/.ssh"
touch "/home/${DEPLOY_USER}/.ssh/authorized_keys"
chmod 600 "/home/${DEPLOY_USER}/.ssh/authorized_keys"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh"

# Add deploy user to www-data group
usermod -aG www-data "${DEPLOY_USER}"

# Set directory ownership
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}"
chown -R www-data:www-data "${WEB_DIR}"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${LOG_DIR}"

# Allow deploy user to restart services without password
cat > /etc/sudoers.d/github-deploy << 'EOF'
github-deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart rwcpp
github-deploy ALL=(ALL) NOPASSWD: /bin/systemctl stop rwcpp
github-deploy ALL=(ALL) NOPASSWD: /bin/systemctl start rwcpp
github-deploy ALL=(ALL) NOPASSWD: /bin/systemctl status rwcpp
github-deploy ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx
github-deploy ALL=(ALL) NOPASSWD: /bin/cp * /var/www/retainingwall/*
github-deploy ALL=(ALL) NOPASSWD: /bin/mv * /var/www/retainingwall/*
github-deploy ALL=(ALL) NOPASSWD: /bin/rm -rf /var/www/retainingwall/*
github-deploy ALL=(ALL) NOPASSWD: /bin/chown -R www-data\:www-data /var/www/retainingwall
github-deploy ALL=(ALL) NOPASSWD: /bin/chmod -R 755 /var/www/retainingwall
EOF

chmod 440 /etc/sudoers.d/github-deploy

log_info "Deploy user configured with limited sudo access"

# =============================================================================
# 7. Install Systemd Service
# =============================================================================
log_info "[7/8] Installing systemd service..."

cat > /etc/systemd/system/rwcpp.service << EOF
[Unit]
Description=Retaining Wall C++ Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${DEPLOY_USER}
Group=${DEPLOY_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/retainingwall-server
Restart=always
RestartSec=5
StandardOutput=append:${LOG_DIR}/server.log
StandardError=append:${LOG_DIR}/error.log
EnvironmentFile=${APP_DIR}/.env

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${APP_DIR}/outputs ${APP_DIR}/data ${LOG_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rwcpp

log_info "Systemd service installed and enabled"

# =============================================================================
# 8. Configure Nginx
# =============================================================================
log_info "[8/8] Configuring Nginx..."

# Create initial HTTP-only config for certbot
cat > /etc/nginx/sites-available/retainingwall << EOF
# Retaining Wall Nginx Configuration
# Domain: ${DOMAIN_NAME}
# Generated: $(date)

# Rate limiting zones
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
limit_req_zone \$binary_remote_addr zone=general_limit:10m rate=30r/s;

# HTTP server - Let's Encrypt challenge and redirect
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME};

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Redirect all other HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server (will be updated after certbot)
# Placeholder until SSL certificate is obtained
EOF

ln -sf /etc/nginx/sites-available/retainingwall /etc/nginx/sites-enabled/retainingwall

# Create placeholder index.html
cat > "${WEB_DIR}/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Retaining Wall Design</title>
    <style>
        body { font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #f5f5f5; }
        .message { text-align: center; padding: 40px; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; }
        p { color: #666; }
    </style>
</head>
<body>
    <div class="message">
        <h1>Retaining Wall Design</h1>
        <p>Server is running. Application deployment pending.</p>
    </div>
</body>
</html>
EOF

chown www-data:www-data "${WEB_DIR}/index.html"

nginx -t && systemctl restart nginx

log_info "Nginx configured"

# =============================================================================
# 9. Configure Firewall
# =============================================================================
log_info "Configuring firewall..."

ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

log_info "Firewall enabled (SSH, HTTP, HTTPS allowed)"

# =============================================================================
# 10. Create Environment File Template
# =============================================================================
log_info "Creating environment file template..."

if [[ ! -f "${APP_DIR}/.env" ]]; then
    cat > "${APP_DIR}/.env" << 'EOF'
# Retaining Wall Server Environment Configuration
# Fill in these values before starting the server

# SMTP Configuration (for sending PDFs via email)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USE_SSL=true
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM_EMAIL=noreply@your-domain.com
SMTP_FROM_NAME=Retaining Wall Design

# Stripe Configuration (REQUIRED)
STRIPE_SECRET_KEY=sk_live_your_stripe_secret_key

# Application Configuration
BASE_URL=https://your-domain.com
EOF
    chown "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}/.env"
    chmod 600 "${APP_DIR}/.env"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
echo "Provisioning Complete!"
echo "=============================================="
echo ""
echo "Installed:"
echo "  - Build tools (g++, make, cmake)"
echo "  - Cairo, Boost, OpenSSL, libcurl, SQLite"
echo "  - Nginx web server"
echo "  - Certbot for SSL"
echo "  - Fail2ban security"
echo "  - UFW firewall"
echo ""
echo "Created:"
echo "  - User: ${DEPLOY_USER}"
echo "  - App directory: ${APP_DIR}"
echo "  - Web directory: ${WEB_DIR}"
echo "  - Log directory: ${LOG_DIR}"
echo "  - Systemd service: rwcpp.service"
echo ""
echo "=============================================="
echo "NEXT STEPS"
echo "=============================================="
echo ""
echo "1. Add GitHub deploy key to authorized_keys:"
echo "   nano /home/${DEPLOY_USER}/.ssh/authorized_keys"
echo "   # Paste the public key from GitHub Secrets"
echo ""
echo "2. Configure SSL certificate (after DNS propagates):"
echo "   sudo ./setup-certbot.sh ${DOMAIN_NAME} admin@${DOMAIN_NAME}"
echo ""
echo "3. Configure environment variables:"
echo "   sudo nano ${APP_DIR}/.env"
echo "   # Set SMTP and Stripe credentials"
echo ""
echo "4. Push code to GitHub to trigger deployment"
echo ""
echo "For manual testing, you can:"
echo "  - Check nginx: sudo nginx -t && sudo systemctl status nginx"
echo "  - Check rwcpp: sudo systemctl status rwcpp"
echo "  - View logs: tail -f ${LOG_DIR}/server.log"
