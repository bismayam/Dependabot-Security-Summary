# 🛡️ Dependabot Security Alerts Demo

This repository demonstrates how to automatically detect and summarize **Dependabot security alerts** — specifically **High** and **Critical** severity vulnerabilities — using a custom **GitHub Action** and a small Go project with a known vulnerable dependency.

---

## 📋 Overview

Whenever a **new Pull Request** is opened or updated, the included GitHub Action:

1. Queries the current repository for open **Dependabot alerts**.
2. Checks for any **High** or **Critical** severity issues.
3. Posts a summary **comment on the Pull Request** if such alerts are found.
4. Skips commenting if there are no severe vulnerabilities.

This helps maintainers stay aware of unresolved security risks in real time.

---

## ⚙️ Repository Contents

| File / Folder | Description |
|----------------|-------------|
| `.github/workflows/dependabot-alert-summary.yml` | GitHub Action that checks Dependabot alerts and comments on PRs. |
| `go.mod` | Go module file referencing a deliberately vulnerable version of a dependency. |
| `main.go` | Simple Go code importing the vulnerable package. |
| `README.md` | You’re reading it — explains setup and usage. |


