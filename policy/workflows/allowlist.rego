# Reusable workflows that callers may reference by branch instead of commit SHA.
# Keep this list short: each entry trusts whoever can push to that branch.
# Key: <owner>/<repo>/<path to workflow file>   Value: the refs allowed for it.
package workflows

ref_allowlist := {"ORG/GOVERNANCE-REPO/.github/workflows/governance-gate.yml": {"main", "refs/heads/main"}}
