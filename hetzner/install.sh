#!/usr/bin/env bash
# Two-phase, explicit test installer for BOA LTS / Drupal 11 on Hetzner Cloud.
# This is an experimental tool: BOA's Debian->Devuan conversion is destructive.
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage:
  bash hetzner/install.sh prepare <server.fqdn> --snapshot-and-rescue-confirmed
  bash hetzner/install.sh install <server.fqdn> <client@email> --snapshot-and-rescue-confirmed
  bash hetzner/install.sh help

Prepare: runs read-only preflight, stages a commit-pinned actools-pl BOA checkout,
sets the host FQDN and invokes the pinned BOA meta-installer to install its tools.
It does NOT convert Debian or install Drupal.

Install: MUST run inside a screen session after successful preparation. Launches
the existing BOA LTS installation (Debian 13 -> Devuan Excalibur), using "nodns"
to skip initial SMTP/DNS checks, while retaining real FQDN + wildcard DNS.
On Excalibur BOA uses Percona 8.4 required by Drupal 11.

This is a DISPOSABLE-VPS / SNAPSHOT-REQUIRED workflow, not tested on Hetzner.
It does not configure SMTP AUTH or automatically create a Drupal site.
EOF
}
fail(){ printf 'BOA HETZNER REFUSED: %s\n' "$*" >&2; exit 76; }
valid_fqdn(){
  local host="$1" count=0 label
  [[ "$host" != *..* && "$host" != .* && "$host" != *. && "$host" != *" "* ]] || return 1
  IFS='.' read -r -a labels <<< "$host"
  (( "${#labels[@]}" >= 3 )) || return 1
  for label in "${labels[@]}"; do
    [[ "$label" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || return 1
    (( "${#label}" <= 63 )) || return 1
  done
  (( "${#host}" <= 253 ))
}
valid_mail(){
  [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}
if [[ "${1:-}" = help || "${1:-}" = --help ]]; then usage; exit 0; fi
(( "$#" >= 1 )) || { usage; exit 2; }
mode="$1"; shift
[[ "$(id -u)" = 0 ]] || fail "log in directly as root"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[[ ! -L "$script_dir" ]] || fail "linked script location"
case "$mode" in
  prepare)
    [[ "$#" = 2 && "$2" = --snapshot-and-rescue-confirmed ]] || { usage; exit 2; }
    host="$1"
    valid_fqdn "$host" || fail "invalid server FQDN (use subdomain.example.com)"
    [[ ! -e /root/.boa-fork-source.sha && ! -L /root/.boa-fork-source.sha ]] \
      || fail "source pin already installed; inspect it, do not reprepare blindly"
    [[ ! -e /var/aegir/.drush/hm.alias.drushrc.php ]] \
      || fail "existing BOA detected; fresh VM required"
    # This checks PUBLIC IPv4 == the hostname AND the wildcard A record.
    bash "$script_dir/preflight.sh" "$host" || fail "preflight failed; no BOA changes made"
    [[ -x "$(command -v hostname)" ]] || fail "hostname command missing"
    bash "$script_dir/bootstrap.sh" --prepare || fail "Git source pin staging failed"
    # Set a stable hostname so the Devuan conversion does not inherit the
    # provider's generic hostname. Upstream BOA recommends this before install.
    hostname -b "$host" || fail "could not set runtime hostname"
    printf '%s\n' "$host" > /etc/hostname
    # The installed BOA code is now taken from the pinned checkout.
    bash /opt/boa-fork/source/BOA.sh.txt || fail "pinned BOA tool bootstrap failed"
    [[ -s /opt/local/bin/boa && -s /opt/local/bin/autoinit ]] \
      || fail "BOA or autoinit tools missing after bootstrap"
    cmp -s /opt/local/bin/boa /opt/boa-fork/source/aegir/tools/bin/boa \
      || fail "installed boa launcher differs from pinned fork"
    echo "PREPARED: source commit $(cat /root/.boa-fork-source.sha)"
    cat <<EOF
Next (on the same disposable VPS):
  screen -S boa-install
  bash /opt/boa-fork/source/hetzner/install.sh install $host client@example.com --snapshot-and-rescue-confirmed
Substitute your actual CLIENT email. BOA will reboot during Debian->Devuan.
EOF
    ;;
  install)
    [[ "$#" = 3 && "$3" = --snapshot-and-rescue-confirmed ]] || { usage; exit 2; }
    host="$1"; email="$2"
    valid_fqdn "$host" || fail "invalid FQDN"
    valid_mail "$email" || fail "invalid client email"
    [[ -n "${STY:-}" ]] || fail "run inside GNU screen (start: screen -S boa-install)"
    [[ "$(cat /etc/hostname 2>/dev/null)" = "$host" ]] \
      || fail "/etc/hostname does not match requested FQDN"
    [[ -s /root/.boa-fork-source.sha && -s /opt/local/bin/boa ]] \
      || fail "fork not prepared; run prepare first"
    [[ ! -e /var/aegir/.drush/hm.alias.drushrc.php ]] \
      || fail "BOA already installed; never rerun the fresh installer"
    [[ ! -s /root/.boa.install.command.cnf ]] \
      || fail "a BOA install is already recorded; inspect autoinit and Barracuda logs"
    # shellcheck disable=SC1091
    source /opt/boa-fork/source/hetzner/fork-source.sh
    boa_fork_init || fail "pinned source failed validation"
    cmp -s /opt/local/bin/boa "$BOA_FORK_ROOT/aegir/tools/bin/boa" \
      || fail "installed BOA launcher is not pinned fork code"
    echo "INSTALL: BOA LTS on $host with local email recovery and nodns."
    echo "Pinned SHA: $BOA_FORK_SHA"
    echo "DO NOT MANUALLY REBOOT until all BOA phases complete."
    # Existing BOA launcher records the install and resumes after autoinit.
    exec /opt/local/bin/boa in-lts public "$host" "$email" o1 nodns
    ;;
  *)
    usage; exit 2 ;;
esac
