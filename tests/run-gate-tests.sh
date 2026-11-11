#!/usr/bin/env bash
# End-to-end tests of gate-run: builds small sample repositories from the other
# test samples, runs the gate image on each, and checks the exit code and the
# rule IDs in the decision.
# Usage (from the repo root):
#   tests/run-gate-tests.sh <image>             # policies baked into the image
#   tests/run-gate-tests.sh <image> policy       # policies from this folder instead
set -u
img=${1:?usage: $0 <image> [policy-dir]}
pol=${2:-}
pol_mount=(); pol_args=()
if [ -n "$pol" ]; then
  pol_mount=(-v "$(realpath "$pol"):/pol:ro,z"); pol_args=(--policy /pol)
fi
t=tests
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# ---------- sample repositories ----------
mkrepo() { mkdir -p "$tmp/$1/.github/workflows"; }

mkrepo clean
cp $t/dockerfile/pass/Dockerfile          "$tmp/clean/Containerfile"
cp $t/workflows/pass-pinned/workflow.yml  "$tmp/clean/.github/workflows/build.yml"
mkdir -p "$tmp/clean/infra" && cp $t/terraform/pass-ruleset/main.tf "$tmp/clean/infra/"

mkrepo mixed
mkdir -p "$tmp/mixed/app" "$tmp/mixed/infra" "$tmp/mixed/tests/x"
cp $t/dockerfile/fail-root/Dockerfile     "$tmp/mixed/app/Dockerfile"
cp $t/dockerfile/pass/Dockerfile          "$tmp/mixed/Containerfile"
cp $t/workflows/fail-tag/workflow.yml     "$tmp/mixed/.github/workflows/ci.yml"
cp $t/workflows/pass-pinned/workflow.yml  "$tmp/mixed/.github/workflows/build.yaml"
cp $t/terraform/fail-unprotected/main.tf  "$tmp/mixed/infra/"
cp $t/dockerfile/fail-unpinned/Dockerfile "$tmp/mixed/tests/x/Dockerfile"

mkrepo broken
mkdir -p "$tmp/broken/infra"
printf 'resource "github_repository" "x" {\n  nonsense = 1\n}\n' > "$tmp/broken/infra/main.tf"

mkrepo empty

# a folder the container user cannot open must give "error", never a silent pass
mkrepo locked
mkdir -p "$tmp/locked/private"
cp $t/dockerfile/fail-root/Dockerfile "$tmp/locked/private/Dockerfile"
chmod 700 "$tmp/locked/private"

# ---------- cases: name | repo | expected exit | expected rule IDs | gate-run args ----------
cases=(
  "clean            |clean |0|                            |--terraform-dir infra"
  "mixed            |mixed |1|DF-004 TF-003 TF-004 WF-001 |--terraform-dir infra --ignore tests"
  "mixed-no-ignore  |mixed |1|DF-001 DF-004 TF-003 TF-004 WF-001|--terraform-dir infra"
  "terraform-error  |broken|2|                            |--terraform-dir infra"
  "path-escape      |empty |2|                            |--terraform-dir ../etc"
  "empty            |empty |0|                            |"
  "unreadable       |locked|2|                            |"
)

rc=0
for c in "${cases[@]}"; do
  IFS='|' read -r name repo want_rc want_ids args <<<"$c"
  name=$(xargs <<<"$name"); repo=$(xargs <<<"$repo"); want_ids=$(xargs <<<"$want_ids")
  # shellcheck disable=SC2086  # args are word-split on purpose
  out=$(podman run --rm --network=none "${pol_mount[@]}" -v "$tmp/$repo:/src:ro,z" "$img" \
          gate-run --source /src "${pol_args[@]}" $args --metadata repo=test/$repo 2>/dev/null)
  got_rc=$?
  got_ids=$(grep -o '"rule_id": "[A-Z]*-[0-9]*"' <<<"$out" | grep -o '[A-Z]*-[0-9]*' | sort -u | xargs)
  decision=$(grep -o '"decision": *"[a-z]*"' <<<"$out" | head -1 | grep -o '[a-z]*"$' | tr -d '"')
  if [ "$got_rc" = "$want_rc" ] && [ "$got_ids" = "$want_ids" ]; then
    echo "ok    $name  exit=$got_rc decision=$decision [${got_ids:-none}]"
  else
    echo "FAIL  $name  expected exit=$want_rc [${want_ids:-none}] got exit=$got_rc [${got_ids:-none}]"; rc=1
  fi
done
exit $rc
