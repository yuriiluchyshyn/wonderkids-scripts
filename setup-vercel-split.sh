#!/usr/bin/env bash
#
# One-time: turn the single Vercel project into two — the SITE and the GAME.
# Run the steps in this order; each is safe to run again.
#
#   ./scripts/setup-vercel-split.sh status    # read-only: what is where right now
#   ./scripts/setup-vercel-split.sh site      # 1. create the site's project and deploy the site
#                                             #    from this folder to its *.vercel.app address
#   ./scripts/setup-vercel-split.sh domains   # 2. move the root domain(s) to the site's project
#   ./scripts/setup-vercel-split.sh game      # 3. the old project builds from game/ from now on
#   then:  ./scripts/deploy.sh all            # 4. push the split repository
#
# Nothing here touches play.* / parents.*: they stay on the old project, which
# keeps serving its current deployment until step 4.
#
# Needs the Vercel CLI, logged in (`vercel whoami`).
#
set -euo pipefail

GAME_PROJECT="wonderkids"
SITE_PROJECT="pulsarkids-site"
REPO="yuriiluchyshyn/wonderkids"
# The site's hosts, in the order they are moved. `www` only forwards to the root domain.
SITE_DOMAINS=(pulsarkids.com www.pulsarkids.com wonderkids.yluch.app)
WWW_REDIRECTS_TO="pulsarkids.com"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../app" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

api()   { vercel api "$@" </dev/null 2>/dev/null; }
field() { python3 -c "import sys,json; d=json.load(sys.stdin); print(d$1)" 2>/dev/null || true; }
# Sends a JSON body with the given method: `send POST /v11/projects '{"name":"x"}'`.
send() {
  printf '%s' "$3" > "$TMP/body.json"
  vercel api "$2" -X "$1" --input "$TMP/body.json" </dev/null >/dev/null
}

domains_of() { api "/v9/projects/$1/domains" | python3 -c "import sys,json; [print('     ', x['name'], '→ ' + x['redirect'] if x.get('redirect') else '') for x in json.load(sys.stdin).get('domains', [])]" 2>/dev/null || echo "      (проєкту немає)"; }
root_of()    { api "/v9/projects/$1" | field "['rootDirectory']"; }

status() {
  for project in "$GAME_PROJECT" "$SITE_PROJECT"; do
    echo "• $project   (Root Directory: $(root_of "$project"))"
    domains_of "$project"
  done
}

step_site() {
  if [ -z "$(api "/v9/projects/$SITE_PROJECT" | field "['id']")" ]; then
    echo "→  Створюю проєкт $SITE_PROJECT (Root Directory: site, репозиторій $REPO)…"
    send POST /v11/projects '{"name":"'"$SITE_PROJECT"'","framework":"vite","rootDirectory":"site","gitRepository":{"type":"github","repo":"'"$REPO"'"}}'
  else
    echo "✓  Проєкт $SITE_PROJECT уже є."
  fi
  echo "→  Деплою сайт із локальної теки в $SITE_PROJECT (домени ще не чіпаю)…"
  cd "$APP_DIR"
  # The link lives in app/.vercel (gitignored); the project's Root Directory picks site/ out of the upload.
  vercel link --yes --project "$SITE_PROJECT" </dev/null
  vercel deploy --prod --yes </dev/null
  URL="https://$SITE_PROJECT.vercel.app"
  rm -rf "$APP_DIR/.vercel"
  echo "✅  Сайт зібрано: $URL"
  for path in / /en/ /pl/ /robots.txt /sitemap.xml /favicon.svg; do
    printf "    %-14s %s\n" "$path" "$(curl -s -o /dev/null -w '%{http_code}' "$URL$path")"
  done
  echo "    Відкрий адресу й глянь сторінку. Якщо все гаразд — крок 2: $0 domains"
  echo "    (Web Analytics для нового проєкту вмикається в панелі Vercel → $SITE_PROJECT → Analytics.)"
}

has_domain() { api "/v9/projects/$1/domains" | python3 -c "import sys,json; sys.exit(0 if any(x['name']==sys.argv[1] for x in json.load(sys.stdin).get('domains', [])) else 1)" "$2" 2>/dev/null; }

step_domains() {
  SITE_ID="$(api "/v9/projects/$SITE_PROJECT" | field "['id']")"
  [ -n "$SITE_ID" ] || { echo "❌  Спершу крок 1: $0 site"; exit 1; }
  for domain in "${SITE_DOMAINS[@]}"; do
    if has_domain "$SITE_PROJECT" "$domain"; then echo "✓  $domain уже в $SITE_PROJECT"; continue; fi
    echo "→  $domain: $GAME_PROJECT → $SITE_PROJECT"
    # One call moves the domain, so it is never without a project in between.
    if [ "$domain" = "www.$WWW_REDIRECTS_TO" ]; then
      send POST "/v1/projects/$GAME_PROJECT/domains/$domain/move" '{"projectId":"'"$SITE_ID"'","redirect":"'"$WWW_REDIRECTS_TO"'"}'
    else
      send POST "/v1/projects/$GAME_PROJECT/domains/$domain/move" '{"projectId":"'"$SITE_ID"'"}'
    fi
  done
  echo "✅  Домени перенесено:"
  status
  echo "    Перевір: curl -sI https://pulsarkids.com/ | head -1    Далі — крок 3: $0 game"
}

step_game() {
  echo "→  $GAME_PROJECT: Root Directory → game (діє з наступної збірки; поточний деплой лишається)"
  send PATCH "/v9/projects/$GAME_PROJECT" '{"rootDirectory":"game"}'
  status
  echo "✅  Лишився крок 4: ./scripts/deploy.sh all"
}

vercel whoami </dev/null >/dev/null 2>&1 || { echo "✋  Спершу: vercel login"; exit 1; }

case "${1:-}" in
  status)  status ;;
  site)    step_site ;;
  domains) step_domains ;;
  game)    step_game ;;
  *)       sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 1 ;;
esac
