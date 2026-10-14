#!/usr/bin/env bash
# Read-only post-install inspection. Never prints a password or login token.
set -uo pipefail
fails=0
warns=0
pass(){ printf 'PASS  %s\n' "$*"; }
warn(){ printf 'WARN  %s\n' "$*"; warns=$((warns + 1)); }
fail(){ printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
usage(){
  echo "Usage: bash hetzner/verify-install.sh <server.fqdn> [@site-alias]"
  echo "Example: bash hetzner/verify-install.sh server.example.com @www-example.com"
  echo "Read-only: checks source, OS, BOA, DB, PHP, Nginx, Ægir, and optional Drupal site."
}
if [[ "${1:-}" = --help || "${1:-}" = help ]]; then usage; exit 0; fi
if (( $# < 1 || $# > 2 )); then usage; exit 2; fi
fqdn="$1"; site_alias="${2:-}"
[[ "$fqdn" =~ ^[A-Za-z0-9.-]+$ && "$fqdn" == *.*.* ]] || { usage; exit 2; }
if [[ -n "$site_alias" && ! "$site_alias" =~ ^@[A-Za-z0-9.-]+$ ]]; then
  echo "Invalid site alias; give a Drush alias such as @example.com" >&2
  exit 2
fi
[[ "$(id -u)" = 0 ]] || { echo 'Root SSH login required' >&2; exit 1; }

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "$ID" = devuan && "${VERSION_CODENAME:-}" = excalibur ]]; then
    pass "Devuan Excalibur is installed after Debian 13 conversion"
  else
    fail "expected Devuan Excalibur, got $ID/${VERSION_CODENAME:-unknown}"
  fi
else fail 'OS release unknown'; fi

if [[ -e /lib/systemd/systemd ]]; then
  fail "systemd binary remains; BOA requires Devuan/SysV init"
else
  pass "no systemd init binary at /lib/systemd/systemd"
fi

if [[ -s /root/.boa-fork-source.sha \
   && -r /opt/boa-fork/source/hetzner/fork-source.sh ]]; then
  # shellcheck disable=SC1091
  source /opt/boa-fork/source/hetzner/fork-source.sh
  if boa_fork_init; then
    pass "BOA source is pinned: ${BOA_FORK_SHA:0:12}"
  else fail "fork pin validation failed"; fi
else
  fail "pinned BOA source not found"
fi

if [[ "${BOA_FORK_MODE:-NO}" = YES ]]; then
  for entry in boa barracuda octopus autoinit; do
    binary="/opt/local/bin/$entry"
    pinned="$BOA_FORK_ROOT/aegir/tools/bin/$entry"
    if [[ -s "$binary" && -s "$pinned" ]] && cmp -s "$binary" "$pinned"; then
      pass "installed $entry matches pinned source"
    else
      fail "installed $entry missing or not identical to pinned source"
    fi
  done
fi

if command -v boa >/dev/null 2>&1; then
  # BOA's documented fresh-install completion criterion is >=3 Percona lines.
  count="$(boa info 2>/dev/null | grep -c 'Percona' || true)"
  if [[ "$count" =~ ^[0-9]+$ && $count -ge 3 ]]; then
    pass "BOA completion report has $count Percona lines"
  else
    fail "BOA completion check not met (Percona lines: $count)"
  fi
else
  fail "boa launcher not found in PATH"
fi

if command -v mysql >/dev/null 2>&1; then
  version="$(mysql --batch --skip-column-names -e 'SELECT @@version;' 2>/dev/null)"
  flavor="$(mysql --batch --skip-column-names -e 'SELECT @@version_comment;' 2>/dev/null)"
  if [[ "$version" == 8.4.* ]]; then
    pass "MySQL-compatible database server version $version"
  else
    fail "database is not version 8.4 (reported ${version:-unavailable})"
  fi
  if [[ "$flavor" == *Percona* ]]; then
    pass "Percona server flavor confirmed"
  else
    warn "database vendor not confirmed as Percona: ${flavor:-unavailable}"
  fi
else fail "MySQL/Percona client not installed"; fi

if command -v php >/dev/null 2>&1; then
  php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null)"
  if [[ "$php_version" =~ ^8\.([3-9]|[1-9][0-9])\. ]]; then
    pass "PHP CLI $php_version supports Drupal 11"
  else fail "Drupal 11 requires PHP 8.3+ (reported ${php_version:-missing})"; fi
else fail "PHP CLI not found"; fi

if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; then
  pass "Nginx configuration validation succeeded"
else fail "Nginx unavailable or configuration test failed"; fi

if id o1 >/dev/null 2>&1; then
  if su -s /bin/bash o1 -c 'drush @hm status' >/dev/null 2>&1; then
    pass "Ægir Hostmaster status responds as o1"
  else
    fail "Ægir Hostmaster Drush status failed"
  fi
else fail "Octopus o1 system account missing"; fi

# A root-owned /opt/local/bin created with inherited umask 077 (0700)
# leaves /bin/sh -> /opt/local/bin/websh inaccessible to instance users.
# Drush runs its mysql/provision children through PHP shell execution, so
# this check is critical even when Hostmaster's PDO connection works.
if id o1 >/dev/null 2>&1; then
  if su -s /bin/bash - o1 -c '/bin/sh -c "/bin/true"' >/dev/null 2>&1; then
    pass "o1 can execute the BOA /bin/sh wrapper"
  else
    fail "o1 cannot execute /bin/sh; inspect /opt/local and /opt/local/bin traversal permissions"
  fi
  if su -s /bin/bash - o1 -c \
    'php -r '\''$out=[]; $status=-1; exec("/bin/true", $out, $status); exit($status === 0 ? 0 : 1);'\''' \
    >/dev/null 2>&1; then
    pass "o1 PHP CLI can launch a subprocess"
  else
    fail "o1 PHP CLI cannot launch a subprocess (Drush task execution is blocked)"
  fi
fi

if [[ -f /data/disk/o1/log/setupmail.txt && ! -L /data/disk/o1/log/setupmail.txt ]]; then
  pass "welcome information exists locally; never copy its passwords to Git"
else
  warn "setupmail.txt not found; if panel is healthy recover access with: su -s /bin/bash o1 -c 'drush @hm uli'"
fi

if command -v getent >/dev/null 2>&1; then
  if getent ahostsv4 "o1.$fqdn" >/dev/null 2>&1; then
    pass "o1.$fqdn has an IPv4 DNS answer"
  else fail "panel FQDN does not resolve"; fi
fi
if command -v curl >/dev/null 2>&1; then
  if curl -fsSIL --max-time 15 "https://o1.$fqdn" >/dev/null 2>&1; then
    pass "control-panel HTTPS responds with a valid TLS certificate"
  else
    warn "control panel HTTPS not verified from this host; check externally and review TLS logs"
  fi
fi

# vdrush is a limited-shell wrapper command, not an executable in o1's
# Bash shell. A locked BOA platform supports Drush 8's read-only status.
# Use its positional field selector (not modern Drush's --field option).
# Never report raw failed-command output: it may contain private config.
boa_verify_site_version() {
  local alias="$1" version
  [[ "$alias" =~ ^@[A-Za-z0-9.-]+$ ]] || return 1
  if ! version="$(su -s /bin/bash - o1 -c \
    "drush8 $alias status drupal-version --format=string --no-show-passwords" 2>/dev/null)"; then
    return 1
  fi
  [[ "$version" =~ ^11\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]] || return 1
  printf '%s\n' "$version"
}

if [[ -n "$site_alias" ]]; then
  if result="$(boa_verify_site_version "$site_alias")"; then
    pass "site $site_alias reports Drupal $result"
  else
    fail "site $site_alias Drupal 11 version probe failed; inspect: su -s /bin/bash - o1 -c 'drush8 $site_alias status drupal-version --format=string'"
  fi
else
  warn "Drupal 11 site not checked; supply @site-alias after registering a platform and installing a site"
fi
echo
printf 'Result: %s failure(s), %s warning(s)\n' "$fails" "$warns"
if (( fails > 0 )); then exit 1; fi
if [[ -z "$site_alias" ]]; then
  echo "INCOMPLETE: BOA stack checks passed, but no Drupal 11 site was verified."
  exit 2
fi
exit 0
