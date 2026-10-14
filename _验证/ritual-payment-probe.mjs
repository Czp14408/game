import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';

// Isolated proposal probe only; the skill is not enabled in the combat catalog.
function probe({ shield, cost = 8, amount = 3, selfTrigger = false, events = 1, damageBeforeExecution = 0, targetValid = true }) {
  const queue = Array.from({ length: events }, () => ({ cost, amount, origin: 'item', target: 'enemy' }));
  const log = []; let poison = 0, steps = 0;
  shield = Math.max(0, shield - damageBeforeExecution);
  while (queue.length && steps < 10000) {
    steps++;
    const entry = queue.shift();
    if (!targetValid || shield < entry.cost) { log.push({ step: steps, result: 'invalid-or-insufficient', shield }); continue; }
    shield -= entry.cost; poison += entry.amount;
    log.push({ step: steps, result: 'paid', shield, poison });
    if (selfTrigger) queue.push({ ...entry, origin: 'skill' });
  }
  assert(queue.length === 0, 'Probe protection exceeded; not a normal outcome');
  return { shield, poison, steps, paid: log.filter(x => x.result === 'paid').length, log };
}
assert.equal(probe({ shield: 8 }).shield, 0);
assert.equal(probe({ shield: 7 }).poison, 0);
assert.equal(probe({ shield: 16, events: 2, damageBeforeExecution: 12 }).shield, 4);
assert.equal(probe({ shield: 16, events: 2, damageBeforeExecution: 12 }).poison, 0);
assert.equal(probe({ shield: 100, targetValid: false }).shield, 100);
assert.equal(probe({ shield: 100, selfTrigger: false }).poison, 3);
assert.equal(probe({ shield: 100, selfTrigger: true }).poison, 36);
assert.equal(probe({ shield: 100, selfTrigger: true }).shield, 4);
const rows = [40, 100, 400, 1000].flatMap(shield => [false, true].map(selfTrigger => ({ initialShield: shield, selfTrigger, ...probe({ shield, selfTrigger }) })));
const out = { date: '2026-10-14', scope: 'Eight atomic payment checks and finite isolated shield-to-poison proposals; no real combat, regen, death, blood bonus, input skill acquisition or balance claim. Neither trigger mode is adopted.', rows };
if (process.argv.includes('--write')) writeFileSync(new URL('./ritual-payment-probe-results.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(JSON.stringify(rows.map(({ log, ...x }) => x), null, 2));
