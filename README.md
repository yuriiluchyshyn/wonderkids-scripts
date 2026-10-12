# Pulsar Kids (WonderKids) • scripts

Допоміжні скрипти для проєкту Pulsar Kids.

- **`dev.sh`** — запускає dev-сервери. Сайт і гра — два окремі проєкти в `app/` (npm workspaces), у кожного свій сервер; обидва доступні по локальній мережі (для телефона/планшета).
  ```bash
  ./dev.sh            # гра: http://localhost:4321 (фронтенд + API з app/game/api/* в одному процесі Vite)
  ./dev.sh 4500       # гра на іншому порту
  ./dev.sh site       # сайт: http://localhost:4322 (/, /en/, /pl/)
  ./dev.sh all        # обидва одразу
  ```

- **`autopush.sh`** — перевіряє репозиторії на зміни і, якщо є, автоматично комітить та пушить їх.
  ```bash
  ./autopush.sh                 # авто-повідомлення з датою/часом
  ./autopush.sh "fix: ..."      # власне повідомлення коміту
  ```
  Коміти створюються від імені приватного акаунта (через `git -c`, без зміни глобального конфіга).

- **`ads/meta-ads.mjs`** — реклама у Facebook / Instagram через Meta Marketing API. Кампанії, аудиторії й тексти описані в `ads/campaigns.json`, ключі — в `ads/.env` (зразок у `.env.example`).
  ```bash
  node ads/meta-ads.mjs check                      # токен, рекламний акаунт і сторінка доступні
  node ads/meta-ads.mjs search "батьки"            # критерії таргетингу для campaigns.json
  node ads/meta-ads.mjs plan                       # показати, що буде створено, без звернення до Meta
  node ads/meta-ads.mjs create                     # створити все на паузі
  node ads/meta-ads.mjs launch pulsar-parents-ua   # увімкнути — звідси списуються гроші
  node ads/meta-ads.mjs stats                      # статус і результати
  ```

- **`ads/creative/`** — вихідники рекламних картинок і відео трьома мовами (слова — у `texts.js`, мова — `?lang=en|pl`; `render.mjs` знімає сторінку headless-браузером, `encode.swift` збирає кадри в mp4); готові файли лежать поруч у `ads/`. Як усе влаштовано — `app/docs/marketing.md`.

- **`deploy.sh`** — деплой. Сайт (`app/site` → pulsarkids.com) і гра (`app/game` → play.* / parents.* + API) — два Vercel-проєкти з одного репозиторію `app/`, і кожен деплоїться окремо. Деплой — це коміт вибраної частини й пуш: Vercel збирає проєкт лише тоді, коли змінилась його тека або спільне (`app/packages`, залежності) — це `ignoreCommand` у його `vercel.json`. Зміни невибраної частини лишаються в робочій теці незакоміченими.
  ```bash
  ./deploy.sh                       # інтерактивно: показує, що змінилось, і питає, що пушити
  ./deploy.sh site                  # лише сайт
  ./deploy.sh game -m "feat: ..."   # лише гра, зі своїм повідомленням коміту
  ./deploy.sh all -y                # усе, без фінального запитання
  ./deploy.sh game --skip-checks    # без тестів і production-білда перед пушем
  ```
  Перед пушем скрипт проганяє тести й production-білд вибраного. Якщо змінилось спільне (`packages/`), воно їде з будь-яким вибором і перезбирає обидва проєкти — скрипт попередить і запропонує задеплоїти все разом (без термінала — потрібен `all` або `--allow-partial`).

## Одноразове налаштування Vercel після розділення

До розділення був один Vercel-проєкт (корінь репозиторію) на всі домени. Тепер їх два, з одного репозиторію `yuriiluchyshyn/wonderkids`. Порядок такий, щоб сайт не зник ні на хвилину:

1. **Новий проєкт для сайту** (Add New → Project → той самий репозиторій): Root Directory — `site`, Framework — Vite. Змінні оточення не потрібні. Увімкнути Web Analytics. Перший деплой дасть адресу `*.vercel.app` — перевірити на ній сторінку трьома мовами.
2. **Перенести домени сайту** зі старого проєкту в новий: `pulsarkids.com` (і `www`, якщо є) та `wonderkids.yluch.app`. У старому лишаються `play.` і `parents.` (та `play.` / `parents.wonderkids.yluch.app`).
3. **Старий проєкт стає проєктом гри**: Settings → Build and Deployment → Root Directory — `game`. Змінні оточення (база, JWT, Auth0, Resend…) лишаються як є.
4. Запушити розділений репозиторій: `./deploy.sh all`.

Кроки 1–2 можна зробити ще до пушу, якщо задеплоїти сайт із локальної теки: `cd app/site && vercel link && vercel deploy --prod`.

Після цього `/api` живе лише на порталах гри: перевірка здоров’я — `curl https://play.pulsarkids.com/api/health` (адреса `pulsarkids.com/api/...` більше не відповідає).
