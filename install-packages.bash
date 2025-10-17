#!/usr/bin/env bash
# install-groups.bash
# Installs packages from a grouped, comment-friendly list using Nala.
# Groups like [base] or [dev] are for organization only.
# Supports --ignore-missing, --dry-run, and pauses before install.

set -euo pipefail

LIST_FILE="./packages.txt"
IGNORE_MISSING=false
DRY_RUN=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ignore-missing) IGNORE_MISSING=true ;;
    --dry-run)        DRY_RUN=true ;;
    *)                LIST_FILE="$1" ;;
  esac
  shift
done

log() { printf '%s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$LIST_FILE" ]] || die "List file not found: $LIST_FILE"
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root: sudo $0 [--dry-run] [--ignore-missing] [packages.txt]"

ensure_nala() {
  if command -v nala >/dev/null 2>&1; then return; fi
  log "Nala not found; installing via apt..."
  if $DRY_RUN; then
    log "[dry-run] Would install nala via apt-get."
    return
  fi
  apt-get update -y
  apt-get install -y nala
}

# --- Read package list (skip groups/comments/blanks) ---
read_packages() {
  awk '
    { sub(/\r$/, ""); }                               # strip CR if present
    /^[[:space:]]*$/ { next }                         # skip blank lines
    /^[[:space:]]*#/ { next }                         # skip comment lines
    /^\[[^]]+\][[:space:]]*$/ { next }                # skip [group] headers
    {
      line=$0
      sub(/[ \t#].*$/, "", line)                      # strip inline comments
      if (line != "") print line
    }
  ' "$LIST_FILE" | awk '!seen[$0]++'                  # de-dupe
}

pkg_exists() {
  local p="$1"
  if apt-cache --names-only search "^${p}\$" 2>/dev/null | grep -q "^${p} -"; then
    return 0
  fi
  local cand
  cand="$(apt-cache policy "$p" 2>/dev/null | awk -F': ' '/Candidate:/ {print $2; exit}')"
  [[ -n "${cand:-}" && "$cand" != "(none)" ]]
}

pause_confirm() {
  local prompt="${1:-Continue? [y/N]}"
  read -rp "$prompt " answer
  case "${answer,,}" in
    y|yes) return 0 ;;
    *) log "Cancelled."; exit 0 ;;
  esac
}

main() {
  ensure_nala

  mapfile -t ALL_PKGS < <(read_packages)
  if ((${#ALL_PKGS[@]} == 0)); then
    log "No packages found in $LIST_FILE."
    exit 0
  fi

  log "Validating ${#ALL_PKGS[@]} packages..."
  INVALID=()
  VALID=()
  for p in "${ALL_PKGS[@]}"; do
    if pkg_exists "$p"; then
      VALID+=("$p")
    else
      INVALID+=("$p")
    fi
  done

  if ((${#INVALID[@]} > 0)); then
    log "Invalid/unknown packages: ${INVALID[*]}"
    if ! $IGNORE_MISSING; then
      die "Aborting due to invalid package names. Use --ignore-missing to skip."
    else
      log "Skipping invalid: ${INVALID[*]}"
    fi
  fi

  if ((${#VALID[@]} == 0)); then
    log "No valid packages to install."
    exit 0
  fi

  # Filter out already-installed packages
  MISSING=()
  for p in "${VALID[@]}"; do
    dpkg -s "$p" &>/dev/null || MISSING+=("$p")
  done

  if ((${#MISSING[@]} == 0)); then
    log "All valid packages are already installed."
    exit 0
  fi

  log ""
  log "The following packages will be installed (${#MISSING[@]} total):"
  for p in "${MISSING[@]}"; do
    log "  - $p"
  done
  log ""

  if $DRY_RUN; then
    log "[dry-run] No changes made."
    exit 0
  fi


  log "Updating package index..."
  nala update

  log "Installing packages..."
  nala install "${MISSING[@]}"

  log "Done."
}

main "$@"
