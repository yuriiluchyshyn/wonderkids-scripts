// The words of every ad picture and video, per language: `?lang=en` on a page picks one (Ukrainian when not given).
// What they claim must be true on the site in that language — the number of games above all (50 / 50 / 52).
window.TEXTS = {
  uk: {
    tagline: 'Навчання, схоже на пригоду',
    audience: 'Ігри українською · <b>4–10</b> років',
    games: '50 ігор<br />у дев’яти галактиках',
    subjects: ['Математика', 'Логіка', 'Мова', 'Географія', 'Астрономія', 'Історія', 'Екологія', 'Природа', 'Творчість'],
    calm: 'Спокійно для дитини<br />і для батьків',
    calmCards: ['Без програшів і таймерів', 'Без реклами', 'Час за екраном визначаєте ви'],
    hook: 'Займіть дитину<br /><em>з користю</em><br />на 20 хвилин!',
    values: ['Безкоштовна проба', 'Українською', 'Без реклами'],
    cta: 'Тицяйте «Грати»<br />та спробуйте демо безкоштовно!',
    play: 'Грати',
  },
  en: {
    tagline: 'Learning that feels like an adventure',
    audience: 'Learning games · ages <b>4–10</b>',
    games: '50 games<br />in nine galaxies',
    subjects: ['Math', 'Logic', 'Language', 'Geography', 'Astronomy', 'History', 'Ecology', 'Nature', 'Art'],
    calm: 'Calm for the child —<br />and for the parents',
    calmCards: ['No losing, no timers', 'No ads', 'You set the screen time'],
    hook: 'Keep your child busy —<br /><em>and learning</em> —<br />for 20 minutes!',
    values: ['Free to try', 'In English', 'No ads'],
    cta: 'Tap “Play” and try<br />the demo for free!',
    play: 'Play',
  },
  pl: {
    tagline: 'Nauka, która wciąga jak przygoda',
    audience: 'Gry edukacyjne · <b>4–10</b> lat',
    games: '52 gry<br />w dziewięciu galaktykach',
    subjects: ['Matematyka', 'Logika', 'Język', 'Geografia', 'Astronomia', 'Historia', 'Ekologia', 'Przyroda', 'Sztuka'],
    calm: 'Spokojnie dla dziecka<br />i dla rodziców',
    calmCards: ['Bez przegranych i bez stoperów', 'Bez reklam', 'Czas przed ekranem ustalasz Ty'],
    hook: 'Zajmij dziecko<br /><em>mądrze</em><br />na 20 minut!',
    values: ['Za darmo na próbę', 'Po polsku', 'Bez reklam'],
    cta: 'Kliknij „Graj”<br />i wypróbuj demo za darmo!',
    play: 'Graj',
  },
}
window.LANG = new URLSearchParams(location.search).get('lang') ?? 'uk'
window.T = window.TEXTS[window.LANG]
document.documentElement.lang = window.LANG
/** Fills every `data-t="key"` (or `key.2` for an item of a list) with its words. */
window.fillTexts = () => {
  for (const el of document.querySelectorAll('[data-t]')) {
    const [key, index] = el.dataset.t.split('.')
    el.innerHTML = index === undefined ? T[key] : T[key][Number(index)]
  }
}
