# Terraform plan checks for GitHub repositories (integrations/github provider).
# Input: the JSON from "terraform show -json <planfile>".
# Run with: conftest test --parser json --namespace terraform -p <policy dir> <plan.json>
#
# Scope (v1): resources in the root module only. A protection resource counts for a
# repository when it refers to it (github_repository.<name>...) or names it literally.
package terraform

# ---------- helpers ----------

finding(rule_id, address, text) := {"rule_id": rule_id, "resource": address, "msg": $"{rule_id} {address}: {text}"}

# Resource changes that will exist after apply (create or update; not delete-only).
live_changes contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	not rc.module_address
	some action in rc.change.actions
	action in {"create", "update"}
}

# Repositories being created or changed, keyed by their configuration address.
repos[key] := rc if {
	some rc in live_changes
	rc.type == "github_repository"
	key := $"github_repository.{rc.name}"
}

# Configuration expressions, keyed by configuration address.
config[resource.address] := resource.expressions if {
	some resource in input.configuration.root_module.resources
}

# Repository keys that a resource change points at through attribute attr: by
# reference (github_repository.x or github_repository.x.<field>), or by the
# repository's name written literally.
targets(rc, attr) := by_reference | by_name if {
	by_reference := {ref |
		some ref in config[$"{rc.type}.{rc.name}"][attr].references
		repos[ref]
	}
	by_name := {key |
		some key, repo in repos
		rc.change.after[attr] == repo.change.after.name
	}
}

# Names a default-branch pattern can take. A new repository's default branch is
# unknown at plan time, so "main" and "master" are accepted as stand-ins.
default_branch_patterns contains branch if {
	some branch in {"main", "master"}
}

default_branch_patterns contains branch if {
	some repo in repos
	branch := repo.change.after.default_branch
}

ruleset_targets_default(rs) if {
	some include in rs.conditions[0].ref_name[0].include
	include in {"~DEFAULT_BRANCH", "~ALL"}
}

ruleset_targets_default(rs) if {
	some include in rs.conditions[0].ref_name[0].include
	some branch in default_branch_patterns
	include == $"refs/heads/{branch}"
}

# Active branch rulesets covering a repository's default branch.
default_rulesets[key] contains rs if {
	some rc in live_changes
	rc.type == "github_repository_ruleset"
	rs := rc.change.after
	rs.target == "branch"
	rs.enforcement == "active"
	ruleset_targets_default(rs)
	some key in targets(rc, "repository")
}

# Branch protection rules covering a repository's default branch.
default_protections[key] contains bp if {
	some rc in live_changes
	rc.type == "github_branch_protection"
	bp := rc.change.after
	bp.pattern in default_branch_patterns
	some key in targets(rc, "repository_id")
}

visibility_ok(after) if after.visibility in {"private", "internal"}

# the deprecated "private = true" still counts when visibility is not set
visibility_ok(after) if {
	not after.visibility
	after.private == true
}

alerts_on(key) if repos[key].change.after.vulnerability_alerts == true

# the separate resource that replaces the deprecated attribute in provider 6.x
alerts_on(key) if {
	some rc in live_changes
	rc.type == "github_repository_vulnerability_alerts"
	rc.change.after.enabled == true
	key in targets(rc, "repository")
}

review_required(key) if {
	some rs in default_rulesets[key]
	rs.rules[0].pull_request[0].required_approving_review_count >= 1
}

review_required(key) if {
	some bp in default_protections[key]
	bp.required_pull_request_reviews[0].required_approving_review_count >= 1
}

force_push_blocked(key) if {
	some rs in default_rulesets[key]
	rs.rules[0].non_fast_forward == true
}

force_push_blocked(key) if {
	some bp in default_protections[key]
	bp.allows_force_pushes == false
}

# ---------- rules ----------

# METADATA
# title: GitHub repository settings in a Terraform plan
# scope: document
# entrypoint: true
deny contains finding("TF-001", rc.address, "repository is public") if {
	some rc in repos
	rc.change.after.visibility == "public"
}

deny contains finding("TF-001", rc.address, "visibility is not set explicitly (set private or internal)") if {
	some rc in repos
	not rc.change.after.visibility == "public"
	not visibility_ok(rc.change.after)
}

deny contains finding("TF-002", rc.address, "vulnerability alerts are not turned on") if {
	some key, rc in repos
	not alerts_on(key)
}

deny contains finding("TF-003", rc.address, "default branch does not require at least one approving review") if {
	some key, rc in repos
	not review_required(key)
}

deny contains finding("TF-004", rc.address, "force pushes to the default branch are not blocked") if {
	some key, rc in repos
	not force_push_blocked(key)
}
