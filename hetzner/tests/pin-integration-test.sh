#!/usr/bin/env bash
# Root-only integration tests on an EPHEMERAL GitHub-hosted runner.
# Deliberately refuses use on a normal VM or a pre-existing BOA box.
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true || "${CI:-}" != true \
  || "$(id -u)" != 0 ]]; then
  echo 'REFUSED: CI-only integration test requires root on GitHub Actions' >&2
  exit 76
fi
repo="${GITHUB_WORKSPACE:?missing GitHub Actions workspace}"
[[ -f "$repo/hetzner/fork-source.sh" ]] || exit 1
[[ ! -e /root/.boa-fork-source.sha && ! -L /root/.boa-fork-source.sha \
  && ! -e /opt/boa-fork && ! -e /opt/tmp/boa \
  && ! -e /var/aegir/.drush/hm.alias.drushrc.php ]] || {
  echo 'REFUSED: existing pin, source tree, staging or BOA installation' >&2
  exit 76
}
cleanup() {
  rm -f /root/.boa-fork-source.sha
  rm -rf /opt/boa-fork /opt/tmp/boa
}
trap cleanup EXIT
git -c safe.directory="$repo" -C "$repo" rev-parse HEAD >/dev/null
sha="$(git -c safe.directory="$repo" -C "$repo" rev-parse HEAD)"
[[ "$sha" =~ ^[a-f0-9]{40}$ ]]
install -d -m 0700 /opt/boa-fork
git -c safe.directory="$repo" clone --quiet --no-hardlinks "$repo" /opt/boa-fork/source
git -C /opt/boa-fork/source remote set-url origin https://github.com/actools-pl/boa.git
git -C /opt/boa-fork/source checkout --quiet --detach "$sha"
chmod 0700 /opt/boa-fork /opt/boa-fork/source
umask 077
printf '%s\n' "$sha" > /root/.boa-fork-source.sha
chmod 0600 /root/.boa-fork-source.sha
# shellcheck disable=SC1091
source /opt/boa-fork/source/hetzner/fork-source.sh
boa_fork_init
[[ "$BOA_FORK_MODE" == YES && "$BOA_FORK_SHA" = "$sha" ]]
# Fresh destination MUST return success, not just create the tree.
boa_fork_stage_tree /opt/tmp/boa
[[ "$(stat -c %a /opt/tmp/boa)" = "755" ]] || {
  echo 'FAIL: BOA staged tree is not traversable for service accounts' >&2
  exit 1
}
test -s /opt/tmp/boa/lib/functions/helper.sh.inc
cmp -s /opt/tmp/boa/BOA.sh.txt /opt/boa-fork/source/BOA.sh.txt
# Replacing an already staged tree must succeed and leave no stale backups.
printf 'stale\n' > /opt/tmp/boa/old-file-for-test
boa_fork_stage_tree /opt/tmp/boa
test ! -e /opt/tmp/boa/old-file-for-test
test -s /opt/tmp/boa/aegir/helpers/apt.conf.noi.nrml
test -z "$(find /opt/tmp -maxdepth 1 -name 'boa.previous.*' -print -quit)"
# Direct pinned BOA file staging and missing-file nonclobber.
tmp="$(mktemp)"
boa_fork_stage_file https://files.boa.io/versions/lts/boa/aegir/tools/bin/boa "$tmp"
cmp -s "$tmp" /opt/boa-fork/source/aegir/tools/bin/boa
printf 'keep-original' > "$tmp"
if boa_fork_stage_file https://files.boa.io/versions/lts/boa/missing-file "$tmp" 2>/dev/null; then
  echo 'FAIL: staged nonexistent BOA file' >&2
  exit 1
fi
test "$(cat "$tmp")" = keep-original
rm -f "$tmp"
# Pin, origin, tree and marker permission drift must abort, not fallback.
git -C /opt/boa-fork/source remote set-url origin https://github.com/omega8cc/boa.git
if boa_fork_init 2>/dev/null; then echo 'FAIL: accepted wrong origin' >&2; exit 1; fi
git -C /opt/boa-fork/source remote set-url origin https://github.com/actools-pl/boa.git
printf 'tampered\n' >> /opt/boa-fork/source/hetzner/fork-source.sh
if boa_fork_init 2>/dev/null; then echo 'FAIL: accepted dirty checkout' >&2; exit 1; fi
git -C /opt/boa-fork/source restore hetzner/fork-source.sh
chmod 0644 /root/.boa-fork-source.sha
if boa_fork_init 2>/dev/null; then echo 'FAIL: accepted insecure marker mode' >&2; exit 1; fi
chmod 0600 /root/.boa-fork-source.sha
boa_fork_init
echo 'PASS: offline root pin setup, fresh/replacement staging and drift refusal'
