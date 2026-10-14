import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { defs, gear, simulate, checks } from './wudao-balance.mjs';
const first = JSON.parse(readFileSync(new URL('./wudao-stage-one-results.json', import.meta.url), 'utf8'));
const calibration = JSON.parse(readFileSync(new URL('./wudao-stage-calibration-results.json', import.meta.url), 'utf8'));
const prices = { 1: [6, 10, 16, 24], 2: [10, 16, 26, 40], 3: [14, 22, 36, 56] };
const stages = [null, {
  road: { hp: 64, items: gear('blade mirror', 1), skills: { fervor: 2 } },
  chief: { hp: 120, items: [...gear('hammer', 2), ...gear('dagger mirror', 1)], skills: { fervor: 2 } },
  templates: {
    attack: { hp: 160, items: [...gear('blade', 2), ...gear('hammer dagger mirror shield', 1)], skills: { fervor: 2 } },
    defense: { hp: 160, items: [...gear('mirror', 2), ...gear('blade shield medicine stone dagger', 1)], skills: { fervor: 2, restorative: 3 } },
    poison: { hp: 160, items: [...gear('blade', 2), ...gear('needle needle mirror medicine shield', 1)], skills: { restorative: 3 } },
  }, money: { road: 8, chief: 18, main: 32, optional: 16 }, mainPoints: 6, material: 5, heal: 45, healPrice: 8,
}, {
  hubStock: [{ id: 'needle', quality: 3, price: 24 }, { id: 'tassel', quality: 2, price: 16 }, { id: 'stone', quality: 2, price: 16 }, { id: 'wrist', quality: 2, price: 26 }],
  road: { hp: 96, items: gear('blade mirror', 2), skills: { fervor: 3 } },
  chief: { hp: 180, items: [...gear('hammer', 3), ...gear('dagger mirror', 2)], skills: { fervor: 3 } },
  templates: {
    attack: { hp: 220, items: [...gear('blade', 3), ...gear('hammer dagger mirror shield', 2)], skills: { fervor: 3 } },
    defense: { hp: 220, items: [...gear('mirror', 3), ...gear('blade shield medicine stone dagger', 2)], skills: { fervor: 3, restorative: 5 } },
    poison: { hp: 220, items: [...gear('blade', 3), ...gear('needle needle mirror medicine shield', 2)], skills: { restorative: 5 } },
  }, money: { road: 10, chief: 26, main: 40, optional: 20 }, mainPoints: 8, material: 6, heal: 60, healPrice: 10,
}];
function trial(route, template, adapt = false) {
  const l = first.ledgers.find(x => x.name === route);
  const state = { items: l.equipped.map(x => ({ id: x.id, quality: x.q })), bag: l.bag.map(x => ({ ...x })), money: l.money, points: l.points,
    hp: 100, maxHp: 100, bloodRank: 0, species: route === 'main' ? 1 : route === 'normal' ? 2 : 3, fervor: 2, restorative: route === 'main' ? 0 : 2, defeats: 0 };
  const log = [];
  const space = list => list.reduce((sum, x) => sum + (defs[x.id]?.size ?? x.size ?? 1), 0);
  const note = (action, extra = {}) => {
    assert(state.money >= 0 && state.points >= 0 && space(state.items) <= 10 && space(state.bag) <= 10, `${route}:${action}`);
    log.push({ action, money: state.money, points: state.points, hp: state.hp, maxHp: state.maxHp, field: space(state.items), bag: space(state.bag), defeats: state.defeats, ...extra });
  };
  const payPoints = (cost, action) => { assert(state.points >= cost); state.points -= cost; note(action); };
  const vitality = cost => { payPoints(cost, 'buy vitality +20'); state.maxHp += 20; state.hp += 20; note('apply vitality'); };
  const rank = cost => { payPoints(cost, 'buy next blood rank'); state.bloodRank++; };
  const upgrade = (id, q, source) => {
    const index = state.items.findIndex(x => x.id === id);
    assert(index >= 0 && state.items[index].quality < q);
    if (source === 'reward' || source === 'purchase') state.bag.push({ ...state.items[index], q: state.items[index].quality });
    state.items[index] = { id, quality: q }; note(`${source} ${id}:${q}`);
  };
  const sellOld = () => {
    const recoveries = state.bag.filter(x => x.id === 'recovery');
    const keep = recoveries.reduce((best, x) => !best || (x.heal ?? 30) > (best.heal ?? 30) ? x : best, null);
    state.bag = state.bag.filter(x => {
      if (defs[x.id]) { state.money += prices[defs[x.id].size][x.quality ?? x.q] / 2; return false; }
      if (x.id === 'mineral' || x.id === 'material') { state.money += x.id === 'mineral' ? 4 : x.value; return false; }
      if (x.id === 'recovery' && x !== keep) { state.money += x.sale ?? 3; return false; }
      return true;
    }); note('explicitly sell old equipment/materials and surplus recovery; keep strongest one');
  };
  const blood = () => ({ lifesteal: [0.1, 0.15, 0.25, 0.35][state.bloodRank], toxinBonus: state.species * (state.bloodRank + 1) });
  const fight = (enemy, label) => {
    let attempts = 0;
    while (true) {
      const r = simulate({ items: state.items, hp: state.maxHp, currentHp: state.hp, skills: { fervor: state.fervor, restorative: state.restorative }, blood: blood() }, enemy);
      state.hp = r.playerHp; note(label, { winner: r.winner, seconds: r.seconds });
      if (r.winner === 'player') return true;
      state.defeats++; attempts++; if (state.defeats >= 3) { note('third defeat ends trial'); return false; }
      state.hp = state.maxHp; note('defeat restores HP; same enemy, no rewards or free stock');
      if (adapt && label === 'stage 3 opponent' && attempts === 1 && state.items.some(x => x.id === 'hammer')) {
        const bought = stages[2].hubStock.filter(x => ['needle', 'tassel', 'stone'].includes(x.id));
        const cost = bought.reduce((sum, x) => sum + x.price, 0);
        if (state.money >= cost) {
          const i = state.items.findIndex(x => x.id === 'hammer');
          state.bag.push(state.items.splice(i, 1)[0]); note('adaptive retry: unequip hammer, preserve in bag');
          for (const entry of bought) {
            state.money -= entry.price; state.items.push({ id: entry.id, quality: entry.quality }); note(`adaptive retry: buy ${entry.id}`);
          }
        }
      }
      // Fixed-input stress retry: no new purchases or strength changes are injected.
    }
  };
  if (route === 'deep') rank(4); else vitality(2);
  state.hp = state.maxHp; note('hub one explicit free treatment');
  if (!fight(calibration.templates[template], 'stage one opponent')) return { route, template, success: false, log };
  sellOld();
  for (let index = 1; index <= 2; index++) {
    const s = stages[index], q = index + 1;
    state.money -= prices[2][q]; upgrade('blade', q, 'purchase');
    while (state.hp < state.maxHp * 0.8 && state.bag.some(x => x.id === 'recovery')) {
      const i = state.bag.findIndex(x => x.id === 'recovery');
      const recovery = state.bag.splice(i, 1)[0];
      state.hp = Math.min(state.maxHp, state.hp + (recovery.heal ?? 30)); note('consume carried recovery');
    }
    let recoveryBuys = 0;
    while (state.hp < state.maxHp * 0.8 && recoveryBuys < 2 && state.money >= s.healPrice) {
      state.money -= s.healPrice; state.hp = Math.min(state.maxHp, state.hp + s.heal); recoveryBuys++; note('buy and consume world recovery');
    }
    if (!fight(s.road, `world ${index + 1} road`)) return { route, template, success: false, log };
    state.money += s.money.road; state.bag.push({ id: 'material', size: 1, value: s.material }); note('road rewards');
    if (!fight(s.chief, `world ${index + 1} chief`)) return { route, template, success: false, log };
    state.money += s.money.chief + s.money.main + (route === 'main' ? 0 : s.money.optional);
    state.points += s.mainPoints + (route === 'main' ? 0 : 2);
    state.fervor = q + 1;
    note('chief skill duplicate merges; fixed completed tasks pay');
    upgrade('mirror', q, 'reward'); upgrade('dagger', q, 'reward');
    if (state.items.some(x => x.id === 'medicine')) upgrade('medicine', index, 'reward');
    else { state.items.push({ id: 'medicine', quality: index }); note('reward medicine'); }
    state.bag.push({ id: 'recovery', size: 1, heal: s.heal, sale: s.healPrice / 2 }); note('boss chest recovery');
    sellOld();
    if (route !== 'deep' && index === 1) {
      const shield = state.items.findIndex(x => x.id === 'shield');
      state.bag.push({ ...state.items.splice(shield, 1)[0] }); note('unequip shield for heavy weapon');
      state.money -= prices[3][1]; state.items.push({ id: 'hammer', quality: 1 }); note('buy silver hammer');
    }
    if (index === 1) {
      if (route === 'deep') { rank(6); vitality(3); }
      else { vitality(3); payPoints(3, 'upgrade hammer to gold'); upgrade('hammer', 2, 'points'); if (route === 'normal') rank(4); }
    } else {
      if (route === 'deep') rank(8);
      else { vitality(4); if (route === 'main') { payPoints(5, 'upgrade hammer to diamond'); upgrade('hammer', 3, 'points'); } else rank(6); }
    }
    sellOld();
    state.hp = state.maxHp; note('hub explicit free treatment');
    if (!fight(s.templates[template], `stage ${index + 1} opponent`)) return { route, template, success: false, log };
  }
  note('third stage victory: immediate completion, no rewards');
  return { route, template, success: true, log };
}
const results = ['main', 'normal', 'deep'].flatMap(route => ['attack', 'defense', 'poison'].map(template => trial(route, template)));
const recoveryResults = ['main', 'normal'].map(route => trial(route, 'attack', true));
assert(recoveryResults.every(x => x.success && x.log.at(-1).defeats === 1));
const out = { date: '2026-10-14', checks: checks(), scope: 'Three-stage fixed combat/cash/points/inventory skeleton; starts after fixed world one. Later optional tasks and inventories are explicit fixtures, not exploration generation. No class, random supply, control, or 45-minute timing validation.', stages, results, recoveryResults };
if (process.argv.includes('--write')) writeFileSync(new URL('./wudao-three-stages-results.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify([...results, ...recoveryResults].map(x => ({ route: x.route, template: x.template, success: x.success, final: x.log.at(-1) })), null, 2));
