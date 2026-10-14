import { writeFileSync } from 'node:fs';
import { gear, simulate, checks } from './wudao-balance.mjs';
const templates = {
  attack: { items: [...gear('blade', 3), ...gear('hammer dagger mirror shield', 2)], skills: { fervor: 3 } },
  defense: { items: [...gear('mirror', 3), ...gear('blade shield medicine stone dagger', 2)], skills: { fervor: 3, restorative: 5 } },
  poison: { items: [...gear('blade', 3), ...gear('needle needle mirror medicine shield', 2)], skills: { restorative: 5 } },
};
const player = { items: [...gear('blade mirror dagger hammer', 3), ...gear('medicine', 2)], skills: { fervor: 4 }, blood: { lifesteal: 0.1, toxinBonus: 1 } };
const rows = [];
for (const multiplier of [1, 2, 5, 10, 20]) for (const [name, enemy] of Object.entries(templates)) {
  const r = simulate({ ...player, hp: 160 * multiplier }, { ...enemy, hp: 220 * multiplier }, 1, 1800);
  rows.push({ multiplier, playerMaxHp: 160 * multiplier, enemyMaxHp: 220 * multiplier, enemy: name, winner: r.winner, seconds: r.seconds, hp: r.playerHp, enemyHp: r.enemyHp });
}
const out = { date: '2026-10-14', checks: checks(), scope: 'HP-only sensitivity; attack, shielding, healing, growth, poison and storm unchanged. Not a new full-scale balance or economy.', player, templates, rows };
if (process.argv.includes('--write')) writeFileSync(new URL('./wudao-health-scale-results.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify(rows, null, 2));
