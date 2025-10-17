#!/usr/bin/env bash
# install_chrome.bash
# Safe, idempotent installer for Google Chrome Stable on Ubuntu.
# - Adds Google's signed APT repo if missing
# - Heals interrupted dpkg/apt state automatically
# - Prefers Nala if available; falls back to apt-get
# - Re-runnable: won't duplicate repo; skips install if already present

set -euo pipefail

REPO_FILE="/etc/apt/sources.list.d/google-chrome.list"
KEYRING="/usr/share/keyrings/google-chrome.gpg"
REPO_LINE="deb [arch=amd64 signed-by=${KEYRING}] https://dl.google.com/linux/chrome/deb/ stable main"
KEY_URL="https://dl.google.com/linux/linux_signing_key.pub"

log(){ printf '%s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root: sudo $0"

# Pick package manager
if command -v nala >/dev/null 2>&1; then
  PM_UPDATE() { nala update; }
  PM_INSTALL() { nala install --assume-yes "$@"; }
else
  PM_UPDATE() { apt-get update -y; }
  PM_INSTALL() { apt-get install -y "$@"; }
fi

wait_for_locks() {
  # Wait briefly if dpkg/apt locks are held
  local waited=0 max=60
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
        fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    (( waited >= max )) && break
    sleep 2
    waited=$((waited+2))
  done
}

fix_dpkg_state() {
  wait_for_locks
  # Finish any half-configured packages; fix deps; refresh index (quietly tolerate errors)
  dpkg --configure -a || true
  apt-get -f install -y || true
  apt-get update -y || true
}

ensure_prereqs() {
  # Make sure curl, gpg, certs exist (quiet if already present)
  PM_INSTALL curl gnupg ca-certificates
}

ensure_key() {
  if [[ ! -s "$KEYRING" ]]; then
    log "Adding Google signing key..."
    install -d -m 0755 "$(dirname "$KEYRING")"
    curl -fsSL "$KEY_URL" | gpg --dearmor | tee "$KEYRING" >/dev/null
    chmod 0644 "$KEYRING"
  else
    log "Signing key already present: $KEYRING"
  fi
}

ensure_repo() {
  if [[ ! -f "$REPO_FILE" ]] || ! grep -Fxq "$REPO_LINE" "$REPO_FILE"; then
    log "Configuring Chrome repository..."
    echo "$REPO_LINE" > "$REPO_FILE"
    chmod 0644 "$REPO_FILE"
  else
    log "Repository already configured: $REPO_FILE"
  fi
}

main() {
  # Heal any interrupted state first
  log "Checking dpkg/apt state…"
  fix_dpkg_state

  # Prereqs (uses PM_INSTALL so it also self-heals)
  log "Ensuring prerequisites…"
  ensure_prereqs

  # Key + repo
  ensure_key
  ensure_repo

  # Update cache and install if needed
  log "Updating package index…"
  PM_UPDATE

  if dpkg -s google-chrome-stable &>/dev/null; then
    log "Google Chrome is already installed."
  else
    log "Installing Google Chrome Stable…"
    PM_INSTALL google-chrome-stable
  fi

  log "Chrome setup complete."
}

main "$@"
