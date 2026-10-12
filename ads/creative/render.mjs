// Renders one of the pages here with a headless Chromium: a still picture, or the frames of a video.
// usage: node render.mjs <page.html[?query]> <width> <height> <out.png | frames dir> [duration ms]
import { spawn } from 'node:child_process'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const DIR = dirname(fileURLToPath(import.meta.url))
const CHROMIUM = join(homedir(), 'Library/Caches/ms-playwright/chromium-1134/chrome-mac/Chromium.app/Contents/MacOS/Chromium')
const PORT = 9360 + Math.floor(Math.random() * 30)
const FPS = 30
const [page, widthArg, heightArg, out, durationArg] = process.argv.slice(2)
const width = Number(widthArg), height = Number(heightArg)

const browser = spawn(CHROMIUM, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${mkdtempSync(join(tmpdir(), 'pulsar-render-'))}`,
  '--hide-scrollbars', '--allow-file-access-from-files', `--window-size=${width},${height}`, `file://${join(DIR, page)}`,
], { stdio: 'ignore' })

try {
  let target
  for (let i = 0; i < 50 && !target; i++) {
    await new Promise((r) => setTimeout(r, 200))
    target = await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json()).then((l) => l.find((t) => t.type === 'page')).catch(() => undefined)
  }
  const socket = new WebSocket(target.webSocketDebuggerUrl)
  await new Promise((r) => socket.addEventListener('open', r))
  const waiting = new Map()
  let lastId = 0
  socket.addEventListener('message', ({ data }) => {
    const message = JSON.parse(data)
    waiting.get(message.id)?.(message)
    waiting.delete(message.id)
  })
  const send = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++lastId
      waiting.set(id, (m) => (m.error ? reject(new Error(`${method}: ${m.error.message}`)) : resolve(m.result)))
      socket.send(JSON.stringify({ id, method, params }))
    })
  const shot = async (ms) => {
    const { exceptionDetails } = await send('Runtime.evaluate', { expression: `seek(${ms})`, awaitPromise: true })
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description ?? exceptionDetails.text)
    return Buffer.from((await send('Page.captureScreenshot', { format: 'png' })).data, 'base64')
  }

  await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false })
  await new Promise((r) => setTimeout(r, 900))
  if (!durationArg) {
    writeFileSync(out, await shot(0))
  } else {
    rmSync(out, { recursive: true, force: true })
    mkdirSync(out, { recursive: true })
    const count = Math.round((Number(durationArg) / 1000) * FPS)
    for (let i = 0; i < count; i++) writeFileSync(join(out, `frame_${String(i).padStart(4, '0')}.png`), await shot((i * 1000) / FPS))
    console.log(`${count} frames → ${out}`)
  }
} finally {
  browser.kill()
}
