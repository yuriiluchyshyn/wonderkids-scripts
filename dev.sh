#!/usr/bin/env bash
#
# Launch the ДивоСвіт / WonderKids dev server.
#
# Runs Vite on a non-default port (default 4321, overridable) and binds to all
# network interfaces (--host) so you can open the app from a phone or tablet on
# the same Wi-Fi — the primary target devices for this project.
#
# Usage:
#   ./scripts/dev.sh            # http://localhost:4321  (+ LAN URL)
#   ./scripts/dev.sh 4500       # custom port
#
set -euo pipefail

PORT="${1:-4321}"

# Resolve the app directory relative to this script, so it works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../app" && pwd)"

cd "$APP_DIR"

if [ ! -d node_modules ]; then
  echo "📦  node_modules not found — installing dependencies..."
  npm install
fi

echo ""
echo "🦄  ДивоСвіт стартує на порту $PORT"
echo "    Локально:  http://localhost:$PORT"
echo "    На телефоні/планшеті: відкрий 'Network' URL нижче (та сама Wi-Fi)"
echo ""

# --host exposes the server on the LAN; Vite then prints the Network URL to
# open on a mobile device. Port is not strict, so it auto-increments if busy.
exec npm run dev -- --port "$PORT" --host
