#!/usr/bin/env bash
#
# Lidless installer — keeps your MacBook awake with the lid closed.
#
#   curl -fsSL https://raw.githubusercontent.com/abhi12299/lidless/main/install.sh | bash
#
# What it does:
#   1. Verifies you're on a supported macOS (14+) with the tools to build.
#   2. Clones the repo, builds a signed Lidless.app, installs it to /Applications.
#   3. Asks whether to launch Lidless now and whether to start it at login.
#
# It never asks for your password up front. The app itself requests one admin
# prompt the first time you toggle stay-awake, to install a passwordless helper.

set -euo pipefail

# --- Config -----------------------------------------------------------------
REPO_SLUG="abhi12299/lidless"
REPO_URL="https://github.com/${REPO_SLUG}.git"
BRANCH="main"
APP_NAME="Lidless"
BUNDLE_ID="com.lidless"
INSTALL_DIR="/Applications"
APP_PATH="${INSTALL_DIR}/${APP_NAME}.app"
BIN_PATH="${APP_PATH}/Contents/MacOS/${APP_NAME}"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/${BUNDLE_ID}.plist"
MIN_MACOS_MAJOR=14

# --- Pretty output ----------------------------------------------------------
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"; RESET="$(printf '\033[0m')"
  BLUE="$(printf '\033[34m')"; GREEN="$(printf '\033[32m')"; YELLOW="$(printf '\033[33m')"; RED="$(printf '\033[31m')"
else
  BOLD=""; DIM=""; RESET=""; BLUE=""; GREEN=""; YELLOW=""; RED=""
fi
info()  { printf '%s==>%s %s\n' "${BLUE}${BOLD}" "${RESET}" "$*"; }
ok()    { printf '%s  ✓%s %s\n' "${GREEN}" "${RESET}" "$*"; }
warn()  { printf '%s  !%s %s\n' "${YELLOW}" "${RESET}" "$*"; }
die()   { printf '%s  ✗ %s%s\n' "${RED}${BOLD}" "$*" "${RESET}" >&2; exit 1; }

# Prompt helper that works even when the script is piped from curl (stdin is the
# script, not the keyboard) by reading straight from the controlling terminal.
# Non-interactive runs (no tty) fall back to the supplied default.
ask_yes_no() {
  local prompt="$1" default="${2:-n}" reply
  if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
    reply="$default"
  else
    local hint="[y/N]"; [ "$default" = "y" ] && hint="[Y/n]"
    printf '%s%s %s%s ' "${BOLD}" "$prompt" "${hint}" "${RESET}" > /dev/tty
    read -r reply < /dev/tty || reply="$default"
    [ -z "$reply" ] && reply="$default"
  fi
  case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

# --- Preflight --------------------------------------------------------------
printf '\n%s%s Lidless installer %s\n\n' "${BOLD}${BLUE}" "🔒" "${RESET}"

[ "$(uname -s)" = "Darwin" ] || die "Lidless is macOS only (this is $(uname -s))."

macos_ver="$(sw_vers -productVersion)"
macos_major="${macos_ver%%.*}"
if [ "$macos_major" -lt "$MIN_MACOS_MAJOR" ]; then
  die "Requires macOS ${MIN_MACOS_MAJOR}+ (Sonoma). You're on ${macos_ver}."
fi
ok "macOS ${macos_ver}"

command -v git >/dev/null 2>&1 || die "git not found. Install the Xcode Command Line Tools: xcode-select --install"

if ! command -v swift >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
  warn "Swift toolchain not found."
  info "Installing the Xcode Command Line Tools (a system dialog will appear)…"
  xcode-select --install 2>/dev/null || true
  die "Re-run this installer once the Command Line Tools finish installing."
fi
ok "Swift $(swift --version 2>/dev/null | head -1 | sed 's/.*Swift version \([0-9.]*\).*/\1/' || echo present)"

# --- Fetch & build ----------------------------------------------------------
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/lidless.XXXXXX")"
info "Cloning ${REPO_SLUG}…"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORKDIR/src" >/dev/null 2>&1 \
  || die "Clone failed. Is ${REPO_URL} reachable?"
ok "Cloned"

info "Building ${APP_NAME}.app (release)…"
( cd "$WORKDIR/src" && ./build.sh ) >/dev/null 2>&1 \
  || die "Build failed. Try running ./build.sh in a clone to see the error."
BUILT_APP="$WORKDIR/src/dist/${APP_NAME}.app"
[ -d "$BUILT_APP" ] || die "Build did not produce ${BUILT_APP}."
ok "Built"

# --- Install ----------------------------------------------------------------
if [ -d "$APP_PATH" ]; then
  info "Replacing existing ${APP_PATH}…"
  # Stop a running copy so we can overwrite it cleanly.
  pkill -f "$BIN_PATH" 2>/dev/null || true
  rm -rf "$APP_PATH"
fi
info "Installing to ${APP_PATH}…"
if ! cp -R "$BUILT_APP" "$APP_PATH" 2>/dev/null; then
  warn "Couldn't write to ${INSTALL_DIR} directly — retrying with sudo."
  sudo cp -R "$BUILT_APP" "$APP_PATH" || die "Install failed."
fi
ok "Installed ${APP_NAME}.app"

# --- Launch at login --------------------------------------------------------
install_launch_agent() {
  mkdir -p "$(dirname "$LAUNCH_AGENT")"
  cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>${BUNDLE_ID}</string>
    <key>ProgramArguments</key> <array><string>${BIN_PATH}</string></array>
    <key>RunAtLoad</key>        <true/>
    <key>ProcessType</key>      <string>Interactive</string>
</dict>
</plist>
PLIST
  # Reload so it's active immediately and on every login.
  launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
  launchctl load -w "$LAUNCH_AGENT" 2>/dev/null || true
}

printf '\n'
if ask_yes_no "Start Lidless automatically at login?" "y"; then
  install_launch_agent
  ok "Lidless will start at login. (It launched just now, too.)"
  STARTED=1
else
  [ -f "$LAUNCH_AGENT" ] && { launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true; rm -f "$LAUNCH_AGENT"; }
  info "Skipped login-at-startup. Enable it later by re-running this installer."
fi

# --- Launch now -------------------------------------------------------------
if [ -z "${STARTED:-}" ]; then
  if ask_yes_no "Launch Lidless now?" "y"; then
    open "$APP_PATH"
    STARTED=1
  fi
fi

# --- Done -------------------------------------------------------------------
printf '\n%s%s Done!%s Lidless lives in your menu bar — look for the %slaptop icon%s.\n' \
  "${GREEN}${BOLD}" "🎉" "${RESET}" "${BOLD}" "${RESET}"
printf '   Click it and toggle %s“Stay awake on lid close.”%s\n' "${DIM}" "${RESET}"
printf '   The first toggle asks for your password once, to install a passwordless helper.\n\n'
