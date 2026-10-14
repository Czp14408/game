import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// Design-only simulator: no engine or Excel definitions are changed.
const defs = {
  dagger: { size: 1, cd: 20, attack: [4, 6, 9, 13], weapon: true },
  blade: { size: 2, cd: 40, attack: [12, 18, 28, 42], weapon: true },
  hammer: { size: 3, cd: 70, attack: [30, 45, 65, 90], weapon: true },
  shield: { size: 1, cd: 40, shield: [7, 11, 17, 25] },
  mirror: { size: 2, cd: 50, shield: [12, 20, 32, 48] },
  medicine: { size: 2, cd: 60, heal: [8, 13, 20, 30] },
  tassel: { size: 1, cd: 60, haste: [20, 30, 40, 50] },
  stone: { size: 1, cd: 50, growth: [2, 3, 5, 8] },
  wrist: { size: 2, cd: 50, shield: [null, 14, 22, 34], hasteGrowth: [null, 2, 3, 5] },
  charged: { size: 3, cd: 70, attack: [null, 24, 36, 52], stackPower: [null, 4, 6, 9], weapon: true },
  wind: { size: 2, cd: 40, attack: [null, null, 20, 30], hasteGrowth: [null, null, 2, 3], reduction: [null, null, 2, 3], weapon: true },
  needle: { size: 1, cd: 40, attack: [2, 3, 4, 6], poison: [1, 2, 3, 4], weapon: true },
  pulseBlade: { size: 2, cd: 40, attack: [10, 16, 25, 38], weapon: true },
  pistol: { size: 1, cd: 30, attack: [5, 8, 12, 18], weapon: true },
  drone: { size: 3, cd: 60, attack: [18, 28, 44, 66], shield: [8, 12, 18, 28], weapon: true },
  emitter: { size: 2, cd: 50, shield: [10, 16, 26, 40] },
  medpack: { size: 2, cd: 60, heal: [10, 16, 25, 38] },
  accelerator: { size: 1, cd: 60, haste: [20, 30, 40, 50], hasteAny: true },
  battery: { size: 1, cd: 50, charge: [10, 15, 20, 30] },
  mist: { size: 2, cd: 50, poison: [null, 3, 5, 8], heal: [null, 3, 5, 8] },
  igniter: { size: 2, cd: 50, burn: [4, 6, 9, 13] },
  curseBlade: { size: 2, cd: 40, attack: [8, 12, 18, 28], poison: [1, 2, 3, 4], weapon: true },
  soulArmor: { size: 2, cd: 60, shield: [14, 22, 34, 52] },
  candle: { size: 1, cd: 50, burn: [2, 3, 5, 8] },
  vial: { size: 1, cd: 60, poison: [2, 3, 5, 8] },
  bloodCup: { size: 2, cd: 60, heal: [10, 16, 25, 38] },
  boneCharm: { size: 1, cd: 50, shield: [6, 9, 14, 21] },
  incense: { size: 1, cd: 60, heal: [3, 5, 8, 12], burn: [2, 3, 5, 8] },
  soulBell: { size: 2, cd: 70, freeze: [10, 15, 20, 25] },
};
const gear = (names, quality = 0) => names.split(' ').filter(Boolean).map(id => ({ id, quality }));
function actor(config) {
  const items = config.items.map(({ id, quality: q = 0, permanentAttack = 0 }) => {
    const d = defs[id];
    assert(d, `Unknown item ${id}`);
    for (const value of Object.values(d)) if (Array.isArray(value)) assert.notEqual(value[q], null, `Unsupported quality ${id}:${q}`);
    assert(Number.isFinite(permanentAttack) && permanentAttack >= 0);
    return { id, q, d, permanentAttack, cd: d.cd, remaining: d.cd, haste: 0, frozen: 0, stacks: 0, attackGrowth: 0, shieldGrowth: 0, crit: 0, uses: 0 };
  });
  const size = items.reduce((sum, item) => sum + item.d.size, 0);
  assert(size <= 10, `Capacity ${size}`);
  return { items, size, maxHp: config.hp ?? 100, hp: config.currentHp ?? config.hp ?? 100, shield: 0, poison: 0, burn: 0, pending: [], bootUsed: false,
    scale: config.effectScale ?? 1, stormScale: config.stormScale ?? 1,
    skills: config.skills ?? {}, blood: { lifesteal: 0, toxinBonus: 0, ...config.blood }, wardPayments: 0, wardSpent: 0, wardPoison: 0, attack: 0, healing: 0, actualHealing: 0, shielding: 0, poisonDamage: 0, burnDamage: 0, lifeAttackDamage: 0, lifestealHealing: 0, trace: [] };
}
function rng(seed) {
  let value = seed >>> 0;
  return () => { value = (Math.imul(value, 1664525) + 1013904223) >>> 0; return value / 4294967296; };
}
function simulate(playerConfig, enemyConfig, seed = 1, limit = 600, stopOnDeath = true, shieldAllocation = 'attack-first') {
  assert(['attack-first', 'proportional'].includes(shieldAllocation));
  const sides = [actor(playerConfig), actor(enemyConfig)];
  const random = rng(seed);
  const pick = items => items.length ? items[Math.floor(random() * items.length)] : null;
  for (let tick = 1; tick <= limit; tick++) {
    const actions = sides.map((side, s) => {
      const out = [];
      for (const item of side.items) {
        const frozen = item.frozen > 0;
        item.frozen = Math.max(0, item.frozen - 1);
        if (!frozen) item.remaining -= item.haste > 0 ? 2 : 1;
        item.haste = Math.max(0, item.haste - 1);
        if (frozen || item.remaining > 1e-8) continue;
        const factor = item.crit > 0 && random() < Math.min(1, item.crit) ? 2 : 1;
        const d = item.d;
        const attack = ((d.attack?.[item.q] ?? 0) * side.scale + item.permanentAttack + item.attackGrowth + item.stacks * (d.stackPower?.[item.q] ?? 0) * side.scale) * factor;
        const action = { item, attack, shield: ((d.shield?.[item.q] ?? 0) * side.scale + item.shieldGrowth) * factor,
          heal: (d.heal?.[item.q] ?? 0) * side.scale * factor, poison: d.poison ? (d.poison[item.q] * side.scale + side.blood.toxinBonus) * factor : 0,
          burn: (d.burn?.[item.q] ?? 0) * side.scale * factor,
          target: d.haste || d.growth || d.charge ? pick(side.items.filter(other => other.cd > 0 && (d.hasteAny || d.charge ? other !== item : other.d.weapon))) : d.freeze ? pick(sides[1 - s].items.filter(other => other.cd > 0)) : null };
        item.stacks = 0;
        item.remaining = item.cd;
        item.uses++;
        out.push(action);
        side.trace.push({ tick, id: item.id, attack, stacksAfterLock: item.stacks });
      }
      return out;
    });
    const events = [[], []];
    for (let s = 0; s < 2; s++) {
      const side = sides[s];
      for (const action of actions[s]) {
        if (action.item.d.shield) {
          side.shield += action.shield; side.shielding += action.shield;
          events[s].push({ kind: 'shield' });
        }
        if (action.item.d.heal) {
          const actual = Math.min(side.maxHp - side.hp, action.heal);
          side.hp += actual; side.healing += action.heal; side.actualHealing += actual;
          events[s].push({ kind: 'heal' });
        }
      }
    }
    const lifeBeforeDamage = sides.map(side => Math.max(0, side.hp));
    const attackToLife = [0, 0];
    const totalToLife = [0, 0];
    for (let s = 0; s < 2; s++) {
      const source = sides[s], target = sides[1 - s];
      const damage = actions[s].reduce((sum, action) => sum + action.attack, 0);
      source.attack += damage;
      const burning = tick % 10 === 0 ? target.burn : 0;
      const absorbed = Math.min(target.shield, damage + burning);
      target.shield -= absorbed;
      // Adopted rule: shields absorb attacks first, then burn. Proportional is a comparison mode.
      const attackAbsorbed = shieldAllocation === 'proportional' && damage + burning > 0 ? absorbed * damage / (damage + burning) : Math.min(damage, absorbed);
      attackToLife[s] = damage - attackAbsorbed;
      const burnToLife = burning - (absorbed - attackAbsorbed);
      target.hp -= attackToLife[s] + burnToLife;
      totalToLife[1 - s] += attackToLife[s] + burnToLife;
      source.burnDamage += burning;
      if (tick % 10 === 0) target.burn = Math.max(0, target.burn - 1);
      if (tick % 10 === 0) {
        target.hp -= target.poison;
        totalToLife[1 - s] += target.poison;
        source.poisonDamage += target.poison;
      }
    }
    if (tick >= 300 && tick % 10 === 0) for (let s = 0; s < 2; s++) {
      const storm = 5 * (tick / 10 - 29) * sides[s].stormScale;
      sides[s].hp -= storm; totalToLife[s] += storm;
    }
    // Allocate capped HP loss proportionally before simultaneous lifesteal and death checks.
    const recovery = sides.map((side, s) => {
      const target = 1 - s;
      const actualAttack = totalToLife[target] > 0 ? Math.min(lifeBeforeDamage[target], totalToLife[target]) * attackToLife[s] / totalToLife[target] : 0;
      side.lifeAttackDamage += actualAttack;
      return actualAttack * side.blood.lifesteal;
    });
    for (let s = 0; s < 2; s++) {
      const actual = Math.min(sides[s].maxHp - sides[s].hp, recovery[s]);
      sides[s].hp += actual; sides[s].lifestealHealing += actual;
      if (Math.abs(sides[s].hp) < 1e-9) sides[s].hp = 0;
    }
    if (stopOnDeath && sides.some(side => side.hp <= 0)) {
      for (const side of sides) side.pending = [];
      return result(tick, sides);
    }
    // Apply control after damage; new poison cannot jump on the application tick.
    for (let s = 0; s < 2; s++) {
      const side = sides[s];
      for (const action of actions[s]) {
        const { item, target } = action;
        sides[1 - s].poison += action.poison;
        if (action.poison > 0 && side.skills.ward) side.pending.push({ key: 'ward', target: sides[1 - s], amount: side.skills.ward * side.scale, cost: 8 * side.scale });
        sides[1 - s].burn += action.burn;
        events[s].push({ kind: 'use', item });
        if (item.d.burn) events[s].push({ kind: 'burn' });
        if (item.d.weapon) events[s].push({ kind: 'weapon', item });
        if (target && item.d.haste) {
          target.haste += item.d.haste[item.q];
          events[s].push({ kind: 'haste', target });
        }
        if (target && item.d.growth) target.attackGrowth += item.d.growth[item.q] * side.scale;
        if (target && item.d.charge) target.remaining = Math.max(0, target.remaining - item.d.charge[item.q]);
        if (target && item.d.freeze) target.frozen += item.d.freeze[item.q];
      }
      for (const event of events[s]) {
        if (event.kind === 'use' && side.skills.boot && !side.bootUsed && !event.item.d.poison && !event.item.d.burn) {
          side.bootUsed = true;
          for (const target of side.items.filter(x => x.d.poison || x.d.burn)) side.pending.push({ key: 'boot', target, amount: side.skills.boot * 10 });
        }
        if (event.kind === 'heal') for (const [key, property, amount] of [['regulated', 'shield', side.skills.regulated], ['plague', 'poison', side.skills.plague]]) {
          if (amount) { const target = pick(side.items.filter(x => x.d[property] && x.cd > 0)); if (target) side.pending.push({ key, target, amount: amount * 10 }); }
        }
        if (event.kind === 'weapon') {
          for (const item of side.items) {
            if (item.id === 'mirror') item.remaining = Math.max(0, item.remaining - 10);
            if (item.id === 'charged' && item !== event.item) item.stacks++;
          }
          event.item.crit += side.skills.edge ?? 0;
        }
        if (event.kind === 'shield') for (const item of side.items) if (item.d.weapon) item.attackGrowth += (side.skills.fervor ?? 0) * side.scale;
        if (event.kind === 'heal') { side.shield += (side.skills.restorative ?? 0) * side.scale; side.shielding += (side.skills.restorative ?? 0) * side.scale; }
        if (event.kind === 'burn') { side.shield += (side.skills.flame ?? 0) * side.scale; side.shielding += (side.skills.flame ?? 0) * side.scale; }
        if (event.kind === 'haste') {
          for (const item of side.items) if (item.id === 'wrist') item.shieldGrowth += item.d.hasteGrowth[item.q] * side.scale;
          if (event.target.id === 'wind') {
            event.target.attackGrowth += event.target.d.hasteGrowth[event.target.q] * side.scale;
            event.target.cd = Math.max(20, event.target.cd - event.target.d.reduction[event.target.q]);
          }
        }
      }
      const used = new Set(), pending = [];
      for (const entry of side.pending) {
        // Boot's single skill action targets all anomaly items; other skills execute once per step.
        if (entry.key !== 'boot' && used.has(entry.key)) { pending.push(entry); continue; }
        used.add(entry.key);
        if (entry.key === 'ward') {
          if (side.hp <= 0 || entry.target.hp <= 0 || side.shield < entry.cost) continue;
          side.shield -= entry.cost;
          entry.target.poison += entry.amount;
          side.wardPayments++; side.wardSpent += entry.cost; side.wardPoison += entry.amount;
          // Self-trigger advances next step, never recursively inside this drain.
          pending.push({ ...entry });
        } else entry.target.remaining = Math.max(0, entry.target.remaining - entry.amount);
      }
      side.pending = pending;
    }
  }
  return result(limit, sides);
}
function result(tick, sides) {
  const [p, e] = sides;
  return { winner: p.hp > 0 && e.hp <= 0 ? 'player' : p.hp <= 0 ? 'enemy' : 'timeout', seconds: tick / 10,
    simultaneousDeaths: p.hp <= 0 && e.hp <= 0,
    playerHp: Math.max(0, p.hp), enemyHp: Math.max(0, e.hp), attack: p.attack, healing: p.healing,
    actualHealing: p.actualHealing, shielding: p.shielding, poisonDamage: p.poisonDamage,
    lifeAttackDamage: p.lifeAttackDamage, lifestealHealing: p.lifestealHealing, burnDamage: p.burnDamage, bootUsed: p.bootUsed,
    wardPayments: p.wardPayments, wardSpent: p.wardSpent, wardPoison: p.wardPoison, playerShield: p.shield, enemyPoison: e.poison, pendingEffects: p.pending.length,
    items: p.items.map(item => ({ id: item.id, uses: item.uses, attackGrowth: item.attackGrowth, shieldGrowth: item.shieldGrowth, cd: item.cd / 10, stacks: item.stacks })), trace: p.trace };
}
const empty = { hp: 1e9, items: [] };
function checks() {
  const run = (items, ticks, extra = {}) => simulate({ items, ...extra }, empty, 1, ticks, false);
  assert.throws(() => actor({ items: gear('wind', 0) }), /Unsupported quality/);
  assert.throws(() => actor({ items: gear('hammer hammer hammer hammer') }), /Capacity/);
  assert.equal(run(gear('dagger'), 20).attack, 4);
  assert.equal(run(gear('blade mirror'), 40).items[1].uses, 0);
  assert.equal(run(gear('blade mirror'), 41).items[1].uses, 1);
  assert.equal(run(gear('dagger blade charged', 1), 70).trace.find(x => x.id === 'charged').attack, 40);
  assert.equal(run(gear('charged', 1), 140).attack, 48);
  assert.equal(run(gear('hammer charged', 1), 70).trace.find(x => x.id === 'charged').attack, 24);
  assert.equal(run(gear('needle'), 40).poisonDamage, 0);
  assert.equal(run(gear('needle'), 50).poisonDamage, 1);
  assert.equal(run(gear('medicine'), 60, { skills: { restorative: 2 } }).actualHealing, 0);
  assert.equal(run(gear('medicine'), 60, { skills: { restorative: 2 } }).shielding, 2);
  const wind = run(gear('wind tassel', 2), 300);
  assert.equal(wind.items[0].attackGrowth, 10);
  assert.equal(wind.items[0].cd, 3);
  assert.equal(run(gear('wind tassel', 2), 1200).items[0].cd, 2);
  assert.equal(run(gear('wind tassel', 2), 60).items[0].cd, 3.8);
  assert.equal(run(gear('wind tassel', 2), 60).trace.length, 2);
  const wrist = run(gear('blade tassel wrist', 1), 300);
  assert.equal(wrist.items[2].shieldGrowth, 10);
  const killed = simulate({ hp: 4, items: gear('dagger mirror') }, { hp: 4, items: gear('dagger') }, 1, 20);
  assert.equal(killed.winner, 'enemy');
  assert.equal(killed.items[1].uses, 0);
  assert.deepEqual(run(gear('blade dagger tassel'), 300), run(gear('blade dagger tassel'), 300));
  assert.equal(run(gear('wind tassel tassel', 2), 120).items[0].attackGrowth, 8);
  assert.equal(run(gear('wind tassel tassel', 2), 120).items[0].cd, 3.2);
  assert.equal(run(gear('charged charged', 1), 70).attack, 48);
  assert.equal(run(gear('charged charged', 1), 70).items[0].stacks, 1);
  assert.equal(run(gear('dagger shield'), 40, { skills: { fervor: 1 } }).trace.at(-2).attack, 4);
  assert.equal(run(gear('medicine'), 60, { currentHp: 50 }).actualHealing, 8);
  const bloodKill = simulate({ hp: 11, items: gear('blade'), blood: { lifesteal: 0.3, toxinBonus: 0 } }, { hp: 10, items: gear('blade') }, 1, 40);
  assert.equal(bloodKill.winner, 'player');
  assert.equal(bloodKill.playerHp, 2);
  const overkill = simulate({ hp: 1, items: gear('blade'), blood: { lifesteal: 0.3, toxinBonus: 0 } }, { hp: 10, items: gear('blade') }, 1, 40);
  assert.equal(overkill.winner, 'enemy');
  const bloodNeedle = simulate({ currentHp: 50, items: gear('needle'), blood: { lifesteal: 0.1, toxinBonus: 2 }, skills: { restorative: 2 } }, empty, 1, 50, false);
  assert.equal(bloodNeedle.poisonDamage, 3);
  assert.equal(bloodNeedle.shielding, 0);
  assert.equal(bloodNeedle.healing, 0);
  assert.equal(bloodNeedle.lifestealHealing, 0.2);
  const zeroToxin = run(gear('dagger'), 30, { blood: { lifesteal: 0.1, toxinBonus: 10 } });
  assert.equal(zeroToxin.poisonDamage, 0);
  const proportional = simulate({ currentHp: 50, items: gear('needle'), blood: { lifesteal: 0.1 } }, { hp: 7, items: [] }, 1, 80);
  assert(Math.abs(proportional.lifeAttackDamage - 10 / 3) < 1e-8);
  assert(Math.abs(proportional.lifestealHealing - 1 / 3) < 1e-8);
  const blocked = simulate({ currentHp: 50, items: gear('needle'), blood: { lifesteal: 0.1 } }, { items: gear('shield') }, 1, 50);
  assert.equal(blocked.lifeAttackDamage, 0);
  const floatZero = simulate({ hp: 11.000000000000002, items: gear('blade'), blood: { lifesteal: 0.1 } }, { hp: 10, items: gear('blade') }, 1, 40);
  assert.equal(floatZero.winner, 'enemy');
  return 39;
}
const builds = {
  pure: { items: gear('blade hammer dagger shield medicine') },
  quick: { items: gear('dagger blade tassel stone shield medicine shield') },
  charged: { items: gear('dagger blade charged shield medicine', 1) },
  chargedFast: { items: gear('dagger dagger dagger charged shield medicine', 1) },
  defense: { items: gear('dagger blade mirror shield medicine shield') },
  spam: { items: gear('dagger dagger dagger dagger mirror medicine') },
  poison: { items: gear('needle needle blade mirror shield medicine') },
};
// All comparisons use nine spaces, except the explicit eight-space spam stress case.
const enemies = {
  attack: { hp: 100, items: gear('blade hammer dagger shield medicine') },
  defense: { hp: 100, items: gear('blade mirror shield shield medicine stone') },
  poison: { hp: 100, items: gear('needle needle blade mirror shield medicine') },
};
export { actor, gear, simulate, checks, defs, rng };
if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
const testsPassed = checks();
const matrix = [];
for (const quality of [0, 1]) for (const [name, build] of Object.entries(builds)) {
  if (name.startsWith('charged') && quality === 0) continue;
  const player = { items: build.items.map(item => ({ ...item, quality })) };
  for (const [enemyName, enemy] of Object.entries(enemies)) {
    const samples = Array.from({ length: 100 }, (_, i) => simulate(player, { ...enemy, items: enemy.items.map(item => ({ ...item, quality })) }, i + 1));
    matrix.push({ quality, name, spaces: actor(player).size, enemy: enemyName, wins: samples.filter(x => x.winner === 'player').length,
      simultaneousDeaths: samples.filter(x => x.simultaneousDeaths).length,
      meanSeconds: samples.reduce((sum, x) => sum + x.seconds, 0) / samples.length,
      meanHp: samples.reduce((sum, x) => sum + x.playerHp, 0) / samples.length });
  }
}
const probes = {};
for (const [name, build] of Object.entries(builds)) if (!name.startsWith('charged')) probes[name] = simulate(build, empty, 1, 300, false);
probes.charged = simulate(builds.charged, empty, 1, 300, false);
probes.chargedFast = simulate(builds.chargedFast, empty, 1, 300, false);
probes.wind = simulate({ items: gear('wind tassel', 2) }, empty, 1, 300, false);
probes.windBaseline = simulate({ items: gear('blade', 2) }, empty, 1, 300, false);
probes.windEqualSpace = simulate({ items: gear('blade dagger', 2) }, empty, 1, 300, false);
const skills = [];
for (const name of ['quick', 'defense', 'spam']) {
  const active = name === 'quick' ? { edge: 0.02 } : { fervor: 1 };
  const samples = Array.from({ length: 100 }, (_, i) => simulate({ ...builds[name], skills: active }, enemies.attack, i + 1));
  skills.push({ name, skills: active, wins: samples.filter(x => x.winner === 'player').length,
    meanSeconds: samples.reduce((sum, x) => sum + x.seconds, 0) / samples.length,
    meanHp: samples.reduce((sum, x) => sum + x.playerHp, 0) / samples.length });
}
const output = { version: 'v0.1', testsPassed, seeds: 100, stepSeconds: 0.1,
  definitions: defs, builds, enemies,
  scope: 'Design model only; no lifesteal, blood growth, classes, freeze/slow or multicast. Same-tier synthetic opponents, not generated encounters or overall win rates.', matrix, skills, probes };
if (process.argv.includes('--write')) writeFileSync(new URL('./wudao-balance-results.json', import.meta.url), JSON.stringify(output, null, 2) + '\n');
console.log(JSON.stringify({ testsPassed, matrix, skills, probes: Object.fromEntries(Object.entries(probes).map(([key, value]) => [key, { attack: value.attack, shielding: value.shielding, healing: value.healing, poisonDamage: value.poisonDamage }])) }, null, 2));
}
