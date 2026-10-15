/**
 * Geometry lint for generated SVG figures.
 *
 * A generated figure has one characteristic failure: the arithmetic is right in
 * the source and wrong on the page. A label lands on the row above it, a block
 * computed from a row index falls off the bottom edge, a connector is drawn
 * through an annotation. All of it is invisible in the code and obvious in a
 * browser, which is a slow way to find it across a hundred figures.
 *
 * Necessary and not sufficient. It cannot see text under a curved path, a
 * z-order problem, or a figure laid out perfectly that says something false.
 * Always look at the figures as well as linting them.
 *
 * So this reads the emitted SVG back and checks what a person would check by
 * eye: is everything inside the canvas, and does any text sit on top of any
 * other text. Bounding boxes for text are estimated from the font size and the
 * character count, the same estimate the drawing helpers use, so a warning here
 * means the two disagree by more than the slack allowed below.
 *
 * Usage: node scripts/figures/check.mjs <dir> [<dir>...]
 */

import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';

/**
 * Font metrics come from each figure's own stylesheet, not from a table here.
 * Two generators feed this checker and they disagree: `.dim` is 11px monospace
 * in the shared toolkit and 12px sans in Debug80's older generator. A single
 * hardcoded table has to be wrong for one of them, and being wrong about a
 * width is how a real collision gets missed.
 */
function readFonts(src) {
  const fonts = {};
  const style = src.match(/<style>([\s\S]*?)<\/style>/)?.[1] ?? '';
  for (const m of style.matchAll(/\.([\w-]+)\s*\{[^}]*?font:\s*([^;]+);/g)) {
    const decl = m[2];
    const size = Number(decl.match(/(\d+(?:\.\d+)?)px/)?.[1] ?? 13);
    fonts[m[1]] = { size, mono: /mono/i.test(decl) };
  }
  return fonts;
}

/**
 * Width of a string at a given size. Monospace is exact. For a proportional
 * face the average advance depends heavily on case: capitals run about a third
 * wider than lowercase, and a run of narrow letters much less, so an all-caps
 * label measured at the lowercase average comes out far too short. That is
 * what let two labels sit on top of each other inside one pill undetected.
 */
const NARROW = new Set([...'ijltfr.,:;\'"|!()[] ']);
function advance(s, size, mono) {
  if (mono) return s.length * size * 0.6;
  let units = 0;
  for (const ch of s) {
    if (ch >= 'A' && ch <= 'Z') units += 0.68;
    else if (ch >= '0' && ch <= '9') units += 0.56;
    else if (NARROW.has(ch)) units += 0.31;
    else units += 0.53;
  }
  return units * size;
}

/** Text boxes may overlap by this much before it counts. Kerning is approximate. */
const SLACK = 3;

/**
 * A label inside a box wants this much clear space to its left and right. Less
 * than this and the text is touching the stroke, which reads as cramped even
 * when nothing is technically clipped.
 */
const PAD = 3;

function attrs(tag) {
  const out = {};
  for (const m of tag.matchAll(/([\w-]+)="([^"]*)"/g)) out[m[1]] = m[2];
  return out;
}

function textBox(a, content, fonts) {
  const cls = (a.class ?? 't').split(/\s+/)[0];
  const { size, mono } = fonts[cls] ?? { size: 13, mono: true };
  const w = advance(content, size, mono);
  const x = Number(a.x) || 0;
  const y = Number(a.y) || 0;
  const anchor = a['text-anchor'] ?? 'start';
  const left = anchor === 'middle' ? x - w / 2 : anchor === 'end' ? x - w : x;
  // Baseline-relative: cap height above, descender below.
  return { x: left, y: y - size * 0.78, w, h: size * 1.02, s: content, cls };
}

function overlaps(a, b) {
  return (
    a.x + a.w - SLACK > b.x &&
    b.x + b.w - SLACK > a.x &&
    a.y + a.h - SLACK > b.y &&
    b.y + b.h - SLACK > a.y
  );
}

export function checkFigure(file) {
  const src = readFileSync(file, 'utf8');
  const problems = [];

  const svgTag = src.match(/<svg[^>]*>/)[0];
  const { width, height } = attrs(svgTag);
  const W = Number(width);
  const H = Number(height);

  // Measure what is drawn, not what is stored. `&lt;` is four characters in
  // the file and one on the page, and counting the stored form invents
  // collisions in any figure whose labels contain angle brackets.
  const unesc = (s) =>
    s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');

  const fonts = readFonts(src);
  const texts = [];
  for (const m of src.matchAll(/<text([^>]*)>([^<]*)<\/text>/g)) {
    const a = attrs(`<text${m[1]}>`);
    texts.push(textBox(a, unesc(m[2]), fonts));
  }

  const boxes = [];
  for (const m of src.matchAll(/<rect([^>]*)\/>/g)) {
    const a = attrs(m[0]);
    boxes.push({
      x: Number(a.x) || 0,
      y: Number(a.y) || 0,
      w: Number(a.width) || 0,
      h: Number(a.height) || 0,
      s: `rect ${a.class ?? ''}`,
      cls: a.class ?? '',
    });
  }

  // 1. Everything inside the canvas.
  for (const el of [...texts, ...boxes]) {
    if (el.y < -0.5 || el.y + el.h > H + 0.5) {
      problems.push(
        `outside canvas (height ${H}): "${el.s.slice(0, 44)}" spans y ${el.y.toFixed(0)}..${(el.y + el.h).toFixed(0)}`,
      );
    } else if (el.x < -0.5 || el.x + el.w > W + 0.5) {
      problems.push(
        `outside canvas (width ${W}): "${el.s.slice(0, 44)}" spans x ${el.x.toFixed(0)}..${(el.x + el.w).toFixed(0)}`,
      );
    }
  }

  // 2. No text on top of other text.
  for (let i = 0; i < texts.length; i += 1) {
    for (let j = i + 1; j < texts.length; j += 1) {
      if (overlaps(texts[i], texts[j])) {
        problems.push(
          `text collision: "${texts[i].s.slice(0, 30)}" over "${texts[j].s.slice(0, 30)}" near y ${texts[i].y.toFixed(0)}`,
        );
      }
    }
  }

  // 3. No label wider than the box drawn around it. This is the failure the
  //    overlap check cannot see: a label centred in a cell it does not fit,
  //    which renders as text spilling over the stroke or colliding with the
  //    neighbouring cell's contents. For each label, take the smallest rect
  //    its centre lands in and ask whether the label fits inside it.
  for (const t of texts) {
    // `inv` is a numeral reversed out of a circular marker, so no rect holds it.
    if (t.cls === 'inv') continue;
    const cx = t.x + t.w / 2;
    const cy = t.y + t.h / 2;
    const holders = boxes
      // A `none` rect is an unfilled outline: a group bracket, or a divider
      // drawn over part of a filled box. It never contains a label, and
      // treating it as one flags text that legitimately spans it.
      .filter((b) => !/\bnone\b/.test(b.cls))
      .filter((b) => cx >= b.x && cx <= b.x + b.w && cy >= b.y && cy <= b.y + b.h)
      .sort((a, b) => a.w * a.h - b.w * b.h);
    const box = holders[0];
    if (!box) continue;
    const spill = Math.max(box.x + PAD - t.x, t.x + t.w - (box.x + box.w - PAD));
    if (spill > 0.5) {
      problems.push(
        `label wider than its box by ${spill.toFixed(0)}px: "${t.s.slice(0, 40)}" in a ${box.w.toFixed(0)}px ${box.s.trim()}`,
      );
    }
  }

  // 4. No label lying across a box it does not belong to. Connector labels
  //    placed between two boxes drift onto a stroke when a box grows, and a
  //    heading placed by row index lands on the row above when the list does.
  //    Neither shows up as a text collision, because the thing underneath is
  //    a shape.
  const filled = boxes.filter((b) => /\b(bx|bx2|bxq|bxs|card|pnl|field|btn|prim|off)\b/.test(b.cls));
  for (const t of texts) {
    if (t.cls === 'inv') continue;
    const cx = t.x + t.w / 2;
    const cy = t.y + t.h / 2;
    for (const b of filled) {
      const inside = cx >= b.x && cx <= b.x + b.w && cy >= b.y && cy <= b.y + b.h;
      if (inside) continue;
      const hit =
        t.x + t.w - 1 > b.x && b.x + b.w - 1 > t.x &&
        t.y + t.h - 1 > b.y && b.y + b.h - 1 > t.y;
      if (hit) {
        problems.push(
          `label lies across a box it is not in: "${t.s.slice(0, 34)}" over a ${b.w.toFixed(0)}x${b.h.toFixed(0)} ${b.s.trim()} at ${b.x.toFixed(0)},${b.y.toFixed(0)}`,
        );
        break;
      }
    }
  }

  // 5. Nothing drawn through a label. A rect is not the only thing that can
  //    obscure text: an arrow routed between two boxes crosses whatever
  //    annotation sits in the gap, a flow diamond is a polygon, and an LED in
  //    a grid is a circle. All of them read as clobbered text on the page and
  //    none of them is a rect.
  const circles = [...src.matchAll(/<circle([^>]*)\/>/g)].map((m) => {
    const a = attrs(m[0]);
    const r = Number(a.r) || 0;
    return {
      x: (Number(a.cx) || 0) - r, y: (Number(a.cy) || 0) - r, w: r * 2, h: r * 2,
      s: `circle r${r}`, cls: a.class ?? '',
    };
  });
  const polys = [...src.matchAll(/<polygon([^>]*)\/>/g)].map((m) => {
    const a = attrs(m[0]);
    const pts = (a.points ?? '').trim().split(/\s+/).map((p) => p.split(',').map(Number));
    const xs = pts.map((p) => p[0]);
    const ys = pts.map((p) => p[1]);
    return {
      x: Math.min(...xs), y: Math.min(...ys),
      w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys),
      s: 'polygon', cls: a.class ?? '',
    };
  });

  for (const t of texts) {
    if (t.cls === 'inv') continue;
    for (const shape of [...circles, ...polys]) {
      const cx = t.x + t.w / 2;
      const cy = t.y + t.h / 2;
      const inside =
        cx >= shape.x && cx <= shape.x + shape.w && cy >= shape.y && cy <= shape.y + shape.h;
      if (inside) continue;
      if (
        t.x + t.w - 1 > shape.x && shape.x + shape.w - 1 > t.x &&
        t.y + t.h - 1 > shape.y && shape.y + shape.h - 1 > t.y
      ) {
        problems.push(`label lies across a ${shape.s}: "${t.s.slice(0, 34)}"`);
        break;
      }
    }
  }

  // A straight connector crossing a label. Both <line> and the axis-aligned
  // <path> forms count: `M x,y H x2 V y2` draws exactly the same stroke as two
  // <line> elements and obscures text exactly as well. Only paths made purely
  // of M/H/V are read; anything with a curve in it can route around a label,
  // and guessing at its extent invents more noise than it catches. Dashed
  // leaders are skipped, since they are drawn to touch their labels.
  const segments = [];
  for (const m of src.matchAll(/<line([^>]*)\/>/g)) {
    const a = attrs(m[0]);
    if (/\b(dash|rule)\b/.test(a.class ?? '')) continue;
    segments.push([Number(a.x1), Number(a.y1), Number(a.x2), Number(a.y2)]);
  }
  for (const m of src.matchAll(/<path([^>]*)\/>/g)) {
    const a = attrs(m[0]);
    if (/\b(dash|rule)\b/.test(a.class ?? '')) continue;
    const d = (a.d ?? '').trim();
    if (!/^M[\d.,\s-]+(?:[HV][\d.\s-]+)+$/i.test(d)) continue;
    const start = d.match(/^M\s*(-?[\d.]+)[,\s]+(-?[\d.]+)/);
    if (!start) continue;
    let cx = Number(start[1]);
    let cy = Number(start[2]);
    for (const step of d.slice(start[0].length).matchAll(/([HV])\s*(-?[\d.]+)/gi)) {
      const v = Number(step[2]);
      const nx = step[1].toUpperCase() === 'H' ? v : cx;
      const ny = step[1].toUpperCase() === 'V' ? v : cy;
      segments.push([cx, cy, nx, ny]);
      cx = nx;
      cy = ny;
    }
  }

  for (const [x1, y1, x2, y2] of segments) {
    for (const t of texts) {
      if (t.cls === 'inv') continue;
      if (Math.abs(y1 - y2) < 0.5) {
        const [lo, hi] = [Math.min(x1, x2), Math.max(x1, x2)];
        if (y1 > t.y + 1 && y1 < t.y + t.h - 1 && hi - 1 > t.x && t.x + t.w - 1 > lo) {
          problems.push(`connector drawn through "${t.s.slice(0, 34)}" at y ${y1}`);
        }
      } else if (Math.abs(x1 - x2) < 0.5) {
        const [lo, hi] = [Math.min(y1, y2), Math.max(y1, y2)];
        if (x1 > t.x + 1 && x1 < t.x + t.w - 1 && hi - 1 > t.y && t.y + t.h - 1 > lo) {
          problems.push(`connector drawn through "${t.s.slice(0, 34)}" at x ${x1}`);
        }
      }
    }
  }

  // 6. Nothing crowded against the canvas edge.
  for (const t of texts) {
    if (t.x < PAD || t.x + t.w > W - PAD) {
      problems.push(`text against the canvas edge: "${t.s.slice(0, 40)}"`);
    }
  }

  // 7. A figure with no title or desc is unreadable to a screen reader.
  if (!/<title[^>]*>[^<]+<\/title>/.test(src)) problems.push('missing <title>');
  if (!/<desc[^>]*>[^<]+<\/desc>/.test(src)) problems.push('missing <desc>');

  return problems;
}

const dirs = process.argv.slice(2);
if (dirs.length) {
  let total = 0;
  let clean = 0;
  for (const dir of dirs) {
    for (const name of readdirSync(dir).filter((n) => n.endsWith('.svg')).sort()) {
      const file = path.join(dir, name);
      const problems = checkFigure(file);
      total += 1;
      if (problems.length === 0) {
        clean += 1;
      } else {
        console.log(`\n${file}`);
        for (const p of problems) console.log(`  ${p}`);
      }
    }
  }
  console.log(`\n${clean}/${total} figures clean`);
  if (clean !== total) process.exitCode = 1;
}
