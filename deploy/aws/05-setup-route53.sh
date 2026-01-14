#!/bin/bash
# =============================================================================
# 05-setup-route53.sh - Configure Route 53 DNS
# =============================================================================
# This script creates/updates an A record in Route 53 to point your domain
# to the Elastic IP address.
#
# Prerequisites:
#   - Domain registered in Route 53 OR hosted zone created
#   - Elastic IP allocated (run 04-allocate-elastic-ip.sh first)
#   - HOSTED_ZONE_ID set in config.env
#
# Usage:
#   ./05-setup-route53.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

echo "=============================================="
echo "Setting Up Route 53 DNS"
echo "=============================================="
echo "Domain: ${DOMAIN_NAME}"
echo "Elastic IP: ${ELASTIC_IP}"
echo ""

# Validate prerequisites
if [[ -z "${ELASTIC_IP}" ]]; then
    echo "ERROR: ELASTIC_IP not set. Run 04-allocate-elastic-ip.sh first."
    exit 1
fi

# -----------------------------------------------------------------------------
# Handle Hosted Zone
# -----------------------------------------------------------------------------
if [[ -z "${HOSTED_ZONE_ID}" ]]; then
    echo "HOSTED_ZONE_ID not set in config.env"
    echo ""
    echo "Looking for existing hosted zones..."

    # Extract base domain (e.g., example.com from www.example.com)
    BASE_DOMAIN=$(echo "${DOMAIN_NAME}" | rev | cut -d. -f1-2 | rev)

    EXISTING_ZONE=$(aws route53 list-hosted-zones-by-name \
        --dns-name "${BASE_DOMAIN}" \
        --region "${AWS_REGION}" \
        --query "HostedZones[?Name=='${BASE_DOMAIN}.'].Id" \
        --output text 2>/dev/null | head -1 | sed 's|/hostedzone/||')

    if [[ -n "${EXISTING_ZONE}" ]]; then
        echo "Found existing hosted zone: ${EXISTING_ZONE}"
        HOSTED_ZONE_ID="${EXISTING_ZONE}"
    else
        echo ""
        echo "No hosted zone found for ${BASE_DOMAIN}"
        echo ""
        echo "Options:"
        echo ""
        echo "1. Create a hosted zone (if domain is registered elsewhere):"
        echo "   aws route53 create-hosted-zone --name ${BASE_DOMAIN} --caller-reference \$(date +%s)"
        echo "   Then update your domain's nameservers to use Route 53 nameservers."
        echo ""
        echo "2. Register domain in Route 53 (creates hosted zone automatically):"
        echo "   Visit: https://console.aws.amazon.com/route53/home#DomainRegistration"
        echo ""
        echo "3. Use external DNS (skip this script):"
        echo "   Configure an A record at your DNS provider:"
        echo "     ${DOMAIN_NAME} -> ${ELASTIC_IP}"
        echo ""
        echo "After creating/finding your hosted zone, update config.env:"
        echo "  export HOSTED_ZONE_ID=\"your-zone-id\""
        echo ""
        exit 1
    fi
fi

# Validate hosted zone exists
echo "Verifying hosted zone ${HOSTED_ZONE_ID}..."
if ! aws route53 get-hosted-zone --id "${HOSTED_ZONE_ID}" &>/dev/null; then
    echo "ERROR: Hosted zone ${HOSTED_ZONE_ID} not found"
    exit 1
fi

ZONE_NAME=$(aws route53 get-hosted-zone \
    --id "${HOSTED_ZONE_ID}" \
    --query 'HostedZone.Name' \
    --output text | sed 's/\.$//')

echo "  Hosted Zone: ${ZONE_NAME}"

# -----------------------------------------------------------------------------
# Create/Update A Record
# -----------------------------------------------------------------------------
echo ""
echo "Creating A record: ${DOMAIN_NAME} -> ${ELASTIC_IP}"

CHANGE_BATCH=$(cat << EOF
{
    "Comment": "Retaining Wall application - managed by deployment script",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${DOMAIN_NAME}",
                "Type": "A",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "${ELASTIC_IP}"
                    }
                ]
            }
        }
    ]
}
EOF
)

CHANGE_ID=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "${HOSTED_ZONE_ID}" \
    --change-batch "${CHANGE_BATCH}" \
    --query 'ChangeInfo.Id' \
    --output text)

echo "  Change submitted: ${CHANGE_ID}"

# -----------------------------------------------------------------------------
# Wait for DNS Propagation
# -----------------------------------------------------------------------------
echo ""
echo "Waiting for DNS change to propagate..."
aws route53 wait resource-record-sets-changed --id "${CHANGE_ID}"
echo "  DNS change propagated"

# -----------------------------------------------------------------------------
# Verify DNS Resolution
# -----------------------------------------------------------------------------
echo ""
echo "Verifying DNS resolution..."
sleep 5

RESOLVED_IP=$(dig +short "${DOMAIN_NAME}" @8.8.8.8 2>/dev/null | head -1)

if [[ "${RESOLVED_IP}" == "${ELASTIC_IP}" ]]; then
    echo "  DNS resolution verified: ${DOMAIN_NAME} -> ${RESOLVED_IP}"
else
    echo "  DNS not yet resolving correctly (got: ${RESOLVED_IP:-nothing})"
    echo "  This may take a few minutes to propagate globally."
    echo "  Check with: dig ${DOMAIN_NAME}"
fi

# -----------------------------------------------------------------------------
# Save Configuration
# -----------------------------------------------------------------------------
export HOSTED_ZONE_ID
save_config "${SCRIPT_DIR}/config.env"

echo ""
echo "=============================================="
echo "Route 53 DNS Configured Successfully!"
echo "=============================================="
echo ""
echo "A Record:"
echo "  ${DOMAIN_NAME} -> ${ELASTIC_IP}"
echo "  TTL: 300 seconds"
echo ""
echo "Configuration saved to config.env"
echo ""
echo "=============================================="
echo "NEXT STEPS"
echo "=============================================="
echo ""
echo "1. Wait for DNS to fully propagate (2-5 minutes)"
echo "   Test with: curl -I http://${DOMAIN_NAME}"
echo ""
echo "2. SSH to the server:"
echo "   ssh -i ${SSH_KEY_NAME}.pem ubuntu@${ELASTIC_IP}"
echo ""
echo "3. Copy and run the provisioning scripts:"
echo "   scp -i ${SSH_KEY_NAME}.pem -r ../ec2 ubuntu@${ELASTIC_IP}:~/"
echo "   ssh -i ${SSH_KEY_NAME}.pem ubuntu@${ELASTIC_IP}"
echo "   cd ~/ec2 && ./provision.sh"
