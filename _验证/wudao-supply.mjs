import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { actor, gear, simulate, checks, defs, rng } from './wudao-balance.mjs';

const pool = ['dagger', 'blade', 'hammer', 'shield', 'mirror', 'medicine', 'tassel', 'stone', 'needle'];
const skillPool = ['fervor', 'restorative', 'edge'];
const guard = { hp: 36, items: gear('blade mirror'), skills: { fervor: 1 } };
const chief = { hp: 64, items: [...gear('hammer', 1), ...gear('dagger mirror')], skills: { fervor: 1 } };
const prices = { 1: [6, 10], 2: [10, 16], 3: [14, 22] };
const skillValues = { fervor: [1, 2, 3, 4], restorative: [2, 3, 5, 8], edge: [0.02, 0.04, 0.06, 0.08] };
function inventory(random, kind) {
  return Array.from({ length: kind === 'gear' ? 4 : 2 }, () => {
    const quality = random() < 0.8 ? 0 : 1;
    const candidates = kind === 'gear' ? [...pool, ...(quality === 1 ? ['charged'] : [])] : skillPool;
    const id = candidates[Math.floor(random() * candidates.length)];
    return { id, quality, kind, price: kind === 'gear' ? prices[defs[id].size][quality] : [12, 20][quality] };
  });
}
function learned(skills, id, q) {
  const out = { ...skills };
  if (out[id] === q && q < 3) out[id]++;
  else out[id] = Math.max(out[id] ?? -1, q);
  return out;
}
const effects = qualities => Object.fromEntries(Object.entries(qualities).map(([id, q]) => [id, skillValues[id][q]]));
// Only current revealed inventory and current visible enemy are searched, never future rewards.
function choose(state, stock, enemy, recoveries = 0) {
  let best = null;
  for (let mask = 0; mask < 2 ** stock.length; mask++) {
    let cost = 0, items = [...state.items], skills = { ...state.skills };
    for (let j = 0; j < stock.length; j++) if (mask & (1 << j)) {
      const entry = stock[j]; cost += entry.price;
      if (entry.kind === 'gear') items.push({ id: entry.id, quality: entry.quality });
      else skills = learned(skills, entry.id, entry.quality);
    }
    if (items.reduce((sum, item) => sum + defs[item.id].size, 0) > 10) continue;
    for (let heals = 0; heals <= recoveries; heals++) {
      const spent = cost + heals * 6;
      if (spent > state.money) continue;
      const predicted = [7, 19, 37].map(seed => simulate({ items, skills: effects(skills), currentHp: Math.min(100, state.hp + heals * 30) }, enemy, seed));
      if (predicted.some(result => result.winner !== 'player')) continue;
      const result = predicted.reduce((worst, next) => next.playerHp < worst.playerHp ? next : worst);
      // Conserve cash first; survivor HP and speed only break equal-cost ties.
      if (!best || spent < best.spent || spent === best.spent && (result.playerHp > best.result.playerHp || result.playerHp === best.result.playerHp && result.seconds < best.result.seconds)) {
        best = { spent, items, skills, result, stock: stock.filter((_, j) => !(mask & (1 << j))), heals };
      }
    }
  }
  return best;
}
function sample(seed, refreshCap, forceMaterials = false) {
  const random = rng(Math.imul(seed, 2654435761) >>> 0);
  let gearStock = inventory(random, 'gear'), skillStock = inventory(random, 'skill');
  const state = { items: gear('blade'), skills: {}, money: 30, hp: 100 };
  const initialStock = [...gearStock, ...skillStock];
  let refreshes = 0, spent = 0;
  const fight = (enemy, recoveries) => {
    let option = choose(state, [...gearStock, ...skillStock], enemy, recoveries);
    while (!option && refreshes < refreshCap && state.money >= 3) {
      // Alternate gear/skill shop; refreshing one never resets the other.
      state.money -= 3; spent += 3;
      if (refreshes % 2 === 0) gearStock = inventory(random, 'gear');
      else skillStock = inventory(random, 'skill');
      refreshes++;
      option = choose(state, [...gearStock, ...skillStock], enemy, recoveries);
    }
    if (!option) return false;
    assert(option.spent <= state.money);
    const actual = simulate({ items: option.items, skills: effects(option.skills), currentHp: Math.min(100, state.hp + option.heals * 30) }, enemy, seed);
    state.money -= option.spent; spent += option.spent;
    state.items = option.items; state.skills = option.skills; state.hp = actual.playerHp;
    gearStock = option.stock.filter(x => x.kind === 'gear'); skillStock = option.stock.filter(x => x.kind === 'skill');
    assert(actor({ items: state.items }).size <= 10);
    return actual.winner === 'player';
  };
  if (!fight(guard, 0)) return { seed, failedAt: 'guard', money: state.money, refreshes, spent, initialStock };
  state.money += 6;
  const drop = forceMaterials || random() >= 0.7 ? 'material' : ['blade', 'mirror', 'fervor'][Math.floor(random() * 3)];
  let bag = 0;
  if (drop === 'material') state.money += 4;
  else if (drop === 'fervor') state.skills = learned(state.skills, 'fervor', 0);
  else if (state.items.reduce((sum, x) => sum + defs[x.id].size, 0) + defs[drop].size <= 10) state.items.push({ id: drop, quality: 0 });
  else bag += defs[drop].size;
  if (!fight(chief, 2)) return { seed, failedAt: 'chief', money: state.money, refreshes, spent, initialStock, drop, bag };
  state.money += 12 + 24;
  // Boss rewards are not read or credited until after the challenge has been won.
  return { seed, failedAt: null, money: state.money, hp: state.hp, refreshes, spent, initialStock, drop, bag, items: state.items, skills: state.skills };
}
const summaries = [];
const examples = [];
checks();
for (const forceMaterials of [false, true]) for (const refreshCap of [0, 2, 4]) {
  const rows = Array.from({ length: 200 }, (_, i) => sample(i + 1, refreshCap, forceMaterials));
  summaries.push({ forceMaterials, refreshCap, samples: rows.length, success: rows.filter(x => !x.failedAt).length,
    guardBlocked: rows.filter(x => x.failedAt === 'guard').length, chiefBlocked: rows.filter(x => x.failedAt === 'chief').length,
    meanRefreshes: rows.reduce((sum, x) => sum + x.refreshes, 0) / rows.length,
    meanSpent: rows.reduce((sum, x) => sum + x.spent, 0) / rows.length });
  examples.push({ forceMaterials, refreshCap, failed: rows.find(x => x.failedAt), successful: rows.find(x => !x.failedAt) });
}
const out = { date: '2026-10-14', scope: 'Main route only; visible-purchase search evaluated on fixed prediction seeds 7/19/37, actual battle seed is not used for purchase selection. No equipment swaps, backpack merging, retries, optional branches, blood or class. Success is policy/model conditional, not human win rate.', guard, chief, pool, prices, skillPool, skillValues, summaries, examples };
if (process.argv.includes('--write')) writeFileSync(new URL('./wudao-supply-results.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify(summaries, null, 2));
