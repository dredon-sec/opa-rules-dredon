#!/usr/bin/env bash
# Plans every sample in tests/terraform/ inside the gate image, with networking
# off and no GitHub token, checks the plan with conftest, and compares the rule IDs
# found with the sample's "expect" file. The plan JSON never leaves the container.
# Usage (from the repo root):
#   tests/run-terraform-tests.sh <image>               # policies baked into the image
#   tests/run-terraform-tests.sh <image> policy         # policies from this folder instead
set -u
img=${1:?usage: $0 <image> [policy-dir]}
pol=${2:-}
pol_mount=(); pol_path=/opt/gate/policy/terraform
if [ -n "$pol" ]; then
  pol_mount=(-v "$(realpath "$pol"):/pol:ro,Z"); pol_path=/pol/terraform
fi
rc=0
for dir in tests/terraform/*/; do
  name=$(basename "$dir")
  want=$(xargs < "$dir/expect")
  out=$(podman run --rm --network=none "${pol_mount[@]}" \
          -v "$(realpath "$dir"):/case:ro,Z" "$img" sh -c '
            cp -r /case /tmp/w && cd /tmp/w || exit 3
            terraform init -input=false -no-color > /tmp/log 2>&1 &&
            terraform plan -input=false -no-color -out=/tmp/plan >> /tmp/log 2>&1 ||
              { echo "terraform failed:"; cat /tmp/log; exit 3; }
            terraform show -json /tmp/plan |
              conftest test --no-color --parser json --namespace terraform -p "$1" -
          ' sh "$pol_path" 2>&1)
  # no summary line means terraform or conftest failed - never a pass
  if ! grep -qE '^[0-9]+ tests?, ' <<<"$out"; then
    echo "ERROR $name"; sed 's/^/      /' <<<"$out"; rc=1; continue
  fi
  got=$(grep -o 'TF-[0-9][0-9][0-9]' <<<"$out" | sort -u | xargs)
  if [ "$want" = "$got" ]; then
    echo "ok    $name  [${got:-none}]"
  else
    echo "FAIL  $name  expected [${want:-none}] got [${got:-none}]"; rc=1
  fi
done
exit $rc
