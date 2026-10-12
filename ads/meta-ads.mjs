#!/usr/bin/env node
// Meta (Facebook / Instagram) ads for Pulsar Kids, described in campaigns.json.
// Everything is created PAUSED — only `launch` starts spending money.

import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { basename, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const DIR = dirname(fileURLToPath(import.meta.url))
const ENV_FILE = resolve(DIR, '.env')
const STATE_FILE = resolve(DIR, 'state.json')
if (existsSync(ENV_FILE)) process.loadEnvFile(ENV_FILE)

const TOKEN = process.env.META_ACCESS_TOKEN
const PAGE = process.env.META_PAGE_ID
const ACCOUNT = `act_${(process.env.META_AD_ACCOUNT_ID ?? '').replace(/^act_/, '')}`
const API = `https://graph.facebook.com/${process.env.META_API_VERSION ?? 'v26.0'}`

const USAGE = `Usage: node meta-ads.mjs <command>

  check                 token, ad account and page are reachable
  search <words>        targeting criteria (interests, parents of …) to paste into campaigns.json
  locales <words>       language ids for "locales"
  plan [campaign]       print what "create" would send, without calling Meta
  create [campaign]     create campaigns from campaigns.json, all PAUSED
  launch <campaign>     switch a created campaign on — money is spent from here
  pause <campaign>      switch it off
  stats                 status and results of every created campaign`

let dryRun = false

function requireEnv() {
  const missing = ['META_ACCESS_TOKEN', 'META_AD_ACCOUNT_ID', 'META_PAGE_ID'].filter((k) => !process.env[k])
  if (missing.length) throw new Error(`Missing in ${ENV_FILE}: ${missing.join(', ')} (see .env.example)`)
}

async function api(method, path, params = {}) {
  const body = new URLSearchParams()
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined) body.set(key, typeof value === 'object' ? JSON.stringify(value) : String(value))
  }
  if (dryRun && method !== 'GET') {
    console.log(`\n${method} ${path}\n${JSON.stringify(params, null, 2)}`)
    return { id: `<${path.split('/').pop()}>` }
  }
  const url = `${API}/${path}`
  const headers = { Authorization: `Bearer ${TOKEN}` }
  const res = method === 'GET' ? await fetch(`${url}?${body}`, { headers }) : await fetch(url, { method, headers, body })
  return unwrap(path, await res.json())
}

function unwrap(path, json) {
  if (!json.error) return json
  const { message, error_user_title, error_user_msg } = json.error
  throw new Error(`${path}: ${[error_user_title, error_user_msg ?? message].filter(Boolean).join(' — ')}`)
}

async function uploadImage(file) {
  if (dryRun) return `<hash of ${basename(file)}>`
  const form = new FormData()
  form.set('filename', new Blob([readFileSync(file)]), basename(file))
  const res = await fetch(`${API}/${ACCOUNT}/adimages`, { method: 'POST', headers: { Authorization: `Bearer ${TOKEN}` }, body: form })
  const { images } = unwrap('adimages', await res.json())
  return Object.values(images)[0].hash
}

const readJson = (file, fallback) => (existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : fallback)
const state = readJson(STATE_FILE, {})
const saveState = () => dryRun || writeFileSync(STATE_FILE, `${JSON.stringify(state, null, 2)}\n`)

// Runs `make` only when `bag[key]` is empty, so a `create` that failed halfway can simply be run again.
async function once(bag, key, make) {
  if (!bag[key]) {
    bag[key] = await make()
    saveState()
  }
  return bag[key]
}

function campaigns(only) {
  const config = readJson(resolve(DIR, 'campaigns.json'))
  const list = config.campaigns.map((c) => ({ ...config.defaults, ...c }))
  if (!only) return list
  const found = list.filter((c) => c.name === only)
  if (!found.length) throw new Error(`No campaign "${only}" in campaigns.json`)
  return found
}

// Criteria of one audience are alternatives: a person matching any of them is in.
function targeting(audience) {
  const byType = {}
  for (const { id, name, type } of audience.criteria ?? []) (byType[type] ??= []).push({ id, name })
  return {
    geo_locations: { countries: audience.countries },
    age_min: audience.ageMin,
    age_max: audience.ageMax,
    genders: audience.genders?.length ? audience.genders : undefined,
    locales: audience.locales?.length ? audience.locales : undefined,
    flexible_spec: Object.keys(byType).length ? [byType] : undefined,
    publisher_platforms: audience.platforms?.length ? audience.platforms : undefined,
    // 0 keeps Meta inside the criteria above instead of widening the audience on its own.
    targeting_automation: { advantage_audience: 0 },
  }
}

async function create(only) {
  for (const c of campaigns(only)) {
    const made = dryRun ? {} : (state[c.name] ??= {})
    made.adsets ??= {}
    made.creatives ??= {}
    made.ads ??= {}

    const campaignId = await once(made, 'campaign', async () =>
      (await api('POST', `${ACCOUNT}/campaigns`, {
        name: c.name,
        objective: c.objective,
        status: 'PAUSED',
        special_ad_categories: [],
        // The account's currency in minor units; the budget is shared by the campaign's audiences.
        daily_budget: Math.round(c.dailyBudget * 100),
        bid_strategy: 'LOWEST_COST_WITHOUT_CAP',
      })).id)

    const imageHash = /^https?:/.test(c.image) ? undefined : await once(made, 'image', () => uploadImage(resolve(DIR, c.image)))

    for (const ad of c.ads) {
      await once(made.creatives, ad.name, async () =>
        (await api('POST', `${ACCOUNT}/adcreatives`, {
          name: `${c.name} / ${ad.name}`,
          object_story_spec: {
            page_id: PAGE,
            link_data: {
              link: c.link,
              message: ad.message,
              name: ad.headline,
              description: ad.description,
              image_hash: imageHash,
              picture: imageHash ? undefined : c.image,
              call_to_action: { type: c.cta, value: { link: c.link } },
            },
          },
          url_tags: `utm_source=facebook&utm_medium=paid&utm_campaign=${c.name}&utm_content=${ad.name}`,
        })).id)
    }

    for (const audience of c.audiences) {
      const adsetId = await once(made.adsets, audience.name, async () =>
        (await api('POST', `${ACCOUNT}/adsets`, {
          name: `${c.name} / ${audience.name}`,
          campaign_id: campaignId,
          status: 'PAUSED',
          billing_event: 'IMPRESSIONS',
          optimization_goal: c.optimizationGoal,
          destination_type: 'WEBSITE',
          promoted_object: c.pixelId ? { pixel_id: c.pixelId, custom_event_type: c.pixelEvent } : undefined,
          targeting: targeting(audience),
        })).id)

      for (const ad of c.ads) {
        await once(made.ads, `${audience.name} / ${ad.name}`, async () =>
          (await api('POST', `${ACCOUNT}/ads`, {
            name: `${audience.name} / ${ad.name}`,
            adset_id: adsetId,
            creative: { creative_id: made.creatives[ad.name] },
            status: 'PAUSED',
          })).id)
      }
    }
    if (!dryRun) console.log(`${c.name}: created, PAUSED — campaign ${campaignId}. Review it in Ads Manager, then: node meta-ads.mjs launch ${c.name}`)
  }
}

function created(name) {
  if (!state[name]?.campaign) throw new Error(`"${name}" is not created yet — run: node meta-ads.mjs create ${name ?? ''}`)
  return state[name]
}

async function launch(name) {
  const made = created(name)
  for (const id of [...Object.values(made.ads), ...Object.values(made.adsets), made.campaign]) {
    await api('POST', id, { status: 'ACTIVE' })
  }
  console.log(`${name}: ACTIVE`)
}

async function pause(name) {
  await api('POST', created(name).campaign, { status: 'PAUSED' })
  console.log(`${name}: PAUSED`)
}

async function stats() {
  for (const [name, made] of Object.entries(state)) {
    if (!made.campaign) continue
    const { effective_status } = await api('GET', made.campaign, { fields: 'effective_status' })
    const { data } = await api('GET', `${made.campaign}/insights`, {
      fields: 'impressions,reach,clicks,ctr,cpc,spend',
      date_preset: 'maximum',
    })
    console.log(name, effective_status, data[0] ?? 'no results yet')
  }
}

async function check() {
  const me = await api('GET', 'me', { fields: 'name' })
  const account = await api('GET', ACCOUNT, { fields: 'name,currency,timezone_name,account_status,min_daily_budget' })
  const page = await api('GET', PAGE, { fields: 'name' })
  console.log(`token:   ${me.name}`)
  console.log(`account: ${account.name} — ${account.currency}, ${account.timezone_name}, status ${account.account_status} (1 = active)`)
  console.log(`         smallest daily budget: ${account.min_daily_budget / 100} ${account.currency}`)
  console.log(`page:    ${page.name}`)
}

async function search(query) {
  const { data } = await api('GET', `${ACCOUNT}/targetingsearch`, { q: query, limit: 25 })
  for (const { id, name, type, path, audience_size_lower_bound: from, audience_size_upper_bound: to } of data) {
    console.log(`${JSON.stringify({ id, name, type })},   // ${(path ?? []).join(' > ')} · ${from}–${to} people`)
  }
}

async function locales(query) {
  const { data } = await api('GET', 'search', { type: 'adlocale', q: query })
  for (const { key, name } of data) console.log(`${key}   // ${name}`)
}

const [command, ...args] = process.argv.slice(2)
const arg = args.join(' ') || undefined
const commands = { check, search, locales, create, launch, pause, stats, plan: create }

try {
  if (!commands[command]) {
    console.log(USAGE)
    process.exit(command ? 1 : 0)
  }
  if ((command === 'search' || command === 'locales' || command === 'launch' || command === 'pause') && !arg) {
    throw new Error(`"${command}" needs an argument.\n\n${USAGE}`)
  }
  dryRun = command === 'plan'
  if (!dryRun) requireEnv()
  await commands[command](arg)
} catch (error) {
  console.error(error.message)
  process.exit(1)
}
