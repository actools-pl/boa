#!/usr/bin/env bash
# Exercise the actual site's version probe without touching a BOA server.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed -n '/^boa_verify_site_version() {/,/^}/p' \
  "$repo/hetzner/verify-install.sh" > "$tmp/probe.sh"
test -s "$tmp/probe.sh"
# shellcheck disable=SC1090
source "$tmp/probe.sh"

# The old verifier invoked vdrush as o1; simulate that command being absent.
# Require the supported Drush 8 command and o1's login-shell environment.
su() {
  [[ $# = 6 && "$1" = -s && "$2" = /bin/bash &&
     "$3" = - && "$4" = o1 && "$5" = -c ]] || return 127
  [[ "$6" = 'drush8 @aarinct.com status drupal-version --format=string --no-show-passwords' ]] || return 127
  printf '%s\n' "$mock_stdout"
  printf '%s\n' 'PRIVATE_DIAGNOSTIC_MUST_NOT_LEAK' >&2
  return "$mock_rc"
}

mock_rc=0
mock_stdout=11.4.9
[[ "$(boa_verify_site_version @aarinct.com)" = 11.4.9 ]]
mock_stdout=11.5.0-rc1
[[ "$(boa_verify_site_version @aarinct.com)" = 11.5.0-rc1 ]]

for scenario in nonzero wrong-major empty ambiguous invalid-alias; do
  mock_rc=0
  alias=@aarinct.com
  case "$scenario" in
    nonzero) mock_rc=1; mock_stdout=11.4.9 ;;
    wrong-major) mock_stdout=10.4.9 ;;
    empty) mock_stdout= ;;
    ambiguous) mock_stdout=$'11.4.9\nPRIVATE_DIAGNOSTIC_MUST_NOT_LEAK' ;;
    invalid-alias) alias='@aarinct.com;false'; mock_stdout=11.4.9 ;;
  esac
  if boa_verify_site_version "$alias" > "$tmp/output" 2> "$tmp/error"; then
    echo "FAIL: accepted $scenario result" >&2
    exit 1
  fi
  [[ ! -s "$tmp/output" && ! -s "$tmp/error" ]]
done
echo 'PASS: read-only locked-platform version check and failed-probe handling'
