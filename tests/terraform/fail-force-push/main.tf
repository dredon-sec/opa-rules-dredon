terraform {
  required_providers {
    github = { source = "integrations/github", version = "= 6.13.0" }
  }
}

provider "github" {}

resource "github_repository" "demo" {
  name       = "gate-demo-repo"
  visibility = "private"
  auto_init  = true
}

resource "github_repository_vulnerability_alerts" "demo" {
  repository = github_repository.demo.name
}

resource "github_branch_protection" "main" {
  repository_id       = github_repository.demo.node_id
  pattern             = "main"
  allows_force_pushes = true
  required_pull_request_reviews {
    required_approving_review_count = 1
  }
}
