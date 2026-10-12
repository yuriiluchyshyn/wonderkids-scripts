#!/usr/bin/env bash
#
# Launch Pulsar Kids on this machine. The public SITE, the GAME and the API are
# three projects in app/, each with a server of its own:
#
#   game  http://localhost:4321   the child's portal, the parents' cabinet and the
#                                 admin panel (Vite); its /api is passed on to ↓
#   api   http://localhost:4323   the backend — app/backend, Java (Spring Boot)
#   site  http://localhost:4322   the public page (/, /en/, /pl/); its links and
#                                 its letter form find the game on port 4321
#
# The game and the site bind to all network interfaces, so they open from a
# phone or tablet on the same Wi-Fi — the primary target devices for this project.
#
# Usage:
#   ./scripts/dev.sh              # the game + the API behind it
#   ./scripts/dev.sh 4500         # the same, the game on another port
#   ./scripts/dev.sh site         # the site
#   ./scripts/dev.sh api          # the API alone (rebuilt first)
#   ./scripts/dev.sh all          # all three; Ctrl+C stops them
#
# The API reads DATABASE_URL / JWT_SECRET / … from app/backend/.env.local or,
# as before, app/game/.env.local (currently the production Neon database).
# Without DATABASE_URL it falls back to the local Docker Postgres
# (`docker compose up -d db`) — see app/game/.env.example.
#
# No Java on this machine? Run the game against the deployed API instead:
#   VITE_API_TARGET=https://api.pulsarkids.com ./scripts/dev.sh
#
set -euo pipefail

WHAT="game"
PORT=""
for arg in "$@"; do
  case "$arg" in
    game|site|api|all) WHAT="$arg" ;;
    *[!0-9]*|"")       echo "✋  Не розумію «${arg}». Приклад: ./scripts/dev.sh [game|site|api|all] [порт]"; exit 1 ;;
    *)                 PORT="$arg" ;;
  esac
done

# Resolve directories relative to this script, so it works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../app" && pwd)"
BACKEND_DIR="$APP_DIR/backend"
API_PORT=4323
cd "$APP_DIR"

if [ "$WHAT" != "api" ] && [ ! -d node_modules ]; then
  echo "📦  app: node_modules not found — installing dependencies..."
  npm install
fi

# Port is not strict, so Vite auto-increments it if busy.
run() { npm run dev -w "@pulsar/$1" -- ${2:+--port "$2"}; }

# Build the backend's jar (only when its sources are newer than the jar).
build_api() {
  command -v mvn >/dev/null 2>&1 || { echo "✋  Для API потрібні Java 21+ і Maven (brew install openjdk@21 maven) — або VITE_API_TARGET=https://api.pulsarkids.com."; exit 1; }
  local jar="$BACKEND_DIR/target/pulsar-api.jar"
  if [ ! -f "$jar" ] || [ -n "$(find "$BACKEND_DIR/src" "$BACKEND_DIR/pom.xml" -newer "$jar" -print -quit)" ]; then
    echo "☕  Збираю API (app/backend)…"
    (cd "$BACKEND_DIR" && mvn -q -DskipTests package)
  fi
}

# The API in the foreground; its working folder is app/backend, where it finds `.env.local` (its own or ../game's).
serve_api() { (cd "$BACKEND_DIR" && PORT="$API_PORT" exec java -jar target/pulsar-api.jar); }

# The API behind the game — unless the game was told to ask another one.
api_in_background() {
  if [ -n "${VITE_API_TARGET:-}" ]; then
    echo "🔌  API: $VITE_API_TARGET (VITE_API_TARGET) — локальний бекенд не запускаю."
    return
  fi
  build_api
  serve_api &
  echo "☕  API стартує: http://localhost:$API_PORT/api/health"
}

trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

echo ""
case "$WHAT" in
  game)
    api_in_background
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
  api)
    build_api
    echo "☕  API стартує: http://localhost:$API_PORT/api/health"
    echo ""
    serve_api
    ;;
  all)
    api_in_background
    echo "🪐  Гра:  http://localhost:4321     🌌  Сайт: http://localhost:4322"
    echo ""
    run site "" &
    run game ""
    ;;
esac
