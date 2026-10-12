// A headless Chromium showing the local app as a phone, with every /api call answered here
// (a made-up child profile) so nothing reaches a real server or database.
import { spawn } from 'node:child_process'
import { mkdtempSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'

const CHROMIUM = join(homedir(), 'Library/Caches/ms-playwright/chromium-1134/chrome-mac/Chromium.app/Contents/MacOS/Chromium')
export const ORIGIN = 'http://127.0.0.1:4399'
export const WIDTH = 540
export const HEIGHT = 960

const SEEN_TIPS = process.env.SEEN_TIPS.split(',')
// The language the game is recorded in (AD_LANG=en|pl; Ukrainian when not set) and the child it is recorded for.
export const LANG = process.env.AD_LANG ?? 'uk'
const CHILD = { uk: 'Соломія', en: 'Emma', pl: 'Zosia' }[LANG]

const owned = [
  ...['b0', 'b1', 'b2', 'b3', 'b4', 'b5', 'b6'].map((id) => `world:galaxy:${id}`),
  ...['d0', 'd1', 'd2', 'd3', 'd4', 'd5'].map((id) => `world:galaxy:${id}`),
  ...['k0', 'k1', 'k2', 'k3'].map((id) => `know:p1:${id}`),
  // first-run tips already seen
  ...SEEN_TIPS.map((id) => `tip:${id}`),
]

const STATE = {
  activeChildId: 'demo',
  children: [{
    id: 'demo',
    profile: { name: CHILD, nickname: 'solomiya', pin: '', email: '', password: '', birthYear: 2019, birthMonth: 5, gender: 'girl' },
    themeId: 'galaxy',
    artifacts: 2400,
    tasksCompleted: 640,
    progress: {
      'math:add': 3, 'math:sub': 11, 'math:mul': 6, 'geography:flags': 12, 'geography:continents': 7,
      'logic:patterns': 9, 'logic:shadows': 6,
    },
    treasures: owned,
    settings: { gameLang: LANG, voiceLang: LANG },
  }],
}

const SESSION = {
  child_profile_id: 'demo', remaining_time_seconds: 1500, session_remaining_seconds: 1500, daily_remaining_seconds: 5400,
  depleted: false, in_cooldown: false, cooldown_remaining_seconds: 0, server_time: Date.now(),
  screen_time: { dayKey: new Date().toISOString().slice(0, 10), minutesUsedToday: 5, sessionElapsedMs: 300000, lastSessionEndedAt: null },
}

function answer(url, method) {
  const path = new URL(url).pathname
  if (path === '/api/state') return method === 'GET' ? { state: STATE, features: { cloudTts: false } } : { ok: true, updatedAt: new Date().toISOString() }
  if (path.startsWith('/api/v1/session/')) return { ...SESSION, server_time: Date.now() }
  return {}
}

export async function openApp(port = 9348) {
  const browser = spawn(CHROMIUM, [
    '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), 'pulsar-app-'))}`,
    '--hide-scrollbars', '--mute-audio', `--window-size=${WIDTH},${HEIGHT + 200}`, 'about:blank',
  ], { stdio: 'ignore' })

  let target
  for (let i = 0; i < 50 && !target; i++) {
    await sleep(200)
    target = await fetch(`http://127.0.0.1:${port}/json/list`).then((r) => r.json()).then((l) => l.find((t) => t.type === 'page')).catch(() => undefined)
  }
  const socket = new WebSocket(target.webSocketDebuggerUrl)
  await new Promise((r) => socket.addEventListener('open', r))
  const waiting = new Map()
  const listeners = new Map()
  let lastId = 0
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++lastId
      waiting.set(id, (m) => (m.error ? reject(new Error(`${method}: ${m.error.message}`)) : resolve(m.result)))
      socket.send(JSON.stringify({ id, method, params }))
    })
  socket.addEventListener('message', ({ data }) => {
    const message = JSON.parse(data)
    if (message.id) {
      waiting.get(message.id)?.(message)
      waiting.delete(message.id)
    } else listeners.get(message.method)?.(message.params)
  })
  const on = (event, handler) => listeners.set(event, handler)

  await send('Page.enable')
  await send('Runtime.enable')
  await send('Emulation.setDeviceMetricsOverride', { width: WIDTH, height: HEIGHT, deviceScaleFactor: 2, mobile: true })
  await send('Emulation.setTouchEmulationEnabled', { enabled: true })
  await send('Page.addScriptToEvaluateOnNewDocument', {
    source: `localStorage.setItem('wonderkids-auth-v1', JSON.stringify({ state: { token: 'demo', user: { id: 1 }, childId: 'demo' }, version: 0 }))`,
  })
  await send('Fetch.enable', { patterns: [{ urlPattern: ORIGIN + '/api/*' }] })
  on('Fetch.requestPaused', ({ requestId, request }) => {
    send('Fetch.fulfillRequest', {
      requestId, responseCode: 200,
      responseHeaders: [{ name: 'Content-Type', value: 'application/json' }],
      body: Buffer.from(JSON.stringify(answer(request.url, request.method))).toString('base64'),
    }).catch(() => {})
  })

  const evaluate = async (expression) => {
    const { result, exceptionDetails } = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description ?? exceptionDetails.text)
    return result.value
  }
  const goto = async (path) => {
    await send('Page.navigate', { url: ORIGIN + path })
    await sleep(4500)
  }
  const touch = (type, x, y) => send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] })
  const tap = async (x, y) => {
    await touch('touchStart', x, y)
    await sleep(60)
    await touch('touchEnd', x, y)
  }
  // A finger sliding from one point to another over `ms`.
  const swipe = async (x1, y1, x2, y2, ms = 600) => {
    const steps = Math.max(2, Math.round(ms / 16))
    await touch('touchStart', x1, y1)
    for (let i = 1; i <= steps; i++) {
      await touch('touchMove', x1 + ((x2 - x1) * i) / steps, y1 + ((y2 - y1) * i) / steps)
      await sleep(16)
    }
    await touch('touchEnd', x2, y2)
  }
  const shot = async () => Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64')
  // Centre of the first element matching the selector (optionally with this text), in CSS pixels.
  const locate = (selector, text) =>
    evaluate(`(() => {
      const all = Array.from(document.querySelectorAll(${JSON.stringify(selector)}))
      const el = ${text ? `all.find((e) => e.textContent.includes(${JSON.stringify(text)}))` : 'all[0]'}
      if (!el) return null
      el.scrollIntoView({ block: 'center' })
      const r = el.getBoundingClientRect()
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
    })()`)

  return { send, on, evaluate, goto, tap, swipe, shot, locate, close: () => browser.kill() }
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
