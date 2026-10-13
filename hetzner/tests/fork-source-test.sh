#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
for f in hetzner/fork-source.sh hetzner/bootstrap.sh hetzner/preflight.sh \
  hetzner/tests/pin-integration-test.sh hetzner/tests/preflight-dns-test.sh hetzner/install.sh \
  hetzner/verify-install.sh \
  BOA.sh.txt BARRACUDA.sh.txt OCTOPUS.sh.txt \
  aegir/tools/bin/boa aegir/tools/bin/barracuda aegir/tools/bin/octopus \
  aegir/tools/bin/autoupboa aegir/tools/system/clear.sh \
  lib/settings/barracuda.sh.cnf lib/settings/octopus.sh.cnf; do
  bash -n "$repo/$f"
done
bash "$repo/hetzner/tests/preflight-dns-test.sh"
bash "$repo/hetzner/install.sh" help >/dev/null
bash "$repo/hetzner/verify-install.sh" help >/dev/null
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
# Validate every static BOA versioned file, not just the main launchers.
python3 - "$repo" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
content = (root / "BOA.sh.txt").read_text()
matches = re.findall(r'_fetch_versioned[^\n]*"\${_urlHmr}/([^"]+)"', content)
assert matches, "No versioned source paths found"
dynamic, missing = [], []
for path in matches:
    path = path.replace("${_tBn}", "tools/bin")
    if "${" in path:
        dynamic.append(path)
    elif not (root / "aegir" / path).is_file():
        missing.append(path)
assert not missing, "BOA files absent from pinned repo: " + ", ".join(missing)
print(f"PASS: {len(matches)-len(dynamic)} BOA LTS code paths present; {len(dynamic)} dynamic paths need runtime checks")
PY
# The source resolver copies pinned bytes and never damages an existing file
# when a requested source is missing.
_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT
boa_fork_stage_file https://files.boa.io/versions/lts/boa/aegir/tools/bin/boa "$_tmp/boa"
cmp -s "$_tmp/boa" "$repo/aegir/tools/bin/boa"
printf 'original' > "$_tmp/guard"
if boa_fork_stage_file https://files.boa.io/versions/lts/boa/no-such-file "$_tmp/guard" 2>/dev/null; then
  echo 'FAIL: unexpectedly accepted missing pinned file' >&2; exit 1
fi
[[ "$(cat "$_tmp/guard")" = original ]]
# Every pinned code tree must have these archive sentinels.
mkdir "$_tmp/export"
(set -o pipefail; git -c safe.directory="$repo" -C "$repo" archive HEAD | tar -xf - -C "$_tmp/export")
for file in lib/functions/helper.sh.inc aegir/helpers/apt.conf.noi.nrml \
  aegir/helpers/apt.conf.noi.dist hetzner/fork-source.sh; do
  test -s "$_tmp/export/$file"
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
