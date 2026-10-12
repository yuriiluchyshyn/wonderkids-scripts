// Records a walk through the real app (hub → a game → the child's planet → the solar system)
// as 30 fps frames.  usage: node record.mjs <frames dir>
import { mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { openApp, sleep } from './browser.mjs'

const FPS = 30
const out = process.argv[2]
rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })

const app = await openApp()
const frames = []

// A finger mark drawn over the page — the only thing in the recording that is not the app.
const OVERLAY = `(() => {
  const style = document.createElement('style')
  style.textContent = \`
    .ad-finger { position: fixed; z-index: 99998; width: 58px; height: 58px; margin: -29px 0 0 -29px; border-radius: 50%;
      background: rgba(255, 255, 255, 0.45); border: 3px solid #fff; pointer-events: none; animation: ad-finger 520ms ease-out forwards; }
    @keyframes ad-finger { from { transform: scale(0.5); opacity: 1; } to { transform: scale(1.5); opacity: 0; } }
  \`
  document.head.appendChild(style)
  window.__finger = (x, y) => {
    const mark = document.createElement('div')
    mark.className = 'ad-finger'
    mark.style.left = x + 'px'
    mark.style.top = y + 'px'
    document.body.appendChild(mark)
    setTimeout(() => mark.remove(), 600)
  }
})()`

// Captions are laid over the recording later (see stage.html): here only the moment each one begins.
const cues = []
const caption = (text) => cues.push({ text, at: Date.now() / 1000 })
const tap = async (point) => {
  await app.evaluate(`__finger(${point.x}, ${point.y})`)
  await sleep(140)
  await app.tap(point.x, point.y)
}
const find = async (selector, text) => {
  for (let i = 0; i < 25; i++) {
    const point = await app.locate(selector, text)
    if (point) return point
    await sleep(200)
  }
  throw new Error(`not on the page: ${selector} ${text ?? ''}`)
}
const tapOn = async (selector, text) => tap(await find(selector, text))

// Reads the sum off the board and taps the right answer.
async function solve() {
  const answer = await app.evaluate(`(() => {
    const parts = Array.from(document.querySelectorAll('[data-tip="board"] button[aria-label="Повторити завдання"] span[aria-hidden]')).map((s) => s.textContent.trim())
    return String(Number(parts[0]) + Number(parts[2]))
  })()`)
  const point = await app.evaluate(`(() => {
    const button = Array.from(document.querySelectorAll('[data-tip="board"] button[tabindex="0"]')).find((b) => b.textContent.trim() === ${JSON.stringify(answer)})
    if (!button) return null
    const r = button.getBoundingClientRect()
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
  })()`)
  if (!point) throw new Error(`no answer ${answer} on the board`)
  await tap(point)
}

try {
  await app.goto('/')
  await app.evaluate(OVERLAY)
  await sleep(600)

  app.on('Page.screencastFrame', ({ data, metadata, sessionId }) => {
    frames.push({ data, at: metadata.timestamp })
    app.send('Page.screencastFrameAck', { sessionId }).catch(() => {})
  })
  await app.send('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: 1080, maxHeight: 1920, everyNthFrame: 1 })

  // 1. the hub and its galaxies
  caption('Що всередині Pulsar Kids?')
  await sleep(1300)
  caption('Дев’ять галактик знань')
  await tapOn('[data-tip="galaxy"]')
  await sleep(1900)
  await tapOn('button[aria-label="Закрити"]')
  await sleep(450)

  // 2. a game: its path, then two tasks
  caption('Дитина обирає гру\nі йде своїм шляхом')
  await tapOn('button[aria-label="Відкрити шлях: Додавання"]')
  await sleep(1500)
  await tapOn('button', 'Грати')
  await sleep(1000)
  await tapOn('button', 'Почнемо')
  caption('Завдання без програшів\nі таймерів')
  await sleep(1500)
  await solve()
  await sleep(2100)
  await solve()
  await sleep(1500)

  // 3. the child's own planet: turn it, then build on it
  await tapOn('button[aria-label="Назад до пригод"]')
  await sleep(800)
  caption('За зірочки дитина\nбудує свою планету')
  await tapOn('button[aria-label^="Зірочка"]')
  await sleep(1300)
  const globe = { x: 270, y: 470 }
  await app.swipe(globe.x + 110, globe.y, globe.x - 110, globe.y + 10, 800)
  await sleep(300)
  await tapOn('button', 'Парк туманностей')
  await sleep(1200)
  await tapOn('button', '🔨')
  await sleep(1700)

  // 4. the whole solar system
  caption('І відкриває всю\nСонячну систему')
  await tapOn('button[aria-label="Показати всю Сонячну систему"]')
  await sleep(3000)

  await app.send('Page.stopScreencast')
} finally {
  app.close()
}

// Screencast frames come only when the picture changes: lay them on an even 30 fps grid.
const start = frames[0].at
writeFileSync(join(out, 'cues.json'), JSON.stringify(cues.map((c) => ({ text: c.text, at: Math.max(0, c.at - start) }))))
const length = frames.at(-1).at - start
let source = 0
const total = Math.ceil(length * FPS)
for (let i = 0; i < total; i++) {
  const t = start + i / FPS
  while (source + 1 < frames.length && frames[source + 1].at <= t) source++
  writeFileSync(join(out, `frame_${String(i).padStart(4, '0')}.jpg`), Buffer.from(frames[source].data, 'base64'))
}
console.log(`${frames.length} captured → ${total} frames (${length.toFixed(1)} s) in ${out}`)
