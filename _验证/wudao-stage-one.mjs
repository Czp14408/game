import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { actor, gear, simulate, checks } from './wudao-balance.mjs';

const encounters = {
  guard: { hp: 36, items: gear('blade mirror'), skills: { fervor: 1 } },
  hunter: { hp: 40, items: gear('dagger') },
  beast: { hp: 60, items: [...gear('needle'), ...gear('shield', 1)] },
  chief: { hp: 64, items: [...gear('hammer', 1), ...gear('dagger mirror')], skills: { fervor: 1 } },
  arsenal: { hp: 64, items: gear('blade mirror dagger', 1), skills: { fervor: 2 } },
  mine: { hp: 40, items: gear('hammer') },
  cellar: { hp: 44, items: gear('needle shield') },
};
const bp = gear('blade shield dagger');
const supported = gear('blade shield dagger medicine');
const afterGuard = gear('blade shield dagger mirror');
const deep = [...gear('blade shield medicine'), ...gear('dagger needle', 1)];
const named = { start: bp, supported, afterGuard, normalBeforeChief: gear('blade shield dagger medicine mirror'), deepBeforeChief: [...deep, ...gear('mirror')] };
const boundary = [];
for (const [build, items] of Object.entries(named)) for (const hp of [100, 60, 30]) {
  const enemy = build.endsWith('Chief') || build === 'afterGuard' ? 'chief' : build === 'supported' ? 'beast' : 'guard';
  const sample = simulate({ items, currentHp: hp }, encounters[enemy]);
  boundary.push({ build, hp, enemy, winner: sample.winner, seconds: sample.seconds, remaining: sample.playerHp });
}
const prices = { shield: [6, 10], dagger: [6, 10], medicine: [10, 16], fervor: [12, 20] };
function ledger(name) {
  let money = 30, peak = 0;
  const bag = [], equipped = [{ id: 'blade', q: 0, size: 2 }], log = [];
  const size = list => list.reduce((sum, item) => sum + item.size, 0);
  const record = action => {
    assert(size(bag) <= 10 && size(equipped) <= 10 && money >= 0, `${name}:${action}`);
    peak = Math.max(peak, size(bag));
    log.push({ action, money, bag: size(bag), equipped: size(equipped) });
  };
  const item = (id, q = 0) => ({ id, q, size: ['blade', 'mirror', 'medicine'].includes(id) ? 2 : 1 });
  const buy = id => { money -= prices[id][0]; equipped.push(item(id)); record(`buy ${id}`); };
  const put = id => { bag.push(item(id)); record(`collect ${id}`); };
  const replace = (id, q) => {
    const index = equipped.findIndex(x => x.id === id);
    bag.push(equipped.splice(index, 1)[0]); equipped.push(item(id, q)); record(`replace ${id}:${q}`);
  };
  const mergeDagger = () => {
    const index = equipped.findIndex(x => x.id === 'dagger' && x.q === 0);
    bag.push(equipped.splice(index, 1)[0]); record('unequip dagger to bag');
    const match = bag.findIndex(x => x.id === 'dagger' && x.q === 0);
    assert(match >= 0); bag[match] = item('dagger', 1); record('claim bronze dagger; atomic merge to silver');
    equipped.push(bag.splice(match, 1)[0]); record('equip silver dagger');
  };
  buy('shield'); buy('dagger');
  if (name !== 'main') {
    buy('medicine'); put('hide'); put('parcel'); put('copper'); put('recovery');
    money += 6; put('bone');
    if (name === 'deep') {
      put('herb'); money += 10;
      equipped.push(item('needle')); record('elite drops bronze needle');
      replace('needle', 1); mergeDagger(); put('gland');
    }
    for (const id of ['hide', 'copper', 'bone', ...(name === 'deep' ? ['herb', 'gland'] : [])]) {
      bag.splice(bag.findIndex(x => x.id === id), 1); money += 4; record(`sell ${id}`);
    }
    bag.splice(bag.findIndex(x => x.id === 'parcel'), 1); money += 12; record('deliver parcel and disciple quests');
  }
  put('mineral');
  if (name !== 'main') { bag.splice(bag.findIndex(x => x.id === 'recovery'), 1); record('submit recovery for restorative skill'); }
  money += 6; equipped.push(item('mirror')); record('guard win; equip mirror');
  money -= prices.fervor[0]; record('revisit market; buy bronze fervor');
  money += 12 + 24; record('chief and main quest money; learn second bronze fervor -> silver');
  replace('blade', 1); replace('mirror', 1);
  if (name === 'deep') { equipped.push(item('dagger')); record('equip boss bronze dagger'); } else mergeDagger();
  put('recovery');
  return { name, money, peak, bagSize: size(bag), equippedSize: size(equipped), bag, equipped, log, points: name === 'main' ? 4 : 6 };
}
function route(name) {
  let hp = 100;
  const battles = [];
  const fight = (enemy, items, skills = {}) => {
    const result = simulate({ currentHp: hp, items, skills }, encounters[enemy]);
    battles.push({ enemy, openingHp: hp, winner: result.winner, seconds: result.seconds, remaining: result.playerHp });
    assert.equal(result.winner, 'player', `${name}:${enemy}`);
    hp = result.playerHp;
  };
  if (name !== 'main') fight('hunter', supported);
  if (name === 'deep') fight('beast', supported);
  fight('guard', name === 'main' ? bp : name === 'deep' ? deep : supported, name === 'main' ? {} : { restorative: 2 });
  fight('chief', name === 'main' ? afterGuard : name === 'deep' ? named.deepBeforeChief : named.normalBeforeChief, name === 'main' ? { fervor: 1 } : { fervor: 1, restorative: 2 });
  return { name, battles, finalHp: hp };
}
const ledgers = ['main', 'normal', 'deep'].map(ledger);
for (const [i, expected] of [[0, [48, 6, 6, 6]], [1, [68, 8, 6, 6]], [2, [86, 10, 7, 8]]]) {
  const l = ledgers[i]; assert.deepEqual([l.money, l.equippedSize, l.bagSize, l.peak], expected);
}
const stageEnemies = {
  attack: { hp: 100, items: [...gear('blade', 1), ...gear('dagger mirror medicine shield')] },
  defense: { hp: 100, items: [...gear('mirror', 1), ...gear('blade shield shield medicine stone')] },
  poison: { hp: 100, items: [...gear('needle', 1), ...gear('blade mirror shield medicine')] },
};
const stage = ledgers.flatMap(l => Object.entries(stageEnemies).map(([enemy, config]) => {
  const r = simulate({ items: l.equipped.map(x => ({ id: x.id, quality: x.q })), skills: { fervor: 2, ...(l.name === 'main' ? {} : { restorative: 2 }) } }, config);
  return { route: l.name, enemy, winner: r.winner, seconds: r.seconds, remaining: r.playerHp };
}));
const alternatives = ['blade shield dagger mirror hammer', 'blade shield dagger mirror medicine'].map(names => {
  const r = simulate({ currentHp: 82, items: gear(names) }, encounters.chief);
  return { items: names, winner: r.winner, seconds: r.seconds, remaining: r.playerHp };
});
assert.equal(alternatives[0].winner, 'player');
assert.equal(alternatives[1].winner, 'enemy');
const output = { date: '2026-10-14', modelChecks: checks(), scope: 'Fixed legal reward and shop inputs; no class, blood or lifesteal. Not random supply success rates.', encounters, named, boundary, routes: ['main', 'normal', 'deep'].map(route), prices, ledgers, stageEnemies, stage, alternatives };
if (process.argv.includes('--write')) writeFileSync(new URL('./wudao-stage-one-results.json', import.meta.url), JSON.stringify(output, null, 2) + '\n');
console.log(JSON.stringify(output, null, 2));
