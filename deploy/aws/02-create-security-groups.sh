#!/bin/bash
# =============================================================================
# 02-create-security-groups.sh - Create Security Group for Retaining Wall
# =============================================================================
# This script creates a security group with rules for:
#   - SSH (port 22) - for deployment and management
#   - HTTP (port 80) - for Let's Encrypt and redirect
#   - HTTPS (port 443) - for production traffic
#
# Prerequisites:
#   - VPC created (run 01-create-vpc.sh first)
#   - config.env has VPC_ID populated
#
# Usage:
#   ./02-create-security-groups.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

echo "=============================================="
echo "Creating Security Group"
echo "=============================================="
echo "VPC ID: ${VPC_ID}"
echo ""

# Validate VPC exists
if [[ -z "${VPC_ID}" ]]; then
    echo "ERROR: VPC_ID not set. Run 01-create-vpc.sh first."
    exit 1
fi

# Check if VPC exists in AWS
if ! aws ec2 describe-vpcs --vpc-ids "${VPC_ID}" --region "${AWS_REGION}" &>/dev/null; then
    echo "ERROR: VPC ${VPC_ID} not found in region ${AWS_REGION}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Create Security Group
# -----------------------------------------------------------------------------
echo "[1/4] Creating Security Group..."

# Check if security group already exists
EXISTING_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=retaining-wall-web-sg" "Name=vpc-id,Values=${VPC_ID}" \
    --region "${AWS_REGION}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [[ "${EXISTING_SG}" != "None" && -n "${EXISTING_SG}" ]]; then
    echo "  Security group already exists: ${EXISTING_SG}"
    SG_ID="${EXISTING_SG}"
else
    SG_ID=$(aws ec2 create-security-group \
        --group-name "retaining-wall-web-sg" \
        --description "Security group for Retaining Wall web server - allows SSH, HTTP, HTTPS" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=retaining-wall-web-sg},{Key=Project,Value=retaining-wall}]" \
        --region "${AWS_REGION}" \
        --query 'GroupId' \
        --output text)

    if [[ -z "${SG_ID}" ]]; then
        echo "ERROR: Failed to create Security Group"
        exit 1
    fi
    echo "  Security Group created: ${SG_ID}"
fi

# -----------------------------------------------------------------------------
# Add Inbound Rules
# -----------------------------------------------------------------------------
echo "[2/4] Adding SSH rule (port 22)..."
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 22 \
    --cidr "0.0.0.0/0" \
    --region "${AWS_REGION}" 2>/dev/null || echo "  SSH rule already exists"

echo "[3/4] Adding HTTP rule (port 80)..."
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 80 \
    --cidr "0.0.0.0/0" \
    --region "${AWS_REGION}" 2>/dev/null || echo "  HTTP rule already exists"

echo "[4/4] Adding HTTPS rule (port 443)..."
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 443 \
    --cidr "0.0.0.0/0" \
    --region "${AWS_REGION}" 2>/dev/null || echo "  HTTPS rule already exists"

# -----------------------------------------------------------------------------
# Display Security Group Rules
# -----------------------------------------------------------------------------
echo ""
echo "Security Group Rules:"
aws ec2 describe-security-groups \
    --group-ids "${SG_ID}" \
    --region "${AWS_REGION}" \
    --query 'SecurityGroups[0].IpPermissions[*].{Port:FromPort,Protocol:IpProtocol,Source:IpRanges[0].CidrIp}' \
    --output table

# -----------------------------------------------------------------------------
# Save Configuration
# -----------------------------------------------------------------------------
export SG_ID
save_config "${SCRIPT_DIR}/config.env"

echo ""
echo "=============================================="
echo "Security Group Created Successfully!"
echo "=============================================="
echo ""
echo "Security Group ID: ${SG_ID}"
echo ""
echo "Inbound rules:"
echo "  - SSH (22):    0.0.0.0/0  - For deployment access"
echo "  - HTTP (80):   0.0.0.0/0  - For Let's Encrypt & redirect"
echo "  - HTTPS (443): 0.0.0.0/0  - For production traffic"
echo ""
echo "Note: Port 8080 (rwcpp) is NOT exposed externally."
echo "      Nginx handles all external traffic and proxies to rwcpp."
echo ""
echo "Configuration saved to config.env"
echo ""
echo "Next step: Run ./03-create-ec2.sh"
