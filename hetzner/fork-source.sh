#!/usr/bin/env bash
# Opt-in BOA code source. Inactive on upstream hosts without the root marker.
_BF_MARK=/root/.boa-fork-source.sha
_BF_TREE=/opt/boa-fork/source
_BF_ORIGIN=https://github.com/actools-pl/boa.git

boa_fork_error() { printf 'BOA FORK REFUSED: %s\n' "$*" >&2; return 1; }

boa_fork_init() {
  [[ -e "$_BF_MARK" || -L "$_BF_MARK" ]] || return 0
  [[ "$(id -u)" = 0 ]] || { boa_fork_error "root required"; return 1; }
  [[ -f "$_BF_MARK" && ! -L "$_BF_MARK" ]] \
    || { boa_fork_error "unsafe source marker"; return 1; }
  [[ "$(stat -c '%u:%a' "$_BF_MARK" 2>/dev/null)" = "0:600" ]] \
    || { boa_fork_error "marker must be root owned, mode 0600"; return 1; }

  local _pin _head _remote _dirty
  _pin="$(cat "$_BF_MARK")"
  [[ "$_pin" =~ ^[0-9a-f]{40}$ ]] \
    || { boa_fork_error "pin must be a 40-character lowercase Git SHA"; return 1; }
  [[ -d "$_BF_TREE" && ! -L "$_BF_TREE" ]] \
    || { boa_fork_error "pinned checkout missing or symlinked"; return 1; }
  [[ "$(stat -c '%u' "$_BF_TREE" 2>/dev/null)" = 0 ]] \
    || { boa_fork_error "checkout not root-owned"; return 1; }
  command -v git >/dev/null 2>&1 \
    || { boa_fork_error "git unavailable; no upstream fallback"; return 1; }
  _head="$(git -C "$_BF_TREE" rev-parse HEAD 2>/dev/null)" \
    || { boa_fork_error "checkout HEAD unreadable"; return 1; }
  _remote="$(git -C "$_BF_TREE" remote get-url origin 2>/dev/null)" \
    || { boa_fork_error "checkout origin missing"; return 1; }
  [[ "$_head" = "$_pin" && "$_remote" = "$_BF_ORIGIN" ]] \
    || { boa_fork_error "checkout SHA or origin differs from pin"; return 1; }
  [[ "$(git -C "$_BF_TREE" cat-file -t "$_pin" 2>/dev/null)" = commit ]] \
    || { boa_fork_error "pinned object is not a commit"; return 1; }
  _dirty="$(git -C "$_BF_TREE" status --porcelain --untracked-files=normal 2>/dev/null)" \
    || { boa_fork_error "cannot verify checkout cleanliness"; return 1; }
  [[ -z "$_dirty" ]] \
    || { boa_fork_error "checkout differs from pinned commit"; return 1; }
  [[ -s "$_BF_TREE/BOA.sh.txt" && -s "$_BF_TREE/hetzner/fork-source.sh" ]] \
    || { boa_fork_error "required BOA source missing"; return 1; }
  BOA_FORK_MODE=YES
  BOA_FORK_SHA="$_pin"
  BOA_FORK_ROOT="$_BF_TREE"
  export BOA_FORK_MODE BOA_FORK_SHA BOA_FORK_ROOT
}

# Return 0 with local path for a BOA LTS URL; 2 for unrelated URLs;
# return 1 for an unexpected BOA code URL or missing pinned file.
boa_fork_path_for_url() {
  local _url="$1" _rel _p
  case "$_url" in
    https://files.boa.io/versions/lts/boa/*|https://files.o8.io/versions/lts/boa/*|https://files.host8.biz/versions/lts/boa/*)
      _rel="${_url#*/versions/lts/boa/}" ;;
    https://*/versions/*/boa/*)
      boa_fork_error "unexpected non-LTS BOA code URL $_url"; return 1 ;;
    *) return 2 ;;
  esac
  if [[ -z "$_rel" || "$_rel" = /* || "$_rel" = *..* || "$_rel" = *\?* || "$_rel" = *\#* ]]; then
    boa_fork_error "unsafe BOA source path"; return 1
  fi
  _p="${BOA_FORK_ROOT:-}/$_rel"
  [[ -f "$_p" && ! -L "$_p" && -s "$_p" ]] \
    || { boa_fork_error "pinned file missing: $_rel"; return 1; }
  printf '%s\n' "$_p"
}

boa_fork_stage_file() {
  local _url="$1" _dst="$2" _src
  _src="$(boa_fork_path_for_url "$_url")" || return 1
  cp -p -- "$_src" "$_dst" || { boa_fork_error "copy failed: $_src"; return 1; }
  [[ -s "$_dst" ]] || { boa_fork_error "empty staged file $_dst"; return 1; }
}

# Restrict tar extraction destinations to BOA's own staging directories.
boa_fork_stage_tree() {
  local _dst="$1" _parent _tmp _old
  case "$_dst" in
    /opt/tmp/boa|/opt/tmp/boa-refetch/boa) ;;
    *) boa_fork_error "disallowed staging path $_dst"; return 1 ;;
  esac
  [[ ! -L "$_dst" && ! -L "${_dst%/*}" ]] \
    || { boa_fork_error "symlinked staging path"; return 1; }
  _parent="${_dst%/*}"
  mkdir -p -- "$_parent" || return 1
  _tmp="$(mktemp -d "$_parent/.boa-pin.XXXXXXXX")" || return 1
  if ! (set -o pipefail; git -C "$BOA_FORK_ROOT" archive "$BOA_FORK_SHA" | tar -xf - -C "$_tmp"); then
    rm -rf -- "$_tmp"; boa_fork_error "Git archive extraction failed"; return 1
  fi
  if [[ ! -s "$_tmp/lib/functions/helper.sh.inc" \
    || ! -s "$_tmp/aegir/helpers/apt.conf.noi.nrml" \
    || ! -s "$_tmp/aegir/helpers/apt.conf.noi.dist" ]]; then
    rm -rf -- "$_tmp"; boa_fork_error "staged tree fails sentinels"; return 1
  fi
  _old="${_dst}.previous.$"
  [[ ! -e "$_old" && ! -L "$_old" ]] \
    || { rm -rf -- "$_tmp"; boa_fork_error "old staging backup already exists"; return 1; }
  if [[ -e "$_dst" ]]; then
    mv -- "$_dst" "$_old" || { rm -rf -- "$_tmp"; return 1; }
  fi
  if ! mv -- "$_tmp" "$_dst"; then
    [[ -d "$_old" ]] && mv -- "$_old" "$_dst"
    rm -rf -- "$_tmp"; boa_fork_error "could not place pinned BOA tree"; return 1
  fi
  [[ -d "$_old" ]] && rm -rf -- "$_old"
}
