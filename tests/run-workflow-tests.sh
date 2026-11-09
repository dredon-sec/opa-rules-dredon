#!/usr/bin/env bash
# Runs every sample in tests/workflows/ through the gate image and compares
# the rule IDs found with the sample's "expect" file.
# Usage (from the repo root):
#   tests/run-workflow-tests.sh <image>               # policies baked into the image
#   tests/run-workflow-tests.sh <image> policy         # policies from this folder instead
set -u
img=${1:?usage: $0 <image> [policy-dir]}
pol=${2:-}
pol_mount=(); pol_path=/opt/gate/policy/workflows
if [ -n "$pol" ]; then
  pol_mount=(-v "$(realpath "$pol"):/pol:ro,Z"); pol_path=/pol/workflows
fi
rc=0
for dir in tests/workflows/*/; do
  name=$(basename "$dir")
  want=$(xargs < "$dir/expect")
  out=$(podman run --rm --network=none "${pol_mount[@]}" \
          -v "$(realpath "$dir"):/case:ro,Z" "$img" \
          conftest test --no-color --parser yaml --namespace workflows \
          -p "$pol_path" /case/workflow.yml 2>&1)
  # no summary line means conftest itself failed (bad policy, bad mount) - never a pass
  if ! grep -qE '^[0-9]+ tests?, ' <<<"$out"; then
    echo "ERROR $name  conftest did not run:"; sed 's/^/      /' <<<"$out"; rc=1; continue
  fi
  got=$(grep -o 'WF-[0-9][0-9][0-9]' <<<"$out" | sort -u | xargs)
  if [ "$want" = "$got" ]; then
    echo "ok    $name  [${got:-none}]"
  else
    echo "FAIL  $name  expected [${want:-none}] got [${got:-none}]"; rc=1
  fi
done
exit $rc
