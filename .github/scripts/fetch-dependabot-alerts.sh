#!/bin/bash
set -euo pipefail

REPO=${GITHUB_REPOSITORY}

echo "Fetching open Dependabot alerts for $REPO ..."

# Use gh api instead of curl
RESPONSE=$(gh api "repos/$REPO/dependabot/alerts" \
    --method GET \
    --field state=open \
    --field per_page=100)

echo "$RESPONSE" > alerts.json
echo "[INFO] API raw response:"
cat alerts.json

# Parse and count alerts
CRITICAL=$(jq '[.[] | select(.security_advisory.severity == "critical")] | length' alerts.json)
HIGH=$(jq '[.[] | select(.security_advisory.severity == "high")] | length' alerts.json)
TOTAL=$((CRITICAL + HIGH))

# Output to GitHub Actions
echo "critical=$CRITICAL" >> $GITHUB_OUTPUT
echo "high=$HIGH" >> $GITHUB_OUTPUT
echo "total=$TOTAL" >> $GITHUB_OUTPUT

echo "Found $CRITICAL critical and $HIGH high severity vulnerabilities."