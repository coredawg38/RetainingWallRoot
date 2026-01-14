#!/bin/bash
# =============================================================================
# 04-allocate-elastic-ip.sh - Allocate and Associate Elastic IP
# =============================================================================
# This script:
#   - Allocates a new Elastic IP address
#   - Associates it with the EC2 instance
#   - Provides DNS configuration instructions
#
# Prerequisites:
#   - EC2 instance created (run 03-create-ec2.sh first)
#   - config.env has INSTANCE_ID populated
#
# Usage:
#   ./04-allocate-elastic-ip.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

echo "=============================================="
echo "Allocating Elastic IP"
echo "=============================================="
echo "Instance ID: ${INSTANCE_ID}"
echo "Domain: ${DOMAIN_NAME}"
echo ""

# Validate prerequisites
if [[ -z "${INSTANCE_ID}" ]]; then
    echo "ERROR: INSTANCE_ID not set. Run 03-create-ec2.sh first."
    exit 1
fi

# Check if instance exists and is running
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "not-found")

if [[ "${INSTANCE_STATE}" != "running" ]]; then
    echo "ERROR: Instance ${INSTANCE_ID} is not running (state: ${INSTANCE_STATE})"
    exit 1
fi

# -----------------------------------------------------------------------------
# Allocate Elastic IP
# -----------------------------------------------------------------------------
echo "[1/3] Allocating Elastic IP..."

# Check if we already have an EIP associated
EXISTING_EIP=$(aws ec2 describe-addresses \
    --filters "Name=instance-id,Values=${INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query 'Addresses[0].PublicIp' \
    --output text 2>/dev/null || echo "None")

if [[ "${EXISTING_EIP}" != "None" && -n "${EXISTING_EIP}" ]]; then
    echo "  Instance already has Elastic IP: ${EXISTING_EIP}"
    ELASTIC_IP="${EXISTING_EIP}"
    EIP_ALLOC_ID=$(aws ec2 describe-addresses \
        --public-ips "${ELASTIC_IP}" \
        --region "${AWS_REGION}" \
        --query 'Addresses[0].AllocationId' \
        --output text)
else
    # Allocate new EIP
    EIP_RESULT=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${INSTANCE_NAME}-eip},{Key=Project,Value=retaining-wall}]" \
        --region "${AWS_REGION}")

    EIP_ALLOC_ID=$(echo "${EIP_RESULT}" | jq -r '.AllocationId')
    ELASTIC_IP=$(echo "${EIP_RESULT}" | jq -r '.PublicIp')

    if [[ -z "${ELASTIC_IP}" || "${ELASTIC_IP}" == "null" ]]; then
        echo "ERROR: Failed to allocate Elastic IP"
        exit 1
    fi
    echo "  Elastic IP allocated: ${ELASTIC_IP}"

    # -----------------------------------------------------------------------------
    # Associate Elastic IP with Instance
    # -----------------------------------------------------------------------------
    echo "[2/3] Associating Elastic IP with instance..."
    aws ec2 associate-address \
        --instance-id "${INSTANCE_ID}" \
        --allocation-id "${EIP_ALLOC_ID}" \
        --region "${AWS_REGION}" > /dev/null

    echo "  Elastic IP associated"
fi

# -----------------------------------------------------------------------------
# Verify Association
# -----------------------------------------------------------------------------
echo "[3/3] Verifying association..."
sleep 2

INSTANCE_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --region "${AWS_REGION}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

if [[ "${INSTANCE_PUBLIC_IP}" != "${ELASTIC_IP}" ]]; then
    echo "WARNING: Instance public IP (${INSTANCE_PUBLIC_IP}) doesn't match Elastic IP (${ELASTIC_IP})"
fi

# -----------------------------------------------------------------------------
# Save Configuration
# -----------------------------------------------------------------------------
export ELASTIC_IP
export EIP_ALLOC_ID
save_config "${SCRIPT_DIR}/config.env"

echo ""
echo "=============================================="
echo "Elastic IP Allocated Successfully!"
echo "=============================================="
echo ""
echo "Elastic IP:     ${ELASTIC_IP}"
echo "Allocation ID:  ${EIP_ALLOC_ID}"
echo ""
echo "Configuration saved to config.env"
echo ""
echo "=============================================="
echo "DNS CONFIGURATION REQUIRED"
echo "=============================================="
echo ""
echo "You must configure DNS to point your domain to this IP."
echo ""
echo "Option 1: Route 53 (recommended if domain is in AWS)"
echo "  Run: ./05-setup-route53.sh"
echo ""
echo "Option 2: External DNS Provider"
echo "  Create an A record:"
echo "    Name:  ${DOMAIN_NAME}"
echo "    Type:  A"
echo "    Value: ${ELASTIC_IP}"
echo "    TTL:   300 (5 minutes)"
echo ""
echo "After DNS is configured, you can SSH to the server:"
echo "  ssh -i ${SSH_KEY_NAME}.pem ubuntu@${ELASTIC_IP}"
echo ""
echo "Next step: Configure DNS, then SSH to server and run provision.sh"
