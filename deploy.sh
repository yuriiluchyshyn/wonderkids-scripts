#!/usr/bin/env bash
#
# Deploy Pulsar Kids: the public SITE and the GAME are two Vercel projects fed
# from one repository (app/), and each is deployed on its own.
#
#   app/site/      → the site      (pulsarkids.com)
#   app/game/      → the game      (play.* and parents.*, with the API)
#   app/packages/  → what both share
#
# A deploy is a commit of the chosen part pushed to GitHub: each Vercel project
# builds only when its own folder — or something it shares — has changed (the
# `ignoreCommand` in its vercel.json), so pushing the site leaves the game as it
# is, and the other way round. Changes of the part you did not choose stay in
# the working tree, uncommitted.
#
# Usage:
#   ./scripts/deploy.sh                      # asks what to deploy
#   ./scripts/deploy.sh site                 # the site only
#   ./scripts/deploy.sh game -m "feat: ..."  # the game only, with a commit message
#   ./scripts/deploy.sh all -y               # both, without the final question
#
# Options:
#   -m, --message <text>   commit message (default: "chore: deploy <what> <time>")
#   -y, --yes              do not ask for confirmation
#       --skip-checks      push without running the tests and the production build
#       --allow-partial    push one part although the shared packages changed too
#   -h, --help             this text
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app"

# Commit identity (private account) applied per-command — never persisted,
# so your global git config stays untouched.
GIT_NAME="Yurii Luchyshyn"
# Private GitHub no-reply address — keeps your gmail out of the public commit
# history while still linking commits to the yuriiluchyshyn account.
GIT_EMAIL="8182389+yuriiluchyshyn@users.noreply.github.com"

# ---- the parts of the repository -------------------------------------------
# What a target is: its folder, its npm workspace, where it ends up.
target_path()      { case "$1" in site) echo "site" ;; game) echo "game" ;; esac; }
target_workspace() { case "$1" in site) echo "@pulsar/site" ;; game) echo "@pulsar/game" ;; esac; }
target_title()     { case "$1" in site) echo "Сайт" ;; game) echo "Гра" ;; esac; }
target_where()     { case "$1" in site) echo "pulsarkids.com" ;; game) echo "play.* і parents.* + API" ;; esac; }
TARGETS="site game"

# Shared by both: a change here rebuilds both projects.
SHARED_PATHS=(packages package.json package-lock.json)
# Everything else in the repository (docs, CLAUDE.md, …): rebuilds nothing, goes with any deploy.
OTHER_PATHS=(. ':(exclude)site' ':(exclude)game' ':(exclude)packages' ':(exclude)package.json' ':(exclude)package-lock.json')

changed() { git status --porcelain -- "$@" | wc -l | tr -d ' '; }

die()  { echo "❌  $*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'; }

# ---- arguments ---------------------------------------------------------------
CHOICE=""
MSG=""
ASSUME_YES=0
SKIP_CHECKS="${SKIP_CHECKS:-${SKIP_BUILD:-0}}"
ALLOW_PARTIAL=0

while [ $# -gt 0 ]; do
  case "$1" in
    site|game|all) [ -z "$CHOICE" ] || die "Ціль уже вказано: $CHOICE"; CHOICE="$1" ;;
    -m|--message)  [ $# -ge 2 ] || die "Після $1 потрібен текст повідомлення."; MSG="$2"; shift ;;
    -y|--yes)      ASSUME_YES=1 ;;
    --skip-checks) SKIP_CHECKS=1 ;;
    --allow-partial) ALLOW_PARTIAL=1 ;;
    -h|--help)     usage; exit 0 ;;
    *)             usage >&2; die "Не розумію «$1»." ;;
  esac
  shift
done

[ -d "$APP_DIR/.git" ] || die "Не знайдено git-репозиторій у $APP_DIR"
cd "$APP_DIR"

INTERACTIVE=0
if [ -t 0 ] && [ -t 1 ]; then INTERACTIVE=1; fi

N_SITE="$(changed site)"
N_GAME="$(changed game)"
target_count() { case "$1" in site) echo "$N_SITE" ;; game) echo "$N_GAME" ;; esac; }
N_SHARED="$(changed "${SHARED_PATHS[@]}")"
N_OTHER="$(changed "${OTHER_PATHS[@]}")"

if [ $((N_SITE + N_GAME + N_SHARED + N_OTHER)) -eq 0 ]; then
  echo "✓  Без змін у app/ — нічого деплоїти."
  exit 0
fi

# ---- what to deploy ----------------------------------------------------------
if [ -z "$CHOICE" ]; then
  [ "$INTERACTIVE" -eq 1 ] || die "Вкажи, що деплоїти: site, game або all (див. --help)."
  echo ""
  echo "Що змінилось у app/:"
  echo "    сайт      site/       $N_SITE файл(ів)"
  echo "    гра       game/       $N_GAME файл(ів)"
  echo "    спільне   packages/   $N_SHARED файл(ів)"
  echo "    решта     доки тощо   $N_OTHER файл(ів)"
  echo ""
  echo "Що деплоїмо?"
  echo "    1) Сайт   → $(target_where site)"
  echo "    2) Гру    → $(target_where game)"
  echo "    3) Усе"
  echo "    q) Нічого, вийти"
  while [ -z "$CHOICE" ]; do
    read -r -p "Вибір [1/2/3/q]: " answer
    case "$answer" in
      1|site) CHOICE="site" ;;
      2|game) CHOICE="game" ;;
      3|all)  CHOICE="all" ;;
      q|Q|"") echo "Гаразд, нічого не чіпаю."; exit 0 ;;
      *)      echo "    Введи 1, 2, 3 або q." ;;
    esac
  done
fi

if [ "$CHOICE" = "all" ]; then CHOSEN="$TARGETS"; else CHOSEN="$CHOICE"; fi

# The shared packages belong to both: pushing them with one part rebuilds the
# other project too — against code of its own that is not committed yet.
if [ "$CHOICE" != "all" ] && [ "$N_SHARED" -gt 0 ] && [ "$ALLOW_PARTIAL" -ne 1 ]; then
  for other in $TARGETS; do
    [ "$other" != "$CHOICE" ] || continue
    echo ""
    echo "⚠️   Змінилось і спільне (packages/ або залежності) — воно поїде разом із вибраним,"
    echo "    і Vercel перезбере також «$(target_title "$other")» — з того коду, що вже в репозиторії."
    if [ "$(changed "$(target_path "$other")")" -gt 0 ]; then
      echo "    А у «$(target_title "$other")» є незакомічені зміни, яких у тій збірці не буде."
    fi
    if [ "$INTERACTIVE" -eq 1 ] && [ "$ASSUME_YES" -ne 1 ]; then
      read -r -p "Деплоїти все разом? [Y — усе / o — лише вибране / q — вийти]: " answer
      case "$answer" in
        ""|y|Y) CHOICE="all"; CHOSEN="$TARGETS" ;;
        o|O)    ;;
        *)      echo "Гаразд, нічого не чіпаю."; exit 0 ;;
      esac
    else
      die "Запусти з «all», або додай --allow-partial, якщо так і задумано."
    fi
  done
fi

# What goes into the commit: everything except the part that was not chosen —
# so the chosen part, the shared packages and the rest of the repository.
COMMIT_PATHS=(.)
for target in $TARGETS; do
  case " $CHOSEN " in *" $target "*) ;; *) COMMIT_PATHS+=(":(exclude)$(target_path "$target")") ;; esac
done

if [ "$(changed "${COMMIT_PATHS[@]}")" -eq 0 ]; then
  echo "✓  У вибраному змін немає — нічого деплоїти."
  exit 0
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ -z "$MSG" ] && [ "$INTERACTIVE" -eq 1 ] && [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "Повідомлення коміту (Enter — стандартне): " MSG
fi
[ -n "$MSG" ] || MSG="chore: deploy $CHOICE $(date '+%Y-%m-%d %H:%M:%S')"

# ---- checks: a broken build must never reach Vercel -------------------------
if [ "$SKIP_CHECKS" != "1" ]; then
  [ -d node_modules ] || { echo "📦  Встановлюю залежності..."; npm install; }
  if [ "$N_SHARED" -gt 0 ]; then
    echo "🔎  Тести спільних пакетів..."
    npm test -w @pulsar/i18n -w @pulsar/platform
  fi
  for target in $CHOSEN; do
    echo "🔨  $(target_title "$target"): тести і production-білд..."
    npm test -w "$(target_workspace "$target")"
    npm run build -w "$(target_workspace "$target")"
  done
  echo "✅  Перевірки пройдено."
fi

# ---- the last look -----------------------------------------------------------
echo ""
echo "До пушу в «${BRANCH}»:"
git status --short -- "${COMMIT_PATHS[@]}" | sed -n '1,15p' | sed 's/^/    /'
TOTAL="$(changed "${COMMIT_PATHS[@]}")"
[ "$TOTAL" -le 15 ] || echo "    … і ще $((TOTAL - 15))"
echo "Повідомлення: $MSG"
if [ "$BRANCH" != "main" ]; then
  echo "ℹ️   Гілка не main — Vercel зробить preview-деплой, а не production."
fi
if [ "$INTERACTIVE" -eq 1 ] && [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "Комітити й пушити? [y/N]: " answer
  case "$answer" in y|Y) ;; *) echo "Гаразд, нічого не запушено."; exit 0 ;; esac
fi

# ---- commit & push -----------------------------------------------------------
git add -A -- "${COMMIT_PATHS[@]}"
git -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" commit -m "$MSG" -- "${COMMIT_PATHS[@]}"
git push

# Which projects Vercel rebuilds: those whose own folder went along, and both when the shared part did.
BUILDS=""
for target in $TARGETS; do
  own=0
  case " $CHOSEN " in *" $target "*) own="$(target_count "$target")" ;; esac
  if [ "$own" -gt 0 ] || [ "$N_SHARED" -gt 0 ]; then BUILDS="$BUILDS $target"; fi
done

echo ""
if [ -z "$BUILDS" ]; then
  echo "🚀  Запушено. Змінилось лише те, що не йде в збірку (доки тощо) — Vercel нічого не перезбирає."
  exit 0
fi
echo "🚀  Запушено. Vercel збере:"
for target in $BUILDS; do echo "    • $(target_title "$target") → $(target_where "$target")"; done
echo "    Статус: https://vercel.com/dashboard"
case " $BUILDS " in *" game "*) echo "    Після деплою гри:  curl https://play.pulsarkids.com/api/health" ;; esac
