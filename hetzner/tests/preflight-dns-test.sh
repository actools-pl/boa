#!/usr/bin/env bash
# Verify BOA DNS preflight bypasses Debian/Hetzner /etc/hosts aliases.
# No DNS/network calls and no modifications to /etc/hosts.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
src="$repo/hetzner/preflight.sh"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed -n '/^dns_a_records() {/,/^}/p' "$src" > "$tmp"
[[ -s "$tmp" ]] || { echo "FAIL: DNS-only resolver function missing"; exit 1; }
bash -n "$tmp"
# shellcheck disable=SC1090
source "$tmp"

# Unqualified getent queries (NSS files first) would return 127.0.1.1.
# DNS-only queries must return the published A record instead.
getent() {
  if [[ "${1:-}" = -s && "${2:-}" = dns && "${3:-}" = ahostsv4 ]]; then
    case "${4:-}" in
      server.aarinct.com | boa-preflight-check.server.aarinct.com)
        printf '116.203.241.156 STREAM example\n'
        return 0 ;;
    esac
    return 2
  fi
  printf '127.0.1.1 STREAM local-hosts-shadow\n'
  return 0
}
got="$(dns_a_records server.aarinct.com)"
[[ "$got" = 116.203.241.156 ]] || {
  echo "FAIL: hostname DNS resolver used /etc/hosts shadow: $got"; exit 1;
}
got="$(dns_a_records boa-preflight-check.server.aarinct.com)"
[[ "$got" = 116.203.241.156 ]] || {
  echo "FAIL: wildcard DNS resolver used /etc/hosts shadow: $got"; exit 1;
}
# An NXDOMAIN is expected to yield no output and may return nonzero from
# glibc getent; that failure must not abort this negative assertion.
got="$(dns_a_records unknown.example.invalid || true)"
[[ -z "$got" ]] || {
  echo "FAIL: missing DNS name returned a local hosts result: $got"; exit 1;
}
echo "PASS: preflight DNS resolver bypasses /etc/hosts without changes"
