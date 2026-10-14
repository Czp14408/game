import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { gear, simulate } from './wudao-balance.mjs';

const input = JSON.parse(readFileSync(new URL('./wudao-stage-one-results.json', import.meta.url), 'utf8'));
const templates = {
  attack: { hp: 120, items: [...gear('blade', 1), ...gear('hammer dagger mirror shield')], skills: { fervor: 1 } },
  defense: { hp: 120, items: [...gear('blade mirror', 1), ...gear('shield medicine stone dagger')], skills: { fervor: 1, restorative: 2 } },
  poison: { hp: 120, items: [...gear('needle needle', 1), ...gear('blade mirror medicine shield')], skills: { restorative: 2 } },
};
const menu = { maxHp: { points: 2, amount: 20, purchasesPerStage: 1 }, bronzeItemToSilver: { points: 2 }, bronzeSkillToSilver: { points: 3 }, bloodFirstRank: { points: 4, simulated: false } };
const rows = [];
for (const l of input.ledgers) {
  const base = { items: l.equipped.map(x => ({ id: x.id, quality: x.q })), skills: { fervor: 2, ...(l.name === 'main' ? {} : { restorative: 2 }) } };
  const plans = [{ name: 'no-spend', points: 0, ...base }, { name: 'health', points: 2, ...base, hp: 120 }];
  for (let i = 0; i < base.items.length; i++) if (base.items[i].quality === 0) {
    const items = base.items.map((x, j) => j === i ? { ...x, quality: 1 } : x);
    plans.push({ name: `upgrade-${base.items[i].id}-${i}`, points: 2, ...base, items });
    plans.push({ name: `health+upgrade-${base.items[i].id}-${i}`, points: 4, ...base, items, hp: 120 });
  }
  if (l.name !== 'main') plans.push({ name: 'restorative', points: 3, ...base, skills: { fervor: 2, restorative: 3 } });
  for (const plan of plans) {
    assert(plan.points <= l.points);
    for (const [enemy, config] of Object.entries(templates)) {
      const r = simulate(plan, config);
      rows.push({ route: l.name, plan: plan.name, points: plan.points, remainingPoints: l.points - plan.points, enemy, winner: r.winner, seconds: r.seconds, hp: r.playerHp });
    }
  }
}
const out = { date: '2026-10-14', scope: 'Fixed non-player-adaptive templates; points do not include money. No blood/class simulation. Existing silver skills cannot be exchanged to gold in stage one.', templates, menu, rows };
if (process.argv.includes('--write')) writeFileSync(new URL('./wudao-stage-calibration-results.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify(rows, null, 2));
