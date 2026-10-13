#!/usr/bin/env bash
# Read-only BOA / Drupal 11 preflight for a fresh Hetzner Cloud Debian 13 VM.
# No package installs, service changes, firewall changes, credentials or reboot.
set -uo pipefail

usage() {
  printf 'Usage: bash %s <server-fqdn> [smtp-relay-host]\n' "$0"
  printf 'Example: bash %s server.example.com smtp.example.net\n' "$0"
}
if (( $# < 1 || $# > 2 )) || [[ "$1" == "--help" || "$1" == "-h" ]]; then
  usage
  exit 2
fi

fqdn="$1"
relay=""
if (( $# == 2 )); then relay="$2"; fi
failures=0
warnings=0

ok()   { printf 'PASS  %s\n' "$*"; }
info() { printf 'INFO  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }

info "Hetzner Cloud / BOA LTS / Drupal 11 read-only preflight"
info "Target host: $fqdn"

if (( EUID == 0 )); then
  ok "running as root (required by BOA installation)"
else
  fail "run this preflight as root; BOA installation requires direct root login"
fi

if [[ "$fqdn" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ && "$fqdn" == *.* ]]; then
  ok "hostname is plausibly a fully qualified domain name"
else
  fail "hostname should be an FQDN such as server.example.com"
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "$ID" == "debian" && "$VERSION_ID" == "13" ]]; then
    ok "Debian 13 (Trixie) starting image detected"
  else
    fail "expected fresh Debian 13; detected ID=$ID VERSION_ID=$VERSION_ID"
  fi
else
  fail "/etc/os-release not available"
fi

if [[ "$(uname -m)" == "x86_64" ]]; then
  ok "x86-64 architecture"
else
  fail "requires x86-64 VM; found $(uname -m)"
fi

if [[ -r /proc/meminfo ]]; then
  mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  if (( mem_kb >= 3500000 )); then
    ok "RAM meets approximately 4 GiB BOA minimum"
    if (( mem_kb < 7500000 )); then
      warn "8 GiB or more recommended for first Hetzner/Drupal 11 test"
    fi
  else
    fail "RAM below BOA's 4 GiB recommendation"
  fi
else
  fail "cannot determine installed RAM"
fi

if command -v nproc >/dev/null 2>&1; then
  cpus=$(nproc)
  if (( cpus >= 2 )); then
    ok "$cpus CPU(s) available"
    if (( cpus < 4 )); then warn "4 CPU(s) recommended for first test"; fi
  else
    fail "fewer than 2 CPU(s)"
  fi
else
  warn "nproc unavailable; verify at least 2 CPUs"
fi

if [[ -f /root/.ssh/authorized_keys ]] \
  && grep -Eq '^ssh-ed25519[[:space:]]' /root/.ssh/authorized_keys; then
  ok "root has an ed25519 authorized SSH public key"
else
  fail "no root ed25519 authorized SSH key found; BOA may disable password SSH"
fi
info "Manually verify you can log in with that key AND access Hetzner rescue console."

if command -v ip >/dev/null 2>&1 \
  && ip -4 route show default 2>/dev/null | grep -q '^default '; then
  ok "IPv4 default route is configured"
else
  fail "IPv4 default route missing or ip command unavailable"
fi

# BOA requires wildcard A records pointing directly to this VM. A mere DNS
# answer is insufficient (127.0.1.1 via /etc/hosts, or a proxy elsewhere).
public_ips=""
if command -v ip >/dev/null 2>&1; then
  public_ips="$(ip -o -4 addr show scope global 2>/dev/null |
    awk '{sub(/\/.*/, "", $4); print $4}' | sort -u)"
fi
if [[ -z "$public_ips" ]]; then
  fail "no public/global IPv4 address detected on this VM"
fi
if command -v getent >/dev/null 2>&1; then
  for name in "$fqdn" "boa-preflight-check.$fqdn"; do
    resolved="$(getent ahostsv4 "$name" 2>/dev/null | awk '{print $1}' | sort -u)"
    if [[ -z "$resolved" ]]; then
      fail "$name has no IPv4 DNS answer"
    elif [[ -z "$public_ips" ]]; then
      fail "$name DNS cannot be matched to server IPv4"
    elif comm -12 <(printf '%s\n' "$public_ips") <(printf '%s\n' "$resolved") | grep -q .; then
      ok "$name resolves to an IPv4 address assigned to this VM"
    else
      fail "$name resolves to a different IPv4 address (wildcard/direct A required)"
    fi
  done
else
  fail "getent unavailable; cannot verify A records"
fi

if [[ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] \
  && [[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)" == "0" ]]; then
  warn "IPv6 enabled; upstream BOA currently disables IPv6"
fi

if [[ -d /etc/nginx || -d /etc/apache2 || -d /var/lib/mysql ]]; then
  fail "pre-existing web or database installation detected; use a clean Debian VM"
else
  ok "no common existing Nginx/Apache/MySQL directories"
fi

if command -v df >/dev/null 2>&1; then
  free_mb=$(df -Pm / | awk 'NR == 2 {print $4}')
  if [[ "$free_mb" =~ ^[0-9]+$ ]]; then
    info "available space on /: $free_mb MiB"
    if (( free_mb < 20000 )); then
      warn "less than 20 GiB free; BOA packages, databases and backups need headroom"
    fi
  else
    warn "could not determine filesystem free space"
  fi
fi

if command -v git >/dev/null 2>&1; then
  ok "Git is available for pinned-fork staging"
else
  fail "Git is required before pin preparation. On a disposable VM only, install it explicitly after taking a snapshot."
fi

if command -v wget >/dev/null 2>&1; then
  ok "wget available"
else
  fail "wget missing; required by upstream BOA installation"
fi
if command -v curl >/dev/null 2>&1; then
  if curl --fail --location --silent --show-error --max-time 10 \
      --output /dev/null https://files.boa.io/BOA.sh.txt 2>/dev/null; then
    ok "upstream BOA bootstrap URL reachable via HTTPS"
  else
    warn "cannot reach upstream BOA bootstrap URL via HTTPS"
  fi
else
  warn "curl unavailable; bootstrap URL not tested"
fi

if [[ -n "$relay" ]]; then
  if [[ "$relay" =~ ^[a-zA-Z0-9.-]+$ ]] && command -v timeout >/dev/null 2>&1; then
    if timeout 6 bash -c 'exec 3<>/dev/tcp/$1/587' _ "$relay" 2>/dev/null; then
      ok "TCP/587 reachable at $relay (authentication and delivery NOT tested)"
    else
      warn "TCP/587 unavailable at $relay; configure and test an SMTP relay separately"
    fi
  else
    warn "cannot test relay host (invalid hostname or timeout unavailable)"
  fi
else
  info "No SMTP relay supplied; port 25 is not required for credential recovery."
fi
info "The port-25 bypass requires the documented BOA 'nodns' option."
info "This preflight does not perform Debian->Devuan conversion or install BOA."

printf '\nPreflight: %s failure(s), %s warning(s)\n' "$failures" "$warnings"
if (( failures > 0 )); then exit 1; fi
exit 0
