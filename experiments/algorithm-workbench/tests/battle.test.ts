import { test } from "node:test";
import assert from "node:assert/strict";
import {
  causalEvent,
  uniqueEvents,
  type BattleEvent,
  type BattleFrame,
} from "../src/presentation/battle";
import { validateBattle } from "../src/presentation/validateBattle";
const allocation: BattleEvent = {
  id: "allocation_5_unit",
  tick: 1,
  kind: "shared_fire_allocation",
  effectiveTime: 5,
  targetId: "blue",
  causeIds: ["red"],
  raw: { event_id: "allocation_5_unit" },
};
const injury: BattleEvent = {
  id: "person_1",
  tick: 1,
  kind: "personal_injury",
  effectiveTime: 5,
  actorId: "squad",
  causeIds: ["allocation_5_unit"],
  raw: {
    event_id: "person_1",
    detail: { before_health: 1, after_health: 0.99 },
  },
};
const frame: BattleFrame = {
  schemaVersion: "wwo-battle/frame/v1",
  tick: 1,
  time: 5,
  view: "DEBUG_TRUTH",
  sourceCommit: "test",
  entities: [],
  events: [allocation, injury],
  dropped: 0,
  unlocatedUnits: [],
  nodes: {},
  gaps: [],
  scope: "test",
  source: {},
};
test("damage follows original cause IDs only, missing causes stay missing", () => {
  assert.equal(causalEvent(injury, [allocation, injury]), allocation);
  assert.equal(
    causalEvent({ ...injury, causeIds: ["not-exported"] }, [allocation]),
    undefined,
  );
  assert.deepEqual(uniqueEvents([frame, frame]), [allocation, injury]);
});
test("replay rejects mismatched IDs, duplicate events and malformed nodes", () => {
  validateBattle(frame);
  assert.throws(
    () =>
      validateBattle({
        ...frame,
        events: [{ ...injury, raw: { event_id: "invented" } }],
      }),
    /因果/,
  );
  assert.throws(
    () => validateBattle({ ...frame, events: [injury, injury] }),
    /因果/,
  );
  assert.throws(
    () => validateBattle({ ...frame, nodes: { A: { xy: [0] } } }),
    /坐标/,
  );
  assert.throws(
    () => validateBattle({ ...frame, view: "PERSON_VISIBLE" }),
    /观测/,
  );
});

import { gridCells, cellAt } from "../src/presentation/battleGrid";
test("50km parent contains four theatres and 100 disjoint 5km cells; camera hierarchy adds no state", () => {
  const parents = gridCells(25),
    cells = gridCells(5);
  assert.equal(parents.length, 4);
  assert.equal(cells.length, 100);
  assert.equal(new Set(cells.map((c) => c.id)).size, 100);
  for (const p of parents)
    assert.equal(
      cells.filter((c) => cellAt(c.x + 2.5, c.y + 2.5, 25)?.id === p.id).length,
      25,
    );
  assert.equal(cellAt(0, 0, 5)?.id, "5:0:0");
  assert.equal(cellAt(50, 50, 5), undefined);
});
