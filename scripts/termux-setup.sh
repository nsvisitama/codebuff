#!/data/data/com.termux/files/usr/bin/bash
# Sets up Termux (Android) to run Codebuff or Freebuff.
# Usage: bash termux-setup.sh [codebuff|freebuff]
set -euo pipefail

PACKAGE="${1:-freebuff}"
if [[ "$PACKAGE" != "codebuff" && "$PACKAGE" != "freebuff" ]]; then
  echo "Usage: $0 [codebuff|freebuff]" >&2
  exit 1
fi

echo "==> Switching to Cloudflare mirror (avoids termux.net being blocked/unreachable on some ISPs)"
mkdir -p "$PREFIX/etc/apt/sources.list.d"
rm -f "$PREFIX/etc/apt/sources.list.d/termux-main.list"
echo "deb https://packages-cf.termux.dev/apt/termux-main stable main" > "$PREFIX/etc/apt/sources.list"

echo "==> Updating Termux packages"
pkg update -y && pkg upgrade -y

echo "==> Installing Node.js and git"
pkg install -y nodejs-lts git

echo "==> Granting storage access (Termux will prompt for Android permission)"
termux-setup-storage || true

echo "==> Installing $PACKAGE"
npm install -g "$PACKAGE"

echo
echo "Setup complete. Run '$PACKAGE' inside any project directory to start."
