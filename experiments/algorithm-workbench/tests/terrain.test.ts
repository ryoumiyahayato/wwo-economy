import test from "node:test";
import assert from "node:assert/strict";
import { unloadedFrance } from "../src/terrain/types";
import {
  aggregateTerrain,
  gridConsistency,
  validateTerrain,
} from "../src/terrain/grid";
import { clone } from "../src/core/types";
test("500km hierarchy aggregates one base grid without multiplying states", () => {
  const t = clone(unloadedFrance);
  t.elevationM = Array.from({ length: 10000 }, (_, i) =>
    i % 11 === 0 ? null : i % 301,
  );
  t.cover = Array.from({ length: 10000 }, (_, i) =>
    i % 5 === 0 ? "water" : "land",
  );
  assert.equal(aggregateTerrain(t, 5).cells.length, 10000);
  assert.equal(aggregateTerrain(t, 25).cells.length, 400);
  assert.equal(aggregateTerrain(t, 50).cells.length, 100);
  assert.deepEqual(gridConsistency(t), {
    countResidual: 0,
    heightSumResidual: 0,
    waterResidual: 0,
    unknownResidual: 0,
  });
});
test("missing height or cover does not become sea or a false terrain consumer claim", () => {
  const t = clone(unloadedFrance);
  const checked = validateTerrain({
    ...t,
    derived: { ...t.derived, algorithmConsumesTerrain: true },
  });
  assert.ok(checked.elevationM.every((v) => v === null));
  assert.ok(checked.cover.every((v) => v === "unknown"));
  assert.equal(checked.derived.algorithmConsumesTerrain, false);
  checked.frame.origin = [0, 0];
  assert.throws(() => validateTerrain(checked), /原点/);
});
