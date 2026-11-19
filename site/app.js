// Seasons website. The page is a small desktop: leaves (or snow) fall, settle on the tops of the
// windows, the Dock and the floor, ride a dragged window, and lift when the pointer sweeps them.
(() => {
  'use strict';

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const rand = (low, high) => low + Math.random() * (high - low);
  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));

  const canvas = $('#weather');
  const ctx = canvas.getContext('2d');
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const stacked = matchMedia('(max-width: 1039px), (max-height: 619px)');

  const BIN = 6;              // width of one pile column, in CSS pixels
  const SPRITE = 44;          // sprite box, in CSS pixels
  const SPRITE_LEAF = 38;     // leaf length inside that box
  const COLOURS = 12;
  const KIND = {
    fall: { rise: 2.7, slope: 2, rate: 9, cap: 1500, seed: 560, floor: 300 },
    winter: { rise: 1.6, slope: 3, rate: 30, cap: 5600, seed: 2400, floor: 900 },
  };
  const HINTS = {
    fall: {
      glove: 'Brush a pile with a slow sweep.',
      rake: 'Drag sideways through a pile to gather it.',
      blower: 'Sweep fast past a pile. A faster pass lifts more.',
    },
    winter: {
      glove: 'Brush the snow with a slow sweep.',
      rake: 'Push through a drift to clear it.',
    },
  };

  let width = 0, height = 0, ratio = 1;
  let mode = 'auto', season = 'fall', tool = 'glove', kind = KIND.fall;
  let leafAge = 0.6;
  let sprites = [], flakeSprite = null;
  let surfaces = [];
  let flying = [];
  let resting = 0;
  let wind = 0, windTarget = 0, breeze = 0, gustLeft = 0, gustDir = 1, nextGust = 7;
  let spawnDebt = 0;
  let last = 0;
  let drag = null;
  const pointer = { x: -999, y: -999, vx: 0, vy: 0, t: 0, inside: false, overUi: false };

  // ---------- Season and calendar ----------

  function calendar(date = new Date()) {
    const year = date.getFullYear();
    const start = new Date(year, 8, 22), end = new Date(year, 11, 21);
    const inFall = date >= start && date < end;
    return { season: inFall ? 'fall' : 'winter', age: inFall ? (date - start) / (end - start) : 0.6 };
  }

  // ---------- Leaf artwork ----------

  const RAMP = ['#93a63b', '#c9b23a', '#e6b535', '#f0992c', '#e2742a', '#cf4d1e', '#a9321b', '#7c3b20']
    .map(hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)));
  const mix = (a, b, t) => a.map((channel, i) => Math.round(channel + (b[i] - channel) * t));
  const css = (rgb, alpha = 1) => `rgba(${rgb[0]},${rgb[1]},${rgb[2]},${alpha})`;
  function ramp(position) {
    const scaled = clamp(position, 0, 1) * (RAMP.length - 1);
    const index = Math.min(RAMP.length - 2, Math.floor(scaled));
    return mix(RAMP[index], RAMP[index + 1], scaled - index);
  }

  // Half outlines, tip at the top, mirrored across the midrib.
  const MAPLE = [[0, -1], [0.18, -0.6], [0.44, -0.74], [0.36, -0.38], [0.8, -0.44], [0.6, -0.12], [0.96, 0.08],
    [0.52, 0.22], [0.6, 0.5], [0.18, 0.38], [0, 0.62]];
  const OAK = [[0, -1], [0.26, -0.84], [0.4, -0.66], [0.2, -0.5], [0.5, -0.28], [0.52, -0.16], [0.24, -0.02],
    [0.46, 0.2], [0.44, 0.32], [0.2, 0.42], [0.3, 0.58], [0.16, 0.7], [0, 0.78]];

  function outline(shape) {
    const path = new Path2D();
    if (shape === 0) {
      path.moveTo(0, -1);
      path.bezierCurveTo(0.64, -0.56, 0.62, 0.44, 0, 0.78);
      path.bezierCurveTo(-0.62, 0.44, -0.64, -0.56, 0, -1);
      return path;
    }
    const half = shape === 1 ? MAPLE : OAK;
    const points = half.concat(half.slice(1, -1).reverse().map(([x, y]) => [-x, y]));
    if (shape === 1) {
      points.forEach(([x, y], i) => (i ? path.lineTo(x, y) : path.moveTo(x, y)));
    } else {
      // Rounded lobes: curve through the midpoints, using each point as the control.
      const count = points.length;
      const midpoint = i => [(points[i][0] + points[(i + 1) % count][0]) / 2, (points[i][1] + points[(i + 1) % count][1]) / 2];
      path.moveTo(...midpoint(count - 1));
      for (let i = 0; i < count; i++) path.quadraticCurveTo(points[i][0], points[i][1], ...midpoint(i));
    }
    path.closePath();
    return path;
  }

  function buildSprites() {
    const scale = ratio * 2;   // drawn at up to twice size for the large foreground leaves
    const dark = [58, 28, 16];
    sprites = [];
    for (let shape = 0; shape < 3; shape++) {
      const path = outline(shape);
      const stemFrom = shape === 0 ? 0.78 : shape === 1 ? 0.62 : 0.78;
      for (let c = 0; c < COLOURS; c++) {
        const colour = ramp(c / (COLOURS - 1));
        const sheet = document.createElement('canvas');
        sheet.width = sheet.height = Math.ceil(SPRITE * scale);
        const g = sheet.getContext('2d');
        g.scale(scale, scale);
        g.translate(SPRITE / 2, SPRITE / 2);
        g.scale(SPRITE_LEAF / 2, SPRITE_LEAF / 2);
        g.lineCap = g.lineJoin = 'round';
        g.strokeStyle = css(mix(colour, dark, 0.55));
        g.lineWidth = 0.07;
        g.beginPath(); g.moveTo(0, stemFrom - 0.05); g.lineTo(0, 1); g.stroke();
        g.fillStyle = css(colour);
        g.fill(path);
        g.save(); g.clip(path);
        g.fillStyle = css(mix(colour, [255, 244, 214], 0.5), 0.34);
        g.fillRect(0, -1, 1, 2);            // one half catches the light
        g.restore();
        g.strokeStyle = css(mix(colour, dark, 0.5), 0.7);
        g.lineWidth = 0.05;
        g.stroke(path);
        g.strokeStyle = css(mix(colour, dark, 0.42), 0.85);
        g.lineWidth = 0.055;
        g.beginPath();
        g.moveTo(0, -0.78); g.lineTo(0, stemFrom);
        for (const y of [-0.22, 0.2]) {
          g.moveTo(0, y); g.lineTo(0.3, y - 0.26);
          g.moveTo(0, y); g.lineTo(-0.3, y - 0.26);
        }
        g.stroke();
        sprites.push(sheet);
      }
    }
    flakeSprite = document.createElement('canvas');
    flakeSprite.width = flakeSprite.height = Math.ceil(16 * ratio);
    const f = flakeSprite.getContext('2d');
    const glow = f.createRadialGradient(8 * ratio, 8 * ratio, 0, 8 * ratio, 8 * ratio, 8 * ratio);
    glow.addColorStop(0, 'rgba(255,255,255,1)');
    glow.addColorStop(0.45, 'rgba(255,255,255,0.92)');
    glow.addColorStop(1, 'rgba(255,255,255,0)');
    f.fillStyle = glow;
    f.fillRect(0, 0, flakeSprite.width, flakeSprite.height);
  }

  function makeLeaf(x, y) {
    if (season === 'winter') {
      return {
        x, y, px: x, py: y, flake: true, size: rand(3, 7.5), rot: 0, spin: 0, flip: 1,
        flipPhase: 0, flipRate: 0, swayPhase: rand(0, 6.28), swayRate: rand(0.8, 1.8), sway: rand(6, 20),
        fall: rand(42, 92), drift: rand(0.7, 1.1), drag: 2.4, pushX: 0, pushY: 0, noLand: 0, dx: 0, dy: 0,
      };
    }
    const shapePick = Math.random();
    const shape = shapePick < 0.45 ? 0 : shapePick < 0.75 ? 1 : 2;
    const tone = clamp(0.18 + 0.62 * leafAge + (Math.random() - 0.5) * 0.75, 0.02, 0.98);
    return {
      x, y, px: x, py: y, flake: false,
      sprite: sprites[shape * COLOURS + Math.round(tone * (COLOURS - 1))],
      size: rand(10, 17), rot: rand(0, 6.28), spin: rand(-1.6, 1.6), flip: 1,
      flipPhase: rand(0, 6.28), flipRate: rand(1.2, 3.4), swayPhase: rand(0, 6.28), swayRate: rand(1.1, 2.4),
      sway: rand(18, 48), fall: rand(46, 96), drift: rand(0.75, 1.25), drag: 2,
      pushX: 0, pushY: 0, noLand: 0, dx: 0, dy: 0,
    };
  }

  // ---------- Surfaces: window tops, the Dock, the floor ----------

  function makeSurface(el, type) {
    return { el, type, left: 0, right: 0, top: 0, bottom: 0, z: 0, bins: [], covered: new Uint8Array(0),
      max: type === 'floor' ? 52 : type === 'dock' ? 30 : 44, spill: type !== 'floor', inset: type === 'floor' ? 0 : 9 };
  }

  function measure() {
    for (const surface of surfaces) {
      if (surface.type === 'floor') {
        surface.left = 0; surface.right = width; surface.top = height; surface.bottom = height + 1; surface.z = -1;
      } else {
        const box = surface.el.getBoundingClientRect();
        surface.left = box.left; surface.right = box.right; surface.top = box.top; surface.bottom = box.bottom;
        surface.z = surface.type === 'dock' ? 9999 : (parseInt(surface.el.style.zIndex, 10) || 10);   // the Dock sits in front
      }
      const count = Math.max(1, Math.ceil((surface.right - surface.left) / BIN));
      if (count !== surface.bins.length) {
        for (const bin of surface.bins) resting -= bin.length;   // a resized surface starts clean
        surface.bins = Array.from({ length: count }, () => []);
        surface.covered = new Uint8Array(count);
      }
    }
    // A column is covered when something in front sits on or just above that stretch of the top edge.
    for (const surface of surfaces) {
      surface.covered.fill(0);
      for (const other of surfaces) {
        if (other === surface || other.type === 'floor' || other.z <= surface.z) continue;
        if (other.top >= surface.top - 1 || other.bottom <= surface.top - 40) continue;
        const from = clamp(Math.floor((other.left - surface.left) / BIN), 0, surface.bins.length);
        const to = clamp(Math.ceil((other.right - surface.left) / BIN), 0, surface.bins.length);
        for (let b = from; b < to; b++) surface.covered[b] = 1;
      }
      // Whatever was resting there is ploughed into the air.
      for (let b = 0; b < surface.bins.length; b++) {
        if (!surface.covered[b] || !surface.bins[b].length) continue;
        while (surface.bins[b].length) {
          const leaf = lift(surface, b);
          leaf.pushX = (drag ? drag.vx * 0.45 : 0) + rand(-70, 70);
          leaf.pushY = -rand(50, 150);
          leaf.noLand = 0.5;
        }
      }
    }
  }

  function lift(surface, b) {
    const leaf = surface.bins[b].pop();
    resting--;
    leaf.x = leaf.px = surface.left + leaf.dx;
    leaf.y = leaf.py = surface.top - leaf.dy;
    flying.push(leaf);
    return leaf;
  }

  // Returns true when the leaf came to rest (or left the scene) and must leave the flying list.
  function settle(leaf, surface, b) {
    const bins = surface.bins, count = bins.length;
    for (let step = 0; step < 10; step++) {
      const here = bins[b].length;
      const edge = surface.spill ? (here >= 6 ? here - kind.slope : here) : Infinity;
      const leftH = b > 0 ? (surface.covered[b - 1] ? Infinity : bins[b - 1].length) : edge;
      const rightH = b < count - 1 ? (surface.covered[b + 1] ? Infinity : bins[b + 1].length) : edge;
      if (here - Math.min(leftH, rightH) < kind.slope) break;
      const direction = leftH === rightH ? (Math.random() < 0.5 ? -1 : 1) : (leftH < rightH ? -1 : 1);
      const next = b + direction;
      if (next < 0 || next >= count) {          // slips off the edge and keeps falling
        leaf.x = leaf.px = next < 0 ? surface.left - 3 : surface.right + 3;
        leaf.y = leaf.py = surface.top - here * kind.rise;
        leaf.pushX += direction * 30;
        leaf.noLand = 0.05;
        return false;
      }
      b = next;
    }
    if (bins[b].length * kind.rise >= surface.max) return true;   // the pile is full
    leaf.dx = (b + Math.random()) * BIN;
    leaf.dy = bins[b].length * kind.rise + kind.rise * 0.5 + Math.random() * 1.5;
    leaf.rot = (Math.random() < 0.5 ? 1 : -1) * 1.57 + rand(-0.8, 0.8);
    leaf.flip = (Math.random() < 0.5 ? -1 : 1) * rand(0.55, 1);
    leaf.pushX = leaf.pushY = 0;
    bins[b].push(leaf);
    resting++;
    return true;
  }

  function tryLand(leaf) {
    for (const surface of surfaces) {
      if (leaf.x < surface.left + surface.inset || leaf.x > surface.right - surface.inset) continue;
      const b = clamp(Math.floor((leaf.x - surface.left) / BIN), 0, surface.bins.length - 1);
      if (surface.covered[b]) continue;
      const pileTop = surface.top - surface.bins[b].length * kind.rise;
      if (leaf.py <= pileTop + 1 && leaf.y >= pileTop) return settle(leaf, surface, b) ? 'gone' : 'moved';
    }
    return null;
  }

  function clearAll() {
    flying = [];
    resting = 0;
    for (const surface of surfaces) for (const bin of surface.bins) bin.length = 0;
  }

  // Start with the scene already settled, as if the app had been running for a while.
  function seed() {
    measure();
    const total = Math.round(kind.seed * clamp(width / 1400, 0.4, 1.4) * (reduceMotion.matches ? 1.3 : 1));
    for (let i = 0; i < total; i++) {
      const x = rand(0, width);
      let best = null, bestBin = 0;
      for (const surface of surfaces) {
        if (x < surface.left + surface.inset || x > surface.right - surface.inset || surface.top < 0) continue;
        const b = clamp(Math.floor((x - surface.left) / BIN), 0, surface.bins.length - 1);
        if (surface.covered[b]) continue;
        if (!best || surface.top < best.top) { best = surface; bestBin = b; }
      }
      if (best) settle(makeLeaf(x, best.top), best, bestBin);
    }
    // Wind carries plenty under the windows too, so the floor gets its own share.
    const floor = surfaces[surfaces.length - 1];
    for (let i = 0; i < Math.round(kind.floor * clamp(width / 1400, 0.4, 1.4)); i++) {
      const b = Math.floor(Math.random() * floor.bins.length);
      if (!floor.covered[b]) settle(makeLeaf(0, floor.top), floor, b);
    }
    flying = [];
    if (!reduceMotion.matches) {
      for (let i = 0; i < (season === 'winter' ? 90 : 34); i++) flying.push(makeLeaf(rand(0, width), rand(-20, height * 0.8)));
    }
  }

  // ---------- Weather ----------

  function startGust(direction) {
    gustDir = direction || (Math.random() < 0.5 ? -1 : 1);
    gustLeft = 2.6;
    windTarget = gustDir * rand(150, 230);
    nextGust = rand(11, 18);
  }

  function gustLift(count) {
    for (let i = 0; i < count; i++) {
      const surface = surfaces[Math.floor(Math.random() * surfaces.length)];
      const b = Math.floor(Math.random() * surface.bins.length);
      if (!surface.bins[b].length) continue;
      const leaf = lift(surface, b);
      leaf.pushX = gustDir * rand(150, 300);
      leaf.pushY = -rand(50, 150);
      leaf.noLand = 0.7;
    }
  }

  function weather(dt, time) {
    breeze = Math.sin(time * 0.23) * 14 + Math.sin(time * 0.071 + 1.3) * 9;
    if (gustLeft > 0) {
      gustLeft -= dt;
      const strength = season === 'winter' ? 0.012 : 0.025;
      gustLift(Math.floor(resting * strength * dt + Math.random()));
      if (gustLeft <= 0) windTarget = 0;
    } else if (!reduceMotion.matches) {
      nextGust -= dt;
      if (nextGust <= 0) startGust();
    }
    wind += (windTarget - wind) * Math.min(1, dt * 1.8);

    if (reduceMotion.matches) return;
    const fill = clamp(1 - resting / (kind.cap * clamp(width / 1400, 0.4, 1.4)), 0.12, 1);
    spawnDebt += kind.rate * clamp(width / 1400, 0.35, 1.5) * fill * dt;
    while (spawnDebt >= 1) {
      spawnDebt--;
      flying.push(makeLeaf(rand(-140, width + 140) - (wind + breeze) * 1.2, -24));
    }
  }

  // ---------- Cursor tools ----------

  function applyTool() {
    const speed = Math.hypot(pointer.vx, pointer.vy);
    if (!pointer.inside || drag || speed < 35) return;
    const ux = pointer.vx / speed, uy = pointer.vy / speed;
    const active = season === 'winter' && tool === 'blower' ? 'glove' : tool;
    const radius = active === 'glove' ? 24 : active === 'rake' ? 40 : 30;
    const reach = active === 'blower' ? 190 : radius;

    const hit = (x, y) => {
      const dx = x - pointer.x, dy = y - pointer.y;
      const distance = Math.hypot(dx, dy);
      if (distance < radius) return 1 - 0.4 * distance / radius;
      if (active === 'blower' && distance < reach && (dx * ux + dy * uy) / distance > 0.78) return 0.9 * (1 - distance / reach);
      return 0;
    };
    // A leaf lifted off a pile takes the full shove; one already in the air is steered towards it.
    const launch = (leaf, power, fresh) => {
      let tx, ty, hold;
      if (active === 'glove') {
        tx = pointer.vx * 0.32 + rand(-30, 30); ty = pointer.vy * 0.3 - rand(50, 120); hold = 0.25;
      } else if (active === 'rake') {
        tx = pointer.vx * 0.85 + rand(-15, 15); ty = Math.min(0, pointer.vy * 0.3) - rand(25, 60); hold = 0.12;
      } else {
        const force = (230 + speed * 0.5) * power;
        tx = ux * force + rand(-40, 40); ty = uy * force - rand(80, 170); hold = 0.5;
      }
      const size = Math.hypot(tx, ty);
      if (size > 900) { tx *= 900 / size; ty *= 900 / size; }
      const blend = fresh ? 1 : 0.22 * power;
      leaf.pushX += (tx - leaf.pushX) * blend;
      leaf.pushY += (ty - leaf.pushY) * blend;
      leaf.noLand = Math.max(leaf.noLand, hold);
    };

    for (const leaf of flying) {
      const power = hit(leaf.x, leaf.y);
      if (power) launch(leaf, power, false);
    }
    let budget = Math.round((active === 'blower' ? clamp(2 + speed / 110, 2, 16) : active === 'rake' ? 7 : 4)
      * (season === 'winter' ? 3 : 1));
    for (const surface of surfaces) {
      if (pointer.y < surface.top - surface.max - reach || pointer.y > surface.top + reach) continue;
      const from = clamp(Math.floor((pointer.x - reach - surface.left) / BIN), 0, surface.bins.length);
      const to = clamp(Math.ceil((pointer.x + reach - surface.left) / BIN), 0, surface.bins.length);
      for (let b = from; b < to && budget > 0; b++) {
        for (let pass = 0; pass < 2 && budget > 0; pass++) {
          const bin = surface.bins[b];
          if (!bin.length) break;
          const top = bin[bin.length - 1];
          const power = hit(surface.left + top.dx, surface.top - top.dy);
          if (!power) break;
          launch(lift(surface, b), power, true);
          budget--;
        }
      }
    }
  }

  // ---------- Simulation and drawing ----------

  function step(dt) {
    for (let i = flying.length - 1; i >= 0; i--) {
      const leaf = flying[i];
      leaf.px = leaf.x; leaf.py = leaf.y;
      leaf.swayPhase += leaf.swayRate * dt;
      leaf.flipPhase += leaf.flipRate * dt;
      leaf.rot += leaf.spin * dt;
      const turn = Math.cos(leaf.flipPhase);
      leaf.flip = (turn < 0 ? -1 : 1) * (0.3 + 0.7 * Math.abs(turn));
      const vy = leaf.fall + leaf.pushY;
      leaf.x += ((wind + breeze) * leaf.drift + Math.cos(leaf.swayPhase) * leaf.sway + leaf.pushX) * dt;
      leaf.y += vy * dt;
      const fade = Math.exp(-leaf.drag * dt);
      leaf.pushX *= fade; leaf.pushY *= fade;
      leaf.noLand -= dt;
      let gone = leaf.y > height + 40 || leaf.x < -220 || leaf.x > width + 220 || leaf.y < -600;
      if (!gone && vy > 0 && leaf.noLand <= 0) gone = tryLand(leaf) === 'gone';
      if (gone) { flying[i] = flying[flying.length - 1]; flying.pop(); }
    }
  }

  function drawLeaf(leaf, x, y) {
    if (leaf.flake) {
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      ctx.drawImage(flakeSprite, x - leaf.size / 2, y - leaf.size / 2, leaf.size, leaf.size);
      return;
    }
    const scale = leaf.size / SPRITE_LEAF * ratio;
    const cos = Math.cos(leaf.rot) * scale, sin = Math.sin(leaf.rot) * scale;
    ctx.setTransform(cos * leaf.flip, sin * leaf.flip, -sin, cos, x * ratio, y * ratio);
    ctx.drawImage(leaf.sprite, -SPRITE / 2, -SPRITE / 2, SPRITE, SPRITE);
  }

  function drawSnow(surface) {
    const bins = surface.bins, count = bins.length;
    let any = false;
    const heightAt = b => {
      let sum = 0, weight = 0;
      for (let k = -2; k <= 2; k++) {
        const j = b + k;
        if (j < 0 || j >= count) continue;
        const w = 3 - Math.abs(k);
        sum += bins[j].length * w; weight += w;
      }
      const edge = surface.spill ? Math.min(1, (Math.min(b, count - 1 - b) + 0.5) * BIN / 14) : 1;
      return sum / weight * kind.rise * edge;
    };
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.beginPath();
    ctx.moveTo(surface.left, surface.top + 1);
    for (let b = 0; b < count; b++) {
      const h = heightAt(b);
      if (h > 0.2) any = true;
      ctx.lineTo(surface.left + (b + 0.5) * BIN, surface.top - h);
    }
    ctx.lineTo(surface.right, surface.top + 1);
    ctx.closePath();
    if (!any) return;
    const shade = ctx.createLinearGradient(0, surface.top - surface.max, 0, surface.top);
    shade.addColorStop(0, '#ffffff');
    shade.addColorStop(1, '#d3e4f2');
    ctx.fillStyle = shade;
    ctx.shadowColor = 'rgba(10,30,60,0.25)';
    ctx.shadowBlur = 6;
    ctx.fill();
    ctx.shadowBlur = 0;
    ctx.shadowColor = 'transparent';
  }

  function draw() {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (const surface of surfaces) {
      if (surface.top < -60 || surface.top > height + 60) continue;
      if (season === 'winter') { drawSnow(surface); continue; }
      for (const bin of surface.bins) {
        for (const leaf of bin) drawLeaf(leaf, surface.left + leaf.dx, surface.top - leaf.dy);
      }
    }
    // Airborne leaves pass behind the windows and the Dock; only what has settled sits on top.
    ctx.save();
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    for (const surface of surfaces) {
      if (surface.type === 'floor') continue;
      ctx.beginPath();
      ctx.rect(0, 0, width, height);
      ctx.roundRect(surface.left, surface.top, surface.right - surface.left, surface.bottom - surface.top, surface.type === 'dock' ? 20 : 12);
      ctx.clip('evenodd');
    }
    for (const leaf of flying) drawLeaf(leaf, leaf.x, leaf.y);
    ctx.restore();

    // A quiet ring shows the tool's reach while the pointer is over the wallpaper.
    if (pointer.inside && !pointer.overUi && !drag && !stacked.matches) {
      const speed = Math.hypot(pointer.vx, pointer.vy);
      const active = season === 'winter' && tool === 'blower' ? 'glove' : tool;
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = 'rgba(255,255,255,0.5)';
      ctx.beginPath();
      ctx.arc(pointer.x, pointer.y, active === 'glove' ? 24 : active === 'rake' ? 40 : 30, 0, 6.2832);
      ctx.stroke();
      if (active === 'blower' && speed > 120) {
        const ux = pointer.vx / speed, uy = pointer.vy / speed;
        ctx.lineCap = 'round';
        for (let i = -1; i <= 1; i++) {
          const ox = -uy * i * 16, oy = ux * i * 16;
          const length = clamp(speed * 0.12, 30, 150) * (i ? 0.7 : 1);
          ctx.strokeStyle = `rgba(255,255,255,${i ? 0.22 : 0.38})`;
          ctx.beginPath();
          ctx.moveTo(pointer.x + ux * 38 + ox, pointer.y + uy * 38 + oy);
          ctx.lineTo(pointer.x + ux * (38 + length) + ox * 1.6, pointer.y + uy * (38 + length) + oy * 1.6);
          ctx.stroke();
        }
      }
    }
  }

  function frame(now) {
    const dt = clamp((now - last) / 1000 || 0.016, 0.001, 0.05);
    last = now;
    measure();
    weather(dt, now / 1000);
    applyTool();
    if (drag && Math.hypot(drag.vx, drag.vy) > 1300) {   // a hard shake throws some of the pile off
      const surface = surfaces.find(s => s.el === drag.el);
      for (let i = 0; i < 5 && surface; i++) {
        const b = Math.floor(Math.random() * surface.bins.length);
        if (!surface.bins[b].length) continue;
        const leaf = lift(surface, b);
        leaf.pushX = -drag.vx * 0.25 + rand(-60, 60); leaf.pushY = -rand(60, 160); leaf.noLand = 0.6;
      }
    }
    const ease = Math.exp(-9 * dt);
    pointer.vx *= ease; pointer.vy *= ease;
    if (drag) { drag.vx *= ease; drag.vy *= ease; }
    step(dt);
    draw();
    requestAnimationFrame(frame);
  }

  function resize() {
    ratio = Math.min(2, window.devicePixelRatio || 1);
    width = window.innerWidth; height = window.innerHeight;
    canvas.width = Math.round(width * ratio); canvas.height = Math.round(height * ratio);
  }

  // ---------- Controls ----------

  function setTool(next) {
    tool = season === 'winter' && next === 'blower' ? 'glove' : next;
    document.body.dataset.tool = tool;
    for (const button of $$('[data-tool]')) {
      if (button.matches('body *')) button.setAttribute(button.hasAttribute('aria-pressed') ? 'aria-pressed' : 'aria-checked', String(button.dataset.tool === tool));
    }
    $('#tool-hint').textContent = HINTS[season][tool];
  }

  function setSeason(next, keep) {
    mode = next;
    const today = calendar();
    season = mode === 'auto' ? today.season : mode;
    leafAge = today.season === 'fall' ? today.age : 0.6;
    kind = KIND[season];
    document.body.dataset.season = season;
    $('meta[name="theme-color"]').content = season === 'winter' ? '#0e2540' : '#6d92b7';
    for (const button of $$('[data-season]:not(body)')) {
      button.setAttribute(button.hasAttribute('aria-pressed') ? 'aria-pressed' : 'aria-checked', String(button.dataset.season === mode));
    }
    setTool(tool);
    if (!keep) { clearAll(); seed(); }
    try { localStorage.setItem('seasons.mode', mode); } catch { /* private browsing */ }
  }

  function closeMenus(except) {
    for (const title of $$('.menu-title')) {
      if (title === except) continue;
      title.setAttribute('aria-expanded', 'false');
      $('#' + title.getAttribute('aria-controls')).hidden = true;
    }
  }

  function wire() {
    for (const title of $$('.menu-title')) {
      title.addEventListener('click', event => {
        event.stopPropagation();
        const list = $('#' + title.getAttribute('aria-controls'));
        closeMenus(title);
        list.hidden = !list.hidden;
        title.setAttribute('aria-expanded', String(!list.hidden));
      });
    }
    document.addEventListener('click', () => closeMenus());
    document.addEventListener('keydown', event => { if (event.key === 'Escape') closeMenus(); });
    for (const button of $$('button[data-season]')) button.addEventListener('click', () => setSeason(button.dataset.season));
    for (const button of $$('button[data-tool]')) button.addEventListener('click', () => setTool(button.dataset.tool));
    for (const id of ['#gust', '#dock-gust']) $(id).addEventListener('click', () => startGust());
    $('#clear').addEventListener('click', () => clearAll());
    $('#dock-tidy').addEventListener('click', () => {
      for (const win of $$('.win')) { win.style.left = ''; win.style.top = ''; }
      front($('#win-about'));
    });

    // Dragging a window by its title bar.
    for (const bar of $$('[data-drag]')) {
      const win = bar.closest('.win');
      bar.addEventListener('pointerdown', event => {
        if (stacked.matches || event.button !== 0) return;
        const box = win.getBoundingClientRect();
        const origin = $('#desktop').getBoundingClientRect();
        drag = { el: win, dx: event.clientX - box.left, dy: event.clientY - box.top, ox: origin.left, oy: origin.top,
          x: event.clientX, y: event.clientY, t: event.timeStamp, vx: 0, vy: 0, w: box.width };
        bar.setPointerCapture(event.pointerId);
        win.classList.add('dragging');
        event.preventDefault();
      });
      bar.addEventListener('pointermove', event => {
        if (!drag || drag.el !== win) return;
        const elapsed = Math.max(4, event.timeStamp - drag.t) / 1000;
        drag.vx += ((event.clientX - drag.x) / elapsed - drag.vx) * 0.5;
        drag.vy += ((event.clientY - drag.y) / elapsed - drag.vy) * 0.5;
        drag.x = event.clientX; drag.y = event.clientY; drag.t = event.timeStamp;
        const left = clamp(event.clientX - drag.dx, 70 - drag.w, width - 70);
        const top = clamp(event.clientY - drag.dy, origin(), height - 60);
        win.style.left = `${left - drag.ox}px`;
        win.style.top = `${top - drag.oy}px`;
      });
      const release = () => { if (drag && drag.el === win) { win.classList.remove('dragging'); drag = null; } };
      bar.addEventListener('pointerup', release);
      bar.addEventListener('pointercancel', release);
    }
    for (const win of $$('.win')) win.addEventListener('pointerdown', () => front(win), true);

    window.addEventListener('pointermove', event => {
      const elapsed = Math.max(4, event.timeStamp - pointer.t) / 1000;
      if (pointer.inside && elapsed < 0.2) {
        pointer.vx += ((event.clientX - pointer.x) / elapsed - pointer.vx) * 0.5;
        pointer.vy += ((event.clientY - pointer.y) / elapsed - pointer.vy) * 0.5;
      }
      pointer.x = event.clientX; pointer.y = event.clientY; pointer.t = event.timeStamp;
      pointer.inside = event.clientY > origin();
      pointer.overUi = !!(event.target.closest && event.target.closest('.win, .dock, .menubar'));
    }, { passive: true });
    document.addEventListener('pointerleave', () => { pointer.inside = false; });
    window.addEventListener('blur', () => { pointer.inside = false; });

    // A phone's address bar hiding changes the height alone, and the piles should survive that.
    // Only a new width, which changes the floor and may restack the windows, starts over.
    let resizeTimer = 0;
    window.addEventListener('resize', () => {
      const oldWidth = width, oldRatio = ratio;
      resize();
      if (ratio !== oldRatio) buildSprites();
      if (width === oldWidth) return;
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        for (const win of $$('.win')) { win.style.left = ''; win.style.top = ''; }   // back on screen
        clearAll();
        seed();
      }, 120);
    });
    reduceMotion.addEventListener('change', () => { clearAll(); seed(); });
  }

  const origin = () => $('.menubar').getBoundingClientRect().bottom;

  // Windows are renumbered each time one comes forward, so the order never climbs past the
  // Dock, the leaf canvas or the menu bar however long the page stays open.
  function front(win) {
    const depth = el => parseInt(el.style.zIndex, 10) || 10;
    const order = $$('.win').filter(other => other !== win).sort((a, b) => depth(a) - depth(b));
    order.push(win);
    order.forEach((el, index) => {
      el.style.zIndex = String(20 + index);
      el.classList.toggle('front', el === win);
    });
  }

  function clock() {
    const format = new Intl.DateTimeFormat(undefined, { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    const tick = () => { $('#clock').textContent = format.format(new Date()); };
    tick();
    setInterval(tick, 20000);
  }

  function start() {
    // A Mac download makes no sense on a phone or a PC; say so instead of handing over a file.
    const onMac = /Mac/.test(navigator.platform || navigator.userAgent) && (navigator.maxTouchPoints || 0) < 2;
    if (!onMac) $('#download-meta').textContent = 'Seasons is a Mac app. Open this page on your Mac to get it.';

    resize();
    buildSprites();
    surfaces = [...$$('.win').map(el => makeSurface(el, 'win')), makeSurface($('.dock'), 'dock'), makeSurface(null, 'floor')];
    wire();
    clock();
    front($('#win-about'));
    let saved = 'auto';
    try { saved = localStorage.getItem('seasons.mode') || 'auto'; } catch { /* private browsing */ }
    setSeason(['auto', 'fall', 'winter'].includes(saved) ? saved : 'auto');
    window.seasonsDebug = () => ({ season, mode, tool, flying: flying.length, resting, wind: Math.round(wind),
      pointer: { ...pointer }, dragging: !!drag });
    requestAnimationFrame(now => { last = now; requestAnimationFrame(frame); });
  }

  start();
})();
