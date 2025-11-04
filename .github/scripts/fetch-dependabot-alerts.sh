#!/bin/bash
set -euo pipefail

REPO=${GITHUB_REPOSITORY}
GITHUB_TOKEN=${GITHUB_TOKEN}

echo "Fetching open Dependabot alerts for $REPO ..."

RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                  -H "Accept: application/vnd.github+json" \
                  "https://api.github.com/repos/$REPO/dependabot/alerts?state=open&per_page=100")

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