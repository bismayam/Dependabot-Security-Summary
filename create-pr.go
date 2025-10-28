package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/google/go-github/v57/github"
	"golang.org/x/oauth2"
)

func main() {
	// ======== CONFIGURATION ========
	owner := "bismayam"                                        // 👈 your GitHub username or org
	repo := "Dependabot-Security-Summary"                      // 👈 target repository name
	localFile := ".github/workflows/security-alerts-on-pr.yml" // 👈 local YAML file path
	targetDir := ".github/workflows/dependabot/"               // 👈 upload location in repo
	prTitle := "Add Dependabot Security Summary workflow"
	prBody := "This PR adds a GitHub Action to comment Dependabot High/Critical vulnerability summary on pull requests."
	// ===============================

	token := os.Getenv("GITHUB_TOKEN")
	if token == "" {
		log.Fatal("❌ GITHUB_TOKEN environment variable not set")
	}

	// ---- Read local file ----
	content, err := os.ReadFile(localFile)
	if err != nil {
		log.Fatalf("❌ Failed to read local file %s: %v", localFile, err)
	}
	fmt.Printf("📄 Read workflow file: %s (%d bytes)\n", localFile, len(content))

	fileName := filepath.Base(localFile)
	targetPath := filepath.Join(targetDir, fileName)
	branchName := fmt.Sprintf("add-dependabot-ga-%d", time.Now().Unix())

	// ---- Create GitHub client ----
	ctx := context.Background()
	ts := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	tc := oauth2.NewClient(ctx, ts)
	client := github.NewClient(tc)

	// ---- Get base branch (main) ----
	baseRef, _, err := client.Git.GetRef(ctx, owner, repo, "refs/heads/main")
	if err != nil {
		log.Fatalf("❌ Failed to get main branch ref: %v", err)
	}

	// ---- Create new branch ----
	newRef := &github.Reference{
		Ref:    github.String("refs/heads/" + branchName),
		Object: &github.GitObject{SHA: baseRef.Object.SHA},
	}
	_, _, err = client.Git.CreateRef(ctx, owner, repo, newRef)
	if err != nil {
		log.Fatalf("❌ Failed to create new branch: %v", err)
	}
	fmt.Printf("✅ Created branch: %s\n", branchName)

	// ---- Create the workflow file ----
	opts := &github.RepositoryContentFileOptions{
		Message: github.String(fmt.Sprintf("Add workflow file: %s", fileName)),
		Content: content,
		Branch:  github.String(branchName),
	}

	_, _, err = client.Repositories.CreateFile(ctx, owner, repo, targetPath, opts)
	if err != nil {
		log.Fatalf("❌ Failed to create file in repo: %v", err)
	}
	fmt.Printf("✅ Created file: %s\n", targetPath)

	// ---- Create Pull Request ----
	newPR := &github.NewPullRequest{
		Title: github.String(prTitle),
		Head:  github.String(branchName),
		Base:  github.String("main"),
		Body:  github.String(prBody),
	}
	pr, _, err := client.PullRequests.Create(ctx, owner, repo, newPR)
	if err != nil {
		log.Fatalf("❌ Failed to create Pull Request: %v", err)
	}

	fmt.Printf("🎉 Pull Request created: %s\n", pr.GetHTMLURL())
}
