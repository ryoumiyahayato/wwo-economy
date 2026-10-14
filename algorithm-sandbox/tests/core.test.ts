import test from "node:test";
import assert from "node:assert/strict";
import { economyAdapter } from "../src/adapters/economy";
import { militaryAdapter } from "../src/adapters/military";
import { Run, parseResult, runToEnd } from "../src/core/runtime";
import {
  economyScenario,
  militaryScenario,
  presets,
  validateScenario,
} from "../src/core/scenario";
import { evaluateExpectations } from "../src/core/expectations";
import { clone, type AlgorithmAdapter } from "../src/core/types";

test("ideal market cycles move goods and funds; independent expectations pass", async () => {
  const result = await runToEnd(economyAdapter, economyScenario),
    last = result.history.at(-1)!;
  assert.equal(last.metrics.fulfilled, 600);
  assert.equal(last.metrics.unmet, 0);
  assert.ok(last.metrics.sellerCash > 0);
  assert.ok(last.injections.totalGoods > 0);
  assert.ok(last.injections.totalFunds > 0);
  assert.ok(
    result.history.every((s) =>
      Object.values(s.invariants).every((v) => v === 0),
    ),
  );
  assert.ok(result.verdicts.every((v) => v.status === "pass"));
});
test("zero-money synthetic fixture reveals independent expectation mismatch and blocker", async () => {
  const fixture = presets.find((s) => s.name.startsWith("无资金"))!;
  const result = await runToEnd(economyAdapter, fixture);
  assert.equal(result.history.at(-1)!.metrics.fulfilled, 0);
  assert.ok(result.verdicts.some((v) => v.status === "fail"));
  assert.match(result.history.at(-1)!.blockedReason, /资金/);
  assert.ok(result.history.at(-1)!.metrics.stallTicks > 3);
});
test("finite inventory restores constraint without granting successful matching", async () => {
  const s = clone(economyScenario);
  s.boundary = "inventory";
  s.dependencies.supply = "finite";
  s.params.stock = 0;
  const result = await runToEnd(economyAdapter, s);
  assert.equal(result.history.at(-1)!.metrics.fulfilled, 0);
  assert.equal(result.history.at(-1)!.injections.totalGoods, 0);
  assert.match(result.history.at(-1)!.blockedReason, /库存/);
});
test("bounded transport preserves delay, escrow, damage and refunds", async () => {
  const s = clone(presets[1]);
  s.params.lossRate = 1;
  s.maxTicks = 6;
  const run = await Run.create(economyAdapter, s);
  await run.step();
  assert.equal(run.current.metrics.fulfilled, 0);
  assert.equal(run.current.metrics.inTransit, 10);
  assert.equal(run.current.metrics.escrow, 120);
  await run.step();
  await run.step();
  await run.step();
  assert.equal(run.current.metrics.lost, 10);
  assert.equal(run.current.metrics.sellerCash, 0);
  assert.ok(run.current.events.some((e) => e.message.includes("退款 120")));
  assert.ok(
    run.history.every((s) => Object.values(s.invariants).every((v) => v === 0)),
  );
});
test("reset reproduces the exact initial state and stochastic first transition", async () => {
  const run = await Run.create(economyAdapter, presets[1]);
  const first = clone(run.current);
  await run.step();
  const step = clone(run.current);
  await run.reset();
  assert.deepEqual(run.current, first);
  await run.step();
  assert.deepEqual(run.current, step);
});
test("seeded stochastic runs replay exactly; another seed changes losses", async () => {
  const s = clone(presets[1]);
  s.params.lossRate = 0.5;
  const a = await runToEnd(economyAdapter, s),
    b = await runToEnd(economyAdapter, s);
  assert.deepEqual(a, b);
  s.seed = 43;
  const c = await runToEnd(economyAdapter, s);
  assert.notDeepEqual(a.history, c.history);
});
test("military movement and independent task completion agree", async () => {
  const result = await runToEnd(militaryAdapter, militaryScenario);
  assert.equal(result.history.at(-1)!.metrics.position, 10);
  assert.equal(result.history.at(-1)!.tick, 10);
  assert.ok(result.verdicts.every((v) => v.status === "pass"));
  assert.equal(result.history[1].metrics.position, 1);
});
test("zero-speed synthetic fixture is a visible mismatch rather than success animation", async () => {
  const fixture = presets.find((s) => s.name.startsWith("故意不符"))!;
  const r = await runToEnd(militaryAdapter, fixture);
  assert.equal(r.history.at(-1)!.metrics.position, 0);
  assert.ok(r.verdicts.some((v) => v.status === "fail"));
  assert.match(r.history.at(-1)!.blockedReason, /速度/);
});
test("blocked external path prevents movement, while ideal path still uses actual speed", async () => {
  const s = clone(militaryScenario);
  s.dependencies.path = "blocked";
  const r = await runToEnd(militaryAdapter, s);
  assert.equal(r.history.at(-1)!.metrics.position, 0);
  assert.match(r.history.at(-1)!.blockedReason, /路径/);
});
test("resupply never guarantees hits or victory; finite ammo records actual shots", async () => {
  const s = clone(militaryScenario);
  s.boundary = "engagement";
  s.params.hitChance = 0;
  const r = await runToEnd(militaryAdapter, s);
  assert.equal(r.history.at(-1)!.metrics.enemyCasualties, 0);
  assert.notEqual(r.outcome.status, "pass");
  const limited = clone(s);
  limited.boundary = "ammunition";
  limited.dependencies.resupply = "finite";
  limited.params.ammo = 1;
  const l = await runToEnd(militaryAdapter, limited);
  assert.equal(l.history.at(-1)!.metrics.shots, 1);
  assert.equal(l.history.at(-1)!.injections.totalAmmo, 0);
  assert.ok(
    l.history.every((x) => Object.values(x.invariants).every((v) => v === 0)),
  );
});
test("no expectations and missing observables remain undefined", async () => {
  const run = await Run.create(economyAdapter, economyScenario),
    s = clone(economyScenario);
  s.expectations.rules = [];
  assert.equal(evaluateExpectations(s, run.history)[0].status, "undefined");
  s.expectations.rules = [
    {
      id: "missing",
      label: "undefined pricing behavior",
      target: "metric",
      key: "priceEquilibrium",
      operator: "eq",
      value: 1,
      byTick: 0,
    },
  ];
  assert.equal(evaluateExpectations(s, run.history)[0].status, "undefined");
});
test("scenario rejects non-finite balances and bypass of mechanisms under test", () => {
  const s = clone(economyScenario);
  s.params.stock = Infinity;
  assert.throws(() => validateScenario(s), /有限/);
  s.params.stock = 60;
  s.boundary = "inventory";
  assert.throws(() => validateScenario(s), /必须有限/);
  s.boundary = "transport";
  assert.throws(() => validateScenario(s), /即时/);
  const m = clone(militaryScenario);
  m.boundary = "ammunition";
  assert.throws(() => validateScenario(m), /按需补给/);
});
test("result import preserves reproducibility and recomputes judgments from independent rules", async () => {
  const r = await runToEnd(economyAdapter, economyScenario);
  assert.deepEqual(parseResult(JSON.parse(JSON.stringify(r))), r);
  const altered = clone(r);
  altered.verdicts = [];
  assert.deepEqual(parseResult(altered).verdicts, r.verdicts);
  altered.history[2].tick = 99;
  assert.throws(() => parseResult(altered), /不连续/);
});
test("protocol failures do not fabricate progress", async () => {
  const bad: AlgorithmAdapter = {
    metadata: economyAdapter.metadata,
    async create(s) {
      const real = await economyAdapter.create(s);
      return {
        snapshot: real.snapshot,
        session: {
          async step() {
            return real.snapshot;
          },
          async close() {},
        },
      };
    },
  };
  const run = await Run.create(bad, economyScenario);
  await assert.rejects(run.step(), /恰好 1/);
  assert.equal(run.history.length, 1);
});
test("a historical invariant violation shows its failing value even after recovery", async () => {
  const run = await Run.create(economyAdapter, economyScenario);
  await run.step();
  await run.step();
  const history = clone(run.history);
  history[1].invariants.goods = 9;
  const verdict = evaluateExpectations(economyScenario, history).find(
    (v) => v.id === "goods",
  )!;
  assert.equal(verdict.status, "fail");
  assert.equal(verdict.actual, 9);
  assert.equal(verdict.difference, 9);
});
test("malformed imported events are rejected before rendering", async () => {
  const run = await Run.create(economyAdapter, economyScenario);
  const r = run.result();
  r.history[0].events = [null as never];
  assert.throws(() => parseResult(r), /事件记录无效/);
});
