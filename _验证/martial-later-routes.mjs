import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { routes, traverse } from './theme-world-routes.mjs';
const worlds = [{id:'martial2',stage:2,name:'围城镖案',final:'battle'}, {id:'martial3',stage:3,name:'剑冢夺旗',final:'battle'}];
const rows = [];
for (const world of worlds) for (const [route,steps] of Object.entries(routes)) {
  const result = traverse(world,steps);
  assert(result.complete);
  rows.push({world:world.id,route,...result});
}
if (process.argv.includes('--write')) writeFileSync(new URL('./martial-later-routes-results.json',import.meta.url),JSON.stringify({scope:'Eight fixed structural routes only; no combat or acquisition proof.',worlds,rows},null,2)+'\n');
console.log('Two later martial task maps: eight structural route checks passed.');
