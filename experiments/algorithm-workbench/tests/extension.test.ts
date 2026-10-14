import test from "node:test";
import assert from "node:assert/strict";
import {
  Run,
  runToEnd,
  validateSnapshot,
  stateDifferences,
} from "../src/core/runtime";
import { metricSegments } from "../src/presentation/metricSeries";
import { economyAdapter } from "../src/adapters/economy";
import { militaryAdapter } from "../src/adapters/military";
import {
  economyScenario,
  militaryScenario,
  validateScenario,
} from "../src/core/scenario";
import {
  evaluateExpectations,
  diagnoseVerdict,
} from "../src/core/expectations";
import { clone, type AlgorithmAdapter } from "../src/core/types";
import { syntheticTerrain } from "../src/terrain/synthetic";
import {
  projectUnits,
  terrainPositions,
  groundHeight,
  clippedSegment,
} from "../src/terrain/sceneData";
test("river segments crossing the display boundary are clipped without joining gaps or modifying source", () => {
  const terrain = syntheticTerrain();
  const original = JSON.stringify(terrain);
  assert.deepEqual(
    clippedSegment(terrain, [640000, 6200000], [1160000, 6200000]),
    [
      [650000, 6200000],
      [1150000, 6200000],
    ],
  );
  assert.deepEqual(
    clippedSegment(terrain, [640000, 6200000], [640000, 6250000]),
    [],
  );
  assert.equal(JSON.stringify(terrain), original);
});
import {
  createUnitGeometry,
  disposeObject,
} from "../src/presentation/unitGeometry";

test("missing measurements stay gaps in curves and explicit unknowns in differences", async () => {
  const run = await Run.create(economyAdapter, economyScenario);
  await run.step();
  await run.step();
  await run.step();
  const history = clone(run.history);
  delete history[1].metrics.fulfilled;
  assert.deepEqual(metricSegments(history, "fulfilled"), [
    [{ tick: 0, value: 0 }],
    [
      { tick: 2, value: 20 },
      { tick: 3, value: 30 },
    ],
  ]);
  assert.deepEqual(metricSegments(history, "unprovided"), []);
  assert.deepEqual(
    stateDifferences(history[0], history[1]).find((c) => c.key === "fulfilled"),
    { key: "fulfilled", from: 0, to: null },
  );
  assert.deepEqual(
    stateDifferences(history[1], history[2]).find((c) => c.key === "fulfilled"),
    { key: "fulfilled", from: null, to: 20 },
  );
});
test("real source orders may omit loss and status; missing loss never becomes a passed zero", async () => {
  const run = await Run.create(economyAdapter, economyScenario);
  await run.step();
  const snapshot = clone(run.current);
  delete snapshot.orders[0].lost;
  delete snapshot.orders[0].status;
  assert.doesNotThrow(() => validateSnapshot(snapshot));
  const scenario = clone(economyScenario);
  scenario.expectations.rules = [
    {
      id: "loss",
      label: "independent loss check",
      target: "order",
      subjectId: "ORD-001",
      key: "lost",
      operator: "eq",
      value: 0,
      byTick: 1,
    },
  ];
  assert.equal(
    evaluateExpectations(scenario, [run.history[0], snapshot])[0].status,
    "undefined",
  );
});
test("entity-specific independent expectation diagnoses the actual unit and failing tick", async () => {
  const s = clone(militaryScenario);
  s.params.speed = 0;
  const result = await runToEnd(militaryAdapter, s);
  const verdict = result.verdicts.find((v) => v.id === "unit-arrival")!;
  assert.equal(verdict.status, "fail");
  assert.equal(verdict.subjectId, "blue");
  assert.equal(verdict.tick, 10);
  const diagnosis = diagnoseVerdict(verdict, result.history);
  assert.equal(diagnosis.subject?.id, "blue");
  assert.ok(diagnosis.events.every((e) => e.entityId === "blue"));
  assert.ok(diagnosis.events.some((e) => e.message.includes("位置 0")));
});
test("typed order state and cumulative event rules detect original duplicate-event counterexample", async () => {
  const run = await Run.create(economyAdapter, economyScenario);
  await run.step();
  const s = clone(economyScenario);
  s.expectations.rules = [
    {
      id: "state",
      label: "Order must be consumed",
      target: "order",
      subjectId: "ORD-001",
      key: "status",
      operator: "eq",
      value: "已消费",
      byTick: 1,
    },
    {
      id: "allocation",
      label: "This order is allocated once",
      target: "eventCount",
      subjectId: "ORD-001",
      key: "allocation",
      operator: "eq",
      value: 1,
      byTick: 1,
    },
  ];
  assert.ok(
    evaluateExpectations(s, run.history).every((v) => v.status === "pass"),
  );
  const faulty = clone(run.history);
  faulty[1].events.push(
    clone(faulty[1].events.find((e) => e.stage === "allocation")!),
  );
  const verdict = evaluateExpectations(s, faulty).find(
    (v) => v.id === "allocation",
  )!;
  assert.equal(verdict.status, "fail");
  assert.equal(verdict.actual, 2);
  assert.equal(verdict.difference, 1);
});
test("missing subject stays pending before deadline, then undefined rather than passing", async () => {
  const run = await Run.create(militaryAdapter, militaryScenario),
    s = clone(militaryScenario);
  s.expectations.rules = [
    {
      id: "absent",
      label: "unprovided unit",
      target: "entity",
      subjectId: "missing",
      key: "x",
      operator: "eq",
      value: 10,
      byTick: 1,
    },
  ];
  assert.equal(evaluateExpectations(s, run.history)[0].status, "pending");
  await run.step();
  assert.equal(evaluateExpectations(s, run.history)[0].status, "undefined");
  const bad = clone(s);
  bad.expectations.rules[0].value = "arrived";
  bad.expectations.rules[0].operator = "gte";
  assert.throws(() => validateScenario(bad), /预期规则/);
});
test("an observed failure is retained even when a different sample is unavailable", async () => {
  const run = await Run.create(militaryAdapter, militaryScenario);
  await run.step();
  await run.step();
  const history = clone(run.history);
  history[1].invariants.ammo = 1;
  delete history[2].invariants.ammo;
  const verdict = evaluateExpectations(militaryScenario, history).find(
    (v) => v.id === "ammo",
  )!;
  assert.equal(verdict.status, "fail");
  assert.equal(verdict.tick, 1);
  assert.equal(verdict.actual, 1);
});
test("malformed causal identifiers are rejected before the diagnosis UI renders", async () => {
  const run = await Run.create(economyAdapter, economyScenario);
  await run.step();
  const snapshot = clone(run.current);
  (snapshot.events[0] as unknown as Record<string, unknown>).causeId = {
    bad: "object",
  };
  assert.throws(() => validateSnapshot(snapshot), /事件记录无效/);
});
test("source-declared causes are followed without guessing unrelated entities", async () => {
  const run = await Run.create(economyAdapter, economyScenario);
  await run.step();
  await run.step();
  const history = clone(run.history);
  history[1].events = [
    {
      id: "cause-1",
      tick: 1,
      stage: "command",
      status: "success",
      message: "explicit synthetic command",
      entityId: "buyer",
    },
  ];
  history[2].events = [
    {
      id: "effect-2",
      causeId: "cause-1",
      tick: 2,
      stage: "result",
      status: "blocked",
      message: "explicit synthetic effect",
      entityId: "ORD-002",
    },
  ];
  const detail = diagnoseVerdict(
    {
      id: "fixture",
      label: "fixture",
      status: "fail",
      expected: "fixture",
      actual: 0,
      difference: 1,
      detail: "original fixture only",
      tick: 2,
      subjectId: "ORD-002",
    },
    history,
  );
  assert.deepEqual(
    detail.events.map((e) => e.id),
    ["cause-1", "effect-2"],
  );
  assert.equal(detail.explicitCausalLinks, true);
});
test("PENDING keeps committed state/history unchanged until a complete tick arrives", async () => {
  const adapter: AlgorithmAdapter = {
    metadata: economyAdapter.metadata,
    async create(s) {
      const original = await economyAdapter.create(s);
      let first = true;
      return {
        snapshot: original.snapshot,
        session: {
          async step() {
            if (first) {
              first = false;
              return {
                kind: "pending" as const,
                committedTick: 0,
                reason: "bounded kernel continuation",
              };
            }
            return original.session.step();
          },
          close: () => original.session.close(),
        },
      };
    },
  };
  const run = await Run.create(adapter, economyScenario);
  const before = clone(run.current);
  await run.step();
  assert.deepEqual(run.current, before);
  assert.equal(run.history.length, 1);
  assert.match(run.pendingReason, /continuation/);
  await run.step();
  assert.equal(run.current.tick, 1);
  assert.equal(run.pendingReason, "");
});
test("failed calls freeze the committed state, persist failure, and require reset before reuse", async () => {
  let creates = 0,
    calls = 0;
  const adapter: AlgorithmAdapter = {
    metadata: economyAdapter.metadata,
    async create(s) {
      const original = await economyAdapter.create(s);
      creates++;
      const first = creates === 1;
      return {
        snapshot: original.snapshot,
        session: {
          async step() {
            calls++;
            if (first) throw new Error("source failed after invocation");
            return original.session.step();
          },
          close: () => original.session.close(),
        },
      };
    },
  };
  const run = await Run.create(adapter, economyScenario);
  const before = clone(run.current);
  await assert.rejects(run.step(), /source failed/);
  assert.deepEqual(run.current, before);
  assert.equal(run.history.length, 1);
  assert.equal(run.result().executionError?.lastCommittedTick, 0);
  await assert.rejects(run.step(), /先重置/);
  assert.equal(calls, 1);
  await run.reset();
  assert.equal(run.result().executionError, undefined);
  await run.step();
  assert.equal(run.current.tick, 1);
});
test("PENDING cannot invent committed progress and endless pending has a bounded failure", async () => {
  const bad: AlgorithmAdapter = {
    metadata: economyAdapter.metadata,
    async create(s) {
      const original = await economyAdapter.create(s);
      return {
        snapshot: original.snapshot,
        session: {
          async step() {
            return {
              kind: "pending" as const,
              committedTick: 1,
              reason: "invalid",
            };
          },
          async close() {},
        },
      };
    },
  };
  const run = await Run.create(bad, economyScenario);
  await assert.rejects(run.step(), /保留已提交/);
  assert.equal(run.history.length, 1);
  const endless: AlgorithmAdapter = {
    ...bad,
    async create(s) {
      const original = await economyAdapter.create(s);
      return {
        snapshot: original.snapshot,
        session: {
          async step() {
            return {
              kind: "pending" as const,
              committedTick: 0,
              reason: "unfinished",
            };
          },
          async close() {},
        },
      };
    },
  };
  await assert.rejects(runToEnd(endless, economyScenario), /轮询上限/);
  const noReason: AlgorithmAdapter = {
    ...bad,
    async create(s) {
      const original = await economyAdapter.create(s);
      return {
        snapshot: original.snapshot,
        session: {
          async step() {
            return { kind: "pending" as const, committedTick: 0, reason: "  " };
          },
          async close() {},
        },
      };
    },
  };
  await assert.rejects(runToEnd(noReason, economyScenario), /说明原因/);
});
test("2D/3D share projected origin, unit IDs and same-source levels without state mutations", async () => {
  const terrain = syntheticTerrain(),
    run = await Run.create(militaryAdapter, militaryScenario);
  await run.step();
  const before = JSON.stringify([terrain, run.current, militaryScenario]);
  const units = projectUnits(terrain, militaryScenario, run.current.entities);
  assert.equal(units.length, 2);
  assert.equal(units[0].entity.id, "blue");
  assert.equal(units[0].eastKm, 5);
  assert.equal(units[0].northKm, 15);
  for (const level of [5, 25, 50] as const) {
    const mesh = terrainPositions(terrain, level, 10);
    assert.equal(mesh.positions.length, (500 / level) ** 2 * 18);
    assert.equal(mesh.grid.totals.count, 10000);
  }
  assert.equal(
    JSON.stringify([terrain, run.current, militaryScenario]),
    before,
  );
  const undeclared = clone(militaryScenario);
  delete undeclared.displayFrame;
  assert.equal(
    projectUnits(terrain, undeclared, run.current.entities).length,
    0,
  );
  const outside = clone(run.current.entities);
  outside[0].x = 101;
  assert.equal(projectUnits(terrain, militaryScenario, outside).length, 1);
});
test("unknown height remains null; geometric model represents one real entity rather than invented soldiers", async () => {
  const terrain = syntheticTerrain();
  terrain.elevationM[300] = null;
  assert.equal(
    groundHeight(
      terrain,
      terrain.frame.origin[0] + 2500,
      terrain.frame.origin[1] + 17500,
    ),
    null,
  );
  const run = await Run.create(militaryAdapter, militaryScenario),
    entity = run.current.entities[0],
    before = clone(entity);
  const model = createUnitGeometry(entity);
  assert.equal(model.userData.entityId, entity.id);
  assert.equal(model.children.length, 2);
  assert.ok(model.children.every((c) => c.userData.entityId === entity.id));
  assert.deepEqual(entity, before);
  disposeObject(model);
});
