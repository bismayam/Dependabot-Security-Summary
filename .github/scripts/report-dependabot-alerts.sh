#!/bin/bash

# A shell script to fetch open Dependabot alerts and post them as a table
# in a GitHub Pull Request comment.
#
# USAGE:
#   ./report_dependabot_alerts.sh "owner/repo" <pr_number>
#
# PREREQUISITES:
#   1. GitHub CLI (`gh`) - https://cli.github.com/
#   2. jq (`jq`) - https://jqlang.github.io/jq/
#
# AUTHENTICATION:
#   This script requires a GITHUB_TOKEN to be set as an environment variable.
#   The token MUST have the following permissions:
#     - dependabot_alerts: read (to read alerts)
#     - pull_requests: write (to comment on the PR)

set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Return the exit status of the last command in a pipe

# --- Input Validation ---
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 \"owner/repo\" <pr_number>"
  exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_TOKEN environment variable is not set."
  echo "Please export a token with 'dependabot_alerts: read' and 'pull_requests: write' permissions."
  exit 1
fi

REPO=${GITHUB_REPOSITORY}
PR_NUMBER=${PR_NUMBER}

# --- Prerequisite Tool Check ---
if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI ('gh') is not installed. Please install it to continue."
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "Error: 'jq' is not installed. Please install it to continue."
  exit 1
fi

# Split "owner/repo" into separate variables for the GraphQL query
OWNER=$(echo "$REPO" | cut -d'/' -f1)
REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)

if [ -z "$OWNER" ] || [ -z "$REPO_NAME" ]; then
  echo "Error: Invalid repository format. Expected 'owner/repo'."
  exit 1
fi

echo "Fetching Dependabot alerts for $REPO..."

# --- 1. Define the GraphQL Query ---
# This query fetches the first 100 open vulnerability alerts.
# It requests the fields you specified: severity, summary, path, created_at,
# and htmlUrl (for the hyperlink).
GRAPHQL_QUERY=$(cat <<EOF
query(\$owner: String!, \$repo: String!) {
  repository(owner: \$owner, name: \$repo) {
    vulnerabilityAlerts(first: 100, states: OPEN) {
      nodes {
        createdAt
        securityVulnerability {
          severity
        }
        vulnerableManifestPath
        htmlUrl
        advisory {
          summary
        }
      }
    }
  }
}
EOF
)

# --- 2. Define the JQ Filter ---
# This filter transforms the JSON response into a Markdown table.
# It creates the header, then iterates over each alert (.nodes[])
# and builds a table row, formatting the summary as a Markdown link.
JQ_FILTER=$(cat <<EOF
(
  ["Severity", "Summary", "Path", "Created At"],
  ["---", "---", "---", "---"],
  (.data.repository.vulnerabilityAlerts.nodes[] | [
    .securityVulnerability.severity,
    "[\(.advisory.summary)](\(.htmlUrl))",
    "\`\(.vulnerableManifestPath)\`",
    (.createdAt | split("T") | .[0])
  ])
)
| @tsv
| gsub("\t"; " | ")
| "\(. ) |"
EOF
)

# --- 3. Execute the Commands ---
# 1. `gh api graphql...`: Runs the query, passing the owner and repo as variables.
# 2. `jq -r "$JQ_FILTER"`: Pipes the JSON output to jq, which formats it as a table.
# 3. `gh pr comment...`: Pipes the table output to the `gh pr comment` command.
#    `--body-file -` tells the command to read the comment body from standard input (stdin).

# Note: The 'gh' CLI automatically respects the GH_TOKEN env variable.
GRAPHQL_DATA=$(echo "$GRAPHQL_QUERY" | GITHUB_TOKEN="$PAT_TOKEN" gh api graphql -f owner="$OWNER" -f repo="$REPO_NAME")

if [ -z "$GRAPHQL_DATA" ]; then
  echo "Error: Failed to fetch data from GitHub API. Check GH_API_TOKEN permissions."
  exit 1
fi


echo "$GRAPHQL_DATA" | \
  jq -r "$JQ_FILTER" | \
  GITHUB_TOKEN="$GITHUB_TOKEN" gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file -

echo "Successfully posted Dependabot alert summary to PR #$PR_NUMBER in $REPO."
