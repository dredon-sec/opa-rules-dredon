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
