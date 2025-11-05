#!/bin/bash
set -euo pipefail

REPO=${GITHUB_REPOSITORY}
PR_NUMBER=${PR_NUMBER}

echo "Fetching open Dependabot alerts for $REPO ..."

# Fetch open Dependabot alerts (force JSON output)
RESPONSE=$(GITHUB_TOKEN="$PAT_TOKEN" gh api \
    "repos/$REPO/dependabot/alerts" \
    --method GET \
    --field state=open \
    --field per_page=100 \
    --jq '.')

# Ensure response is valid JSON
if ! echo "$RESPONSE" | jq empty > /dev/null 2>&1; then
    echo "❌ Error: API response is not valid JSON for dependabot alerts."
    echo "$RESPONSE"
    exit 0
fi

echo "$RESPONSE" > alerts.json
echo "[INFO] API raw response saved to alerts.json"

# Normalize JSON so it works whether the root is an array or an object with 'alerts'
ALERTS=$(jq 'if type == "object" and has("alerts") then .alerts else . end' alerts.json)

# Count critical and high alerts
CRITICAL=$(echo "$ALERTS" | jq '[.[] | select(.security_advisory.severity == "critical")] | length')
HIGH=$(echo "$ALERTS" | jq '[.[] | select(.security_advisory.severity == "high")] | length')
TOTAL=$((CRITICAL + HIGH))


echo "Found $CRITICAL critical and $HIGH high severity vulnerabilities."

if [ "$TOTAL" -eq 0 ]; then
    echo "✅ No High or Critical Dependabot alerts found."
    exit 0
fi

echo "Building Markdown table for Dependabot alerts..."

ALERTS_TABLE=$(jq -r '
  # Current time (not strictly needed for due date but kept for clarity)
  (now | floor) as $now
  | (["Severity", "Summary", "Created At", "Due Date"],
     ["---", "---", "---", "---"],
     (.[] 
       | select(.security_advisory.severity == "critical" or .security_advisory.severity == "high")
       | (
           # Parse created_at and compute due date (+30 days)
           (.created_at | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime + (30*24*3600) | strftime("%Y-%m-%d")) as $due
           | [
               .security_advisory.severity,
               "[\(.security_advisory.summary)](\(.html_url))",
               (.created_at | split("T")[0]),
               $due
             ]
         )
     )
  )
  | @tsv
  | gsub("\t"; " | ")
  | split("\n")
  | map(" | " + . + " |")
  | .[]
' alerts.json)

echo "Markdown table built."

# Build the PR comment
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

gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" \
    -f body="$COMMENT_BODY"

echo "✅ Comment with Dependabot alert details posted successfully!"