/**
 * Shared drawing toolkit for generated documentation figures.
 *
 * Working code, extracted from a five-book technical documentation set where it
 * produced around 130 figures. Copy it into the project and adapt the palette
 * and the class names; keep the structure, because the value is in every figure
 * being drawn from one vocabulary rather than each generator inventing its own.
 *
 * Two decisions worth keeping:
 *
 * 1. The ground is transparent, so the host page's own background shows
 *    through whatever wrapper the figure sits in.
 * 2. Colours are custom properties redefined under
 *    `prefers-color-scheme: dark` inside the SVG itself. An <img>-referenced
 *    SVG cannot see the host page's properties, so it has to carry its own. It
 *    follows the OS preference and cannot follow a manual toggle on the page.
 *
 * Sizes assume a 720px canvas. See the skill for why text is never shrunk to
 * fit, and for the measurement gotchas that make the accompanying lint
 * necessary.
 */

/**
 * One signal colour per section, light and dark ground. Replace these with the
 * project's own, and keep the set small: the signal marks the thing a figure is
 * about, so a figure using several has lost the point of having one.
 */
export const BOOKS = {
  red: { light: '#b4442f', dark: '#e08a76' },
  blue: { light: '#14607e', dark: '#5fa8c6' },
  green: { light: '#2a7139', dark: '#6cbb7e' },
  ochre: { light: '#96620f', dark: '#d1a052' },
};

export const W = 720;

const esc = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/**
 * Advance width per character. There is no text measurement here, so anything
 * that centres or sizes itself around a string estimates.
 *
 * Monospace is exact. Proportional is not, and the naive version, one average
 * advance for every character, is wrong in a way that matters: capitals run
 * about a third wider than lowercase, so an all-caps label comes out far too
 * short and quietly overruns whatever is beside it. These weights must stay in
 * step with the geometry lint, or the drawing and the checking disagree and the
 * disagreement is the bug.
 */
const NARROW = new Set([...'ijltfr.,:;\'"|!()[] ']);
export const monoW = (s, size) => String(s).length * size * 0.6;
export const sansW = (s, size) => {
  let units = 0;
  for (const ch of String(s)) {
    if (ch >= 'A' && ch <= 'Z') units += 0.68;
    else if (ch >= '0' && ch <= '9') units += 0.56;
    else if (NARROW.has(ch)) units += 0.31;
    else units += 0.53;
  }
  return units * size;
};

function styles(signal) {
  return `
    :root {
      --ink:    #111417;
      --ink-2:  #454b52;
      --dim:    #8797a5;
      --rule:   #c8ccd0;
      --fill:   #ffffff;
      --fill-2: #eef0f1;
      --sig:    ${signal.light};
      --sig-bg: ${signal.light}1a;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --ink:    #e6e8ea;
        --ink-2:  #b3b9bf;
        --dim:    #7d8890;
        --rule:   #3d4348;
        --fill:   #1c1f22;
        --fill-2: #262a2e;
        --sig:    ${signal.dark};
        --sig-bg: ${signal.dark}26;
      }
    }

    .bx    { fill: var(--fill);   stroke: var(--ink);  stroke-width: 1.5; }
    .bx2   { fill: var(--fill-2); stroke: var(--ink);  stroke-width: 1.5; }
    .bxq   { fill: var(--fill-2); stroke: var(--rule); stroke-width: 1.5; }
    .bxs   { fill: var(--sig-bg); stroke: var(--sig);  stroke-width: 2; }
    .sig   { fill: var(--sig);    stroke: var(--sig);  stroke-width: 1.5; }
    .none  { fill: none;          stroke: var(--ink);  stroke-width: 1.5; }
    .rule  { fill: none; stroke: var(--rule); stroke-width: 1; }
    .dash  { fill: none; stroke: var(--dim);  stroke-width: 1.2; stroke-dasharray: 4 3; }
    .sline { fill: none; stroke: var(--sig);  stroke-width: 2; }

    .t     { font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; fill: var(--ink); }
    .ts    { font: 11px ui-monospace, SFMono-Regular, Menlo, monospace; fill: var(--ink-2); }
    .tb    { font: 600 13px ui-monospace, SFMono-Regular, Menlo, monospace; fill: var(--ink); }
    .n     { font: 13px system-ui, -apple-system, "Segoe UI", sans-serif; fill: var(--ink); }
    .ns    { font: 11px system-ui, -apple-system, "Segoe UI", sans-serif; fill: var(--ink-2); }
    .nb    { font: 600 13px system-ui, -apple-system, "Segoe UI", sans-serif; fill: var(--ink); }
    .dim   { font: 11px ui-monospace, SFMono-Regular, Menlo, monospace; fill: var(--dim); }
    .dimn  { font: 11px system-ui, -apple-system, "Segoe UI", sans-serif; fill: var(--dim); }
    .cap   { font: 600 10px ui-monospace, SFMono-Regular, Menlo, monospace;
             fill: var(--sig); letter-spacing: .12em; }
    .on-sig { fill: var(--sig); }
    .on-dim { fill: var(--dim); }
    .inv   { fill: var(--fill); }
  `;
}

/**
 * Wrap a body in an SVG document. `title` and `desc` are what a screen reader
 * gets; the markdown alt text becomes the printed caption, so the two say
 * different things on purpose.
 */
export function svg({ title, desc, height, book = 'blue', width = W, body }) {
  const signal = BOOKS[book] ?? BOOKS.blue;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="figTitle figDesc">
  <title id="figTitle">${esc(title)}</title>
  <desc id="figDesc">${esc(desc)}</desc>
  <defs>
    <style>${styles(signal)}</style>
    <!-- markerUnits defaults to strokeWidth, which sizes every arrowhead by the
         weight of the line carrying it. A 2px signal arrow then gets a head a
         third larger than the 1.5px ink arrow beside it, and in a figure that
         uses both the heads read as mismatched rather than as emphasis. Fixed
         in user space so one arrowhead is one size everywhere. -->
    <marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" markerUnits="userSpaceOnUse" orient="auto-start-reverse">
      <path d="M0,0.5 L10,5 L0,9.5 z" fill="var(--ink)"/>
    </marker>
    <marker id="arS" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" markerUnits="userSpaceOnUse" orient="auto-start-reverse">
      <path d="M0,0.5 L10,5 L0,9.5 z" fill="var(--sig)"/>
    </marker>
    <marker id="arD" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" markerUnits="userSpaceOnUse" orient="auto-start-reverse">
      <path d="M0,0.5 L10,5 L0,9.5 z" fill="var(--dim)"/>
    </marker>
  </defs>
${body}
</svg>
`;
}

/* ---------- primitives ---------- */

export const rect = (cls, x, y, w, h, r = 3) =>
  `  <rect class="${cls}" x="${r0(x)}" y="${r0(y)}" width="${r0(w)}" height="${r0(h)}" rx="${r}"/>`;

/**
 * SVG collapses runs of whitespace the way HTML does, so a code sample drawn
 * with `ld   a,5` renders as `ld a,5` and every column in the figure loses its
 * alignment. The geometry lint cannot see this: it counts characters, and the
 * character count is unchanged. `xml:space="preserve"` keeps the runs.
 */
export const text = (cls, x, y, s, anchor = 'start') =>
  `  <text class="${cls}" x="${r0(x)}" y="${r0(y)}" text-anchor="${anchor}" xml:space="preserve">${esc(s)}</text>`;

export const line = (cls, x1, y1, x2, y2, marker = '') =>
  `  <line class="${cls}" x1="${r0(x1)}" y1="${r0(y1)}" x2="${r0(x2)}" y2="${r0(y2)}"${
    marker ? ` marker-end="url(#${marker})"` : ''
  }/>`;

export const path = (cls, d, marker = '') =>
  `  <path class="${cls}" d="${d}"${marker ? ` marker-end="url(#${marker})"` : ''}/>`;

export const circle = (cls, cx, cy, r) =>
  `  <circle class="${cls}" cx="${r0(cx)}" cy="${r0(cy)}" r="${r0(r)}"/>`;

/** Round to 2dp so the emitted files stay diffable. */
const r0 = (n) => (typeof n === 'number' ? Math.round(n * 100) / 100 : n);

/** An arrow that leaves horizontally, turns once, and arrives vertically. */
export function elbow(cls, x1, y1, x2, y2, marker = 'ar') {
  return path(cls, `M${r0(x1)},${r0(y1)} H${r0(x2)} V${r0(y2)}`, marker);
}

/** A small uppercase caption in the signal colour, used to head a group. */
export const caption = (x, y, s, anchor = 'start') =>
  text('cap', x, y, String(s).toUpperCase(), anchor);

/* ---------- composites ---------- */

/**
 * A run of memory cells. `cells` is an array of `{ v, hi, sub }`: `v` is the
 * byte drawn inside, `sub` a label under the cell, `hi` marks it in the
 * signal colour. Addresses are printed above every `addrEvery`-th cell.
 */
export function strip({
  x,
  y,
  cells,
  cw = 46,
  ch = 30,
  base = null,
  addrEvery = 1,
  addrFmt = (a) => `$${a.toString(16).toUpperCase().padStart(4, '0')}`,
}) {
  const out = [];
  cells.forEach((c, i) => {
    const cx = x + i * cw;
    out.push(rect(c.hi ? 'bxs' : 'bx', cx, y, cw, ch, 2));
    if (c.v !== undefined && c.v !== null) {
      out.push(text(c.hi ? 'tb' : 't', cx + cw / 2, y + ch / 2 + 4.5, c.v, 'middle'));
    }
    if (base !== null && i % addrEvery === 0) {
      out.push(text('dim', cx + cw / 2, y - 7, addrFmt(base + i), 'middle'));
    }
    if (c.sub) out.push(text('dimn', cx + cw / 2, y + ch + 14, c.sub, 'middle'));
  });
  return out.join('\n');
}

/**
 * Eight (or fewer) bit cells with a bit-number row beneath. `bits` is a
 * string like "01110101" or an array of per-bit labels; `marks` names the
 * indices drawn in the signal colour.
 */
export function bitfield({ x, y, bits, cw = 34, ch = 28, marks = [], names = null, numbers = true }) {
  const arr = Array.isArray(bits) ? bits : String(bits).split('');
  const out = [];
  arr.forEach((b, i) => {
    const cx = x + i * cw;
    const hi = marks.includes(i);
    out.push(rect(hi ? 'bxs' : b === '-' ? 'bxq' : 'bx', cx, y, cw, ch, 2));
    out.push(text(hi ? 'tb' : b === '-' ? 'dim' : 't', cx + cw / 2, y + ch / 2 + 4.5, b, 'middle'));
    if (numbers) {
      out.push(text('dim', cx + cw / 2, y - 7, String(arr.length - 1 - i), 'middle'));
    }
    if (names && names[i]) {
      out.push(text('dimn', cx + cw / 2, y + ch + 14, names[i], 'middle'));
    }
  });
  return out.join('\n');
}

/** A labelled block, optionally with body lines. Returns the markup only. */
export function box({ x, y, w, h, title, lines = [], cls = 'bx', titleCls = 'nb' }) {
  const out = [rect(cls, x, y, w, h, 4)];
  const cx = x + w / 2;
  if (title) out.push(text(titleCls, cx, y + (lines.length ? 20 : h / 2 + 4.5), title, 'middle'));
  lines.forEach((l, i) => {
    out.push(text('ts', cx, y + 38 + i * 16, l, 'middle'));
  });
  return out.join('\n');
}

/**
 * A stack drawn the way the Z80 actually uses it: high addresses at the top,
 * pushes moving down. `slots` runs top (highest address) to bottom.
 */
export function stack({ x, y, slots, w = 150, sh = 26, topAddr, spIndex = null }) {
  const out = [];
  slots.forEach((s, i) => {
    const sy = y + i * sh;
    const empty = s.v === undefined || s.v === null;
    out.push(rect(s.hi ? 'bxs' : empty ? 'bxq' : 'bx', x, sy, w, sh, 2));
    if (!empty) out.push(text(s.hi ? 'tb' : 't', x + w / 2, sy + sh / 2 + 4.5, s.v, 'middle'));
    if (topAddr !== undefined) {
      out.push(text('dim', x - 8, sy + sh / 2 + 4, `$${(topAddr - i * (s.wide ? 2 : 1)).toString(16).toUpperCase().padStart(4, '0')}`, 'end'));
    }
    if (s.note) out.push(text('dimn', x + w + 12, sy + sh / 2 + 4, s.note));
  });
  if (spIndex !== null) {
    const sy = y + spIndex * sh + sh / 2;
    out.push(line('sline', x + w + 92, sy, x + w + 58, sy, 'arS'));
    out.push(text('cap', x + w + 98, sy + 4, 'SP'));
  }
  return out.join('\n');
}

/** A grid of LEDs, for the 8x8 matrix. `lit` is a predicate on (col, row). */
export function ledGrid({ x, y, cols = 8, rows = 8, pitch = 26, r = 8, lit, colour }) {
  const out = [];
  for (let ry = 0; ry < rows; ry += 1) {
    for (let cx = 0; cx < cols; cx += 1) {
      const on = lit ? lit(cx, ry) : false;
      out.push(
        `  <circle class="${on ? (colour ? colour(cx, ry) : 'sig') : 'bxq'}" cx="${r0(x + cx * pitch + pitch / 2)}" cy="${r0(y + ry * pitch + pitch / 2)}" r="${r}"/>`,
      );
    }
  }
  out.push(rect('none', x, y, cols * pitch, rows * pitch, 4));
  return out.join('\n');
}

/**
 * A plotted curve on a light grid. `f` maps 0..1 to 0..1; the y axis is
 * flipped so higher values sit higher on the page.
 */
export function plot({ x, y, w, h, f, label, samples = 48, guide = true }) {
  const out = [rect('bxq', x, y, w, h, 3)];
  if (guide) {
    out.push(line('dash', x, y + h, x + w, y));
  }
  const pts = [];
  for (let i = 0; i <= samples; i += 1) {
    const t = i / samples;
    const v = f(t);
    pts.push(`${r0(x + t * w)},${r0(y + h - v * h)}`);
  }
  out.push(`  <polyline class="sline" points="${pts.join(' ')}"/>`);
  if (label) out.push(text('ts', x + w / 2, y + h + 16, label, 'middle'));
  return out.join('\n');
}

/** A flow-chart node. `kind` is 'box', 'test' (diamond) or 'term' (rounded). */
export function node({ x, y, w, h, label, kind = 'box', hi = false }) {
  const cls = hi ? 'bxs' : 'bx';
  const out = [];
  if (kind === 'test') {
    const cx = x + w / 2;
    const cy = y + h / 2;
    out.push(
      `  <polygon class="${cls}" points="${r0(cx)},${r0(y)} ${r0(x + w)},${r0(cy)} ${r0(cx)},${r0(y + h)} ${r0(x)},${r0(cy)}"/>`,
    );
  } else {
    out.push(rect(cls, x, y, w, h, kind === 'term' ? h / 2 : 4));
  }
  const lines = Array.isArray(label) ? label : [label];
  const first = y + h / 2 + 4.5 - ((lines.length - 1) * 15) / 2;
  lines.forEach((l, i) => out.push(text('t', x + w / 2, first + i * 15, l, 'middle')));
  return out.join('\n');
}

/** A small legend row: swatch plus text. */
export function legend(x, y, items) {
  const out = [];
  let cx = x;
  items.forEach((it) => {
    out.push(rect(it.cls, cx, y - 9, 13, 13, 2));
    out.push(text('dimn', cx + 20, y + 2, it.label));
    cx += 20 + sansW(it.label, 11) + 26;
  });
  return out.join('\n');
}
