#!/usr/bin/env bash
# Exercise the actual version probe and PHP JSON parser without a BOA server.
set -euo pipefail
command -v php >/dev/null || { echo 'FAIL: PHP CLI required for parser regression' >&2; exit 1; }
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed -n '/^boa_verify_site_version() {/,/^}/p' \
  "$repo/hetzner/verify-install.sh" > "$tmp/probe.sh"
test -s "$tmp/probe.sh"
# shellcheck disable=SC1090
source "$tmp/probe.sh"

# Drush 8 core-status returns a format-list and rejects the string formatter.
# Model its supported full JSON status result, not an already-extracted string.
# Require the o1 login environment and never invoke limited-shell-only vdrush.
su() {
  [[ $# = 6 && "$1" = -s && "$2" = /bin/bash &&
     "$3" = - && "$4" = o1 && "$5" = -c ]] || return 127
  [[ "$6" = 'drush8 @aarinct.com status --format=json --no-show-passwords' ]] || return 1
  printf '%s\n' "$mock_stdout"
  printf '%s\n' 'PRIVATE_DIAGNOSTIC_MUST_NOT_LEAK' >&2
  return "$mock_rc"
}

mock_rc=0
mock_stdout='{"drupal-version":"11.4.9","bootstrap":"Successful","db-status":"Connected","other":"PRIVATE_DIAGNOSTIC_MUST_NOT_LEAK"}'
[[ "$(boa_verify_site_version @aarinct.com)" = 11.4.9 ]]
mock_stdout='{"drupal-version":"11.5.0-rc1"}'
[[ "$(boa_verify_site_version @aarinct.com)" = 11.5.0-rc1 ]]

for scenario in nonzero wrong-major empty malformed missing-field null-field array-field scalar prefix invalid-alias; do
  mock_rc=0
  alias=@aarinct.com
  mock_stdout='{"drupal-version":"11.4.9"}'
  case "$scenario" in
    nonzero) mock_rc=1 ;;
    wrong-major) mock_stdout='{"drupal-version":"10.4.9"}' ;;
    empty) mock_stdout= ;;
    malformed) mock_stdout='{PRIVATE_DIAGNOSTIC_MUST_NOT_LEAK' ;;
    missing-field) mock_stdout='{"notice":"11.4.9"}' ;;
    null-field) mock_stdout='{"drupal-version":null}' ;;
    array-field) mock_stdout='{"drupal-version":["11.4.9"]}' ;;
    scalar) mock_stdout='"11.4.9"' ;;
    prefix) mock_stdout=$'PRIVATE_DIAGNOSTIC_MUST_NOT_LEAK\n{"drupal-version":"11.4.9"}' ;;
    invalid-alias) alias='@aarinct.com;false' ;;
  esac
  if boa_verify_site_version "$alias" > "$tmp/output" 2> "$tmp/error"; then
    echo "FAIL: accepted $scenario result" >&2
    exit 1
  fi
  [[ ! -s "$tmp/output" && ! -s "$tmp/error" ]]
done
echo 'PASS: supported Drush 8 JSON status, real PHP parser, and private failure handling'
