#!/bin/bash
set -euo pipefail

REPO=${GITHUB_REPOSITORY}
PR_NUMBER=${PR_NUMBER}

echo "Fetching open Dependabot alerts for $REPO ..."

# Fetch open Dependabot alerts
RESPONSE=$(GITHUB_TOKEN="$PAT_TOKEN" gh api \
    "repos/$REPO/dependabot/alerts" \
    --method GET \
    --field state=open \
    --field per_page=100)

echo "$RESPONSE" > alerts.json
echo "[INFO] API raw response saved to alerts.json"

# Count alerts
CRITICAL=$(jq '[.[] | select(.security_advisory.severity == "critical")] | length' alerts.json)
HIGH=$(jq '[.[] | select(.security_advisory.severity == "high")] | length' alerts.json)
TOTAL=$((CRITICAL + HIGH))

# Output for GitHub Actions
echo "critical=$CRITICAL" >> "$GITHUB_OUTPUT"
echo "high=$HIGH" >> "$GITHUB_OUTPUT"
echo "total=$TOTAL" >> "$GITHUB_OUTPUT"

echo "Found $CRITICAL critical and $HIGH high severity vulnerabilities."

if [ "$TOTAL" -eq 0 ]; then
    echo "✅ No High or Critical Dependabot alerts found."
    exit 0
fi

echo "Building Markdown table for Dependabot alerts..."

# Generate Markdown table with jq
ALERTS_TABLE=$(jq -r '
(
  ["Severity", "Summary (link)", "Created At"],
  ["---", "---", "---"],
  (.[] | select(.security_advisory.severity == "critical" or .security_advisory.severity == "high") | [
    .security_advisory.severity,
    "[\(.security_advisory.summary)](\(.html_url))",
    (.created_at | split("T")[0])
  ])
)
| @tsv
| gsub("\t"; " | ")
| . as $lines
| ($lines | map(" | " + . + " |")) | .[]
' alerts.json)

# Build the full PR comment body
COMMENT_BODY=$(cat <<EOF
🔒 **Dependabot Security Summary**

| Severity | Count |
|-----------|--------|
| 🟥 Critical | ${CRITICAL} |
| 🟧 High | ${HIGH} |

> This data comes directly from the Security → Dependabot Alerts tab for this repository.

---

### ⚠️ Detailed Alerts
${ALERTS_TABLE}
EOF
)

echo "Posting comment to PR #$PR_NUMBER..."

# Post directly to PR comment
gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" \
    -f body="$COMMENT_BODY"

echo "✅ Comment with Dependabot alert details posted successfully!"
