// The stars and the planet shared by every ad picture (see space.css).

function random(seed) {
  return () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296
}

/** Fills the page with stars; `clear` are boxes (in %) the big stars keep out of, so text stays readable. */
window.sky = ({ dots = 140, sparks = 26, seed = 7, clear = [] } = {}) => {
  const next = random(seed)
  const inside = (x, y) => clear.some(([x0, y0, x1, y1]) => x > x0 && x < x1 && y > y0 && y < y1)
  let html = ''
  for (let i = 0; i < dots; i++) {
    const size = 2 + next() * 4
    html += `<i class="dot" style="left:${next() * 100}%;top:${next() * 100}%;width:${size}px;height:${size}px;opacity:${0.25 + next() * 0.6}"></i>`
  }
  for (let i = 0; i < sparks; i++) {
    const x = next() * 100, y = next() * 100, size = 0.022 + next() * 0.034, kind = next() < 0.6 ? '⭐' : '✨', delay = -next() * 2600
    if (inside(x, y)) continue
    html += `<i class="spark emoji" style="left:${x}%;top:${y}%;font-size:${size * Math.min(innerWidth, innerHeight) * 1.6}px;animation-delay:${delay}ms">${kind}</i>`
  }
  const sky = document.createElement('div')
  sky.className = 'sky'
  sky.innerHTML = html
  document.body.prepend(sky)
}

const LANDS = [
  'left:8%;top:14%;width:44%;height:30%;border-radius:58% 42% 61% 39% / 47% 60% 40% 53%',
  'left:52%;top:34%;width:36%;height:26%;border-radius:40% 60% 45% 55% / 60% 40% 60% 40%',
  'left:20%;top:58%;width:34%;height:24%;border-radius:55% 45% 38% 62% / 42% 58% 42% 58%',
  'left:62%;top:8%;width:20%;height:14%;border-radius:50%',
  'left:64%;top:70%;width:22%;height:16%;border-radius:45% 55% 60% 40% / 50% 45% 55% 50%',
]

const RESIDENTS = [
  ['🏰', 52, 8, 0.3], ['🌈', 17, 22, 0.24], ['🚀', 90, 30, 0.22], ['🦄', 9, 58, 0.2], ['🌳', 36, 3, 0.15],
  ['🦖', 88, 70, 0.19], ['🌳', 70, 91, 0.16], ['🚀', 24, 90, 0.19], ['⭐', 97, 50, 0.1], ['⭐', 4, 38, 0.09],
]

/** The planet's markup; `size` is a CSS length, `few` leaves only the castle, a rocket and the unicorn. */
window.planet = (size, few = false) =>
  `<div class="planet" style="--s:${size}"><div class="globe">${LANDS.map((land) => `<b style="${land}"></b>`).join('')}</div>${RESIDENTS.filter(
    ([who], i) => !few || i < 4,
  )
    .map(([who, x, y, s]) => `<span class="emoji" style="left:${x}%;top:${y}%;font-size:${s}em">${who}</span>`)
    .join('')}</div>`
