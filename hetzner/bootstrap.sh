#!/usr/bin/env bash
# One-time pin preparation, not a BOA installer. Never reuses an existing pin.
set -euo pipefail
if [[ "${1:-}" != "--prepare" || "$#" -ne 1 ]]; then
  echo "Usage: bash hetzner/bootstrap.sh --prepare" >&2
  echo "Stages a pinned local source, without installing BOA or rebooting." >&2
  exit 2
fi
[[ "$(id -u)" = 0 ]] || { echo "Root required" >&2; exit 1; }
[[ -r /etc/os-release ]] || { echo "No /etc/os-release" >&2; exit 1; }
. /etc/os-release
[[ "$ID" = debian && "$VERSION_ID" = 13 && "$(uname -m)" = x86_64 ]] \
  || { echo "Requires clean x86-64 Debian 13" >&2; exit 1; }
[[ ! -e /var/aegir/.drush/hm.alias.drushrc.php ]] \
  || { echo "Existing BOA installation; refusing" >&2; exit 1; }
command -v git >/dev/null 2>&1 \
  || { echo "Git required; install it only on a disposable snapshotted VM" >&2; exit 1; }
_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ ! -L "$_src" && ! -e /root/.boa-fork-source.sha && ! -L /root/.boa-fork-source.sha ]] \
  || { echo "Pin exists or source checkout is linked" >&2; exit 1; }
[[ "$(git -C "$_src" remote get-url origin)" = https://github.com/actools-pl/boa.git ]] \
  || { echo "Only actools-pl/boa HTTPS origin is allowed" >&2; exit 1; }
[[ "$(git -C "$_src" branch --show-current)" = hetzner-drupal11 ]] \
  || { echo "Requires hetzner-drupal11 branch" >&2; exit 1; }
[[ -z "$(git -C "$_src" status --porcelain --untracked-files=normal)" ]] \
  || { echo "Dirty checkout; refusing" >&2; exit 1; }
_sha="$(git -C "$_src" rev-parse HEAD)"
[[ "$_sha" =~ ^[0-9a-f]{40}$ ]] || exit 1
[[ ! -e /opt/boa-fork ]] || { echo "Existing /opt/boa-fork; refusing" >&2; exit 1; }
install -d -m 0700 /opt/boa-fork
if ! git clone --no-hardlinks --quiet "$_src" /opt/boa-fork/source; then
  rm -rf /opt/boa-fork; exit 1
fi
git -C /opt/boa-fork/source remote set-url origin https://github.com/actools-pl/boa.git
git -C /opt/boa-fork/source checkout --detach --quiet "$_sha"
chmod 0700 /opt/boa-fork /opt/boa-fork/source
umask 077
printf '%s\n' "$_sha" > /root/.boa-fork-source.sha
chmod 0600 /root/.boa-fork-source.sha
# shellcheck disable=SC1091
source /opt/boa-fork/source/hetzner/fork-source.sh
if ! boa_fork_init; then
  rm -f /root/.boa-fork-source.sha
  echo "Pin validation failed; BOA not installed" >&2
  exit 1
fi
cat <<EOF
Pinned actools-pl/boa commit: $_sha
After snapshot + tested Hetzner Rescue access and passing preflight:
  bash /opt/boa-fork/source/BOA.sh.txt
  boa help
  boa in-lts public server.example.com client@example.com o1 nodns
Never use these example addresses literally. First deployment is TEST ONLY.
EOF
