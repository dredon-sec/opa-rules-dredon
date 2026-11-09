#!/usr/bin/env bash
# Runs every sample in tests/dockerfile/ through the gate image and compares
# the rule IDs found with the sample's "expect" file.
# Usage (from the repo root):
#   tests/run-dockerfile-tests.sh <image>               # policies baked into the image
#   tests/run-dockerfile-tests.sh <image> policy         # policies from this folder instead
set -u
img=${1:?usage: $0 <image> [policy-dir]}
pol=${2:-}
pol_mount=(); pol_path=/opt/gate/policy/dockerfile
if [ -n "$pol" ]; then
  pol_mount=(-v "$(realpath "$pol"):/pol:ro,Z"); pol_path=/pol/dockerfile
fi
rc=0
for dir in tests/dockerfile/*/; do
  name=$(basename "$dir")
  want=$(xargs < "$dir/expect")
  out=$(podman run --rm --network=none "${pol_mount[@]}" \
          -v "$(realpath "$dir"):/case:ro,Z" "$img" \
          conftest test --no-color --parser dockerfile --namespace dockerfile \
          -p "$pol_path" /case/Dockerfile 2>&1)
  # no summary line means conftest itself failed (bad policy, bad mount) - never a pass
  if ! grep -qE '^[0-9]+ tests?, ' <<<"$out"; then
    echo "ERROR $name  conftest did not run:"; sed 's/^/      /' <<<"$out"; rc=1; continue
  fi
  got=$(grep -o 'DF-[0-9][0-9][0-9]' <<<"$out" | sort -u | xargs)
  if [ "$want" = "$got" ]; then
    echo "ok    $name  [${got:-none}]"
  else
    echo "FAIL  $name  expected [${want:-none}] got [${got:-none}]"; rc=1
  fi
done
exit $rc
