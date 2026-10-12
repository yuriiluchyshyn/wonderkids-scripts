#!/usr/bin/env bash
#
# One-time: give the API a Vercel project of its own. The API is app/backend —
# Java (Spring Boot), built by Vercel into a container image (Dockerfile.vercel)
# and served as ONE function, so the Hobby plan's «12 functions per deployment»
# no longer counts endpoints.
#
# Run the steps in this order; each is safe to run again. Until step 5 nothing
# changes for visitors: the game keeps serving its own /api.
#
#   ./scripts/setup-vercel-api.sh status   # read-only: what is where right now
#   ./scripts/setup-vercel-api.sh project  # 1. create the project (Root Directory: backend)
#   ./scripts/setup-vercel-api.sh env      # 2. copy the API's variables from the game's project
#   ./scripts/setup-vercel-api.sh deploy   # 3. build and deploy the API from this folder
#   ./scripts/setup-vercel-api.sh domain   # 4. api.pulsarkids.com → the new project
#   ./scripts/setup-vercel-api.sh check    #    the API answers, and knows the visitor's country
#   then:  ./scripts/deploy.sh all         # 5. push: the game and the site start asking the API
#
# Needs the Vercel CLI, logged in (`vercel whoami`).
#
set -euo pipefail

GAME_PROJECT="wonderkids"
API_PROJECT="pulsarkids-api"
REPO="yuriiluchyshyn/wonderkids"
API_DOMAIN="api.pulsarkids.com"
# Next to the database (Neon, us-east-1).
REGION="iad1"
# What the API reads (app/game/.env.example explains each). The VITE_AUTH0_* pair is
# public and is needed by BOTH projects: the game builds with it, the API checks tokens with it.
API_ENV=(DATABASE_URL JWT_SECRET JWT_EXPIRES_IN ADMIN_KEY SECRETS_KEY PGSSL PGSSL_INSECURE
         RESEND_API_KEY FEEDBACK_TO FEEDBACK_FROM VITE_AUTH0_DOMAIN VITE_AUTH0_CLIENT_ID GOOGLE_TTS_ENDPOINT)

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../app" && pwd)"
umask 077
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

api()   { vercel api "$@" </dev/null 2>/dev/null; }
field() { python3 -c "import sys,json; d=json.load(sys.stdin); print(d$1)" 2>/dev/null || true; }
# Sends a JSON body with the given method: `send POST /v11/projects '{"name":"x"}'`.
send() {
  printf '%s' "$3" > "$TMP/body.json"
  vercel api "$2" -X "$1" --input "$TMP/body.json" </dev/null >/dev/null
}

domains_of() { api "/v9/projects/$1/domains" | python3 -c "import sys,json; [print('     ', x['name']) for x in json.load(sys.stdin).get('domains', [])]" 2>/dev/null || echo "      (проєкту немає)"; }
root_of()    { api "/v9/projects/$1" | field "['rootDirectory']"; }
env_keys()   { api "/v9/projects/$1/env" | python3 -c "import sys,json; print(' '.join(sorted({e['key'] for e in json.load(sys.stdin).get('envs', []) if 'production' in e.get('target', [])})))" 2>/dev/null || true; }

status() {
  for project in "$GAME_PROJECT" "$API_PROJECT"; do
    echo "• $project   (Root Directory: $(root_of "$project"))"
    domains_of "$project"
    echo "      змінні (production): $(env_keys "$project")"
  done
}

step_project() {
  if [ -z "$(api "/v9/projects/$API_PROJECT" | field "['id']")" ]; then
    echo "→  Створюю проєкт $API_PROJECT (Root Directory: backend, репозиторій $REPO)…"
    send POST /v11/projects '{"name":"'"$API_PROJECT"'","rootDirectory":"backend","serverlessFunctionRegion":"'"$REGION"'","gitRepository":{"type":"github","repo":"'"$REPO"'"}}'
  else
    echo "✓  Проєкт $API_PROJECT уже є."
  fi
  status
  echo "✅  Далі — крок 2: $0 env"
}

# Prints one variable of a pulled .env file (KEY="value"), unquoted.
cat > "$TMP/pick.py" <<'PY'
import sys
path, key = sys.argv[1], sys.argv[2]
for line in open(path, encoding='utf-8'):
    name, sep, raw = line.rstrip('\n').partition('=')
    if sep and name == key:
        if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in ('"', "'"):
            raw = raw[1:-1].replace('\\n', '\n').replace('\\"', '"')
        sys.stdout.write(raw)
        break
PY

# Link a scratch folder to a project, so `vercel env` talks to that project and app/ stays unlinked.
linked() { mkdir -p "$TMP/$1" && (cd "$TMP/$1" && vercel link --yes --project "$1" </dev/null >/dev/null 2>&1) && echo "$TMP/$1"; }

# The value of a variable for the API: what the game's project gives out, or —
# for the ones Vercel keeps Sensitive and never shows again — the developer's
# own copy in app/game/.env.local. Never echoed.
value_of() {
  local value
  value="$(python3 "$TMP/pick.py" "$TMP/game.env" "$1")"
  if [ -z "$value" ] && [ -f "$APP_DIR/game/.env.local" ]; then value="$(python3 "$TMP/pick.py" "$APP_DIR/game/.env.local" "$1")"; fi
  printf '%s' "$value"
}

# Write one variable into the API's project (production), as Sensitive. The value comes on stdin.
put_env() { (cd "$TO" && vercel env add "$1" production --sensitive --force >/dev/null 2>&1) || { echo "    ⚠️  $1 не записано"; return 1; }; }

step_env() {
  [ -n "$(api "/v9/projects/$API_PROJECT" | field "['id']")" ] || { echo "❌  Спершу крок 1: $0 project"; exit 1; }
  echo "→  Читаю production-змінні проєкту $GAME_PROJECT (значення нікуди не друкуються)…"
  from="$(linked "$GAME_PROJECT")"
  (cd "$from" && vercel env pull "$TMP/game.env" --environment=production --yes </dev/null >/dev/null 2>&1) || touch "$TMP/game.env"
  TO="$(linked "$API_PROJECT")"
  game_keys=" $(env_keys "$GAME_PROJECT") "
  api_keys=" $(env_keys "$API_PROJECT") "
  missing=""
  for key in "${API_ENV[@]}"; do
    case "$key" in JWT_SECRET|SECRETS_KEY) continue ;; esac
    value="$(value_of "$key")"
    if [ -z "$value" ]; then
      case "$key" in DATABASE_URL|ADMIN_KEY) missing="$missing $key" ;; esac
      continue
    fi
    printf '%s' "$value" | put_env "$key" && echo "    ✓ $key"
  done

  # The secret that signs sessions. The game's project may have none at all —
  # then the old API signed with the development default, which is written in
  # the code for anyone to read, and any session could be forged. The API gets
  # a secret of its own, made here and shown to nobody; everybody signs in once
  # more. What the old key had encrypted (stored Google Speech keys) stays
  # readable, because SECRETS_KEY keeps the value it effectively had.
  case "$api_keys" in
    *" JWT_SECRET "*) echo "    ✓ JWT_SECRET уже є в $API_PROJECT — не чіпаю (інакше всі сесії знову злетять)" ;;
    *)
      case "$game_keys" in
        *" JWT_SECRET "*)
          value="$(value_of JWT_SECRET)"
          if [ -n "$value" ]; then printf '%s' "$value" | put_env JWT_SECRET && echo "    ✓ JWT_SECRET (той самий, що в грі)"; else missing="$missing JWT_SECRET"; fi
          ;;
        *)
          openssl rand -base64 48 | tr -d '\n' | put_env JWT_SECRET && echo "    ✓ JWT_SECRET — новий, випадковий (у грі його не було: сесії підписувались типовим ключем із коду)"
          case "$game_keys$api_keys" in *" SECRETS_KEY "*) ;; *) printf '%s' "dev-only-change-me" | put_env SECRETS_KEY && echo "    ✓ SECRETS_KEY — яким і був, щоб збережені ключі озвучки читались далі" ;; esac
          ;;
      esac
      ;;
  esac

  if [ -n "$missing" ]; then
    echo "⚠️   Немає значення для:$missing — Vercel не віддає Sensitive-змінні, а в app/game/.env.local їх теж немає."
    echo "    Додай їх у $API_PROJECT → Settings → Environment Variables руками."
  fi
  echo "✅  Змінні в $API_PROJECT: $(env_keys "$API_PROJECT")"
  echo "    Далі — крок 3: $0 deploy"
}

step_deploy() {
  echo "→  Збираю й деплою API з локальної теки в $API_PROJECT (образ збирає Vercel: Maven + Docker, кілька хвилин)…"
  cd "$APP_DIR"
  # The link lives in app/.vercel (gitignored); the project's Root Directory picks backend/ out of the upload.
  vercel link --yes --project "$API_PROJECT" </dev/null
  vercel deploy --prod --yes </dev/null
  rm -rf "$APP_DIR/.vercel"
  URL="https://$API_PROJECT.vercel.app"
  echo "✅  API задеплоєно: $URL"
  printf "    %-14s %s\n" "/api/health" "$(curl -s -m 60 -o /dev/null -w '%{http_code}' "$URL/api/health")"
  echo "    Далі — крок 4: $0 domain"
}

step_domain() {
  if api "/v9/projects/$API_PROJECT/domains" | grep -q "\"$API_DOMAIN\""; then
    echo "✓  $API_DOMAIN уже в $API_PROJECT"
  else
    echo "→  $API_DOMAIN → $API_PROJECT"
    send POST "/v10/projects/$API_PROJECT/domains" '{"name":"'"$API_DOMAIN"'"}'
  fi
  status
  echo "✅  Домен додано (сертифікат з'являється за хвилину-дві). Перевір: $0 check"
}

step_check() {
  for url in "https://$API_DOMAIN/api/health" "https://play.pulsarkids.com/api/health"; do
    body="$(curl -s -m 60 "$url" || true)"
    country="$(printf '%s' "$body" | field "['country']")"
    printf "    %-44s ok=%s country=%s\n" "$url" "$(printf '%s' "$body" | field "['ok']")" "${country:-—}"
  done
  echo "    «country» має бути кодом твоєї країни (UA, PL…) в ОБОХ рядках."
  echo "    Якщо через play.* там None — гра все одно ходить на $API_DOMAIN напряму; через play.* лишаються тільки старі вкладки."
  echo "    Перший запит після простою повільніший: Vercel будить контейнер (JVM стартує за секунду-дві)."
}

vercel whoami </dev/null >/dev/null 2>&1 || { echo "✋  Спершу: vercel login"; exit 1; }

case "${1:-}" in
  status)  status ;;
  project) step_project ;;
  env)     step_env ;;
  deploy)  step_deploy ;;
  domain)  step_domain ;;
  check)   step_check ;;
  *)       sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 1 ;;
esac
