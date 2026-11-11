# Markdown for the run's summary page, built from a finished decision.json.
# Decision, counts per rule and error count only: no file names or messages.
package decision.summary

icon := {"allow": "PASS", "block": "BLOCK", "error": "ERROR"}

rows := [$"| {rule_id} | {n} |" |
	some rule_id in sort(object.keys(input.rule_counts))
	n := input.rule_counts[rule_id]
]

scanned := concat(", ", [$"{kind}: {n}" |
	some kind in ["dockerfile", "workflows", "terraform"]
	n := object.get(input.scanned, kind, 0)
])

joined_or_none(xs) := concat(", ", xs) if count(xs) > 0

joined_or_none(xs) := "none" if count(xs) == 0

settings := object.get(input, "settings", {})

ignored := joined_or_none(object.get(settings, "ignore_paths", []))

planned := joined_or_none(object.get(settings, "terraform_dirs", []))

default enforce_text := "not set"

enforce_text := "on" if settings.enforce == true

enforce_text := "off" if settings.enforce == false

table := concat("\n", array.concat(["| Rule | Findings |", "|---|---|"], rows)) if count(rows) > 0

table := "No findings." if count(rows) == 0

markdown := concat("\n", [
	$"### Governance gate: {icon[input.decision]}",
	"",
	$"Checked: {scanned}. Errors: {count(input.errors)}.",
	"",
	$"Ignored: {ignored}. Terraform folders: {planned}. Enforce: {enforce_text}.",
	"",
	table,
	"",
	"Full findings are in decision.json (kept on the runner host).",
	"",
])
