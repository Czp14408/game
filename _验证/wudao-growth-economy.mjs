import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { gear, defs, simulate, rng, checks } from './wudao-balance.mjs';

const products = {
  vitality: { price: [18, 30, 48], value: [100, 250, 500] },
  edge: { price: [10, 18, 30], value: [2, 5, 10] },
  bloodHp: { price: [16, 28, 44], value: [100, 250, 500] },
  bloodToxin: { price: [16, 28, 44], value: [1, 2, 3] },
};
function state(stage = 0, money = 100) {
  return { stage, money, baseHp: 300, roleHp: 0, hp: 450, bloodActive: true,
    blood: { rank: 0, hp: 0, toxin: 0, species: 3 }, items: gear('blade dagger mirror shield medicine'), bag: [], shops: {}, log: [] };
}
const maxHp = s => s.baseHp + s.roleHp + (s.bloodActive ? [150, 350, 750, 1500][s.blood.rank] + s.blood.hp : 0);
function changeHp(s, operation, newGrowth = true) {
  const before = maxHp(s); operation(); const after = maxHp(s);
  s.hp = newGrowth && after > before ? Math.min(after, s.hp + after - before) : Math.min(after, s.hp);
}
function apply(s, index, target = 0) {
  const entry = s.bag[index]; if (!entry || !products[entry.id]) return false;
  const value = products[entry.id].value[entry.stage];
  if (entry.id === 'edge') {
    const item = s.items[target]; if (!item || !defs[item.id].weapon || !defs[item.id].attack) return false;
    item.permanentAttack = (item.permanentAttack ?? 0) + value;
  } else if (entry.id.startsWith('blood') && !s.bloodActive) return false;
  else if (entry.id === 'vitality') changeHp(s, () => { s.roleHp += value; });
  else if (entry.id === 'bloodHp') changeHp(s, () => { s.blood.hp += value; });
  else s.blood.toxin += value;
  s.bag.splice(index, 1); return true;
}
const bagSpace = s => s.bag.reduce((sum, x) => sum + (defs[x.id]?.size ?? 1), 0);
const equipmentPrices = { 1: [6, 10, 16, 24], 2: [10, 16, 26, 40], 3: [14, 22, 36, 56] };
function enterBag(s, incoming) {
  const bag = structuredClone(s.bag); let entry = structuredClone(incoming);
  if (defs[entry.id]) while (entry.quality < 3) {
    const match = bag.findIndex(x => x.id === entry.id && x.quality === entry.quality);
    if (match < 0) break;
    const previous = bag[match];
    entry = { ...entry, quality: entry.quality + 1, permanentAttack: (entry.permanentAttack ?? 0) + (previous.permanentAttack ?? 0) };
    // The product occupies the matching item's position, including chained merges.
    bag.splice(match, 1); entry.position = match;
  }
  if (entry.position !== undefined) { const position = entry.position; delete entry.position; bag.splice(position, 0, entry); }
  else bag.push(entry);
  if (bagSpace({ bag }) > 10) return false;
  s.bag = bag; return true;
}
function sell(s, index) {
  const entry = s.bag[index]; if (!entry) return false;
  const price = defs[entry.id] ? equipmentPrices[defs[entry.id].size][entry.quality] : products[entry.id]?.price[entry.stage];
  if (price === undefined) return false;
  s.money += price / 2; s.bag.splice(index, 1); return true;
}
function upgrade(s, index) {
  const item = s.items[index];
  if (!item || !defs[item.id] || item.quality >= Math.min(3, s.stage + 1)) return false;
  item.quality++; return true;
}
function buy(s, shop, index) {
  const entry = shop.stock[index]; if (!entry || bagSpace(s) >= 10) return false;
  const price = products[entry.id].price[entry.stage]; if (s.money < price) return false;
  s.money -= price; s.bag.push({ ...entry }); shop.stock[index] = null; return true;
}
function refresh(s, shop, generate) {
  const price = (s.stage + 3) * (shop.refreshes + 1);
  if (shop.locked || s.money < price) return false;
  const stock = generate(); s.money -= price; shop.refreshes++; shop.stock = stock; return true;
}
function combat(s, items = s.items) {
  return { hp: maxHp(s), currentHp: s.hp, items, effectScale: [3, 5, 8][s.stage], stormScale: [2, 4, 8][s.stage],
    skills: { fervor: s.stage + 2, restorative: 2 },
    blood: { lifesteal: s.bloodActive ? [0.1, 0.15, 0.25, 0.35][s.blood.rank] : 0, toxinBonus: s.bloodActive ? s.blood.species * (s.blood.rank + 1) + s.blood.toxin : 0 } };
}
function tests() {
  checks(); const s = state(); s.hp = 50;
  s.bag.push({ id: 'vitality', stage: 0 }); assert(apply(s, 0)); assert.equal(s.hp, 150); assert.equal(maxHp(s), 550);
  s.bag.push({ id: 'bloodHp', stage: 1 }); assert(apply(s, 0)); assert.equal(maxHp(s), 800);
  // Numeric boundary fixtures, not legal unequip/re-equip actions in the current version.
  changeHp(s, () => { s.bloodActive = false; }, false); assert.equal(maxHp(s), 400); assert.equal(s.hp, 400);
  s.bag.push({ id: 'bloodToxin', stage: 0 }); assert.equal(apply(s, 0), false); assert.equal(s.bag.length, 1);
  changeHp(s, () => { s.bloodActive = true; }, false); assert.equal(maxHp(s), 800); assert.equal(s.hp, 400);
  assert(apply(s, 0)); changeHp(s, () => { s.blood.rank = 1; }); assert.equal(combat(s).blood.toxinBonus, 7);
  const t = state(); t.bag.push({ id: 'edge', stage: 0 }); assert.equal(apply(t, 0, 2), false); assert.equal(t.bag.length, 1);
  assert(apply(t, 0, 1)); assert.equal(t.items[1].permanentAttack, 2);
  const a = simulate(combat(t), { hp: 1e9, items: [] }, 1, 20, false);
  const b = simulate(combat(t), { hp: 1e9, items: [] }, 1, 20, false);
  assert.equal(a.attack, b.attack); assert.equal(t.items[1].permanentAttack, 2);
  const shop = { stock: [{ id: 'vitality', stage: 0 }], refreshes: 0, locked: false };
  t.money = 18; assert(buy(t, shop, 0)); assert.equal(t.money, 0); assert.equal(shop.stock[0], null);
  assert.equal(refresh(t, shop, () => []), false); assert.equal(shop.refreshes, 0);
  t.money = 100; shop.locked = true; assert.equal(refresh(t, shop, () => []), false); assert.equal(t.money, 100);
  shop.locked = false; for (let i = 0; i < 4; i++) assert(refresh(t, shop, () => [])); assert.equal(t.money, 70);
  const full = state(); full.bag = Array.from({ length: 10 }, () => ({ id: 'material' }));
  const stock = { stock: [{ id: 'edge', stage: 0 }] }; assert.equal(buy(full, stock, 0), false); assert.equal(full.money, 100);
  const merged = state(); merged.items = [];
  merged.bag = [...Array.from({ length: 9 }, () => ({ id: 'material' })), { id: 'dagger', quality: 0, permanentAttack: 2 }];
  assert(enterBag(merged, { id: 'dagger', quality: 0, permanentAttack: 3 }));
  assert.equal(bagSpace(merged), 10); assert.equal(merged.bag[9].quality, 1); assert.equal(merged.bag[9].permanentAttack, 5);
  const before = structuredClone(merged.bag); assert.equal(enterBag(merged, { id: 'hammer', quality: 0 }), false); assert.deepEqual(merged.bag, before);
  merged.money = 0; assert(sell(merged, 9)); assert.equal(merged.money, 5);
  const upgraded = state(); upgraded.items[1].permanentAttack = 5; assert(upgrade(upgraded, 1)); assert.equal(upgraded.items[1].permanentAttack, 5);
  assert.equal(upgrade(upgraded, 1), false);
  return '39 existing combat checks plus growth/inventory/refresh assertions passed';
}
function sample(stage, seed, policy) {
  const random = rng(Math.imul(seed, 2654435761) >>> 0), s = state(stage, [48, 100, 180][stage]);
  s.blood.rank = stage; s.hp = maxHp(s); s.items = gear(['toxin', 'mixed'].includes(policy) ? 'blade needle needle mirror shield medicine' : 'blade dagger mirror hammer medicine', stage + 1);
  const initialMoney = s.money;
  const generate = () => Array.from({ length: 3 }, () => ({ id: Object.keys(products)[Math.floor(random() * 4)], stage }));
  const shop = { stock: generate(), refreshes: 0, locked: false }; const purchases = [];
  const wanted = () => policy === 'mixed' ? (maxHp(s) < [550, 1000, 1600][stage] ? ['vitality', 'bloodHp'] : ['bloodToxin']) : policy === 'weapon' ? ['edge'] : policy === 'toxin' ? ['bloodToxin'] : ['vitality', 'bloodHp'];
  for (let turn = 0; turn < 5; turn++) {
    for (let i = 0; i < shop.stock.length; i++) {
      const id = shop.stock[i]?.id;
      if (!wanted().includes(id)) continue;
      if (buy(s, shop, i)) { assert(apply(s, s.bag.length - 1, 1)); purchases.push(id); }
    }
    const cheapest = Math.min(...wanted().map(id => products[id].price[stage]));
    const nextRefresh = (stage + 3) * (shop.refreshes + 1);
    if (turn === 4 || s.money < nextRefresh + cheapest || !refresh(s, shop, generate)) break;
  }
  s.hp = maxHp(s);
  const enemy = { hp: [600, 1600, 3500][stage], items: gear('blade hammer dagger mirror shield', stage), skills: { fervor: stage + 1 }, effectScale: [3, 5, 8][stage], stormScale: [2, 4, 8][stage] };
  const r = simulate(combat(s), enemy, seed, 1200);
  return { seed, policy, stage, initialMoney, money: s.money, maxHp: maxHp(s), refreshes: shop.refreshes, purchases, permanentAttack: s.items[1].permanentAttack ?? 0, toxinBonus: combat(s).blood.toxinBonus, winner: r.winner, seconds: r.seconds, hp: r.playerHp };
}
export { state, maxHp, apply, changeHp, buy, refresh, combat, tests, products, enterBag, sell, upgrade, equipmentPrices, bagSpace };
if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  const validation = tests(), summaries = [], examples = [];
  for (let stage = 0; stage < 3; stage++) for (const policy of ['health', 'weapon', 'toxin', 'mixed']) {
    const rows = Array.from({ length: 100 }, (_, i) => sample(stage, i + 1, policy));
    summaries.push({ stage: stage + 1, policy, wins: rows.filter(x => x.winner === 'player').length, meanMoney: rows.reduce((a, x) => a + x.money, 0) / 100, meanHp: rows.reduce((a, x) => a + x.maxHp, 0) / 100, meanRefreshes: rows.reduce((a, x) => a + x.refreshes, 0) / 100 }); examples.push(...rows.slice(0, 3));
  }
  const out = { date: '2026-10-14', validation, scope: 'Twelve isolated hub policy samples, 100 seeds each; not an entire trial. Changed HP/effects/storm are experiment inputs, no optimum purchase search, class or control.', summaries, examples };
  if (process.argv.includes('--write')) writeFileSync(new URL('./wudao-growth-economy-results.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
  console.log(JSON.stringify(out, null, 2));
}
