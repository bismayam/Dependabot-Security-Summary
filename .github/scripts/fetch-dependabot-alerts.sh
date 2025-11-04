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
    echo "❌ Error: API response is not valid JSON"
    echo "$RESPONSE"
    exit 1
fi

echo "$RESPONSE" > alerts.json
echo "[INFO] API raw response saved to alerts.json"

# Normalize: Some GitHub responses are objects with a 'alerts' array
ALERTS=$(jq '.alerts // .' alerts.json)

# Count critical and high alerts
CRITICAL=$(echo "$ALERTS" | jq '[.[] | select(.security_advisory.severity == "critical")] | length')
HIGH=$(echo "$ALERTS" | jq '[.[] | select(.security_advisory.severity == "high")] | length')
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

# Generate Markdown table
ALERTS_TABLE=$(echo "$ALERTS" | jq -r '
  # Get current timestamp in seconds
  (now | floor) as $now
  | (["Severity", "Summary (link)", "Created At", "Status"],
     ["---", "---", "---", "---"],
     (.[] 
       | select(.security_advisory.severity == "critical" or .security_advisory.severity == "high")
       | (
           # Parse created_at to seconds
           (.created_at | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) as $created
           | [
               .security_advisory.severity,
               "[\(.security_advisory.summary)](\(.html_url))",
               (.created_at | split("T")[0]),
               # Status column logic
               (if $now - $created > 30*24*3600 then "❌ Crossed Remediation Timeline"
                else "⚠️ Close to Remediation Timeline" end)
             ]
         )
     )
  )
  | @tsv
  | gsub("\t"; " | ")
  | split("\n")
  | map(" | " + . + " |")
  | .[]
')


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
