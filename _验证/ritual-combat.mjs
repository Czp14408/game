import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { simulate, gear, checks } from './wudao-balance.mjs';

const empty = { hp: 1e9, items: [] };
const run = (names, ticks, extra = {}, enemy = empty) => simulate({ hp: 10000, items: gear(names), skills: { ward: 3 }, ...extra }, enemy, 1, ticks);
const first = run('shield needle', 40);
assert.equal(first.wardPayments, 0);
assert.equal(first.playerShield, 7);
assert.equal(first.pendingEffects, 0);
const paid = run('soulArmor vial', 60);
assert.equal(paid.wardPayments, 1);
assert.equal(paid.wardSpent, 8);
assert.equal(paid.wardPoison, 3);
assert.equal(paid.poisonDamage, 0);
assert.equal(paid.playerShield, 6);
assert.equal(run('soulArmor vial', 61).pendingEffects, 0);
const repeated = run('soulArmor vial', 62, { items: gear('soulArmor vial', 1) });
assert.equal(repeated.wardPayments, 2);
assert.equal(repeated.wardPoison, 6);
const scaled = run('soulArmor vial', 62, { items: gear('soulArmor vial', 1), effectScale: 5, blood: { toxinBonus: 9 } });
assert.equal(scaled.wardSpent, 80);
assert.equal(scaled.wardPoison, 30);
assert.equal(scaled.enemyPoison, 54);
const attacked = run('soulArmor vial', 60, {}, { hp: 10000, items: gear('drone') });
assert.equal(attacked.wardPayments, 0);
assert.equal(attacked.playerShield, 0);
const simultaneous = run('soulArmor vial vial', 60, { items: gear('soulArmor vial vial', 1) });
assert.equal(simultaneous.wardPayments, 1);
assert.equal(simultaneous.pendingEffects, 2);
assert.equal(run('soulArmor vial vial', 62, { items: gear('soulArmor vial vial', 1) }).pendingEffects, 1);
assert.equal(run('soulArmor vial vial', 63, { items: gear('soulArmor vial vial', 1) }).pendingEffects, 0);
const death = run('soulArmor vial', 60, {}, { hp: 10000, items: gear('drone', 3), effectScale: 1000 });
assert.equal(death.wardPayments, 0);
assert.equal(death.pendingEffects, 0);
assert.equal(run('soulArmor vial', 62, { items: gear('soulArmor vial', 1), skills: { ward: 3, fervor: 2, restorative: 2 } }).shielding, 22);

const rows = [];
for (const [name, names] of Object.entries({ poison: 'curseBlade soulArmor vial bloodCup boneCharm incense', shield: 'curseBlade soulArmor soulArmor vial boneCharm boneCharm', hybrid: 'needle mirror soulArmor vial medicine boneCharm incense' })) {
  for (const [enemy, equipment] of Object.entries({ attack: 'blade hammer dagger shield medicine', cyber: 'pulseBlade drone emitter battery medpack', weird: 'curseBlade soulArmor vial bloodCup boneCharm incense' })) {
    for (const ward of [0, 3, 5]) {
      const results = Array.from({ length: 50 }, (_, i) => simulate({ hp: 1300, items: gear(names), effectScale: 5, stormScale: 4, skills: { ward }, blood: { lifesteal: 0.15, toxinBonus: 4 } }, { hp: 1300, items: gear(equipment), effectScale: 5, stormScale: 4 }, i + 1, 1200));
      const mean = key => results.reduce((sum, r) => sum + r[key], 0) / results.length;
      rows.push({ name, enemy, ward, wins: results.filter(r => r.winner === 'player').length, payments: mean('wardPayments'), spent: mean('wardSpent'), extraPoison: mean('wardPoison'), seconds: mean('seconds') });
    }
  }
}
const output = { baselineChecks: checks(), scope: 'Fixed equipment combat only; no acquisition or economy model. Gold/diamond skill tested with bronze equipment.', rows };
if (process.argv.includes('--write')) writeFileSync(new URL('./ritual-combat-results.json', import.meta.url), JSON.stringify(output, null, 2) + '\n');
console.log(JSON.stringify(output, null, 2));
