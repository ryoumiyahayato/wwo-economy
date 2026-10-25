export interface GeoFrame {
  crs: string;
  coordinateUnit: "m";
  heightUnit: "m";
  extent: [number, number, number, number];
  origin: [number, number];
  baseCellM: number;
  width: number;
  height: number;
  rowOrder: "south-to-north";
  heightKind: "DSM" | "DTM" | "synthetic" | "unavailable";
}
export interface TerrainDataset {
  schemaVersion: "wwo-sandbox/terrain/v1";
  id: string;
  name: string;
  frame: GeoFrame;
  elevationM: (number | null)[];
  cover: ("land" | "water" | "sea" | "urban" | "unknown")[];
  rivers: { id: string; coordinates: [number, number][] }[];
  cities: { id: string; name: string; x: number; y: number }[];
  sources: {
    title: string;
    url: string;
    license: string;
    attribution: string;
    status: "loaded" | "not-loaded";
    sha256?: string;
  }[];
  derived: {
    elevationMethod: string;
    coverMethod: string;
    riverConnectivity: string;
    historicalState: false;
    algorithmConsumesTerrain: false;
  };
}
export const franceFrame: GeoFrame = {
  crs: "EPSG:2154",
  coordinateUnit: "m",
  heightUnit: "m",
  extent: [650000, 6150000, 1150000, 6650000],
  origin: [650000, 6150000],
  baseCellM: 5000,
  width: 100,
  height: 100,
  rowOrder: "south-to-north",
  heightKind: "unavailable",
};
export const unloadedFrance: TerrainDataset = {
  schemaVersion: "wwo-sandbox/terrain/v1",
  id: "france-se-500km-unloaded",
  name: "法国东南 · 500 × 500 公里",
  frame: franceFrame,
  elevationM: Array(10000).fill(null),
  cover: Array(10000).fill("unknown"),
  rivers: [],
  cities: [],
  sources: [
    {
      title: "Copernicus DEM GLO-30 Public",
      url: "https://registry.opendata.aws/copernicus-dem/",
      license: "Copernicus DEM licence (separate from code)",
      attribution: "No DEM data loaded",
      status: "not-loaded",
    },
    {
      title: "ESA WorldCover 2021 v200",
      url: "https://esa-worldcover.org/en/data-access",
      license: "CC BY 4.0",
      attribution: "No land cover data loaded",
      status: "not-loaded",
    },
  ],
  derived: {
    elevationMethod: "not loaded; no fabricated height",
    coverMethod: "not loaded; unknown is not sea",
    riverConnectivity:
      "explicit vector network required; majority cover does not imply bridge access",
    historicalState: false,
    algorithmConsumesTerrain: false,
  },
};
