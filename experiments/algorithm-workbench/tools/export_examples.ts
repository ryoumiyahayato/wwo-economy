import { writeFileSync, mkdirSync } from "node:fs";
import { presets } from "../src/core/scenario";
import { syntheticTerrain } from "../src/terrain/synthetic";
mkdirSync("examples", { recursive: true });
for (const [index, name] of [
  [0, "economy-ideal"],
  [1, "economy-transport"],
  [2, "economy-intentional-mismatch"],
  [4, "military-movement"],
  [5, "military-engagement"],
  [7, "military-intentional-mismatch"],
] as const) {
  writeFileSync(
    `examples/${name}.json`,
    JSON.stringify(presets[index], null, 2) + "\n",
  );
}
writeFileSync(
  "examples/synthetic-terrain.json",
  JSON.stringify(syntheticTerrain()) + "\n",
);
