/* Линейный календарь · фиксированная лента спринтов.
   Правила ленты — из канона fin-calendar:
   - финнеделя: семидневка от границы (здесь суббота);
   - год начинается с первой финнедели, целиком лежащей в новом году;
   - квартал: узор 2–2–2–2–2–3 (13 финнедель), 4 квартала = 52;
   - если между стартами соседних лет 53 финнедели —
     последний спринт года удлиняется до четырёх (високосный). */

const BOUNDARY = 6;               // 6 = суббота (getUTCDay)
const PATTERN = [2, 2, 2, 2, 2, 3];
const MONTHS = ["ЯНВАРЬ","ФЕВРАЛЬ","МАРТ","АПРЕЛЬ","МАЙ","ИЮНЬ",
                "ИЮЛЬ","АВГУСТ","СЕНТЯБРЬ","ОКТЯБРЬ","НОЯБРЬ","ДЕКАБРЬ"];
const DOW = ["СБ","ВС","ПН","ВТ","СР","ЧТ","ПТ"];
const DAY = 864e5;

let year = 2027;
let mode = "own";

/* первая финнеделя, целиком лежащая в году */
function firstFullWeekStart(y) {
  let d = new Date(Date.UTC(y, 0, 1));
  while (d.getUTCDay() !== BOUNDARY) d = new Date(d.getTime() + DAY);
  return d;
}

/* спринты года: [{n, len, start(ms)}], с учётом високосного */
function tape(y) {
  const s0 = firstFullWeekStart(y);
  const s1 = firstFullWeekStart(y + 1);
  const weeks = Math.round((s1 - s0) / DAY / 7);
  const pat = PATTERN.concat(PATTERN, PATTERN, PATTERN).slice();
  if (weeks === 53) pat[23] = 4;
  const sprints = [];
  let t = s0.getTime();
  pat.forEach((len, i) => {
    sprints.push({ n: i + 1, len, start: t, leap: len === 4 });
    t += len * 7 * DAY;
  });
  return { start: s0.getTime(), weeks, sprints };
}

/* свой календарь: старты от фактических дат приходов */
function tapeOwn(y, dayNums) {
  const facts = [];
  for (let yy = y - 1; yy <= y + 1; yy++)
    dayNums.forEach(dn => {
      if (!dn) return;
      for (let m = 0; m < 12; m++) {
        const last = new Date(Date.UTC(yy, m + 1, 0)).getUTCDate();
        let d = new Date(Date.UTC(yy, m, Math.min(dn, last)));
        while (d.getUTCDay() === 0 || d.getUTCDay() === 6)
          d = new Date(d.getTime() - DAY);
        let s = d.getTime();
        while (new Date(s).getUTCDay() !== BOUNDARY) s += DAY;
        facts.push(s);
      }
    });
  const starts = [...new Set(facts)].sort((a, b) => a - b);
  const all = [];
  for (let i = 0; i < starts.length - 1; i++)
    all.push({ start: starts[i], len: Math.round((starts[i + 1] - starts[i]) / DAY / 7) });
  /* окно показа: спринты, пересекающие год */
  const y0 = Date.UTC(y, 0, 1), y1 = Date.UTC(y + 1, 0, 1);
  const vis = all.filter(s => s.start < y1 && s.start + s.len * 7 * DAY > y0);
  /* обычная длина = мода; длиннее — long, короче — short */
  const freq = {};
  vis.forEach(s => freq[s.len] = (freq[s.len] || 0) + 1);
  const modal = +Object.keys(freq).sort((a, b) => freq[b] - freq[a])[0];
  vis.forEach((s, i) => {
    s.n = i + 1;
    s.long = s.len > modal;
    s.short = s.len < modal;
  });
  return {
    start: vis.length ? vis[0].start : Date.UTC(y, 0, 1),
    weeks: vis.reduce((a, s) => a + s.len, 0),
    sprints: vis
  };
}

/* фактические даты приходов: выходной -> назад до пятницы */
function paydays(y, dayNum) {
  const out = [];
  for (let m = 0; m < 12; m++) {
    const last = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
    let d = new Date(Date.UTC(y, m, Math.min(dayNum, last)));
    const nominal = d.getTime();
    while (d.getUTCDay() === 0 || d.getUTCDay() === 6)
      d = new Date(d.getTime() - DAY);
    out.push({ fact: d.getTime(), nominal });
  }
  return out;
}

function render() {
  document.getElementById("yearLabel").textContent = year;
  const dayNums = ["p1","p2","p3"].map(id => +document.getElementById(id).value || 0);
  const t = mode === "own" ? tapeOwn(year, dayNums.filter(Boolean)) : tape(year);
  const { start, weeks, sprints } = t;
  if (!sprints.length) {
    document.getElementById("strip").innerHTML =
      '<p style="color:var(--muted)">Задай хотя бы один приход — в своём календаре опорные даты берутся из них.</p>';
    return;
  }

  /* карта дат: факт -> [классы], номинал -> true */
  const facts = {}, noms = {};
  [["p1","c1"],["p2","c2"],["p3","c3"]].forEach(([id, cls]) => {
    const v = +document.getElementById(id).value || 0;
    if (!v) return;
    paydays(year, v).forEach(p => {
      (facts[p.fact] = facts[p.fact] || []).push(cls);
      if (p.fact !== p.nominal) noms[p.nominal] = true;
    });
  });

  /* карта недель: номер недели -> спринт */
  const weekSprint = [];
  sprints.forEach(s => {
    for (let i = 0; i < s.len; i++)
      weekSprint.push({ ...s, firstWeek: i === 0 });
  });

  const strip = document.createElement("div");
  strip.className = "strip";

  const gutter = document.createElement("div");
  gutter.className = "gutter";
  gutter.innerHTML =
    '<div class="cell"></div><div class="cell"></div>' +
    DOW.map(d => `<div class="cell">${d}</div>`).join("");
  strip.appendChild(gutter);

  for (let w = 0; w < weeks; w++) {
    const info = weekSprint[w];
    const wStart = start + w * 7 * DAY;
    const col = document.createElement("div");
    col.className = "week";
    if (info.firstWeek) col.classList.add("sprint-start");
    const isLong = mode === "own" ? info.long : info.len === 3;
    if (isLong) col.classList.add("long");
    if (mode === "own" && info.short) col.classList.add("short");
    if (info.leap) col.classList.add("leap");

    /* имя месяца — над неделей, содержащей 1-е число */
    let mLabel = "";
    for (let i = 0; i < 7; i++) {
      const d = new Date(wStart + i * DAY);
      if (d.getUTCDate() === 1) {
        mLabel = MONTHS[d.getUTCMonth()];
        col.classList.add("month-start");
      }
    }
    if (w === 0 && !mLabel)
      mLabel = MONTHS[new Date(wStart).getUTCMonth()];

    col.insertAdjacentHTML("beforeend", `<div class="mname">${mLabel}</div>`);
    col.insertAdjacentHTML("beforeend",
      `<div class="wnum">${w + 1}${info.firstWeek ? ` <span class="snum">№${info.n}</span>` : ""}</div>`);

    for (let i = 0; i < 7; i++) {
      const t = wStart + i * DAY;
      const d = new Date(t);
      const cls = ["day"];
      if (i === 0 || i === 1) cls.push("weekend");     /* сб, вс */
      if (d.getUTCDate() === 1) cls.push("first");
      let marks = (facts[t] || [])
        .map(c => `<span class="pd ${c}"></span>`).join("");
      if (noms[t]) marks += '<span class="pd nom"></span>';
      col.insertAdjacentHTML("beforeend",
        `<div class="${cls.join(" ")}">${d.getUTCDate()}${marks}</div>`);
    }
    strip.appendChild(col);
  }

  const host = document.getElementById("strip");
  host.replaceWith(strip);
  strip.id = "strip";
}

document.querySelectorAll('input[name="mode"]').forEach(r =>
  r.addEventListener("change", e => { mode = e.target.value; render(); }));
["p1","p2","p3"].forEach(id =>
  document.getElementById(id).addEventListener("input", render));
document.getElementById("yearPrev").addEventListener("click",
  () => { year--; render(); });
document.getElementById("yearNext").addEventListener("click",
  () => { year++; render(); });

render();
