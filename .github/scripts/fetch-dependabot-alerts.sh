#!/bin/bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY}"
PR_NUMBER="${PR_NUMBER}"

echo "Fetching open Dependabot alerts for $REPO ..."
echo "Using PR number: $PR_NUMBER"

# -------------------------------------------------
# Fetch open Dependabot alerts
# -------------------------------------------------
RESPONSE=$(GITHUB_TOKEN="$PAT_TOKEN" gh api \
  "repos/$REPO/dependabot/alerts" \
  --method GET \
  --field state=open \
  --field per_page=100 \
  --jq '.')

if ! echo "$RESPONSE" | jq empty >/dev/null 2>&1; then
  echo "❌ Error: API response is not valid JSON."
  echo "$RESPONSE"
  exit 0
fi

echo "$RESPONSE" > alerts.json
echo "[INFO] API raw response saved to alerts.json"

ALERTS=$(jq 'if type == "object" and has("alerts") then .alerts else . end' alerts.json)

# -------------------------------------------------
# Extract module names from PR files (initial path)
# -------------------------------------------------
mapfile -t MODULES < <(
  gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" \
    --paginate \
    --jq '.[].filename' |
  awk -F'/' '{print $1}' |
  sort -u
)

if [ "${#MODULES[@]}" -eq 0 ]; then
  echo "ℹ️ No files found in PR."
  exit 0
fi

echo "Modules changed in PR:"
printf '  - %s\n' "${MODULES[@]}"

# -------------------------------------------------
# Filter alerts by module name ONLY
# -------------------------------------------------
FILTERED_ALERTS=$(jq --argjson modules "$(printf '%s\n' "${MODULES[@]}" | jq -R . | jq -s .)" '
  [
    .[] |
    select(
      .dependency.manifest_path as $manifest
      | (
          # Only consider manifests inside a module
          ($manifest | contains("/"))
          and
          (
            ($manifest | split("/")[0]) as $manifest_module
            | any($modules[]; . == $manifest_module)
          )
        )
    )
  ]
' <<<"$ALERTS")

MATCHING_COUNT=$(echo "$FILTERED_ALERTS" | jq 'length')

if [ "$MATCHING_COUNT" -eq 0 ]; then
  echo "✅ No Dependabot alerts match the modified modules."
  exit 0
fi

# -------------------------------------------------
# Count severities (filtered only)
# -------------------------------------------------
CRITICAL=$(echo "$FILTERED_ALERTS" | jq '[.[] | select(.security_advisory.severity == "critical")] | length')
HIGH=$(echo "$FILTERED_ALERTS" | jq '[.[] | select(.security_advisory.severity == "high")] | length')
TOTAL=$((CRITICAL + HIGH))

echo "Found $CRITICAL critical and $HIGH high severity vulnerabilities affecting modified modules."

if [ "$TOTAL" -eq 0 ]; then
  echo "✅ No High or Critical vulnerabilities in modified modules."
  exit 0
fi

# -------------------------------------------------
# Build Markdown table
# -------------------------------------------------
echo "Building Markdown table..."

ALERTS_TABLE=$(echo "$FILTERED_ALERTS" | jq -r '
  (now | floor) as $now
  | (
      ["Severity", "Summary", "Module", "Manifest Path", "Created At", "Due Date"],
      ["---", "---", "---", "---", "---", "---"],
      (
        [.[] 
          | select(.security_advisory.severity == "critical" or .security_advisory.severity == "high")
          | (
              7 as $days
              | (.created_at | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) as $created
              | ($created + ($days * 86400)) as $due_ts
              | ($due_ts | strftime("%Y-%m-%d")) as $due_date
              | (if $due_ts < $now then ("⚠️ " + $due_date) else $due_date end) as $due_display
              | {
                  severity: .security_advisory.severity,
                  summary: .security_advisory.summary,
                  link: .html_url,
                  module: (.dependency.manifest_path | split("/")[0]),
                  manifest: .dependency.manifest_path,
                  created: (.created_at | split("T")[0]),
                  due_ts: $due_ts,
                  due_display: $due_display
                }
            )
        ]
        | sort_by(.due_ts)
        | .[] | [
            .severity,
            "[\(.summary)](\(.link))",
            .module,
            .manifest,
            .created,
            .due_display
          ]
      )
    )
  | @tsv
  | gsub("\t"; " | ")
  | split("\n")
  | map(" | " + . + " |")
  | .[]
')

echo "Markdown table built."

# -------------------------------------------------
# Post PR comment
# -------------------------------------------------
COMMENT_BODY=$(cat <<EOF
🔒 **Dependabot Security Summary (Scoped to Modified Modules)**

**${CRITICAL} Critical**, **${HIGH} High** vulnerabilities detected.

**Affected modules:**  
$(printf '%s\n' "${MODULES[@]}" | sed 's/^/- /')

---
${ALERTS_TABLE}
EOF
)

echo "Posting comment to PR #$PR_NUMBER..."

gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" \
  -f body="$COMMENT_BODY"

echo "✅ Dependabot security summary posted successfully."
