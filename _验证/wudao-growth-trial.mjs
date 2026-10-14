import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { gear, defs, simulate, rng } from './wudao-balance.mjs';
import { state, maxHp, changeHp, apply, buy, refresh, combat, enterBag, sell, equipmentPrices, bagSpace, tests } from './wudao-growth-economy.mjs';
const input = JSON.parse(readFileSync(new URL('./wudao-stage-one-results.json', import.meta.url), 'utf8'));
const enemies = stage => ({
  road: { hp: [108, 320, 720][stage], items: gear('blade mirror', stage), skills: { fervor: stage + 1 } },
  chief: { hp: [192, 800, 1700][stage], items: [...gear('hammer', stage + 1), ...gear('dagger mirror', stage)], skills: { fervor: stage + 1 } },
  opponent: { hp: [600, 1600, 3500][stage], items: gear('blade hammer dagger mirror shield', stage), skills: { fervor: stage + 1 } },
});
function trial(route, seed, policy) {
  const source = input.ledgers.find(x => x.name === route), s = state(0, source.money);
  s.items = source.equipped.map(x => ({ id: x.id, quality: x.q }));
  s.bag = source.bag.map(x => ({ id: x.id, quality: x.q }));
  s.points = source.points; s.blood.species = route === 'main' ? 1 : route === 'normal' ? 2 : 3;
  const random = rng(Math.imul(seed, 2654435761) >>> 0), log = []; let defeats = 0;
  const fieldSpace = () => s.items.reduce((sum, x) => sum + defs[x.id].size, 0);
  const note = (action, extra = {}) => {
    assert(s.money >= 0 && s.points >= 0 && fieldSpace() <= 10 && bagSpace(s) <= 10);
    log.push({ stage: s.stage + 1, action, money: s.money, points: s.points, hp: s.hp, maxHp: maxHp(s), bag: bagSpace(s), field: fieldSpace(), ...extra });
  };
  const sellOld = () => {
    for (let i = s.bag.length - 1; i >= 0; i--) {
      if (defs[s.bag[i].id]) { assert(sell(s, i)); note('sell old equipment at hub'); }
      else if (s.bag[i].id === 'mineral') { s.money += 4; s.bag.splice(i, 1); note('sell carried mineral'); }
    }
  };
  const acquire = (entry, price = 0) => {
    if (s.money < price || !enterBag(s, entry)) return false;
    s.money -= price; note('acquire item via bag', { id: entry.id, quality: entry.quality, price });
    const i = s.bag.findIndex(x => x.id === entry.id && x.quality >= entry.quality);
    const item = s.bag[i], current = s.items.findIndex(x => x.id === item.id);
    if (current >= 0 && s.items[current].quality < item.quality) {
      const before = structuredClone(s);
      const incoming = s.bag.splice(i, 1)[0], outgoing = s.items[current];
      if (!enterBag(s, outgoing)) { Object.assign(s, before); return true; }
      s.items[current] = incoming; note('equip replacement; old growth stays on old item');
    } else if (current < 0 && fieldSpace() + defs[item.id].size <= 10) { s.items.push(s.bag.splice(i, 1)[0]); note('equip new item'); }
    return true;
  };
  const fight = (enemy, label) => {
    const config = { ...enemy, effectScale: [3, 5, 8][s.stage], stormScale: [2, 4, 8][s.stage] };
    while (true) {
      const r = simulate(combat(s), config, seed, 1200);
      s.hp = r.playerHp; note(label, { winner: r.winner, seconds: r.seconds });
      if (r.winner === 'player') return true;
      defeats++; if (defeats === 3) return false;
      s.hp = maxHp(s); note('defeat recovery; no income or stock reset', { defeats });
    }
  };
  const consumeHub = () => {
    const generate = () => Array.from({ length: 3 }, () => ({ id: ['vitality', 'edge', 'bloodHp', 'bloodToxin'][Math.floor(random() * 4)], stage: s.stage }));
    const shop = { stock: generate(), refreshes: 0, locked: false }; s.shops.consumables = shop;
    const wanted = () => maxHp(s) < [650, 1300, 2300][s.stage] ? ['vitality', 'bloodHp'] : policy === 'weapon' ? ['edge'] : s.items.some(x => x.id === 'needle') ? ['bloodToxin'] : [];
    for (let batch = 0; batch < 4; batch++) {
      if (!wanted().length) break;
      for (let i = 0; i < shop.stock.length; i++) if (wanted().includes(shop.stock[i]?.id)) {
        const id = shop.stock[i].id;
        const target = s.items.findIndex(x => x.id === (policy === 'weapon' ? 'dagger' : 'needle'));
        if (id === 'bloodToxin' && target < 0) continue;
        if (buy(s, shop, i)) { assert(apply(s, s.bag.length - 1, Math.max(0, target))); note('buy and use growth consumable', { id }); }
      }
      if (!wanted().length) break;
      const minimum = wanted().includes('edge') ? [10, 18, 30][s.stage] : [16, 28, 44][s.stage];
      if (batch === 3 || s.money < (s.stage + 3) * (shop.refreshes + 1) + minimum || !refresh(s, shop, generate)) break;
      note('paid increasing refresh', { count: shop.refreshes });
    }
  };
  for (let stage = 0; stage < 3; stage++) {
    s.stage = stage;
    if (stage > 0) {
      acquire({ id: 'blade', quality: stage + 1 }, equipmentPrices[2][stage + 1]);
      if (s.hp < maxHp(s) * 0.8 && s.bag.some(x => x.id === 'recovery')) {
        s.bag.splice(s.bag.findIndex(x => x.id === 'recovery'), 1);
        s.hp = Math.min(maxHp(s), s.hp + 30); note('consume old carried recovery at its original value');
      }
      // Two fixed supplemental recovery offers; no free healing on world entry.
      for (let i = 0; i < 2 && s.hp < maxHp(s) * 0.8 && s.money >= [6, 8, 10][stage] && bagSpace(s) < 10; i++) {
        s.money -= [6, 8, 10][stage]; s.bag.push({ id: 'recovery', stage }); note('buy recovery');
        s.hp = Math.min(maxHp(s), s.hp + [150, 350, 700][stage]); s.bag.pop(); note('consume recovery');
      }
      if (!fight(enemies(stage).road, 'world road')) return { route, seed, policy, success: false, defeats, log };
      s.money += [6, 8, 10][stage]; note('road victory income');
      if (!fight(enemies(stage).chief, 'world chief')) return { route, seed, policy, success: false, defeats, log };
      s.money += [12, 18, 26][stage] + [24, 32, 40][stage] + (route === 'main' ? 0 : [12, 16, 20][stage]);
      s.points += [4, 6, 8][stage] + (route === 'main' ? 0 : 2); note('fixed completed quest incomes');
      for (const id of ['mirror', 'dagger']) acquire({ id, quality: stage + 1 });
      acquire({ id: 'medicine', quality: stage });
    }
    sellOld();
    if (policy === 'weapon' && stage === 0 && !s.items.some(x => x.id === 'hammer')) {
      const shield = s.items.findIndex(x => x.id === 'shield');
      if (shield >= 0 && enterBag(s, s.items[shield])) { s.items.splice(shield, 1); sellOld(); }
      acquire({ id: 'hammer', quality: 1 }, 22);
      if (!s.items.some(x => x.id === 'medicine')) acquire({ id: 'medicine', quality: 1 }, 16);
    }
    if (policy === 'weapon' && stage > 0 && s.items.some(x => x.id === 'hammer' && x.quality < stage + 1)) {
      acquire({ id: 'hammer', quality: stage + 1 }, equipmentPrices[3][stage + 1]);
      sellOld();
    }
    const rankPrice = [4, 6, 8][s.blood.rank];
    if (s.blood.rank <= stage && s.points >= rankPrice) {
      s.points -= rankPrice; changeHp(s, () => { s.blood.rank++; }); note('pay points for blood progression');
    }
    consumeHub(); s.hp = maxHp(s); note('hub explicit free treatment');
    if (!fight(enemies(stage).opponent, 'stage opponent')) return { route, seed, policy, success: false, defeats, log };
  }
  note('complete; third opponent gives no rewards');
  return { route, seed, policy, success: true, defeats, log };
}
tests(); const summaries = [], examples = [];
for (const route of ['main', 'normal', 'deep']) for (const policy of ['weapon', 'toxin']) {
  const rows = Array.from({ length: 100 }, (_, i) => trial(route, i + 1, policy));
  summaries.push({ route, policy, trials: rows.length, completed: rows.filter(x => x.success).length, meanFinalMoney: rows.reduce((sum, x) => sum + x.log.at(-1).money, 0) / 100,
    meanFinalMaxHp: rows.reduce((sum, x) => sum + x.log.at(-1).maxHp, 0) / 100, failures: Object.fromEntries([1, 2, 3].map(stage => [stage, rows.filter(x => !x.success && x.log.at(-1).stage === stage).length])) });
  examples.push(...rows.slice(0, 2));
}
const output = { date: '2026-10-14', scope: '600 conditional continuous trials starting at fixed world-one return, fixed later equipment/quest opportunities and random hub consumables; no full world generation, optional quest path validation, class or control. Failed attempts retry identical builds. Never re-equips blood.', summaries, examples };
if (process.argv.includes('--write')) writeFileSync(new URL('./wudao-growth-trial-results.json', import.meta.url), JSON.stringify(output, null, 2) + '\n');
console.log(JSON.stringify(summaries, null, 2));
