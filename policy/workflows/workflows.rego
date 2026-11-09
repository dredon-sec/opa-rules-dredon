# GitHub Actions workflow file checks.
# Run with: conftest test --parser yaml --namespace workflows -p <policy dir> <workflow.yml>
package workflows

# ---------- helpers ----------

finding(rule_id, where, text) := {"rule_id": rule_id, "where": where, "msg": $"{rule_id} {where}: {text}"}

# The YAML parser reads the key "on" as the boolean true, so triggers can sit
# under either "on" or "true". "on" may be a string, a list or a map.
trigger_block := object.get(input, "on", object.get(input, "true", null))

triggers contains trigger_block if is_string(trigger_block)

triggers contains t if {
	is_array(trigger_block)
	some t in trigger_block
}

triggers contains t if {
	is_object(trigger_block)
	some t, _ in trigger_block
}

# Every step-level "uses", with where it was found.
step_uses contains [$"jobs.{job_id}.steps[{i}]", step.uses] if {
	some job_id, job in input.jobs
	some i, step in job.steps
	step.uses
}

# Job-level "uses" (calls to reusable workflows).
job_uses contains [$"jobs.{job_id}", job.uses] if {
	some job_id, job in input.jobs
	job.uses
}

pinned_to_sha(ref) if regex.match(`^[^@\s]+@[0-9a-f]{40}$`, ref)

local_ref(ref) if startswith(ref, "./")

docker_ref(ref) if startswith(ref, "docker://")

allowlisted(ref) if {
	parts := split(ref, "@")
	count(parts) == 2
	parts[1] in ref_allowlist[parts[0]]
}

pinned_image(image) if {
	contains(image, "@sha256:")
	not contains(image, "${{")
}

# Images used by containers, service containers and docker:// actions.
images contains [$"jobs.{job_id}.container", job.container] if {
	some job_id, job in input.jobs
	is_string(job.container)
}

images contains [$"jobs.{job_id}.container", job.container.image] if {
	some job_id, job in input.jobs
	job.container.image
}

images contains [$"jobs.{job_id}.services.{name}", service.image] if {
	some job_id, job in input.jobs
	some name, service in job.services
	service.image
}

images contains [where, substring(ref, 9, -1)] if {
	some [where, ref] in step_uses
	docker_ref(ref)
}

# Expressions that point a checkout at the pull request's own code.
pr_head_expression(value) if contains(value, "pull_request.head")

pr_head_expression(value) if contains(value, "github.head_ref")

checks_out_pr_head(step) if {
	startswith(step.uses, "actions/checkout")
	some value in step.with
	is_string(value)
	pr_head_expression(value)
}

# ---------- rules ----------

# METADATA
# title: GitHub Actions workflow file checks
# scope: document
# entrypoint: true
deny contains finding("WF-001", where, $"action not pinned to a commit SHA: {ref}") if {
	some [where, ref] in step_uses
	not local_ref(ref)
	not docker_ref(ref)
	not pinned_to_sha(ref)
}

deny contains finding("WF-001", where, $"reusable workflow not pinned to a commit SHA: {ref}") if {
	some [where, ref] in job_uses
	not local_ref(ref)
	not pinned_to_sha(ref)
	not allowlisted(ref)
}

deny contains finding("WF-002", $"jobs.{job_id}", "no permissions declared at workflow or job level") if {
	not "permissions" in object.keys(input)
	some job_id, job in input.jobs
	not "permissions" in object.keys(job)
}

deny contains finding("WF-002", "permissions", "write-all grants every permission") if {
	input.permissions == "write-all"
}

deny contains finding("WF-002", $"jobs.{job_id}.permissions", "write-all grants every permission") if {
	some job_id, job in input.jobs
	job.permissions == "write-all"
}

deny contains finding("WF-003", $"jobs.{job_id}.steps[{i}]", "pull_request_target job checks out PR code") if {
	"pull_request_target" in triggers
	some job_id, job in input.jobs
	some i, step in job.steps
	checks_out_pr_head(step)
}

deny contains finding("WF-004", where, $"container image not pinned by digest: {image}") if {
	some [where, image] in images
	not pinned_image(image)
}
