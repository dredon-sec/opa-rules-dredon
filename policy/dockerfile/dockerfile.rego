# Dockerfile / Containerfile starter checks.
# Run with: conftest test --parser dockerfile --namespace dockerfile -p <policy dir> <file>
package dockerfile

# ---------- helpers ----------

# A finding: the rule ID goes into the message and into conftest's JSON metadata.
finding(rule_id, text) := {"rule_id": rule_id, "msg": $"{rule_id} {text}"}

# Names given to earlier stages with "FROM x AS name" - these are not images.
stage_names contains lower(cmd.Value[2]) if {
	some cmd in input
	cmd.Cmd == "from"
	count(cmd.Value) == 3
	lower(cmd.Value[1]) == "as"
}

# Every FROM that refers to a real image (not scratch, not an earlier stage).
image_refs contains ref if {
	some cmd in input
	cmd.Cmd == "from"
	ref := cmd.Value[0]
	lower(ref) != "scratch"
	not lower(ref) in stage_names
}

final_stage := max({cmd.Stage | some cmd in input})

# USER instructions in the final stage, keyed by position.
final_users[i] := cmd.Value[0] if {
	some i, cmd in input
	cmd.Cmd == "user"
	cmd.Stage == final_stage
}

root_users := {"root", "0", "root:root", "0:0", "root:0", "0:root"}

secret_name := `(?i)(secret|token|passw(or)?d|pwd|api[_-]?key|private[_-]?key|access[_-]?key|credential)`

secret_value := `(ghp_|gho_|ghs_|ghu_|github_pat_|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)`

# [instruction, name, value] from ARG (NAME=value)
kv contains [cmd.Cmd, name, value] if {
	some cmd in input
	cmd.Cmd == "arg"
	some entry in cmd.Value
	contains(entry, "=")
	parts := split(entry, "=")
	name := parts[0]
	value := concat("=", array.slice(parts, 1, count(parts)))
}

# [instruction, name, value] from ENV (the parser gives key, value, separator triples)
kv contains [cmd.Cmd, name, value] if {
	some cmd in input
	cmd.Cmd == "env"
	some i in numbers.range(0, count(cmd.Value) - 1)
	i % 3 == 0
	name := cmd.Value[i]
	value := cmd.Value[i + 1]
}

# ---------- rules ----------

# DF-001: every base image pinned by digest
# METADATA
# title: Dockerfile / Containerfile starter checks
# scope: document
# entrypoint: true
deny contains finding("DF-001", $"base image not pinned by digest: {ref}") if {
	some ref in image_refs
	not contains(ref, "@sha256:")
}

# DF-002: no "latest" tag
deny contains finding("DF-002", $"base image uses the latest tag: {ref}") if {
	some ref in image_refs
	endswith(split(ref, "@")[0], ":latest")
}

# DF-003: final stage must set a USER
deny contains finding("DF-003", "final stage has no USER instruction (runs as root)") if {
	count(final_users) == 0
}

# DF-004: the last USER in the final stage must not be root
deny contains finding("DF-004", $"final stage runs as root: USER {user}") if {
	user := final_users[max(object.keys(final_users))]
	lower(user) in root_users
}

# DF-005: no secret-looking values in ARG or ENV
deny contains finding("DF-005", $"{upper(instr)} {name} looks like it holds a secret") if {
	some [instr, name, value] in kv
	value != ""
	regex.match(secret_name, name)
}

deny contains finding("DF-005", $"{upper(instr)} {name} has a value matching a known credential format") if {
	some [instr, name, value] in kv
	regex.match(secret_value, value)
}
