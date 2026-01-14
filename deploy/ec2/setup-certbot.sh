#!/bin/bash
# =============================================================================
# setup-certbot.sh - Obtain SSL Certificate and Configure HTTPS
# =============================================================================
# This script:
#   - Obtains SSL certificate from Let's Encrypt
#   - Configures Nginx for HTTPS with SSL termination
#   - Sets up automatic certificate renewal
#
# Prerequisites:
#   - DNS is pointing to this server
#   - Nginx is installed and running
#   - Port 80 is accessible from the internet
#
# Usage:
#   sudo ./setup-certbot.sh <domain> <email>
#
# Example:
#   sudo ./setup-certbot.sh retainingwall.example.com admin@example.com
# =============================================================================

set -euo pipefail

DOMAIN_NAME="${1:-}"
ADMIN_EMAIL="${2:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=============================================="
echo "SSL Certificate Setup"
echo "=============================================="
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Validate arguments
if [[ -z "${DOMAIN_NAME}" ]]; then
    read -p "Enter domain name: " DOMAIN_NAME
fi

if [[ -z "${ADMIN_EMAIL}" ]]; then
    read -p "Enter admin email: " ADMIN_EMAIL
fi

log_info "Domain: ${DOMAIN_NAME}"
log_info "Email: ${ADMIN_EMAIL}"
echo ""

# =============================================================================
# 1. Verify DNS
# =============================================================================
log_info "[1/4] Verifying DNS..."

# Get server's public IP
SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)

# Resolve domain
DOMAIN_IP=$(dig +short "${DOMAIN_NAME}" | head -1)

if [[ -z "${DOMAIN_IP}" ]]; then
    log_error "Domain ${DOMAIN_NAME} does not resolve to any IP"
    log_error "Please ensure DNS is configured correctly"
    exit 1
fi

if [[ "${DOMAIN_IP}" != "${SERVER_IP}" ]]; then
    log_warn "Domain resolves to ${DOMAIN_IP}, but server IP is ${SERVER_IP}"
    log_warn "This may cause certificate validation to fail"
    read -p "Continue anyway? (yes/no): " CONTINUE
    if [[ "${CONTINUE}" != "yes" ]]; then
        exit 1
    fi
else
    log_info "DNS verified: ${DOMAIN_NAME} -> ${SERVER_IP}"
fi

# =============================================================================
# 2. Obtain Certificate
# =============================================================================
log_info "[2/4] Obtaining SSL certificate..."

certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "${ADMIN_EMAIL}" \
    --agree-tos \
    --no-eff-email \
    --domain "${DOMAIN_NAME}" \
    --non-interactive

if [[ ! -f "/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem" ]]; then
    log_error "Certificate was not created"
    exit 1
fi

log_info "Certificate obtained successfully"

# =============================================================================
# 3. Configure Full HTTPS Nginx
# =============================================================================
log_info "[3/4] Configuring Nginx for HTTPS..."

cat > /etc/nginx/sites-available/retainingwall << EOF
# Retaining Wall Nginx Configuration
# Domain: ${DOMAIN_NAME}
# Generated: $(date)
# SSL: Let's Encrypt

# Rate limiting zones
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
limit_req_zone \$binary_remote_addr zone=general_limit:10m rate=30r/s;

# HTTP -> HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME};

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN_NAME};

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS (63072000 seconds = 2 years)
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Flutter web root
    root /var/www/retainingwall;
    index index.html;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    # Client body size limit
    client_max_body_size 10M;

    # API proxy - rate limited
    location /api/ {
        limit_req zone=api_limit burst=20 nodelay;

        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_connect_timeout 60s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }

    # File downloads (generated PDFs)
    location /files/ {
        limit_req zone=general_limit burst=10 nodelay;

        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        proxy_read_timeout 300s;
        proxy_buffering off;
    }

    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }

    # Static asset caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Flutter single-page app routing
    location / {
        limit_req zone=general_limit burst=50 nodelay;
        try_files \$uri \$uri/ /index.html;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Logging
    access_log /var/log/nginx/retainingwall_access.log;
    error_log /var/log/nginx/retainingwall_error.log;
}
EOF

# Test and reload nginx
nginx -t
systemctl reload nginx

log_info "Nginx HTTPS configuration applied"

# =============================================================================
# 4. Setup Auto-renewal
# =============================================================================
log_info "[4/4] Setting up certificate auto-renewal..."

# Create renewal hook
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh << 'EOF'
#!/bin/bash
systemctl reload nginx
EOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# Create cron job for renewal
cat > /etc/cron.d/certbot-renew << EOF
# Certbot automatic renewal - runs twice daily
0 3,15 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx"
EOF

# Test renewal (dry run)
log_info "Testing certificate renewal (dry run)..."
certbot renew --dry-run

log_info "Auto-renewal configured"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
echo "SSL Setup Complete!"
echo "=============================================="
echo ""
echo "Certificate Details:"
echo "  Domain: ${DOMAIN_NAME}"
echo "  Certificate: /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
echo "  Private Key: /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem"
echo "  Expiry: $(openssl x509 -enddate -noout -in /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem | cut -d= -f2)"
echo ""
echo "Auto-renewal:"
echo "  - Cron job runs twice daily (3am and 3pm)"
echo "  - Nginx reloads automatically after renewal"
echo ""
echo "Nginx Configuration:"
echo "  - HTTP redirects to HTTPS"
echo "  - HTTPS with TLS 1.2/1.3"
echo "  - Security headers enabled"
echo "  - API proxied to localhost:8080"
echo ""
echo "Test your site:"
echo "  curl -I https://${DOMAIN_NAME}"
echo ""
echo "View certificate info:"
echo "  echo | openssl s_client -connect ${DOMAIN_NAME}:443 2>/dev/null | openssl x509 -text"
