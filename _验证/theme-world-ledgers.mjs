import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { actor, gear, defs, simulate } from './wudao-balance.mjs';
import { worlds, routes } from './theme-world-routes.mjs';
import { equipmentPrices } from './wudao-growth-economy.mjs';

const rows = [], enemies = [], fights = [];
for (const world of worlds) {
  const s = world.stage - 1;
  const cyber = world.id.startsWith('cyber');
  const names = cyber ? ['pistol emitter', 'pulseBlade', 'drone emitter battery', 'pulseBlade drone medpack battery', 'pulseBlade emitter battery', 'pistol battery', 'igniter emitter'] : ['curseBlade boneCharm', 'curseBlade', 'curseBlade soulArmor vial', 'curseBlade soulArmor bloodCup vial boneCharm', 'soulArmor vial bloodCup', 'candle boneCharm', 'curseBlade vial'];
  const nodes = [4,8,10,6,16,17,18];
  const configurations = Object.fromEntries(nodes.map((node, i) => {
    const config = { hp: [220,600,1300][s] * ([6,10,16].includes(node) ? 1.5 : 1), items: gear(names[i], s), effectScale: [3,5,8][s], stormScale: [2,4,8][s], skills: cyber ? (s > 0 && [6,10].includes(node) ? { regulated: [0.3,0.3,0.5][s] } : {}) : (node === 16 ? { ward: s === 1 ? 3 : 5 } : {}) };
    actor(config);
    if (!(node === 6 && world.final === 'event')) enemies.push({ world: world.id, node, ...config });
    return [node, config];
  }));
  for (const [route, steps] of Object.entries(routes).filter(([name]) => name !== 'bypass')) {
    let cash = 30, points = 0, parcel = false, sideDelivered = false;
    const bag = [], seen = new Set(), rewards = new Set(), log = [];
    const space = () => bag.reduce((sum, item) => sum + item.size, 0) + Number(parcel);
    const receive = (node, id, size, value, quality = s) => {
      const trial = structuredClone(bag);
      if (defs[id]) {
        while (quality < 3) {
          const match = trial.findIndex(item => item.id === id && item.quality === quality);
          if (match < 0) break;
          trial.splice(match, 1); quality++;
        }
        value = equipmentPrices[size][quality] / 2;
      }
      if (trial.reduce((sum, item) => sum + item.size, 0) + Number(parcel) + size > 10) { log.push({ node, action: 'leave', id }); return; }
      bag.splice(0, bag.length, ...trial, { id, size, value, quality }); log.push({ node, action: 'pickup', id, quality, space: space() });
      assert(space() <= 10);
    };
    for (const node of steps) {
      if (node === 2) {
        if (parcel && seen.has(12) && !sideDelivered) { cash += [12,18,24][s]; points += 2; parcel = false; sideDelivered = true; }
        cash += bag.reduce((sum, item) => sum + item.value, 0); bag.length = 0;
      }
      if (seen.has(node)) continue;
      seen.add(node);
      if (node === 11) { assert(space() < 10); parcel = true; }
      if ([3,7,9,11,12,13,17,18].includes(node)) receive(node, `material-${node}`, 1, 4);
      if (nodes.includes(node) && !(node === 6 && world.final === 'event')) {
        const config = configurations[node];
        const item = config.items[0];
        cash += [6,9,12][s] * (node === 6 ? 2 : [10,16].includes(node) ? 5 / 3 : 1);
        receive(node, item.id, defs[item.id].size, 3);
        rewards.add(`fight-${node}`);
        if ([6,10,16].includes(node)) {
          const ids = cyber ? ['pulseBlade','pistol', 'battery'] : ['curseBlade','vial','boneCharm'];
          for (const id of ids.slice(0, node === 6 ? 3 : 2)) receive(node, id, defs[id].size, 3);
          receive(node, 'recovery', 1, 3);
          rewards.add(`chest-${node}`);
        }
      }
      if (node === 6) { cash += [world.final === 'event' ? 36 : 24,50,70][s]; points += [4,6,8][s]; rewards.add('main'); }
    }
    assert.equal(rewards.has('chest-6'), world.final === 'battle');
    assert.equal(points, [4,6,8][s] + (route === 'main' ? 0 : 2));
    rows.push({ world: world.id, route, cash, points, bagSpace: space(), bag, rewards: [...rewards], log });
  }
  const player = { hp: [450,1300,2800][s], items: gear(cyber ? 'pulseBlade drone medpack battery emitter' : 'curseBlade soulArmor bloodCup vial boneCharm incense', s), effectScale: [3,5,8][s], stormScale: [2,4,8][s], blood: { lifesteal: 0.15, toxinBonus: 2 } };
  for (const enemy of enemies.filter(e => e.world === world.id)) fights.push({ world: world.id, node: enemy.node, ...simulate(player, enemy, 1, 1200) });
}
const output = { scope: '15 fixed ledger routes, all required fights assumed won; no shopping or equipment use. Fixed material drops and actual configured equipment drops; automatic bag merges and standard equipment resale prices. Combat probes are isolated full-HP tests, not continuous-route validation.', enemies, rows, fights };
if (process.argv.includes('--write')) writeFileSync(new URL('./theme-world-ledgers-results.json', import.meta.url), JSON.stringify(output, null, 2) + '\n');
console.log(JSON.stringify({ routes: rows.map(({ world, route, cash, points, bagSpace }) => ({world,route,cash,points,bagSpace})), fights: fights.map(({world,node,winner}) => ({world,node,winner})) }, null, 2));
