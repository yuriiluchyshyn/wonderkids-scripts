#!/usr/bin/env bash
#
# Launch the Pulsar Kids dev servers. The public SITE and the GAME are two
# projects in app/ (npm workspaces), each with a dev server of its own:
#
#   game  http://localhost:4321   the child's portal, the parents' cabinet, the
#                                 admin panel AND the API (app/game/api/* is
#                                 mounted by the dev-api.ts Vite plugin, so local
#                                 dev runs the same API code that is deployed)
#   site  http://localhost:4322   the public page (/, /en/, /pl/); its links and
#                                 its letter form find the game on port 4321
#
# Both bind to all network interfaces, so they open from a phone or tablet on
# the same Wi-Fi — the primary target devices for this project.
#
# Usage:
#   ./scripts/dev.sh              # the game (as before)
#   ./scripts/dev.sh 4500         # the game on another port
#   ./scripts/dev.sh site         # the site
#   ./scripts/dev.sh all          # both; Ctrl+C stops both
#
# The API uses DATABASE_URL / JWT_SECRET from app/game/.env.local (currently the
# production Neon database). Without DATABASE_URL it falls back to the local
# Docker Postgres (`docker compose up -d db`) — see app/game/.env.example.
#
set -euo pipefail

WHAT="game"
PORT=""
for arg in "$@"; do
  case "$arg" in
    game|site|all) WHAT="$arg" ;;
    *[!0-9]*|"")   echo "✋  Не розумію «${arg}». Приклад: ./scripts/dev.sh [game|site|all] [порт]"; exit 1 ;;
    *)             PORT="$arg" ;;
  esac
done

# Resolve directories relative to this script, so it works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../app" && pwd)"
cd "$APP_DIR"

if [ ! -d node_modules ]; then
  echo "📦  app: node_modules not found — installing dependencies..."
  npm install
fi

# Port is not strict, so Vite auto-increments it if busy.
run() { npm run dev -w "@pulsar/$1" -- ${2:+--port "$2"}; }

echo ""
case "$WHAT" in
  game)
    echo "🪐  Гра стартує: http://localhost:${PORT:-4321}"
    echo "    На телефоні/планшеті: відкрий 'Network' URL нижче (та сама Wi-Fi)"
    echo ""
    run game "$PORT"
    ;;
  site)
    echo "🌌  Сайт стартує: http://localhost:${PORT:-4322}  (/en/, /pl/ — інші мови)"
    echo "    Кнопки «Грати» і форма листа ведуть на гру на порту 4321 — запусти її окремо, якщо потрібна."
    echo ""
    run site "$PORT"
    ;;
  all)
    echo "🪐  Гра:  http://localhost:4321     🌌  Сайт: http://localhost:4322"
    echo ""
    run site "" &
    trap 'kill $(jobs -p) 2>/dev/null' EXIT
    run game ""
    ;;
esac
