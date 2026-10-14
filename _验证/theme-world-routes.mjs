import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// Reusable fixed test topology, not the procedural map generator.
const edges = [[1,2],[2,3],[3,4],[4,5],[5,6],[2,7],[7,8],[8,9],[9,10],[7,11],[7,12],[12,13],[13,14],[14,3],[5,15],[15,16],[15,17],[17,18],[12,17]];
const worlds = [
  { id: 'cyber1', stage: 1, name: '失电工区', final: 'event', trade: 'regulated' },
  { id: 'cyber2', stage: 2, name: '封锁城区', final: 'battle', trade: 'boot' },
  { id: 'cyber3', stage: 3, name: '核心机房', final: 'battle', trade: 'boot' },
  { id: 'weird2', stage: 2, name: '荒镇疫案', final: 'battle', trade: 'ward' },
  { id: 'weird3', stage: 3, name: '失控祭城', final: 'battle', trade: 'ward' },
];
const routes = {
  main: [1,2,3,4,5,6],
  normal: [1,2,7,11,7,12,7,8,7,2,3,4,5,6],
  deep: [1,2,7,11,7,12,7,8,9,10,9,8,7,2,3,4,5,6],
  bypass: [1,2,3,2,7,12,17,15,5,6],
};
function traverse(world, route, wins = new Set([4,6,8,10,16,17,18]), budget = 11) {
  const visited = new Set([1]);
  let node = 1, investigated = false, barrier = false, complete = false, delivered = false;
  const fought = new Set();
  for (const next of route.slice(1)) {
    assert(edges.some(([a,b]) => a === node && b === next || b === node && a === next), `Disconnected ${node}-${next}`);
    if (node === 4 && next === 5 && !wins.has(4)) throw new Error('Guard blocks connection');
    if (!visited.has(next)) { assert(budget >= 1, 'Insufficient exploration time'); budget--; visited.add(next); }
    node = next;
    if ([4,8,10,16,17,18].includes(node) && wins.has(node)) fought.add(node);
    if (node === 3) investigated = true;
    if (node === 5 && investigated) barrier = true;
    if (node === 6 && investigated && barrier && (world.final === 'event' || wins.has(6))) { complete = true; if (world.final === 'battle') fought.add(6); }
    if (node === 2 && visited.has(11) && visited.has(12)) delivered = true;
  }
  return { visited: visited.size, remaining: budget, complete, delivered, fights: fought.size, smallContainers: [3,7,9,11,12,13,17,18].filter(n => visited.has(n)).length, eliteChests: [10,16].filter(n => visited.has(n) && wins.has(n)).length, bossChests: Number(complete && world.final === 'battle') };
}
const summaries = [];
for (const world of worlds) {
  for (const [route, steps] of Object.entries(routes)) {
    const out = traverse(world, steps);
    assert.equal(out.complete, true);
    assert.equal(out.remaining, { main: 6, normal: 2, deep: 0, bypass: 3 }[route]);
    summaries.push({ world: world.id, route, ...out });
  }
  assert.throws(() => traverse(world, routes.main, new Set()), /Guard/);
  assert.equal(traverse(world, [1,2,7,12,17,15,5,6], new Set()).complete, false);
  assert.equal(traverse(world, routes.bypass, new Set()).complete, world.final === 'event');
  assert.throws(() => traverse(world, routes.deep, undefined, 10), /Insufficient/);
  const stranded = traverse(world, [1,2,7,11,7,8,9,10,9,8,7,12,13,14,3,4]);
  assert.equal(stranded.remaining, 0);
  assert.equal(stranded.complete, false);
}
assert.throws(() => traverse(worlds[0], routes.main, new Set()), /Guard/);
const output = { worlds, edges, routes, summaries, scope: 'Five fixed task maps. Assumes successful required fights and bag capacity for side parcel; no combat/economy/procedural-generation proof.' };
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.includes('--write')) writeFileSync(new URL('./theme-world-routes-results.json', import.meta.url), JSON.stringify(output, null, 2) + '\n');
  console.log(JSON.stringify(output, null, 2));
}
export { worlds, routes, traverse };
