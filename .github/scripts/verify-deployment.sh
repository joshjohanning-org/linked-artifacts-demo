#!/usr/bin/env bash
# verify-deployment.sh
#
# Queries the GitHub Linked Artifacts API to verify that an artifact
# has been deployed to a required prior environment before allowing
# promotion to the next one.
#
# Usage:
#   ./verify-deployment.sh <org> <digest> <required_environment>
#
# Environment variables:
#   GITHUB_TOKEN - required for API authentication
#
# Exit codes:
#   0 - Deployment record found for the required environment
#   1 - No deployment record found (promotion blocked)

set -euo pipefail

ORG="${1:?Usage: verify-deployment.sh <org> <digest> <required_environment>}"
DIGEST="${2:?Usage: verify-deployment.sh <org> <digest> <required_environment>}"
REQUIRED_ENV="${3:?Usage: verify-deployment.sh <org> <digest> <required_environment>}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Linked Artifacts Deployment Gate                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "🔍 Checking deployment records..."
echo "   Org:              $ORG"
echo "   Artifact digest:  ${DIGEST:0:20}..."
echo "   Required env:     $REQUIRED_ENV"
echo ""

# URL-encode the digest (the colon in sha256:... needs encoding)
ENCODED_DIGEST=$(echo -n "$DIGEST" | jq -sRr @uri)

# Query the linked artifacts API for deployment records for this digest
RESPONSE=$(gh api \
  -H "Accept: application/vnd.github+json" \
  "orgs/${ORG}/artifacts/${ENCODED_DIGEST}/metadata/deployment-records" \
  2>&1) || {
    echo "⚠️  API call failed. This may mean:"
    echo "   - The linked artifacts feature is not enabled for org '$ORG'"
    echo "   - The artifact has no records yet"
    echo "   - Insufficient permissions"
    echo ""
    echo "API response: $RESPONSE"
    exit 1
  }

# Check if any deployment record matches the required environment
MATCH=$(echo "$RESPONSE" | jq -r \
  --arg env "$REQUIRED_ENV" \
  '.deployment_records[]? | select(.logical_environment == $env and .status != "decommissioned") | .logical_environment' \
  2>/dev/null || echo "")

if [ -n "$MATCH" ]; then
  echo "✅ PASSED: Found active deployment record for '$REQUIRED_ENV'"
  echo ""
  echo "   Deployment details:"
  echo "$RESPONSE" | jq -r \
    --arg env "$REQUIRED_ENV" \
    '.deployment_records[] | select(.logical_environment == $env) | "   - Deployment: \(.deployment_name)\n   - Environment: \(.logical_environment)\n   - Created: \(.created)"'
  echo ""
  echo "🚀 Promotion approved — proceeding to next environment."
  exit 0
else
  echo "❌ BLOCKED: No active deployment record found for '$REQUIRED_ENV'"
  echo ""

  TOTAL=$(echo "$RESPONSE" | jq -r '.total_count // 0')
  if [ "$TOTAL" -gt 0 ]; then
    echo "   Found records for other environments:"
    echo "$RESPONSE" | jq -r '.deployment_records[] | "   - \(.logical_environment) (\(.status // "active"))"'
  else
    echo "   No deployment records exist for this artifact yet."
  fi

  echo ""
  echo "🛑 This artifact must be deployed to '$REQUIRED_ENV' before it can"
  echo "   be promoted to the next environment."
  echo ""
  echo "   To fix: deploy this artifact to '$REQUIRED_ENV' first."
  exit 1
fi
