"""Crop/sample user-provided, licensed regional rasters to the agreed France frame.

No automatic global downloads, accounts, keys or paid endpoints. This script reads
local regional data. Each 5km cell stores a centre sample, NOT a 5km terrain mesh.
Rivers remain a separate vector network through every display aggregation level.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import rasterio
from pyproj import Transformer, Proj
from shapely.geometry import box, shape, mapping
from shapely.ops import transform as transform_geometry

EXTENT = (650000, 6150000, 1150000, 6650000)
CELL = 5000
SIZE = 100
CRS = "EPSG:2154"


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            result.update(block)
    return result.hexdigest()


def sample_files(paths, points):
    output = [None] * len(points)
    for path in paths:
        with rasterio.open(path) as source:
            transform = Transformer.from_crs(CRS, source.crs, always_xy=True)
            transformed = [transform.transform(*p) for p in points]
            for i, (point, value) in enumerate(zip(transformed, source.sample(transformed, masked=True))):
                if not (source.bounds.left <= point[0] < source.bounds.right and source.bounds.bottom <= point[1] < source.bounds.top):
                    continue
                if not np.ma.is_masked(value[0]) and np.isfinite(value[0]):
                    output[i] = float(value[0])
    return output


def read_vectors(path, kind):
    document = json.loads(path.read_text())
    if document.get("type") != "FeatureCollection":
        raise ValueError("vectors must be EPSG:4326 GeoJSON FeatureCollection")
    projection = Transformer.from_crs("EPSG:4326", CRS, always_xy=True)
    clip = box(*EXTENT)
    output = []
    for i, feature in enumerate(document["features"]):
        geometry = transform_geometry(projection.transform, shape(feature["geometry"])).intersection(clip)
        if geometry.is_empty:
            continue
        properties = feature.get("properties", {})
        identity = str(feature.get("id", properties.get("id", f"{kind}-{i}")))
        if kind == "cities" and geometry.geom_type == "Point":
            output.append({"id": identity, "name": str(properties.get("name", identity)), "x": geometry.x, "y": geometry.y})
        elif kind == "rivers":
            segments = [geometry] if geometry.geom_type == "LineString" else list(geometry.geoms) if geometry.geom_type == "MultiLineString" else []
            for j, segment in enumerate(segments):
                output.append({"id": f"{identity}:{j}", "coordinates": [list(p) for p in segment.coords]})
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dem", action="append", type=Path, default=[])
    parser.add_argument("--cover", action="append", type=Path, default=[])
    parser.add_argument("--rivers", type=Path)
    parser.add_argument("--cities", type=Path)
    parser.add_argument("--sources", type=Path, required=True, help="JSON array of source URL/licence/attribution records; confirm actual input rights")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sources = json.loads(args.sources.read_text())
    for source in sources:
        for key in ("title", "url", "license", "attribution"):
            if not source.get(key):
                raise ValueError(f"source record needs {key}")
        source["status"] = "loaded"
    points = [(EXTENT[0] + (col + .5)*CELL, EXTENT[1] + (row + .5)*CELL) for row in range(SIZE) for col in range(SIZE)]
    heights = sample_files(args.dem, points)
    codes = sample_files(args.cover, points)
    cover = ["unknown" if c is None or c == 0 else "urban" if c == 50 else "water" if c == 80 else "land" for c in codes]
    # Water is never inferred to be ocean from height=0 or missing DEM. An explicit
    # ocean mask can be provided later; current input keeps freshwater/sea unknown.
    files = [*args.dem, *args.cover, *([args.rivers] if args.rivers else []), *([args.cities] if args.cities else [])]
    frame = {"crs":CRS,"coordinateUnit":"m","heightUnit":"m","extent":list(EXTENT),"origin":list(EXTENT[:2]),"baseCellM":CELL,"width":SIZE,"height":SIZE,"rowOrder":"south-to-north","heightKind":"DSM" if args.dem else "unavailable"}
    dataset = {"schemaVersion":"wwo-sandbox/terrain/v1","id":"france-se-500km-local","name":"France southeast 500km regional samples","frame":frame,"elevationM":[round(h,2) if h is not None else None for h in heights],"cover":cover,
        "rivers":read_vectors(args.rivers,"rivers") if args.rivers else [],"cities":read_vectors(args.cities,"cities") if args.cities else [],"sources":sources,
        "derived":{"elevationMethod":"5km cell-centre samples from supplied rasters; coarse means are means of samples, not subcell terrain","coverMethod":"cell-centre category; water does not imply ocean; no majority river inference","riverConnectivity":"separate clipped vector paths preserved at all display levels; bridge connectivity unknown","historicalState":False,"algorithmConsumesTerrain":False}}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(dataset,ensure_ascii=False,separators=(",",":"),allow_nan=False))
    to_wgs = Transformer.from_crs(CRS,"EPSG:4326",always_xy=True)
    boundary = to_wgs.transform_bounds(*EXTENT,densify_pts=200)
    factors = [Proj(CRS).get_factors(*to_wgs.transform(*p)).meridional_scale for p in [EXTENT[:2],(EXTENT[2],EXTENT[1]),EXTENT[2:],(EXTENT[0],EXTENT[3]),(900000,6400000)]]
    manifest = {"frame":frame,"wgs84Envelope":boundary,"projectionScaleSamples":factors,"inputFiles":[{"name":p.name,"sha256":digest(p)} for p in files],"outputSha256":digest(args.output),"validHeightCells":sum(h is not None for h in heights),"knownCoverCells":sum(c!="unknown" for c in cover),"sourceRecords":sources}
    args.output.with_suffix('.manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
    print(json.dumps({"output":str(args.output),"validHeightCells":manifest["validHeightCells"],"knownCoverCells":manifest["knownCoverCells"],"wgs84Envelope":boundary}))


if __name__ == "__main__":
    main()
