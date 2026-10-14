import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { gear, simulate, checks } from './wudao-balance.mjs';
const stage = JSON.parse(readFileSync(new URL('./wudao-stage-one-results.json', import.meta.url), 'utf8'));
const calibration = JSON.parse(readFileSync(new URL('./wudao-stage-calibration-results.json', import.meta.url), 'utf8'));
const rows = [];
const journeys = [];
for (const route of ['main', 'normal', 'deep']) {
  let hp = 100, species = 0;
  const battles = [];
  const fight = (enemy, items, skills, collect) => {
    const r = simulate({ items, currentHp: hp, skills, blood: { lifesteal: 0.1, toxinBonus: species } }, stage.encounters[enemy]);
    battles.push({ enemy, openingHp: hp, speciesBefore: species, winner: r.winner, seconds: r.seconds, hp: r.playerHp, lifesteal: r.lifestealHealing });
    assert.equal(r.winner, 'player'); hp = r.playerHp;
    if (collect) species++;
  };
  if (route !== 'main') fight('hunter', stage.named.supported, {}, true);
  if (route === 'deep') fight('beast', stage.named.supported, {}, true);
  fight('guard', route === 'main' ? stage.named.start : route === 'deep' ? stage.named.deepBeforeChief.filter(x => x.id !== 'mirror') : stage.named.supported, route === 'main' ? {} : { restorative: 2 }, true);
  fight('chief', route === 'main' ? stage.named.afterGuard : stage.named[route === 'deep' ? 'deepBeforeChief' : 'normalBeforeChief'], { fervor: 1, ...(route === 'main' ? {} : { restorative: 2 }) }, false);
  journeys.push({ route, species, battles });
  const ledger = stage.ledgers.find(x => x.name === route);
  const base = { items: ledger.equipped.map(x => ({ id: x.id, quality: x.q })), skills: { fervor: 2, ...(route === 'main' ? {} : { restorative: 2 }) } };
  for (const plan of [
    { name: 'initial-blood', points: 0, ...base, blood: { lifesteal: 0.1, toxinBonus: species } },
    { name: 'blood-rank-one', points: 4, ...base, blood: { lifesteal: 0.15, toxinBonus: species * 2 } },
    { name: 'health', points: 2, ...base, hp: 120, blood: { lifesteal: 0.1, toxinBonus: species } },
  ]) for (const [enemy, config] of Object.entries(calibration.templates)) {
    assert(plan.points <= ledger.points);
    const r = simulate(plan, config);
    rows.push({ route, plan: plan.name, points: plan.points, enemy, winner: r.winner, seconds: r.seconds, hp: r.playerHp, attackLifeDamage: r.lifeAttackDamage, lifesteal: r.lifestealHealing, poisonDamage: r.poisonDamage });
  }
}
const out = { date: '2026-10-14', checks: checks(), scope: 'Blood initial rank in world, post-victory species collection only; same fixed rewards and no classes. First-rank spending at hub only. No burn, freeze or slow.', journeys, rows };
if (process.argv.includes('--write')) writeFileSync(new URL('./wudao-blood-results.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify(out, null, 2));
