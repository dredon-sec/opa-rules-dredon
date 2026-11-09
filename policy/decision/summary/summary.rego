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

table := concat("\n", array.concat(["| Rule | Findings |", "|---|---|"], rows)) if count(rows) > 0

table := "No findings." if count(rows) == 0

markdown := concat("\n", [
	$"### Governance gate: {icon[input.decision]}",
	"",
	$"Checked: {scanned}. Errors: {count(input.errors)}.",
	"",
	table,
	"",
	"Full findings are in decision.json (kept on the runner host).",
	"",
])
