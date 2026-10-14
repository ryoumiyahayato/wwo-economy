import { lazy, Suspense, useMemo, useRef, useState } from "react";
import { unloadedFrance, type TerrainDataset } from "../terrain/types";
import {
  aggregateTerrain,
  gridConsistency,
  validateTerrain,
} from "../terrain/grid";
import { downloadJson } from "../useWorkbench";
import { syntheticTerrain } from "../terrain/synthetic";
import { cellColor, projectUnits } from "../terrain/sceneData";
import { type Scenario, type Snapshot } from "../core/types";
const Terrain3D = lazy(() =>
  import("./Terrain3D").then((module) => ({ default: module.Terrain3D })),
);
export function TerrainView({
  snapshot,
  scenario,
  onSelectEntity,
}: {
  snapshot: Snapshot;
  scenario: Scenario;
  onSelectEntity: (id: string) => void;
}) {
  const [terrain, setTerrain] = useState<TerrainDataset>(unloadedFrance),
    [level, setLevel] = useState<5 | 25 | 50>(25),
    [selected, setSelected] = useState<number | null>(null),
    [error, setError] = useState(""),
    file = useRef<HTMLInputElement>(null);
  const [view, setView] = useState<"2d" | "3d">("2d");
  const grid = useMemo(
      () => aggregateTerrain(terrain, level),
      [terrain, level],
    ),
    consistency = useMemo(() => gridConsistency(terrain), [terrain]);
  const size = 500,
    cell = size / grid.width,
    [xmin, ymin, xmax, ymax] = terrain.frame.extent;
  const point = (x: number, y: number) => [
    ((x - xmin) / (xmax - xmin)) * size,
    size - ((y - ymin) / (ymax - ymin)) * size,
  ];
  const loaded = terrain.sources.some((s) => s.status === "loaded");
  const stats = selected === null ? null : grid.cells[selected];
  return (
    <section className="panel terrain">
      <div className="section-line">
        <h2>地块检查 · {terrain.name}</h2>
        <span className="status undefined">当前适配器未接入此地块</span>
      </div>
      <p className="small muted">
        EPSG:2154 · 西南共同原点 650000 / 6150000 m · 500km
        投影方形，含邻国区域。
      </p>
      {!loaded && (
        <div className="draft-notice">
          真实地形数据未取得。高度和地类保持未知；立体平面仅用于坐标检查。
        </div>
      )}
      {terrain.frame.heightKind === "synthetic" && (
        <div className="draft-notice">
          原创合成地形，仅验证数据导入与聚合。不是法国真实山地、海岸、河道或城市。
        </div>
      )}
      <div className="terrain-controls">
        <label>
          显示视图
          <select
            aria-label="地形显示视图"
            value={view}
            onChange={(e) => setView(e.target.value as "2d" | "3d")}
          >
            <option value="2d">平面 · 精确检查</option>
            <option value="3d">立体 · 同源地形与单位</option>
          </select>
        </label>
        <label>
          查看层级
          <select
            aria-label="地形网格层级"
            value={level}
            onChange={(e) => {
              setLevel(Number(e.target.value) as 5 | 25 | 50);
              setSelected(null);
            }}
          >
            <option value={5}>5 km · 100 × 100</option>
            <option value={25}>25 km · 20 × 20</option>
            <option value={50}>50 km · 10 × 10</option>
          </select>
        </label>
        <button onClick={() => file.current?.click()}>导入同源地形 JSON</button>
        <button onClick={() => downloadJson("terrain-france.json", terrain)}>
          导出地形
        </button>
        <input
          className="visually-hidden"
          ref={file}
          type="file"
          accept=".json"
          aria-label="地形 JSON 文件"
          onChange={async (e) => {
            const f = e.target.files?.[0];
            e.target.value = "";
            if (!f) return;
            try {
              if (f.size > 5_000_000) throw new Error("地形 JSON 上限 5MB");
              setTerrain(validateTerrain(JSON.parse(await f.text())));
              setSelected(null);
              setError("");
            } catch (err) {
              setError(String(err instanceof Error ? err.message : err));
            }
          }}
        />
      </div>
      <div className="terrain-controls">
        <button
          onClick={() => {
            setTerrain(syntheticTerrain());
            setSelected(null);
          }}
        >
          载入原创地形夹具（非真实法国）
        </button>
        <button
          onClick={() => {
            setTerrain(unloadedFrance);
            setSelected(null);
          }}
        >
          返回法国待载入地块
        </button>
      </div>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <div className="terrain-layout">
        {view === "3d" ? (
          <Suspense fallback={<p>正在加载立体视图…</p>}>
            <Terrain3D
              terrain={terrain}
              level={level}
              snapshot={snapshot}
              scenario={scenario}
              onSelectCell={setSelected}
              onSelectEntity={onSelectEntity}
            />
          </Suspense>
        ) : (
          <svg
            className="terrain-grid"
            viewBox="0 0 500 500"
            role="img"
            aria-label={`${level}公里地形检查网格；${loaded ? "已载入数据" : "真实数据尚未取得"}`}
          >
            {grid.cells.map((c, i) => {
              const fill = cellColor(c);
              return (
                <rect
                  key={i}
                  x={c.col * cell}
                  y={500 - (c.row + 1) * cell}
                  width={cell}
                  height={cell}
                  fill={fill}
                  stroke={selected === i ? "#067c78" : "#d4dde4"}
                  strokeWidth={selected === i ? 2 : level === 5 ? 0.2 : 0.5}
                  onClick={() => setSelected(i)}
                >
                  <title>
                    cell {c.col},{c.row} · 高度 {c.meanHeight ?? "未知"} · 水{" "}
                    {c.waterCount}/{c.count}
                  </title>
                </rect>
              );
            })}
            {terrain.rivers.map((r) => (
              <polyline
                key={r.id}
                points={r.coordinates
                  .map(([x, y]) => point(x, y).join(","))
                  .join(" ")}
                fill="none"
                stroke="#4b8daa"
                strokeWidth={1.5}
              >
                <title>{r.id}（矢量河道；桥通行未知）</title>
              </polyline>
            ))}
            {terrain.cities.map((c) => {
              const [x, y] = point(c.x, c.y);
              return (
                <g key={c.id} transform={`translate(${x},${y})`}>
                  <circle r={2.5} fill="#5b504b" />
                  <text x={4} y={-3}>
                    {c.name}
                  </text>
                </g>
              );
            })}
            {!loaded && (
              <>
                <rect
                  x={66}
                  y={210}
                  width={368}
                  height={82}
                  rx={5}
                  fill="white"
                  opacity={0.94}
                />
                <text x={250} y={240} textAnchor="middle" className="map-empty">
                  真实地形数据未取得
                </text>
                <text x={250} y={265} textAnchor="middle">
                  未知 ≠ 海域；未绘制虚构山地或城市
                </text>
              </>
            )}
            {projectUnits(terrain, scenario, snapshot.entities).map((p) => {
              const [x, y] = point(p.x, p.y);
              return (
                <g
                  key={p.entity.id}
                  role="button"
                  tabIndex={0}
                  aria-label={`地块追踪单位 ${p.entity.id}`}
                  onClick={() => onSelectEntity(p.entity.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") onSelectEntity(p.entity.id);
                  }}
                >
                  <rect
                    x={x - 3}
                    y={y - 3}
                    width={6}
                    height={6}
                    fill={p.entity.team === "orange" ? "#b46d2d" : "#067c78"}
                  />
                  <title>
                    {p.entity.id} · 实际 x={p.entity.x}, y={p.entity.y}
                    ；仅显示映射
                  </title>
                </g>
              );
            })}
          </svg>
        )}
        <div className="terrain-inspector">
          <h3>同源聚合检查</h3>
          <p className="small">
            基础格 {grid.totals.count} · 有高度 {grid.totals.valid} · 未知地类{" "}
            {grid.totals.unknownCount}
          </p>
          {Object.entries(consistency).map(([k, v]) => (
            <p key={k} className="small mono">
              {k}: {v}
            </p>
          ))}
          <p className="small muted">
            25 / 50km 格从 5km 同源格按整数倍聚合，不创建独立模拟。残差 0
            仅证明聚合一致，不证明数据完整。
          </p>
          {stats && (
            <>
              <h3>
                选中格 {stats.col},{stats.row}
              </h3>
              <p className="small">
                基础格数量 {stats.count} · 有效高度 {stats.valid}
                <br />
                平均高度{" "}
                {stats.meanHeight === null
                  ? "未知"
                  : `${stats.meanHeight.toFixed(1)} m`}
                <br />
                水域格 {stats.waterCount} · 城市覆盖格 {stats.urbanCount}
              </p>
            </>
          )}
          <h3>来源 / 数据许可</h3>
          {terrain.sources.map((s) => (
            <p key={s.title} className="small source-ref">
              <a href={s.url} target="_blank" rel="noreferrer">
                {s.title}
              </a>
              <br />
              {s.status === "loaded" ? "已载入" : "未载入"} · {s.license}
              <br />
              {s.status === "loaded" ? s.attribution : ""}
            </p>
          ))}
          <p className="small muted">
            现代 DSM / 覆盖数据不能代表 1900；5km
            格不提供单兵掩体、弹道或桥梁通行精度。
          </p>
        </div>
      </div>
    </section>
  );
}
