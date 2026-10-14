import { writeFileSync } from 'node:fs';
import { gear, simulate, actor, checks } from './wudao-balance.mjs';

checks();
const builds = {
  original: 'pulseBlade pistol emitter medpack battery pistol accelerator',
  drone: 'pulseBlade drone emitter medpack battery',
  direct: 'drone drone pulseBlade battery battery',
  medical: 'drone emitter medpack medpack battery',
};
const enemies = {
  attack: { items: gear('blade hammer dagger mirror shield stone', 1), skills: { fervor: 2 } },
  defense: { items: gear('pulseBlade emitter medpack battery shield pistol accelerator', 1), skills: { regulated: 0.3, restorative: 3 } },
  anomaly: { items: gear('curseBlade candle bloodCup boneCharm vial soulBell incense', 1), skills: { flame: 4, plague: 0.2 } },
};
const rows = [];
for (const [name, names] of Object.entries(builds)) for (const [skill, skills] of Object.entries({ native: { regulated: 0.3 }, feedback: { regulated: 0.8 }, sharedGrowth: { regulated: 0.3, fervor: 2 } })) for (const [enemy, configuration] of Object.entries(enemies)) {
  const items = gear(names, 1);
  const results = Array.from({ length: 50 }, (_, i) => simulate({ hp: 1300, items, skills, effectScale: 5, stormScale: 4, blood: { lifesteal: 0.15 } }, { hp: 1300, ...configuration, effectScale: 5, stormScale: 4 }, i + 1, 1200));
  rows.push({ name, spaces: actor({ items }).size, skill, enemy, wins: results.filter(r => r.winner === 'player').length, meanSeconds: results.reduce((s, r) => s + r.seconds, 0) / 50 });
}
const output = { scope: '1800 fixed silver-equipment battles; feedback uses diamond skill value, other skills silver. No acquisition proof. Player blood only.', rows };
if (process.argv.includes('--write')) writeFileSync(new URL('./cyber-calibration-results.json', import.meta.url), JSON.stringify(output, null, 2) + '\n');
console.log(JSON.stringify(rows));
