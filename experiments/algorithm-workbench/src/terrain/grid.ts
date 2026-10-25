import { assertFiniteJson } from "../core/scenario";
import { type TerrainDataset } from "./types";
export function validateTerrain(value: unknown): TerrainDataset {
  assertFiniteJson(value);
  const t = value as TerrainDataset;
  if (
    !t ||
    t.schemaVersion !== "wwo-sandbox/terrain/v1" ||
    !t.frame ||
    t.frame.crs !== "EPSG:2154" ||
    t.frame.width !== 100 ||
    t.frame.height !== 100 ||
    t.frame.baseCellM !== 5000 ||
    t.frame.rowOrder !== "south-to-north"
  )
    throw new Error("当前法国地块需要 EPSG:2154、5km、100×100 同源基础网格");
  if (
    JSON.stringify(t.frame.extent) !== "[650000,6150000,1150000,6650000]" ||
    JSON.stringify(t.frame.origin) !== "[650000,6150000]"
  )
    throw new Error("地块范围或共同原点不一致");
  if (
    t.elevationM?.length !== 10000 ||
    t.cover?.length !== 10000 ||
    !Array.isArray(t.rivers) ||
    !Array.isArray(t.cities) ||
    !Array.isArray(t.sources) ||
    !t.derived
  )
    throw new Error("地形数组与源信息不完整");
  if (
    t.elevationM.some((x) => x !== null && typeof x !== "number") ||
    t.cover.some(
      (x) => !["land", "water", "sea", "urban", "unknown"].includes(x),
    )
  )
    throw new Error("高度或地类值无效");
  if (
    t.rivers.some(
      (r) =>
        !r ||
        typeof r.id !== "string" ||
        !Array.isArray(r.coordinates) ||
        r.coordinates.some(
          (p) =>
            !Array.isArray(p) ||
            p.length !== 2 ||
            p.some((v) => typeof v !== "number"),
        ),
    )
  )
    throw new Error("河道坐标无效");
  if (
    t.cities.some(
      (c) =>
        !c ||
        typeof c.id !== "string" ||
        typeof c.name !== "string" ||
        typeof c.x !== "number" ||
        typeof c.y !== "number",
    )
  )
    throw new Error("城市坐标无效");
  if (
    t.sources.some(
      (s) =>
        !s ||
        typeof s.title !== "string" ||
        typeof s.url !== "string" ||
        !/^(https?:\/\/|#)/.test(s.url) ||
        typeof s.license !== "string" ||
        typeof s.attribution !== "string" ||
        !["loaded", "not-loaded"].includes(s.status),
    )
  )
    throw new Error("数据来源记录无效");
  // Import cannot assert that an algorithm consumed terrain merely by displaying it.
  return structuredClone({
    ...t,
    derived: {
      ...t.derived,
      historicalState: false,
      algorithmConsumesTerrain: false,
    },
  });
}
export function aggregateTerrain(t: TerrainDataset, cellKm: 5 | 25 | 50) {
  const factor = cellKm / 5,
    width = t.frame.width / factor,
    height = t.frame.height / factor;
  const cells: {
    col: number;
    row: number;
    count: number;
    valid: number;
    sumHeight: number;
    meanHeight: number | null;
    waterCount: number;
    urbanCount: number;
    unknownCount: number;
  }[] = [];
  for (let row = 0; row < height; row++)
    for (let col = 0; col < width; col++) {
      let valid = 0,
        sumHeight = 0,
        waterCount = 0,
        urbanCount = 0,
        unknownCount = 0;
      for (let dy = 0; dy < factor; dy++)
        for (let dx = 0; dx < factor; dx++) {
          const index = (row * factor + dy) * t.frame.width + col * factor + dx,
            v = t.elevationM[index];
          if (v !== null) {
            valid++;
            sumHeight += v;
          }
          if (["water", "sea"].includes(t.cover[index])) waterCount++;
          if (t.cover[index] === "urban") urbanCount++;
          if (t.cover[index] === "unknown") unknownCount++;
        }
      cells.push({
        col,
        row,
        count: factor * factor,
        valid,
        sumHeight,
        meanHeight: valid ? sumHeight / valid : null,
        waterCount,
        urbanCount,
        unknownCount,
      });
    }
  return {
    width,
    height,
    cells,
    totals: cells.reduce(
      (a, c) => ({
        count: a.count + c.count,
        valid: a.valid + c.valid,
        sumHeight: a.sumHeight + c.sumHeight,
        waterCount: a.waterCount + c.waterCount,
        urbanCount: a.urbanCount + c.urbanCount,
        unknownCount: a.unknownCount + c.unknownCount,
      }),
      {
        count: 0,
        valid: 0,
        sumHeight: 0,
        waterCount: 0,
        urbanCount: 0,
        unknownCount: 0,
      },
    ),
  };
}
export function gridConsistency(t: TerrainDataset) {
  const a = aggregateTerrain(t, 5).totals,
    b = aggregateTerrain(t, 25).totals,
    c = aggregateTerrain(t, 50).totals;
  return {
    countResidual: Math.max(
      Math.abs(a.count - b.count),
      Math.abs(a.count - c.count),
    ),
    heightSumResidual: Math.max(
      Math.abs(a.sumHeight - b.sumHeight),
      Math.abs(a.sumHeight - c.sumHeight),
    ),
    waterResidual: Math.max(
      Math.abs(a.waterCount - b.waterCount),
      Math.abs(a.waterCount - c.waterCount),
    ),
    unknownResidual: Math.max(
      Math.abs(a.unknownCount - b.unknownCount),
      Math.abs(a.unknownCount - c.unknownCount),
    ),
  };
}
