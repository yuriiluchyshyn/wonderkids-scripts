// Records short cuts of several games for the «play» video: each game is opened at a step,
// its board is shown and the right answer tapped (twice when there is time).
// usage: AD_LANG=en node cuts.mjs <out dir> [module:sub:step ...]   → <out>/<n>/frame_0000.jpg…, <out>/cuts.json
import { mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { LANG, openApp, sleep } from './browser.mjs'

const FPS = 30
const START = { uk: 'Почнемо', en: 'Let’s start', pl: 'Zaczynamy' }[LANG]
const [out, ...asked] = process.argv.slice(2)
const GAMES = asked.length ? asked : ['math:add:3', 'geography:flags:2', 'logic:patterns:3', 'geography:capitals:2']
/** How long a cut is recorded for; the video takes its first seconds. */
const CUT_MS = Number(process.env.CUT_MS ?? 3400)

rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
const app = await openApp()

const FINGER = `(() => {
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

// The board's own task, read from the component that draws it: where the right answer of a tap-the-answer board is.
const RIGHT_ANSWER = `(() => {
  const board = document.querySelector('[data-tip="board"]')
  if (!board) return null
  const grid = Array.from(board.querySelectorAll('div')).find((d) => d.children.length >= 2 && Array.from(d.children).every((c) => c.tagName === 'BUTTON'))
  if (!grid) return null
  let fiber = grid[Object.keys(grid).find((k) => k.startsWith('__reactFiber'))]
  while (fiber && !(fiber.memoizedProps && fiber.memoizedProps.payload && fiber.memoizedProps.payload.correctId)) fiber = fiber.return
  if (!fiber) return null
  const { options, correctId } = fiber.memoizedProps.payload
  const button = grid.children[options.findIndex((o) => o.id === correctId)]
  if (!button || button.disabled) return null
  const r = button.getBoundingClientRect()
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
})()`

const tap = async (point) => {
  await app.evaluate(`__finger(${point.x}, ${point.y})`)
  await sleep(140)
  await app.tap(point.x, point.y)
}

let frames = []
app.on('Page.screencastFrame', ({ data, metadata, sessionId }) => {
  frames.push({ data, at: metadata.timestamp })
  app.send('Page.screencastFrameAck', { sessionId }).catch(() => {})
})

const cuts = []
try {
  for (const [n, game] of GAMES.entries()) {
    const [module, sub, step] = game.split(':')
    await app.goto(`/play/${module}/${sub}?step=${step}`)
    await app.evaluate(FINGER)
    const start = await app.locate('button', START)
    if (start) await app.tap(start.x, start.y)
    await sleep(1300)

    frames = []
    await app.send('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: 1080, maxHeight: 1920, everyNthFrame: 1 })
    const began = Date.now()
    await sleep(750)
    let solved = 0
    while (Date.now() - began < CUT_MS - 900) {
      const point = await app.evaluate(RIGHT_ANSWER)
      if (!point) { await sleep(200); continue }
      await tap(point)
      solved++
      await sleep(1500)
    }
    await sleep(Math.max(0, CUT_MS - (Date.now() - began)))
    await app.send('Page.stopScreencast')

    const dir = join(out, String(n))
    mkdirSync(dir)
    const first = frames[0].at
    const total = Math.ceil((frames.at(-1).at - first) * FPS)
    let source = 0
    for (let i = 0; i < total; i++) {
      const t = first + i / FPS
      while (source + 1 < frames.length && frames[source + 1].at <= t) source++
      writeFileSync(join(dir, `frame_${String(i).padStart(4, '0')}.jpg`), Buffer.from(frames[source].data, 'base64'))
    }
    cuts.push({ game, count: total, solved })
    console.log(`${game}: ${total} frames, ${solved} answers`)
  }
} finally {
  app.close()
}
writeFileSync(join(out, 'cuts.json'), JSON.stringify(cuts))
