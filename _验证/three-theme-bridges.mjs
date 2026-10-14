import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { actor, gear, simulate, checks } from './wudao-balance.mjs';
const dummy = { hp: 1e9, items: [] };
const allocation = process.argv.includes('--proportional') ? 'proportional' : 'attack-first';
const probe = (items, skills = {}, ticks = 300, extra = {}) => simulate({ items, skills, ...extra }, dummy, 1, ticks, false, allocation);
checks();
assert.throws(() => actor({ items: gear('mist') }), /Unsupported quality/);
assert.equal(probe(gear('candle'), {}, 50).burnDamage, 0);
assert.equal(probe(gear('candle'), {}, 60).burnDamage, 2);
assert.equal(probe(gear('candle'), {}, 70).burnDamage, 3);
assert.equal(probe(gear('candle'), { flame: 2 }, 50).shielding, 2);
assert.equal(probe(gear('candle'), { flame: 2 }, 70).shielding, 2);
assert.equal(probe(gear('medicine shield'), { regulated: 0.3 }, 300).items[1].uses, 7);
assert.equal(probe(gear('medicine emitter'), { regulated: 1 }, 300).items[1].uses, 6);
assert.equal(probe(gear('medicine emitter'), { regulated: 1 }, 301).items[1].uses, 7);
assert.equal(probe(gear('medicine needle'), { plague: 1 }, 300).items[1].uses, 8);
assert.equal(probe(gear('dagger vial'), { boot: 1 }, 60).items[1].uses, 1);
assert.equal(probe(gear('dagger'), { boot: 1 }, 60).items[0].uses, 3);
assert.equal(probe(gear('dagger'), { boot: 1 }, 60).bootUsed, true);
const frozen = simulate({ items: gear('blade') }, { items: gear('soulBell') }, 1, 81, false, allocation);
assert.equal(frozen.items[0].uses, 1);
const blood = probe(gear('blade'), { restorative: 2, regulated: 1 }, 80, { currentHp: 50, blood: { lifesteal: 0.1 } });
assert.equal(blood.shielding, 0);
const modes = ['attack-first', 'proportional'].map(mode => {
  const r = simulate({ currentHp: 50, items: gear('blade incense'), blood: { lifesteal: 0.1 } }, { items: gear('shield') }, 1, 80, false, mode);
  return { mode, hp: r.playerHp, attackLifeDamage: r.lifeAttackDamage, lifesteal: r.lifestealHealing };
});
assert(modes[1].lifesteal > modes[0].lifesteal);
const builds = {
  martial: { items: gear('blade dagger mirror medicine shield stone dagger', 1), skills: { fervor: 2 } },
  cyber: { items: gear('pulseBlade pistol emitter medpack battery pistol accelerator', 1), skills: { regulated: 0.3 } },
  weird: { items: gear('curseBlade candle bloodCup boneCharm vial soulBell incense', 1), skills: { flame: 4, plague: 0.2 } },
  martialCyber: { items: gear('blade dagger mirror medpack battery pistol accelerator', 1), skills: { fervor: 2, regulated: 0.3 } },
  cyberWeird: { items: gear('pulseBlade emitter medpack candle vial vial incense', 1), skills: { regulated: 0.3, flame: 4, plague: 0.2 } },
  martialWeird: { items: gear('blade mirror incense needle shield soulBell dagger', 1), skills: { fervor: 2, restorative: 3, flame: 4, plague: 0.2 } },
};
const enemies = {
  attack: { hp: 1300, items: gear('blade hammer dagger mirror shield stone', 1), skills: { fervor: 2 } },
  defense: { hp: 1300, items: gear('pulseBlade emitter medpack battery shield pistol accelerator', 1), skills: { regulated: 0.3, restorative: 3 } },
  anomaly: { hp: 1300, items: gear('curseBlade candle bloodCup boneCharm vial soulBell incense', 1), skills: { flame: 4, plague: 0.2 } },
};
const summaries = [];
for (const [name, build] of Object.entries(builds)) for (const [enemyName, enemy] of Object.entries(enemies)) {
  const rows = Array.from({ length: 50 }, (_, i) => simulate({ ...build, hp: 1300, effectScale: 5, stormScale: 4, blood: { lifesteal: 0.15, toxinBonus: 4 } }, { ...enemy, effectScale: 5, stormScale: 4 }, i + 1, 1200, true, allocation));
  summaries.push({ name, spaces: actor(build).size, enemy: enemyName, wins: rows.filter(x => x.winner === 'player').length, meanSeconds: rows.reduce((a, x) => a + x.seconds, 0) / rows.length, meanHp: rows.reduce((a, x) => a + x.playerHp, 0) / rows.length });
}
const out = { date: '2026-10-14', allocation, scope: '39 existing combat checks plus bridge checks; 900 fixed mixed-build battles. Attack-first shield absorption is adopted; proportional is historical comparison only. No acquisition/economy proof, no resource payment skill, no full three-world trial.', builds, enemies, modes, summaries };
if (process.argv.includes('--write')) writeFileSync(new URL(allocation === 'attack-first' ? './three-theme-bridges-results.json' : './three-theme-bridges-proportional-results.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify({ modes, summaries }, null, 2));
