import assert from 'node:assert/strict';

const initial = () => ({ lanes: [['clue','box'],['junk'],[]], cards: {
  clue: { known: true, movable: false },
  box: { known: true, movable: true, support: true, contents: ['medicine'], guardian: 'enemy' },
  junk: { known: true, movable: true, support: true },
  enemy: { known: true, movable: false, enemy: true },
}, defeated: [] });
const locate = (s, id) => s.lanes.findIndex(lane => lane.includes(id));
const exposed = (s, id) => { const i = locate(s,id); return i >= 0 && s.lanes[i].at(-1) === id; };
const accessible = (s, id) => exposed(s,id) && s.cards[id].known;
function move(s, id, destination, confirm = false) {
  assert(accessible(s,id), 'Not accessible');
  assert(s.cards[id].movable, 'Fixed object');
  const source = locate(s,id);
  assert(source !== destination, 'Same location');
  const top = s.lanes[destination].at(-1);
  if (top && s.cards[top].enemy && !s.defeated.includes(top)) {
    if (!confirm) return { status: 'confirmation', before: structuredClone(s) };
    return { status: 'battle', before: structuredClone(s), id, destination };
  }
  if (top) {
    assert(accessible(s,top), 'Unknown destination');
    assert(s.cards[top].support && s.lanes[destination].length < 2, 'Unsupported or full');
  }
  s.lanes[source].pop(); s.lanes[destination].push(id);
  return { status: 'moved' };
}
function settle(battle, won) {
  assert.equal(battle.status,'battle');
  const restored = structuredClone(battle.before);
  if (!won) return restored;
  const enemy = restored.lanes[battle.destination].at(-1);
  restored.defeated.push(enemy);
  restored.lanes[locate(restored,battle.id)].pop();
  restored.lanes[battle.destination].push(battle.id);
  return restored;
}
const s = initial();
assert.equal(accessible(s,'clue'),false);
assert.throws(() => move(s,'clue',2), /accessible/);
move(s,'box',1);
assert.equal(accessible(s,'clue'),true);
assert.deepEqual(s.cards.box.contents,['medicine']);
assert.deepEqual(s.lanes[0],['clue']);
assert.equal(s.cards.clue.known,true);
assert.throws(() => move(s,'junk',2), /accessible/);
move(s,'box',2);
assert.throws(() => move(s,'clue',1), /Fixed/);
const unknown = initial(); unknown.cards.junk.known = false;
assert.throws(() => move(unknown,'box',1), /Unknown/);
const full = initial(); full.cards.extra = { known:true,movable:true,support:true }; full.lanes.push(['extra']);
move(full,'box',1);
assert.throws(() => move(full,'extra',1), /full/);
const danger = initial(); danger.lanes.push(['enemy']);
const before = structuredClone(danger);
assert.equal(move(danger,'box',3).status,'confirmation');
assert.deepEqual(danger,before);
const battle = move(danger,'box',3,true);
assert.equal(battle.status,'battle');
assert.deepEqual(battle.before,before);
assert.deepEqual(danger,battle.before);
assert(!danger.defeated.includes(danger.cards.box.guardian));
assert.deepEqual(settle(battle,false),before);
const victory = settle(battle,true);
assert.deepEqual(victory.lanes[3],['enemy','box']);
assert(victory.defeated.includes(victory.cards.box.guardian));
assert.equal(victory.lanes.flat().filter(id => id === 'box').length,1);
assert.deepEqual(victory.cards.box.contents,['medicine']);

function reachable(start, target) {
  const queue = [structuredClone(start)], seen = new Set();
  while (queue.length) {
    const current = queue.shift(), key = JSON.stringify(current.lanes);
    if (seen.has(key)) continue;
    seen.add(key);
    if (accessible(current,target)) return true;
    for (const lane of current.lanes) {
      const id = lane.at(-1);
      if (!id || !accessible(current,id) || !current.cards[id].movable) continue;
      for (let destination = 0; destination < current.lanes.length; destination++) {
        const next = structuredClone(current);
        try { if (move(next,id,destination).status === 'moved') queue.push(next); } catch {}
      }
    }
  }
  return false;
}
assert.equal(reachable(initial(),'clue'),true);
const deadlock = initial(); deadlock.lanes = [['clue','box']];
assert.equal(reachable(deadlock,'clue'),false);
console.log('Node stack boundaries and reachable/deadlocked fixtures passed. No engine/UI validation.');
