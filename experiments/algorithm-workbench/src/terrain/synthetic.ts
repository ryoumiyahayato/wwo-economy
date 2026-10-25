import { franceFrame, type TerrainDataset } from "./types";
/** Original fictional fixture in the shared coordinate frame; NEVER real France. */
export function syntheticTerrain(): TerrainDataset {
  const elevationM: number[] = [],
    cover: TerrainDataset["cover"] = [];
  for (let row = 0; row < 100; row++)
    for (let col = 0; col < 100; col++) {
      const sea = row < 15,
        river = col === 38 && row >= 15;
      const ridge =
        Math.max(0, 1 - Math.abs(col - 68) / 12) * 2200 * (row > 35 ? 1 : 0.5);
      elevationM.push(sea ? 0 : Math.round(80 + ridge + row * 2));
      cover.push(
        sea
          ? "sea"
          : river
            ? "water"
            : col >= 20 && col < 25 && row >= 35 && row < 40
              ? "urban"
              : "land",
      );
    }
  return {
    schemaVersion: "wwo-sandbox/terrain/v1",
    id: "synthetic-control-terrain-v1",
    name: "原创地形夹具 · 非真实法国",
    frame: { ...franceFrame, heightKind: "synthetic" },
    elevationM,
    cover,
    rivers: [
      {
        id: "synthetic-river",
        coordinates: [
          [842500, 6225000],
          [842500, 6450000],
          [842500, 6640000],
        ],
      },
    ],
    cities: [
      { id: "synthetic-town-a", name: "合成城市 A", x: 762500, y: 6337500 },
    ],
    sources: [
      {
        title: "Original mathematical terrain fixture",
        url: "#synthetic-control-terrain-v1",
        license: "MIT (original fixture only)",
        attribution:
          "Original synthetic values; no geographic truth or historical claim",
        status: "loaded",
      },
    ],
    derived: {
      elevationMethod:
        "original ridge/flat/sea fixture; not observed elevations",
      coverMethod: "original labelled grid; not measured land cover",
      riverConnectivity:
        "explicit original river polyline; no bridge rules implemented",
      historicalState: false,
      algorithmConsumesTerrain: false,
    },
  };
}
