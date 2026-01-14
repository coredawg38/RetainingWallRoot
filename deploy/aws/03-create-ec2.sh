#!/bin/bash
# =============================================================================
# 03-create-ec2.sh - Create EC2 Instance for Retaining Wall
# =============================================================================
# This script creates:
#   - EC2 instance with Ubuntu 22.04 LTS
#   - GP3 EBS volume for storage
#   - Waits for instance to be running
#
# Prerequisites:
#   - VPC and Security Group created (run 01 and 02 scripts first)
#   - SSH key pair exists in AWS (create in EC2 > Key Pairs)
#   - config.env has VPC_ID, SUBNET_ID, SG_ID populated
#
# Usage:
#   ./03-create-ec2.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

echo "=============================================="
echo "Creating EC2 Instance"
echo "=============================================="
echo "Instance Type: ${INSTANCE_TYPE}"
echo "Instance Name: ${INSTANCE_NAME}"
echo "Key Pair: ${SSH_KEY_NAME}"
echo "EBS Size: ${EBS_SIZE} GB"
echo ""

# Validate prerequisites
if [[ -z "${VPC_ID}" ]]; then
    echo "ERROR: VPC_ID not set. Run 01-create-vpc.sh first."
    exit 1
fi

if [[ -z "${SUBNET_ID}" ]]; then
    echo "ERROR: SUBNET_ID not set. Run 01-create-vpc.sh first."
    exit 1
fi

if [[ -z "${SG_ID}" ]]; then
    echo "ERROR: SG_ID not set. Run 02-create-security-groups.sh first."
    exit 1
fi

# Check if key pair exists
if ! aws ec2 describe-key-pairs --key-names "${SSH_KEY_NAME}" --region "${AWS_REGION}" &>/dev/null; then
    echo "ERROR: SSH key pair '${SSH_KEY_NAME}' not found in region ${AWS_REGION}"
    echo ""
    echo "Create a key pair in AWS Console:"
    echo "  1. Go to EC2 > Key Pairs"
    echo "  2. Create key pair named '${SSH_KEY_NAME}'"
    echo "  3. Download and save the .pem file securely"
    echo "  4. Run: chmod 400 ${SSH_KEY_NAME}.pem"
    exit 1
fi

# -----------------------------------------------------------------------------
# Get Latest Ubuntu 22.04 AMI
# -----------------------------------------------------------------------------
echo "[1/4] Finding latest Ubuntu 22.04 LTS AMI..."
AMI_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters \
        "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
        "Name=state,Values=available" \
        "Name=architecture,Values=x86_64" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --region "${AWS_REGION}" \
    --output text)

if [[ -z "${AMI_ID}" || "${AMI_ID}" == "None" ]]; then
    echo "ERROR: Could not find Ubuntu 22.04 AMI"
    exit 1
fi
echo "  AMI: ${AMI_ID}"

# Get AMI name for reference
AMI_NAME=$(aws ec2 describe-images \
    --image-ids "${AMI_ID}" \
    --region "${AWS_REGION}" \
    --query 'Images[0].Name' \
    --output text)
echo "  Name: ${AMI_NAME}"

# -----------------------------------------------------------------------------
# Create EC2 Instance
# -----------------------------------------------------------------------------
echo "[2/4] Launching EC2 instance..."

# Create user data script for initial setup
USER_DATA=$(cat << 'USERDATA'
#!/bin/bash
# Initial setup script - runs on first boot
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install essential packages
apt-get install -y \
    curl \
    git \
    htop \
    jq \
    unzip \
    awscli

# Create app directories
mkdir -p /opt/rwcpp/{outputs,data,images,inputs}
mkdir -p /var/www/retainingwall
mkdir -p /var/log/rwcpp

# Set timezone
timedatectl set-timezone UTC

# Enable automatic security updates
apt-get install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades

echo "Initial setup complete" > /var/log/user-data-complete.log
USERDATA
)

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type "${INSTANCE_TYPE}" \
    --key-name "${SSH_KEY_NAME}" \
    --security-group-ids "${SG_ID}" \
    --subnet-id "${SUBNET_ID}" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${EBS_SIZE},\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Project,Value=retaining-wall}]" \
    --user-data "${USER_DATA}" \
    --region "${AWS_REGION}" \
    --query 'Instances[0].InstanceId' \
    --output text)

if [[ -z "${INSTANCE_ID}" ]]; then
    echo "ERROR: Failed to launch EC2 instance"
    exit 1
fi
echo "  Instance ID: ${INSTANCE_ID}"

# -----------------------------------------------------------------------------
# Wait for Instance to be Running
# -----------------------------------------------------------------------------
echo "[3/4] Waiting for instance to be running..."
aws ec2 wait instance-running \
    --instance-ids "${INSTANCE_ID}" \
    --region "${AWS_REGION}"
echo "  Instance is running"

# -----------------------------------------------------------------------------
# Get Instance Details
# -----------------------------------------------------------------------------
echo "[4/4] Getting instance details..."
INSTANCE_INFO=$(aws ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query 'Reservations[0].Instances[0]')

PUBLIC_IP=$(echo "${INSTANCE_INFO}" | jq -r '.PublicIpAddress // "pending"')
PRIVATE_IP=$(echo "${INSTANCE_INFO}" | jq -r '.PrivateIpAddress')
AZ=$(echo "${INSTANCE_INFO}" | jq -r '.Placement.AvailabilityZone')

# -----------------------------------------------------------------------------
# Save Configuration
# -----------------------------------------------------------------------------
export INSTANCE_ID
export AMI_ID
save_config "${SCRIPT_DIR}/config.env"

echo ""
echo "=============================================="
echo "EC2 Instance Created Successfully!"
echo "=============================================="
echo ""
echo "Instance Details:"
echo "  Instance ID:   ${INSTANCE_ID}"
echo "  Instance Type: ${INSTANCE_TYPE}"
echo "  AMI:           ${AMI_ID}"
echo "  AZ:            ${AZ}"
echo "  Private IP:    ${PRIVATE_IP}"
echo "  Public IP:     ${PUBLIC_IP} (temporary - use Elastic IP)"
echo ""
echo "Configuration saved to config.env"
echo ""
echo "IMPORTANT: Wait 2-3 minutes for user-data script to complete."
echo ""
echo "Next step: Run ./04-allocate-elastic-ip.sh"
