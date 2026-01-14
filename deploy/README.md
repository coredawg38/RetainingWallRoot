# AWS Deployment Infrastructure

This directory contains all the scripts and configurations needed to deploy the Retaining Wall application to AWS.

## Architecture

```
                                    Internet
                                        |
                                        v
                              +-------------------+
                              |    Route 53       |
                              |  (DNS A Record)   |
                              +-------------------+
                                        |
                                        v
                              +-------------------+
                              |   Elastic IP      |
                              +-------------------+
                                        |
                                        v
+-----------------------------------------------------------------------------------+
|                              EC2 Instance (Ubuntu 22.04)                          |
|                                                                                   |
|  +-------------------------+     +--------------------------------------------+   |
|  |        Nginx            |     |              rwcpp-server                  |   |
|  |   (Ports 80/443)        |---->|              (Port 8080)                   |   |
|  |                         |     |                                            |   |
|  | - SSL (Let's Encrypt)   |     | - REST API                                 |   |
|  | - Static files (/)      |     | - PDF generation                           |   |
|  | - Proxy /api/*          |     | - Stripe payments                          |   |
|  +-------------------------+     +--------------------------------------------+   |
|            |                                                                      |
|            v                                                                      |
|  +-------------------------+                                                      |
|  | /var/www/retainingwall  |                                                      |
|  |   (Flutter Web Build)   |                                                      |
+-----------------------------------------------------------------------------------+
```

## Directory Structure

```
deploy/
├── aws/                          # AWS infrastructure scripts
│   ├── config.env                # Configuration (edit this first!)
│   ├── 01-create-vpc.sh          # Create VPC, subnet, IGW
│   ├── 02-create-security-groups.sh  # Create security group
│   ├── 03-create-ec2.sh          # Launch EC2 instance
│   ├── 04-allocate-elastic-ip.sh # Allocate and associate EIP
│   ├── 05-setup-route53.sh       # Configure DNS (optional)
│   └── cleanup.sh                # Delete all resources
├── ec2/                          # Scripts to run ON the EC2 instance
│   ├── provision.sh              # Full server setup
│   ├── setup-certbot.sh          # SSL certificate setup
│   └── setup-rwcpp.sh            # Manual rwcpp deployment
├── github-actions/               # CI/CD workflow templates
│   ├── rwcpp-deploy.yml          # Copy to rwcpp/.github/workflows/
│   └── webui-deploy.yml          # Copy to webui/.github/workflows/
└── README.md                     # This file
```

## Prerequisites

1. **AWS CLI** installed and configured:
   ```bash
   aws configure
   # Enter Access Key ID, Secret Access Key, Region (us-west-2)
   ```

2. **AWS Account** with permissions for:
   - EC2 (instances, VPCs, security groups, elastic IPs)
   - Route 53 (if using AWS DNS)

3. **SSH Key Pair** created in AWS EC2:
   - Go to EC2 > Key Pairs > Create key pair
   - Download the .pem file
   - `chmod 400 your-key.pem`

4. **Domain Name** registered (Route 53 or external registrar)

5. **Stripe Account** with API keys:
   - https://dashboard.stripe.com/apikeys

## Quick Start

### Step 1: Configure Settings

Edit `aws/config.env`:
```bash
export DOMAIN_NAME="your-domain.com"
export SSH_KEY_NAME="your-key-pair-name"
export ADMIN_EMAIL="admin@your-domain.com"
```

### Step 2: Create AWS Infrastructure

```bash
cd deploy/aws

# Make scripts executable
chmod +x *.sh

# Run in order (each script saves state to config.env)
./01-create-vpc.sh
./02-create-security-groups.sh
./03-create-ec2.sh
./04-allocate-elastic-ip.sh

# Configure DNS (choose one)
./05-setup-route53.sh  # If using Route 53
# OR configure A record at your DNS provider pointing to ELASTIC_IP
```

### Step 3: Provision the Server

```bash
# Copy scripts to server
scp -i your-key.pem -r ../ec2 ubuntu@YOUR_ELASTIC_IP:~/

# SSH to server
ssh -i your-key.pem ubuntu@YOUR_ELASTIC_IP

# Run provisioning
cd ~/ec2
sudo ./provision.sh your-domain.com
```

### Step 4: Configure SSL

Wait for DNS to propagate (2-5 minutes), then:
```bash
sudo ./setup-certbot.sh your-domain.com admin@your-domain.com
```

### Step 5: Add Deploy Key

On the server:
```bash
sudo nano /home/github-deploy/.ssh/authorized_keys
# Paste the public key (see GitHub Actions setup below)
```

### Step 6: Configure Environment

```bash
sudo nano /opt/rwcpp/.env
# Add your Stripe and SMTP credentials
```

### Step 7: Setup GitHub Actions

1. Generate SSH key pair for deployment:
   ```bash
   ssh-keygen -t ed25519 -C "github-deploy" -f deploy_key
   ```

2. Add secrets to **both** GitHub repos:
   - `EC2_HOST`: Your domain (e.g., `retainingwall.example.com`)
   - `EC2_SSH_KEY`: Contents of `deploy_key` (private key)

3. Add to **webui** repo only:
   - `API_BASE_URL`: `https://your-domain.com`
   - `STRIPE_PUBLISHABLE_KEY`: `pk_live_...` or `pk_test_...`

4. Copy workflow files:
   ```bash
   cp github-actions/rwcpp-deploy.yml /path/to/rwcpp/.github/workflows/deploy.yml
   cp github-actions/webui-deploy.yml /path/to/webui/.github/workflows/deploy.yml
   ```

5. Push to trigger deployment!

## GitHub Secrets Reference

| Secret | Repo | Description | Example |
|--------|------|-------------|---------|
| `EC2_HOST` | Both | Server domain or IP | `retainingwall.example.com` |
| `EC2_SSH_KEY` | Both | Private SSH key | `-----BEGIN OPENSSH...` |
| `API_BASE_URL` | webui | Full API URL | `https://retainingwall.example.com` |
| `STRIPE_PUBLISHABLE_KEY` | webui | Stripe public key | `pk_live_...` |

## Stripe Configuration

### webui (Flutter app)
Configure via GitHub Secrets and `--dart-define`:
- `STRIPE_PUBLISHABLE_KEY`: Your publishable key (pk_live_... or pk_test_...)

### rwcpp (C++ server)
Configure via environment file on EC2:
```bash
# /opt/rwcpp/.env
STRIPE_SECRET_KEY=sk_live_...  # or sk_test_...
```

### Testing vs Production
- **Test mode**: Use `sk_test_...` and `pk_test_...` keys
- **Production**: Use `sk_live_...` and `pk_live_...` keys
- Test card: `4242 4242 4242 4242`, any future date, any CVC

## SSL Certificate Management

SSL is handled by Let's Encrypt via certbot:
- Certificates auto-renew via cron (twice daily check)
- Nginx automatically reloads after renewal
- Certificates valid for 90 days, renewed at 60 days

Manual renewal test:
```bash
sudo certbot renew --dry-run
```

## Monitoring

### Check Service Status
```bash
# rwcpp server
sudo systemctl status rwcpp
journalctl -u rwcpp -f

# Nginx
sudo systemctl status nginx
tail -f /var/log/nginx/retainingwall_error.log

# Application logs
tail -f /var/log/rwcpp/server.log
```

### Health Check
```bash
curl https://your-domain.com/health
```

## Troubleshooting

### Server not starting
```bash
# Check logs
journalctl -u rwcpp -n 50

# Check if binary exists
ls -la /opt/rwcpp/retainingwall-server

# Check environment file
cat /opt/rwcpp/.env
```

### SSL issues
```bash
# Verify certificate
echo | openssl s_client -connect your-domain.com:443 2>/dev/null | openssl x509 -text

# Check certbot
sudo certbot certificates

# Force renewal
sudo certbot renew --force-renewal
```

### GitHub Actions failing
1. Check secrets are set correctly
2. Verify SSH key has access: `ssh -i deploy_key github-deploy@your-domain.com`
3. Check workflow logs in GitHub Actions tab

### DNS not resolving
```bash
dig your-domain.com
nslookup your-domain.com 8.8.8.8
```

## Cleanup

To delete all AWS resources:
```bash
cd deploy/aws
./cleanup.sh
```

**Warning**: This permanently deletes:
- EC2 instance and all data
- Elastic IP
- Security groups
- VPC and networking

## Cost Estimate

Monthly costs (us-west-2):
- EC2 t3.small: ~$15/month
- Elastic IP (attached): Free
- EBS 30GB gp3: ~$2.40/month
- Data transfer: ~$0.09/GB out

**Total**: ~$20-30/month for light usage

## Security Best Practices

1. **SSH**: Only allow key-based auth (password disabled by default)
2. **Firewall**: UFW configured to allow only 22, 80, 443
3. **Fail2ban**: Installed and active for SSH brute force protection
4. **HTTPS**: All traffic encrypted via TLS 1.2/1.3
5. **Headers**: Security headers configured in Nginx
6. **Updates**: Automatic security updates enabled

## Support

For issues with:
- **Deployment scripts**: Open issue in this repo
- **rwcpp server**: See `rwcpp/CLAUDE.md`
- **Flutter app**: See `webui/` documentation
- **AWS**: Check AWS documentation and CloudWatch logs
