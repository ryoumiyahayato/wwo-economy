import { aggregateTerrain } from "./grid";
import { type TerrainDataset } from "./types";
import { type Entity, type Scenario } from "../core/types";
export type TerrainCell = ReturnType<typeof aggregateTerrain>["cells"][number];
export function cellColor(c: TerrainCell) {
  return c.unknownCount === c.count
    ? "#edf1f4"
    : c.waterCount / c.count > 0.5
      ? "#afcfdc"
      : c.urbanCount / c.count > 0.25
        ? "#c1a386"
        : c.meanHeight === null
          ? "#dce8dc"
          : c.meanHeight > 2000
            ? "#a0998e"
            : c.meanHeight > 500
              ? "#c5c4a7"
              : "#dce8dc";
}
export function projectedPoint(terrain: TerrainDataset, x: number, y: number) {
  const [xmin, ymin, xmax, ymax] = terrain.frame.extent;
  if (x < xmin || x > xmax || y < ymin || y > ymax) return null;
  return { eastKm: (x - xmin) / 1000, northKm: (y - ymin) / 1000 };
}
export function groundHeight(terrain: TerrainDataset, x: number, y: number) {
  const point = projectedPoint(terrain, x, y);
  if (!point) return null;
  const col = Math.min(99, Math.floor(point.eastKm / 5)),
    row = Math.min(99, Math.floor(point.northKm / 5));
  return terrain.elevationM[row * 100 + col];
}
/** Clip individual vector segments; do not join separated river fragments. */
export function clippedSegment(
  terrain: TerrainDataset,
  a: number[],
  b: number[],
) {
  const [xmin, ymin, xmax, ymax] = terrain.frame.extent;
  const dx = b[0] - a[0],
    dy = b[1] - a[1];
  let enter = 0,
    leave = 1;
  for (const [p, q] of [
    [-dx, a[0] - xmin],
    [dx, xmax - a[0]],
    [-dy, a[1] - ymin],
    [dy, ymax - a[1]],
  ]) {
    if (p === 0) {
      if (q < 0) return [];
      continue;
    }
    const ratio = q / p;
    if (p < 0) enter = Math.max(enter, ratio);
    else leave = Math.min(leave, ratio);
    if (enter > leave) return [];
  }
  return [
    [a[0] + enter * dx, a[1] + enter * dy],
    [a[0] + leave * dx, a[1] + leave * dy],
  ];
}
/** One display projection per reported entity; no invented individuals or state writes. */
export function projectUnits(
  terrain: TerrainDataset,
  scenario: Scenario,
  entities: Entity[],
) {
  const frame = scenario.displayFrame;
  if (!frame || frame.crs !== terrain.frame.crs) return [];
  return entities.flatMap((entity) => {
    const x = frame.origin[0] + entity.x * frame.cellM,
      y = frame.origin[1] + entity.y * frame.cellM,
      point = projectedPoint(terrain, x, y);
    return point
      ? [{ entity, x, y, ...point, heightM: groundHeight(terrain, x, y) }]
      : [];
  });
}
/** Flat cell faces show the same aggregate values as 2D; unknown height is only display-flat. */
export function terrainPositions(
  terrain: TerrainDataset,
  level: 5 | 25 | 50,
  exaggeration: number,
) {
  const grid = aggregateTerrain(terrain, level),
    positions: number[] = [],
    cellIndices: number[] = [];
  for (const [index, c] of grid.cells.entries()) {
    const x = c.col * level,
      z = -c.row * level,
      h = ((c.meanHeight ?? 0) / 1000) * exaggeration;
    positions.push(
      x,
      h,
      z,
      x + level,
      h,
      z,
      x + level,
      h,
      z - level,
      x,
      h,
      z,
      x + level,
      h,
      z - level,
      x,
      h,
      z - level,
    );
    cellIndices.push(index, index);
  }
  return { positions: new Float32Array(positions), cellIndices, grid };
}
