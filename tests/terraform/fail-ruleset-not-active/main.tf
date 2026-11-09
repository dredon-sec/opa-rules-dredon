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

resource "github_repository_ruleset" "main" {
  name        = "protect-default-branch"
  repository  = github_repository.demo.name
  target      = "branch"
  enforcement = "evaluate"
  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }
  rules {
    non_fast_forward = true
    pull_request {
      required_approving_review_count = 1
    }
  }
}
