#!/bin/bash
# =============================================================================
# 01-create-vpc.sh - Create VPC infrastructure for Retaining Wall
# =============================================================================
# This script creates:
#   - VPC with DNS support
#   - Internet Gateway
#   - Public Subnet
#   - Route Table with internet route
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - config.env configured with your settings
#
# Usage:
#   ./01-create-vpc.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

echo "=============================================="
echo "Creating VPC Infrastructure"
echo "=============================================="
echo "Region: ${AWS_REGION}"
echo "VPC CIDR: ${VPC_CIDR}"
echo "Subnet CIDR: ${PUBLIC_SUBNET_CIDR}"
echo ""

# Validate config
if ! validate_config; then
    echo "Please fix configuration errors and try again."
    exit 1
fi

# -----------------------------------------------------------------------------
# Create VPC
# -----------------------------------------------------------------------------
echo "[1/6] Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "${VPC_CIDR}" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Project,Value=retaining-wall}]" \
    --region "${AWS_REGION}" \
    --query 'Vpc.VpcId' \
    --output text)

if [[ -z "${VPC_ID}" ]]; then
    echo "ERROR: Failed to create VPC"
    exit 1
fi
echo "  VPC created: ${VPC_ID}"

# Enable DNS hostnames for the VPC
aws ec2 modify-vpc-attribute \
    --vpc-id "${VPC_ID}" \
    --enable-dns-hostnames '{"Value":true}' \
    --region "${AWS_REGION}"
echo "  DNS hostnames enabled"

# Enable DNS support
aws ec2 modify-vpc-attribute \
    --vpc-id "${VPC_ID}" \
    --enable-dns-support '{"Value":true}' \
    --region "${AWS_REGION}"
echo "  DNS support enabled"

# -----------------------------------------------------------------------------
# Create Internet Gateway
# -----------------------------------------------------------------------------
echo "[2/6] Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw},{Key=Project,Value=retaining-wall}]" \
    --region "${AWS_REGION}" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

if [[ -z "${IGW_ID}" ]]; then
    echo "ERROR: Failed to create Internet Gateway"
    exit 1
fi
echo "  Internet Gateway created: ${IGW_ID}"

# Attach IGW to VPC
aws ec2 attach-internet-gateway \
    --internet-gateway-id "${IGW_ID}" \
    --vpc-id "${VPC_ID}" \
    --region "${AWS_REGION}"
echo "  Internet Gateway attached to VPC"

# -----------------------------------------------------------------------------
# Create Public Subnet
# -----------------------------------------------------------------------------
echo "[3/6] Creating Public Subnet..."
SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "${VPC_ID}" \
    --cidr-block "${PUBLIC_SUBNET_CIDR}" \
    --availability-zone "${AWS_REGION}a" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-public},{Key=Project,Value=retaining-wall}]" \
    --region "${AWS_REGION}" \
    --query 'Subnet.SubnetId' \
    --output text)

if [[ -z "${SUBNET_ID}" ]]; then
    echo "ERROR: Failed to create Subnet"
    exit 1
fi
echo "  Subnet created: ${SUBNET_ID}"

# Enable auto-assign public IP
aws ec2 modify-subnet-attribute \
    --subnet-id "${SUBNET_ID}" \
    --map-public-ip-on-launch \
    --region "${AWS_REGION}"
echo "  Auto-assign public IP enabled"

# -----------------------------------------------------------------------------
# Create Route Table
# -----------------------------------------------------------------------------
echo "[4/6] Creating Route Table..."
RTB_ID=$(aws ec2 create-route-table \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-public-rt},{Key=Project,Value=retaining-wall}]" \
    --region "${AWS_REGION}" \
    --query 'RouteTable.RouteTableId' \
    --output text)

if [[ -z "${RTB_ID}" ]]; then
    echo "ERROR: Failed to create Route Table"
    exit 1
fi
echo "  Route Table created: ${RTB_ID}"

# -----------------------------------------------------------------------------
# Create Internet Route
# -----------------------------------------------------------------------------
echo "[5/6] Creating Internet Route..."
aws ec2 create-route \
    --route-table-id "${RTB_ID}" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "${IGW_ID}" \
    --region "${AWS_REGION}" > /dev/null
echo "  Internet route created (0.0.0.0/0 -> IGW)"

# -----------------------------------------------------------------------------
# Associate Route Table with Subnet
# -----------------------------------------------------------------------------
echo "[6/6] Associating Route Table with Subnet..."
aws ec2 associate-route-table \
    --route-table-id "${RTB_ID}" \
    --subnet-id "${SUBNET_ID}" \
    --region "${AWS_REGION}" > /dev/null
echo "  Route Table associated with Subnet"

# -----------------------------------------------------------------------------
# Save Configuration
# -----------------------------------------------------------------------------
export VPC_ID
export IGW_ID
export SUBNET_ID
export RTB_ID
save_config "${SCRIPT_DIR}/config.env"

echo ""
echo "=============================================="
echo "VPC Infrastructure Created Successfully!"
echo "=============================================="
echo ""
echo "Resources created:"
echo "  VPC ID:             ${VPC_ID}"
echo "  Internet Gateway:   ${IGW_ID}"
echo "  Subnet ID:          ${SUBNET_ID}"
echo "  Route Table ID:     ${RTB_ID}"
echo ""
echo "Configuration saved to config.env"
echo ""
echo "Next step: Run ./02-create-security-groups.sh"
