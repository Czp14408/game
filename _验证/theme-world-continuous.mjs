import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { gear, simulate } from './wudao-balance.mjs';
import { worlds, routes } from './theme-world-routes.mjs';
const fixtures = JSON.parse(readFileSync(new URL('./theme-world-ledgers-results.json',import.meta.url),'utf8'));
const summaries = [], examples = [];
function run(world,route,seed) {
  const index = world.stage - 1, cyber = world.id.startsWith('cyber');
  const player = {hp:[450,1300,2800][index], items:gear(cyber ? 'pulseBlade drone medpack battery emitter' : 'curseBlade soulArmor bloodCup vial boneCharm incense',index), effectScale:[3,5,8][index], stormScale:[2,4,8][index], blood:{lifesteal:0.15,toxinBonus:2}};
  let hp = player.hp, losses = 0, money = 30, points = 0;
  const done = new Set(), log = [], visited = new Set();
  for (const node of routes[route]) {
    if (visited.has(node)) continue;
    visited.add(node);
    const enemy = fixtures.enemies.find(e => e.world === world.id && e.node === node);
    if (enemy) {
      while (true) {
        const before = hp, result = simulate({...player,currentHp:hp},enemy,seed,1800);
        assert.notEqual(result.winner,'timeout','Technical ceiling must not become a defeat');
        hp = result.playerHp;
        log.push({node,before,hp,winner:result.winner,seconds:result.seconds});
        if (result.winner === 'player') {
          assert(!done.has(node)); done.add(node);
          money += [6,9,12][index] * (node === 6 ? 2 : [10,16].includes(node) ? 5/3 : 1);
          break;
        }
        losses++;
        if (losses === 3) return {world:world.id,route,seed,completed:false,hp:0,losses,money,points,log};
        hp = player.hp;
        log.push({node,action:'defeat recovery',hp,losses});
      }
    }
    if (node === 6) { money += [world.final === 'event' ? 36 : 24,50,70][index]; points += [4,6,8][index]; }
  }
  return {world:world.id,route,seed,completed:true,hp,losses,money,points,log};
}
for (const world of worlds) for (const route of ['main','normal','deep']) {
  const results = Array.from({length:50},(_,i)=>run(world,route,i+1));
  summaries.push({world:world.id,route,completed:results.filter(r=>r.completed).length,meanLosses:results.reduce((sum,r)=>sum+r.losses,0)/50,meanHp:results.reduce((sum,r)=>sum+r.hp,0)/50});
  examples.push(results[0],results.find(r=>!r.completed) ?? results.at(-1));
}
const output = {scope:'750 conditional five-world route probes with actual configured enemies, HP carry-over and three-loss termination. Fixed starting equipment/HP/blood; no midroute shopping, healing, loot use, resale, sidequest payouts or stage bosses. Victory cash only after winning, failure gains no new reward. Not overall trial win rates.',summaries,examples};
if (process.argv.includes('--write')) writeFileSync(new URL('./theme-world-continuous-results.json',import.meta.url),JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify(summaries,null,2));
