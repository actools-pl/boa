#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
for f in hetzner/fork-source.sh hetzner/bootstrap.sh hetzner/preflight.sh \
  BOA.sh.txt BARRACUDA.sh.txt OCTOPUS.sh.txt \
  aegir/tools/bin/boa aegir/tools/bin/barracuda aegir/tools/bin/octopus \
  aegir/tools/bin/autoupboa aegir/tools/system/clear.sh \
  lib/settings/barracuda.sh.cnf lib/settings/octopus.sh.cnf; do
  bash -n "$repo/$f"
done
# Pure URL resolver tests. Production init always overrides this test variable.
# shellcheck disable=SC1091
source "$repo/hetzner/fork-source.sh"
BOA_FORK_ROOT="$repo"
test "$(boa_fork_path_for_url https://files.boa.io/versions/lts/boa/aegir/tools/bin/boa)" \
  = "$repo/aegir/tools/bin/boa"
for url in https://files.boa.io/versions/dev/boa/aegir/tools/bin/boa \
  https://evil.example/versions/lts/boa/aegir/tools/bin/boa \
  https://files.boa.io/versions/lts/boa/../../etc/passwd \
  https://files.boa.io/versions/lts/boa/nonexistent-file; do
  if boa_fork_path_for_url "$url" >/dev/null 2>&1; then
    echo "FAIL: unexpected source acceptance: $url" >&2; exit 1
  fi
done
for file in aegir/tools/bin/boa aegir/tools/bin/barracuda aegir/tools/bin/octopus; do
  grep -q 'boa_fork_stage_file' "$repo/$file"
done
for file in lib/settings/barracuda.sh.cnf lib/settings/octopus.sh.cnf; do
  grep -q 'boa_fork_stage_tree' "$repo/$file"
done
grep -q 'boa_fork_path_for_url' "$repo/BOA.sh.txt"
grep -q 'BOA_FORK_MODE' "$repo/aegir/tools/system/clear.sh"
echo 'PASS: BOA fork syntax and provenance hooks'
