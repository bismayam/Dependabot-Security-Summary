#!/bin/bash
set -euo pipefail

REPO=${GITHUB_REPOSITORY}
PR_NUMBER=${PR_NUMBER}
CRITICAL=${CRITICAL}
HIGH=${HIGH}
TOTAL=${TOTAL}

if [ "$TOTAL" -eq 0 ]; then
    echo "✅ No High or Critical Dependabot alerts found."
    exit 0
fi

# Generate comment content
cat > comment.md << EOF
🔒 **Dependabot Security Summary**

| Severity | Count |
|-----------|--------|
| 🟥 Critical | ${CRITICAL} |
| 🟧 High | ${HIGH} |

> This data comes directly from the Security → Dependabot Alerts tab for this repository.
EOF

echo "Posting comment to PR #$PR_NUMBER..."

# Post comment using GitHub CLI
gh api repos/${REPO}/issues/${PR_NUMBER}/comments \
    -f body="$(cat comment.md)"

echo "Comment posted successfully!"