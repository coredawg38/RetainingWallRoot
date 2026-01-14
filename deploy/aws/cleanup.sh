#!/bin/bash
# =============================================================================
# cleanup.sh - Remove all AWS resources created for Retaining Wall
# =============================================================================
# WARNING: This script will PERMANENTLY DELETE:
#   - EC2 Instance
#   - Elastic IP
#   - Security Group
#   - Route Table
#   - Subnet
#   - Internet Gateway
#   - VPC
#   - Route 53 DNS records (optional)
#
# Usage:
#   ./cleanup.sh          # Interactive mode - confirms each deletion
#   ./cleanup.sh --force  # Non-interactive - deletes everything
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

FORCE_MODE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_MODE=true
fi

echo "=============================================="
echo "AWS Resource Cleanup"
echo "=============================================="
echo ""
echo "This will DELETE the following resources:"
echo "  Instance: ${INSTANCE_ID:-not set}"
echo "  Elastic IP: ${ELASTIC_IP:-not set}"
echo "  Security Group: ${SG_ID:-not set}"
echo "  VPC: ${VPC_ID:-not set}"
echo ""

if [[ "${FORCE_MODE}" != "true" ]]; then
    read -p "Are you sure you want to delete these resources? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

# Helper function
delete_resource() {
    local name=$1
    local command=$2

    echo -n "  Deleting ${name}... "
    if eval "${command}" 2>/dev/null; then
        echo "done"
    else
        echo "skipped (may not exist)"
    fi
}

# -----------------------------------------------------------------------------
# Delete Route 53 Record
# -----------------------------------------------------------------------------
if [[ -n "${HOSTED_ZONE_ID}" && -n "${DOMAIN_NAME}" && -n "${ELASTIC_IP}" ]]; then
    echo ""
    echo "[1/8] Deleting Route 53 record..."
    CHANGE_BATCH=$(cat << EOF
{
    "Changes": [{
        "Action": "DELETE",
        "ResourceRecordSet": {
            "Name": "${DOMAIN_NAME}",
            "Type": "A",
            "TTL": 300,
            "ResourceRecords": [{"Value": "${ELASTIC_IP}"}]
        }
    }]
}
EOF
)
    delete_resource "DNS record" "aws route53 change-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} --change-batch '${CHANGE_BATCH}'"
else
    echo "[1/8] Skipping Route 53 (not configured)"
fi

# -----------------------------------------------------------------------------
# Terminate EC2 Instance
# -----------------------------------------------------------------------------
echo ""
echo "[2/8] Terminating EC2 instance..."
if [[ -n "${INSTANCE_ID}" ]]; then
    delete_resource "instance ${INSTANCE_ID}" "aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} --region ${AWS_REGION}"
    echo "  Waiting for instance to terminate..."
    aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}" 2>/dev/null || true
    echo "  Instance terminated"
else
    echo "  No instance to terminate"
fi

# -----------------------------------------------------------------------------
# Release Elastic IP
# -----------------------------------------------------------------------------
echo ""
echo "[3/8] Releasing Elastic IP..."
if [[ -n "${EIP_ALLOC_ID}" ]]; then
    # First disassociate if associated
    ASSOC_ID=$(aws ec2 describe-addresses \
        --allocation-ids "${EIP_ALLOC_ID}" \
        --region "${AWS_REGION}" \
        --query 'Addresses[0].AssociationId' \
        --output text 2>/dev/null || echo "None")

    if [[ "${ASSOC_ID}" != "None" && -n "${ASSOC_ID}" ]]; then
        delete_resource "EIP association" "aws ec2 disassociate-address --association-id ${ASSOC_ID} --region ${AWS_REGION}"
    fi

    delete_resource "Elastic IP" "aws ec2 release-address --allocation-id ${EIP_ALLOC_ID} --region ${AWS_REGION}"
else
    echo "  No Elastic IP to release"
fi

# -----------------------------------------------------------------------------
# Delete Security Group
# -----------------------------------------------------------------------------
echo ""
echo "[4/8] Deleting Security Group..."
if [[ -n "${SG_ID}" ]]; then
    # Wait a moment for any dependencies to clear
    sleep 5
    delete_resource "security group ${SG_ID}" "aws ec2 delete-security-group --group-id ${SG_ID} --region ${AWS_REGION}"
else
    echo "  No security group to delete"
fi

# -----------------------------------------------------------------------------
# Delete Subnet
# -----------------------------------------------------------------------------
echo ""
echo "[5/8] Deleting Subnet..."
if [[ -n "${SUBNET_ID}" ]]; then
    delete_resource "subnet ${SUBNET_ID}" "aws ec2 delete-subnet --subnet-id ${SUBNET_ID} --region ${AWS_REGION}"
else
    echo "  No subnet to delete"
fi

# -----------------------------------------------------------------------------
# Delete Route Table
# -----------------------------------------------------------------------------
echo ""
echo "[6/8] Deleting Route Table..."
if [[ -n "${RTB_ID}" ]]; then
    # Disassociate from subnet first
    ASSOC_IDS=$(aws ec2 describe-route-tables \
        --route-table-ids "${RTB_ID}" \
        --region "${AWS_REGION}" \
        --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
        --output text 2>/dev/null || echo "")

    for ASSOC_ID in ${ASSOC_IDS}; do
        delete_resource "route table association" "aws ec2 disassociate-route-table --association-id ${ASSOC_ID} --region ${AWS_REGION}"
    done

    delete_resource "route table ${RTB_ID}" "aws ec2 delete-route-table --route-table-id ${RTB_ID} --region ${AWS_REGION}"
else
    echo "  No route table to delete"
fi

# -----------------------------------------------------------------------------
# Detach and Delete Internet Gateway
# -----------------------------------------------------------------------------
echo ""
echo "[7/8] Deleting Internet Gateway..."
if [[ -n "${IGW_ID}" && -n "${VPC_ID}" ]]; then
    delete_resource "IGW detachment" "aws ec2 detach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID} --region ${AWS_REGION}"
    delete_resource "internet gateway ${IGW_ID}" "aws ec2 delete-internet-gateway --internet-gateway-id ${IGW_ID} --region ${AWS_REGION}"
else
    echo "  No internet gateway to delete"
fi

# -----------------------------------------------------------------------------
# Delete VPC
# -----------------------------------------------------------------------------
echo ""
echo "[8/8] Deleting VPC..."
if [[ -n "${VPC_ID}" ]]; then
    delete_resource "VPC ${VPC_ID}" "aws ec2 delete-vpc --vpc-id ${VPC_ID} --region ${AWS_REGION}"
else
    echo "  No VPC to delete"
fi

# -----------------------------------------------------------------------------
# Clear Config
# -----------------------------------------------------------------------------
echo ""
echo "Clearing resource IDs from config..."
export VPC_ID=""
export SUBNET_ID=""
export IGW_ID=""
export RTB_ID=""
export SG_ID=""
export INSTANCE_ID=""
export EIP_ALLOC_ID=""
export ELASTIC_IP=""
export AMI_ID=""
save_config "${SCRIPT_DIR}/config.env"

echo ""
echo "=============================================="
echo "Cleanup Complete!"
echo "=============================================="
echo ""
echo "All AWS resources have been deleted."
echo "Your domain and ADMIN_EMAIL settings are preserved in config.env."
echo ""
echo "To redeploy, run the scripts in order:"
echo "  ./01-create-vpc.sh"
echo "  ./02-create-security-groups.sh"
echo "  ./03-create-ec2.sh"
echo "  ./04-allocate-elastic-ip.sh"
echo "  ./05-setup-route53.sh"
