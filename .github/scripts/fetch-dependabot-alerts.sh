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
  (now | floor) as $now
  | (
      ["Severity", "Summary (link)", "Created At", "Due Date"],
      ["---", "---", "---", "---"],
      (
        [.[] 
          | select(.security_advisory.severity == "critical" or .security_advisory.severity == "high")
          | (
              # Set 30-day remediation timeline for all
              30 as $days
              # Parse created_at and compute due date
              | (.created_at | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) as $created
              | ($created + ($days * 24 * 3600)) as $due_ts
              | ($due_ts | strftime("%Y-%m-%d")) as $due_date
              | (if $due_ts < $now then ($due_date + " ⚠️") else $due_date end) as $due_display
              # Emit object with sortable due_ts
              | {
                  severity: .security_advisory.severity,
                  summary: .security_advisory.summary,
                  link: .html_url,
                  created: (.created_at | split("T")[0]),
                  due_ts: $due_ts,
                  due_display: $due_display
                }
            )
        ]
        # Sort by due_ts ascending (soonest first)
        | sort_by(.due_ts)
        # Convert to table rows
        | .[] | [ .severity, "[\(.summary)](\(.link))", .created, .due_display ]
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
🔒 Dependabot Security Summary (${CRITICAL} Critical, ${HIGH} High Vulnerabilities)

---
${ALERTS_TABLE}
EOF
)

echo "Posting comment to PR #$PR_NUMBER..."

gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" \
    -f body="$COMMENT_BODY"

echo "✅ Comment with Dependabot alert details posted successfully!"