#!/bin/bash
# Standalone fallback: install the passwordless sudoers rule the app uses.
# The app installs this itself on first toggle; run this only if you prefer
# to do it manually. Usage:  sudo ./install-sudoers.sh   (or run without sudo
# and it will re-invoke itself with sudo).
set -euo pipefail

DEST="/etc/sudoers.d/lidless"
USER_NAME="${SUDO_USER:-$(whoami)}"
RULE="$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"

if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

TMP="$(mktemp)"
printf '%s\n' "$RULE" > "$TMP"

# Validate before installing — never leave a broken sudoers file.
/usr/sbin/visudo -cf "$TMP"
/usr/bin/install -m 0440 -o root -g wheel "$TMP" "$DEST"
rm -f "$TMP"

echo "Installed $DEST for user '$USER_NAME'."
echo "Test (should print nothing and not prompt):"
echo "  sudo -n /usr/bin/pmset -a disablesleep 0 && echo OK"
