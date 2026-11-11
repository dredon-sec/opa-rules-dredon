# Combines the checks gate-run collected into one decision.
# Input (built by gate-run):
#   settings  - ignore_paths and terraform_dirs the run was given
#   metadata  - key/value pairs passed with --metadata ("enforce" is moved to settings)
#   scanned   - how many files or folders of each kind were checked
#   checks    - [{kind, target, conftest: <conftest JSON output>}]
#   errors    - [{kind, target, detail}]
#   source    - the source folder prefix to strip from file names
package decision

kinds := ["dockerfile", "workflows", "terraform"]

findings contains item if {
	some check in input.checks
	some result in check.conftest
	some failure in result.failures
	item := {
		"rule_id": object.get(failure, ["metadata", "rule_id"], "unknown"),
		"kind": check.kind,
		"file": file_name(check, result),
		"msg": failure.msg,
	}
}

# Terraform plans arrive on stdin, so the folder name stands in for the file.
file_name(check, _) := check.target if check.kind == "terraform"

file_name(check, result) := trim_prefix(result.filename, input.source) if check.kind != "terraform"

errors := object.get(input, "errors", [])

raw_metadata := object.get(input, "metadata", {})

# Run settings: what was skipped, what was planned, and whether blocks fail the job.
settings := object.union_n([
	{"ignore_paths": [], "terraform_dirs": []},
	object.get(input, "settings", {}),
	{"enforce": enforce_setting},
])

default enforce_setting := null

enforce_setting if raw_metadata.enforce == "true"

enforce_setting := false if raw_metadata.enforce == "false"

metadata := object.remove(raw_metadata, ["enforce"])

default verdict := "allow"

verdict := "block" if {
	count(errors) == 0
	count(findings) > 0
}

verdict := "error" if count(errors) > 0

rule_counts[rule_id] := n if {
	some item in findings
	rule_id := item.rule_id
	n := count([x | some x in findings; x.rule_id == rule_id])
}

result := {
	"schema": "governance.gate.decision/v1",
	"decision": verdict,
	"evaluated_at": time.format(time.now_ns()),
	"settings": settings,
	"metadata": metadata,
	"scanned": input.scanned,
	"rule_counts": rule_counts,
	"findings": sort_findings,
	"errors": errors,
}

sort_findings := [item |
	some key in sort([k | some x in findings; k := concat("|", [x.rule_id, x.file, x.msg])])
	some item in findings
	concat("|", [item.rule_id, item.file, item.msg]) == key
]

exit_code := 0 if verdict == "allow"

exit_code := 1 if verdict == "block"

exit_code := 2 if verdict == "error"

counts_text := concat(", ", [$"{rule_id} x{n}" |
	some rule_id in sort(object.keys(rule_counts))
	n := rule_counts[rule_id]
])

ignored_text := concat(",", settings.ignore_paths)

scanned_text := concat(" ", [$"{kind}={n}" |
	some kind in kinds
	n := object.get(input.scanned, kind, 0)
])

# One line for the job log: decision and counts only, no file names or messages.
summary_line := concat(" ", [
	$"gate decision={verdict}",
	$"findings={count(findings)} [{counts_text}]",
	$"errors={count(errors)}",
	$"scanned: {scanned_text}",
	$"ignored=[{ignored_text}]",
])
