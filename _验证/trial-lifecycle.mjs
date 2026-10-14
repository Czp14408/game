import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { gear, rng, simulate } from './wudao-balance.mjs';

const themes = stage => stage === 1 ? ['martial','cyber'] : ['martial','cyber','weird'];
function start(seed = 1) {
  return { seed, stage: 1, phase: 'choice', losses: 0, hp: 450, maxHp: 450, money: 30, points: 0,
    items: gear('blade dagger mirror shield medicine'), skills: {}, world: null, opponent: null, shop: null, battleSerial: 0, activeBattle: null, outcome: null, recap: null };
}
function active(s) { assert(!s.outcome, 'Trial ended'); }
function candidates(s) {
  active(s); assert.equal(s.phase,'choice');
  const random = rng(s.seed + s.stage * 10007), pool = [...themes(s.stage)];
  const out = [];
  while (out.length < 2) out.push(pool.splice(Math.floor(random() * pool.length),1)[0]);
  return out;
}
function enter(s, theme) {
  assert(candidates(s).includes(theme), 'Not offered');
  s.world = { id: `${s.stage}:${theme}`, theme, time: 11, visited: [1], records: [], rewards: [], completed: false, board: { placements: ['clue','box'], discovered: ['box'] } };
  s.phase = 'world';
}
function visit(s, node) {
  active(s); assert.equal(s.phase,'world');
  if (!s.world.visited.includes(node)) { assert(s.world.time > 0, 'No exploration time'); s.world.time--; s.world.visited.push(node); }
}
function record(s, key) {
  active(s); assert.equal(s.phase,'world');
  if (!s.world.records.includes(key)) s.world.records.push(key);
}
function finishMain(s) {
  active(s); assert.equal(s.phase,'world');
  assert(s.world.records.includes('investigation') && s.world.records.includes('preparation'), 'Missing prerequisite');
  assert(s.world.records.includes('objective'), 'Objective incomplete');
  if (s.world.completed) return false;
  s.world.completed = true; s.money += [24,50,70][s.stage - 1]; s.points += [4,6,8][s.stage - 1];
  s.world.rewards.push('main'); return true;
}
function opponent(s) {
  const random = rng(s.seed + s.stage * 31337);
  const id = random() < 0.5 ? 'dagger' : 'blade';
  return { hp: [300,700,1400][s.stage - 1], items: gear(`${id} shield medicine`,s.stage - 1), skills: {}, effectScale: [3,5,8][s.stage - 1], stormScale: [2,4,8][s.stage - 1] };
}
function returnHub(s) {
  active(s); assert.equal(s.phase,'world'); assert(s.world.completed,'Main incomplete');
  s.world = null; s.phase = 'hub'; s.opponent = opponent(s);
  s.shop = { refreshes: 0, stock: ['vitality','edge',null] };
}
function heal(s) {
  active(s); assert.equal(s.phase,'hub'); s.hp = s.maxHp;
}
function end(s, outcome) {
  s.recap = { outcome, stage: s.stage, losses: s.losses, money: s.money, points: s.points };
  s.outcome = outcome; s.phase = 'ended'; s.money = 0; s.points = 0; s.items = []; s.skills = {};
  s.hp = 0; s.maxHp = 0; s.world = null; s.shop = null; s.opponent = null;
  s.activeBattle = null;
}
function surrender(s) { active(s); end(s,'surrender'); }
function beginFight(s, kind, id, enemy) {
  active(s); assert(['world','hub'].includes(s.phase),'Battle in progress or wrong phase');
  assert.equal(s.phase,kind === 'boss' ? 'hub' : 'world');
  if (kind !== 'boss') assert(!s.world.rewards.includes(`fight:${id}`),'Already defeated');
  const battle = { token: ++s.battleSerial, kind, id, origin: s.phase, beforeBoard: structuredClone(s.world?.board ?? null), enemy: structuredClone(kind === 'boss' ? s.opponent : enemy) };
  s.activeBattle = battle.token;
  s.phase = 'battle'; return battle;
}
function settleFight(s, battle, result) {
  active(s); assert.equal(s.phase,'battle');
  assert.equal(s.activeBattle,battle.token,'Stale battle result');
  assert(['player','enemy'].includes(result.winner),'Technical timeout is not a gameplay defeat');
  s.activeBattle = null;
  s.hp = result.playerHp;
  if (result.winner === 'enemy') {
    s.losses++;
    if (s.losses >= 3) { end(s,'defeat'); return; }
    if (s.world) s.world.board = structuredClone(battle.beforeBoard);
    s.hp = s.maxHp; s.phase = battle.origin; return;
  }
  if (battle.kind === 'boss') {
    if (s.stage === 3) { end(s,'victory'); return; }
    s.stage++; s.phase = 'choice'; s.opponent = null; s.shop = null;
  } else { s.world.rewards.push(`fight:${battle.id}`); s.money += [6,9,12][s.stage - 1]; s.phase = 'world'; }
}
function fight(s, kind, id, enemy) {
  const battle = beginFight(s,kind,id,enemy);
  const result = simulate({ hp:s.maxHp, currentHp:s.hp, items:s.items, skills:s.skills, effectScale:[3,5,8][s.stage-1], stormScale:[2,4,8][s.stage-1] },battle.enemy,s.seed,1800);
  settleFight(s,battle,result); return result;
}

function checks() {
  const s = start(3); assert.equal(candidates(s).length,2); assert(!candidates(s).includes('weird'));
  const offered = candidates(s); s.items = gear('needle'); assert.deepEqual(candidates(s),offered);
  enter(s,offered[0]); s.hp = 123; visit(s,2); visit(s,2); assert.equal(s.world.time,10);
  assert.throws(() => returnHub(s),/Main/); assert.throws(() => finishMain(s),/prerequisite/);
  record(s,'investigation'); record(s,'preparation'); record(s,'objective');
  assert(finishMain(s)); const money = s.money; assert.equal(finishMain(s),false); assert.equal(s.money,money);
  returnHub(s); assert.equal(s.hp,123); const fixed = structuredClone(s.opponent);
  s.shop.refreshes = 2; s.shop.stock[0] = null;
  const battle = beginFight(s,'boss'); assert.throws(() => heal(s));
  settleFight(s,battle,{winner:'enemy',playerHp:0}); assert.equal(s.hp,450);
  assert.deepEqual(s.opponent,fixed); assert.equal(s.shop.refreshes,2); assert.equal(s.shop.stock[0],null); assert.equal(s.money,money);
  const win = beginFight(s,'boss'); settleFight(s,win,{winner:'player',playerHp:5});
  assert.equal(s.stage,2); assert.equal(s.hp,5); assert.equal(s.money,money);
  enter(s,candidates(s)[0]); assert.equal(s.world.time,11); assert.equal(s.hp,5);
  record(s,'earlier-record'); s.world.board.discovered.push('clue');
  const lost = beginFight(s,'world',4,{hp:100,items:[]}); s.world.board.placements.reverse();
  assert.throws(() => settleFight(s,battle,{winner:'enemy',playerHp:0}),/Stale/);
  settleFight(s,lost,{winner:'enemy',playerHp:0}); assert.deepEqual(s.world.board,lost.beforeBoard); assert(s.world.records.includes('earlier-record'));
  const finalLoss = beginFight(s,'world',4,{hp:100,items:[]}); settleFight(s,finalLoss,{winner:'enemy',playerHp:0});
  assert.equal(s.outcome,'defeat'); assert.equal(s.hp,0); assert.equal(s.money,0); assert.deepEqual(s.items,[]);
  assert.throws(() => enter(s,'martial'),/ended/);
  const won = start(); won.phase = 'hub'; won.stage = 3; won.opponent = opponent(won); const final = beginFight(won,'boss');
  settleFight(won,final,{winner:'player',playerHp:10}); assert.equal(won.outcome,'victory'); assert.equal(won.recap.money,30); assert.equal(won.money,0);
  const quit = start(); enter(quit,candidates(quit)[0]); surrender(quit); assert.equal(quit.losses,0); assert.equal(quit.outcome,'surrender');
}
function probe(seed) {
  const s = start(seed), log = [];
  for (let stage = 1; stage <= 3; stage++) {
    enter(s,candidates(s)[0]);
    for (const node of [2,3,4,5,6]) visit(s,node);
    record(s,'investigation'); record(s,'preparation');
    // Explicit fixed loadout fixture: not earned loot or a production starting kit.
    s.items = gear('blade dagger mirror shield medicine',stage - 1);
    s.maxHp = [450,1300,2800][stage - 1]; s.hp = Math.min(s.maxHp,s.hp);
    for (const node of [4,6]) {
      const enemy = { hp:[100,300,600][stage-1], items:gear('dagger shield',stage-1), effectScale:[3,5,8][stage-1] };
      while (true) {
        const r = fight(s,'world',node,enemy); log.push({stage,kind:'world',node,winner:r.winner,hp:s.hp,losses:s.losses});
        if (s.outcome) return {seed,outcome:s.outcome,log};
        if (r.winner === 'player') break;
      }
    }
    record(s,'objective'); finishMain(s); returnHub(s); heal(s);
    while (true) {
      const r = fight(s,'boss'); log.push({stage,kind:'boss',winner:r.winner,hp:s.hp,losses:s.losses});
      if (s.outcome) return {seed,outcome:s.outcome,log};
      if (r.winner === 'player') break;
    }
  }
  throw new Error('Missing terminal state');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  checks(); const trials = Array.from({length:50},(_,i)=>probe(i+1));
  const output = { scope:'Lifecycle invariants and 50 continuous combat fixtures. Fixed stage equipment and max HP, simplified task/loot, no acquisition or economic balance proof. World combat fixtures do not represent the five task worlds.', counts: Object.fromEntries(['victory','defeat'].map(outcome=>[outcome,trials.filter(r=>r.outcome===outcome).length])), trials };
  if (process.argv.includes('--write')) writeFileSync(new URL('./trial-lifecycle-results.json',import.meta.url),JSON.stringify(output,null,2)+'\n');
  console.log(JSON.stringify({scope:output.scope,counts:output.counts}));
}
export {start,candidates,enter,visit,record,finishMain,returnHub,heal,end,surrender,beginFight,settleFight,fight,checks};
