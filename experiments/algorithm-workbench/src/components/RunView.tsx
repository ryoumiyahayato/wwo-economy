import { useEffect, useRef, useState } from "react";
import { evaluateExpectations, diagnoseVerdict } from "../core/expectations";
import { stateDifferences } from "../core/runtime";
import {
  type AdapterMetadata,
  type Scenario,
  type Snapshot,
} from "../core/types";
import { UnitMarker } from "../presentation/UnitMarker";
import { metricSegments } from "../presentation/metricSeries";
import { TerrainView } from "./TerrainView";

const format = (n: number) =>
  new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 6 }).format(n);
const statusLabel = {
  success: "成功",
  pending: "等待",
  blocked: "阻塞",
  "not-implemented": "未执行",
  pass: "符合",
  fail: "不符",
  undefined: "待判断",
};
function Curve({
  history,
  keys,
  labels,
}: {
  history: Snapshot[];
  keys: string[];
  labels: string[];
}) {
  const width = 720,
    height = 164,
    pad = 30,
    maxX = Math.max(1, history.at(-1)?.tick ?? 1);
  const values = history.flatMap((s) =>
    keys.flatMap((k) => (s.metrics[k] === undefined ? [] : [s.metrics[k]])),
  );
  const maxY = Math.max(1, ...values),
    minY = Math.min(0, ...values);
  const x = (tick: number) => pad + (tick / maxX) * (width - pad * 2),
    y = (value: number) =>
      height - pad - ((value - minY) / (maxY - minY)) * (height - pad * 2);
  return (
    <div className="chart">
      <div className="chart-key">
        {labels.map((label, i) => (
          <span key={label}>
            <i className={i ? "gray" : "teal"} />
            {label}
            {history.some((s) => s.metrics[keys[i]] === undefined)
              ? " · 含未提供观测"
              : ""}
          </span>
        ))}
      </div>
      <svg
        viewBox={`0 0 ${width} ${height}`}
        role="img"
        aria-label={`${labels.join("与")}随 tick 的实际曲线`}
      >
        {[0, 0.5, 1].map((t) => (
          <g key={t}>
            <line
              x1={pad}
              y1={y(minY + (maxY - minY) * t)}
              x2={width - pad}
              y2={y(minY + (maxY - minY) * t)}
              className="grid-line"
            />
            <text
              x={pad - 5}
              y={y(minY + (maxY - minY) * t) + 4}
              textAnchor="end"
            >
              {format(minY + (maxY - minY) * t)}
            </text>
          </g>
        ))}
        {keys.flatMap((key, i) =>
          metricSegments(history, key).map((segment, index) =>
            segment.length === 1 ? (
              <circle
                key={`${key}-${index}`}
                data-metric-key={key}
                cx={x(segment[0].tick)}
                cy={y(segment[0].value)}
                r={2.5}
                fill={i ? "#8593a4" : "#067c78"}
              />
            ) : (
              <polyline
                key={`${key}-${index}`}
                data-metric-key={key}
                points={segment
                  .map((s) => `${x(s.tick)},${y(s.value)}`)
                  .join(" ")}
                fill="none"
                stroke={i ? "#8593a4" : "#067c78"}
                strokeWidth="2.5"
              />
            ),
          ),
        )}
        {[0, 0.5, 1].map((t) => (
          <text key={t} x={x(maxX * t)} y={height - 8} textAnchor="middle">
            {Math.round(maxX * t)}
          </text>
        ))}
      </svg>
      {!values.length && (
        <p className="small muted">未提供曲线观测；不绘制零值占位。</p>
      )}
      <span className="axis-label">Tick</span>
    </div>
  );
}
function UnitView({
  snapshot,
  scenario,
  onSelect,
}: {
  snapshot: Snapshot;
  scenario: Scenario;
  onSelect: (id: string) => void;
}) {
  const [interpolate, setInterpolate] = useState(false);
  const max =
    typeof scenario.params.distance === "number"
      ? Math.max(12, scenario.params.distance + 2)
      : 0.3;
  return (
    <div className="unit-map">
      <svg viewBox="0 0 720 112" role="img" aria-label="抽象游戏单位位置">
        <line
          x1={35}
          y1={62}
          x2={685}
          y2={62}
          stroke="#c7d2db"
          strokeWidth={2}
        />
        {snapshot.entities.map((e) => (
          <UnitMarker
            key={e.id}
            entityId={e.id}
            label={`${e.label} x=${format(e.x)}`}
            team={e.team}
            x={35 + (e.x / max) * 630}
            y={62}
            personnel={e.personnel}
            ammo={e.ammo}
            interpolate={interpolate}
            onSelect={() => onSelect(e.id)}
          />
        ))}
      </svg>
      <label className="interpolation">
        <input
          type="checkbox"
          checked={interpolate}
          onChange={(e) => setInterpolate(e.target.checked)}
        />
        仅显示插值（默认关闭；不改变算法状态）
      </label>
      <p className="small muted">
        标记对应源实际 ID 和上报粒度；沿 x
        自适应显示，不代表道路。未上报的人数或弹药保持未知。
      </p>
    </div>
  );
}
export function RunView({
  scenario,
  history,
  current,
  metadata,
  replayTick,
  onReplay,
}: {
  scenario: Scenario;
  history: Snapshot[];
  current: Snapshot;
  metadata?: AdapterMetadata;
  replayTick: number | null;
  onReplay: (n: number | null) => void;
}) {
  const [trace, setTrace] = useState("");
  const [diagnosisId, setDiagnosisId] = useState<string | null>(null),
    diagnosisRef = useRef<HTMLElement>(null);
  useEffect(() => {
    setDiagnosisId(null);
  }, [scenario.adapterId, scenario.name]);
  useEffect(() => {
    if (diagnosisId) diagnosisRef.current?.scrollIntoView({ block: "nearest" });
  }, [diagnosisId]);
  useEffect(() => setTrace(""), [scenario.adapterId, scenario.name]);
  const visibleHistory = history.slice(0, current.tick + 1),
    verdicts = evaluateExpectations(scenario, visibleHistory),
    changes = stateDifferences(visibleHistory.at(-2), current);
  const defaultMetricKeys =
    scenario.domain === "economy"
      ? ["fulfilled", "unmet", "buyerCash", "goodsResidual"]
      : ["position", "distanceRemaining", "ammo", "casualties"];
  const defaultMetricLabels =
    scenario.domain === "economy"
      ? ["累计消费", "未满足需求", "买方资金", "商品残差"]
      : ["当前位置", "剩余距离", "蓝方弹药", "蓝方伤亡"];
  const metricKeys = metadata?.metrics?.map((m) => m.key) ?? defaultMetricKeys;
  const metricLabels =
    metadata?.metrics?.map((m) => m.label) ?? defaultMetricLabels;
  const entities = new Set(
    visibleHistory.flatMap((s) =>
      s.events.map((e) => e.entityId).filter(Boolean),
    ),
  );
  const events = visibleHistory
    .flatMap((s) => s.events)
    .filter((e) => !trace || e.entityId === trace)
    .slice(-60)
    .reverse();
  const selectedVerdict = evaluateExpectations(scenario, history).find(
    (v) => v.id === diagnosisId,
  );
  const diagnosis = selectedVerdict
    ? diagnoseVerdict(selectedVerdict, history)
    : null;
  return (
    <>
      <section className="metrics" aria-label="实际指标">
        {metricKeys.map((key, i) => (
          <div key={key}>
            <span>{metricLabels[i]}</span>
            <strong data-testid={`metric-${key}`}>
              {current.metrics[key] === undefined
                ? "未接入"
                : format(current.metrics[key])}
            </strong>
          </div>
        ))}
      </section>
      {current.observations && (
        <section className="panel">
          <h2>真实源状态 / 输入单位</h2>
          <p className="small muted">
            以下为源上报观测。军事仅显示本人及已收到报告；未上报字段保持未知，不据此补造隐藏世界状态。
          </p>
          <details>
            <summary>查看源观测 JSON</summary>
            <pre className="subject-json">
              {JSON.stringify(current.observations, null, 2)}
            </pre>
          </details>
        </section>
      )}
      <section className="panel expectations">
        <h2>预期结果 / 实际结果 / 差异</h2>
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>独立规则</th>
                <th>实际值</th>
                <th>差异</th>
                <th>判定</th>
              </tr>
            </thead>
            <tbody>
              {verdicts.map((v) => (
                <tr key={v.id}>
                  <td>
                    <strong>{v.label}</strong>
                    <small>{v.expected}</small>
                  </td>
                  <td className="mono">
                    {v.actual === null
                      ? "未提供"
                      : typeof v.actual === "number"
                        ? format(v.actual)
                        : String(v.actual)}
                  </td>
                  <td className="mono">
                    {v.difference === null ? "—" : format(v.difference)}
                  </td>
                  <td>
                    <span className={`status ${v.status}`}>
                      {statusLabel[v.status]}
                    </span>
                    <small>
                      {v.status === "fail" || v.status === "undefined"
                        ? v.detail
                        : ""}
                    </small>
                    <button
                      className="inspect-rule"
                      aria-label={`定位 ${v.label}`}
                      onClick={() => {
                        setDiagnosisId(v.id);
                        setTrace(v.subjectId ?? "");
                        onReplay(v.tick ?? current.tick);
                      }}
                    >
                      定位对象 / 事件
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="small muted observation">
          行为观察（不自动判定）：{scenario.expectations.observation}
        </p>
      </section>
      {diagnosis && selectedVerdict && (
        <section
          className="panel diagnosis"
          ref={diagnosisRef}
          data-testid="diagnosis-panel"
        >
          <div className="section-line">
            <h2>异常 / 规则定位 · {selectedVerdict.subjectId ?? "全局观测"}</h2>
            <button onClick={() => setDiagnosisId(null)}>关闭定位</button>
          </div>
          <p className="small">
            tick {diagnosis.tick} · {selectedVerdict.expected} · 实际{" "}
            {String(selectedVerdict.actual)} · {selectedVerdict.detail}
          </p>
          <p className="small muted">
            {diagnosis.explicitCausalLinks
              ? "按源事件 causeId 展开关联"
              : "源未提供 causeId，以下仅展示真实事件序列，不推断唯一因果或责任主体。"}
          </p>
          {diagnosis.subject ? (
            <pre className="subject-json">
              {JSON.stringify(diagnosis.subject, null, 2)}
            </pre>
          ) : (
            <p className="small muted">
              没有指定实体或该实体未提供；不虚构对象。
            </p>
          )}
          <div className="diff-list">
            {stateDifferences(diagnosis.before, diagnosis.snapshot).map((c) => (
              <span key={c.key}>
                {c.key}{" "}
                <b className="mono">
                  {c.from ?? "未提供"} → {c.to ?? "未提供"}
                </b>
              </span>
            ))}
          </div>
          <ol className="diagnosis-events">
            {diagnosis.events.length ? (
              diagnosis.events.map((e, i) => (
                <li key={e.id ?? i}>
                  <button
                    onClick={() => {
                      onReplay(e.tick);
                      setTrace(e.entityId ?? "");
                    }}
                  >
                    tick {e.tick} · {e.entityId ?? "全局"} · {e.stage}
                  </button>
                  <span>{e.message}</span>
                  {e.causeId && <small>causeId {e.causeId}</small>}
                </li>
              ))
            ) : (
              <li>该窗口未提供关联事件；原因保持未知。</li>
            )}
          </ol>
        </section>
      )}
      <section className="panel">
        <div className="section-line">
          <h2>算法阶段 · 因果链</h2>
          <span className="small muted">
            {metadata?.kind === "demo" ? "原创 DEMO" : "私有算法观测"}
          </span>
        </div>
        <div className="stages">
          {current.stages.map((s, i) => (
            <div className={`stage ${s.status}`} key={s.id}>
              <strong>
                <i />
                {i + 1}. {s.label}
              </strong>
              <span>{statusLabel[s.status]}</span>
              <small>{s.detail}</small>
            </div>
          ))}
        </div>
        <div className="injections">
          <strong>本步外部注入</strong>
          {Object.entries(current.injections)
            .filter(([k]) => !k.startsWith("total"))
            .map(([k, v]) => (
              <span className="mono" key={k}>
                {k} +{format(v)}
              </span>
            ))}
          <span>
            {scenario.domain === "economy"
              ? `运输 ${scenario.dependencies.transport === "instant" ? "即时 / 无限容量" : "有限 / 有时延"}`
              : `路径 ${scenario.dependencies.path === "direct" ? "可通行" : "阻断"}`}
          </span>
        </div>
        {current.blockedReason && (
          <div className="blocking" role="status">
            <strong>无进展 / 约束原因</strong>
            {current.blockedReason}
          </div>
        )}
      </section>
      <section className="panel differences">
        <div className="section-line">
          <h2>单步状态差异</h2>
          <span className="mono small">
            {Math.max(0, current.tick - 1)} → {current.tick}
          </span>
        </div>
        <div className="diff-list">
          {changes.length ? (
            changes.map((c) => (
              <span key={c.key}>
                <b>{c.key}</b>
                <span className="mono">
                  {c.from === null ? "未提供" : format(c.from)} →{" "}
                  {c.to === null ? "未提供" : format(c.to)}
                </span>
              </span>
            ))
          ) : (
            <p className="muted small">初始状态，尚未执行。</p>
          )}
        </div>
      </section>
      {scenario.domain === "military" && !current.observations?.battle && (
        <section className="panel">
          <h2>单位位置 · 抽象游戏任务</h2>
          <UnitView
            snapshot={current}
            scenario={scenario}
            onSelect={setTrace}
          />
          <p className="small muted">
            完成条件：{current.completion.condition}
          </p>
        </section>
      )}
      <section className="panel">
        <div className="section-line">
          <h2>
            {scenario.domain === "economy" ? "消费与未满足需求" : "位置与弹药"}{" "}
            · 实际曲线
          </h2>
          <span className="small muted">曲线辅助观察，判定以独立规则为准</span>
        </div>
        <Curve
          history={visibleHistory}
          keys={
            scenario.domain === "economy"
              ? ["fulfilled", "unmet"]
              : ["position", "ammo"]
          }
          labels={
            scenario.domain === "economy"
              ? ["累计消费", "未满足需求"]
              : ["位置", "弹药"]
          }
        />
      </section>
      <div className="lower-grid">
        <section className="panel">
          <h2>
            {scenario.domain === "economy" ? "订单与物资账" : "单位与状态账"}
          </h2>
          <div className="table-scroll">
            {scenario.domain === "economy" ? (
              <table>
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>数量</th>
                    <th>待发</th>
                    <th>在途</th>
                    <th>收货 / 损耗</th>
                  </tr>
                </thead>
                <tbody>
                  {current.orders.length ? (
                    current.orders.slice(-8).map((o) => (
                      <tr
                        key={o.id}
                        onClick={() => setTrace(o.id)}
                        tabIndex={0}
                        onKeyDown={(e) => {
                          if (e.key === "Enter") setTrace(o.id);
                        }}
                        title="追踪此订单"
                      >
                        <td className="mono">{o.id}</td>
                        <td>{o.quantity}</td>
                        <td>{o.pending}</td>
                        <td>{o.inTransit}</td>
                        <td>
                          {o.delivered} / {o.lost ?? "未提供"}
                        </td>
                      </tr>
                    ))
                  ) : (
                    <tr>
                      <td colSpan={5} className="muted">
                        尚无订单
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>单位</th>
                    <th>位置</th>
                    <th>人数</th>
                    <th>弹药</th>
                  </tr>
                </thead>
                <tbody>
                  {current.entities.map((e) => (
                    <tr
                      key={e.id}
                      onClick={() => setTrace(e.id)}
                      tabIndex={0}
                      onKeyDown={(event) => {
                        if (event.key === "Enter") setTrace(e.id);
                      }}
                    >
                      <td>{e.label}</td>
                      <td>{format(e.x)}</td>
                      <td>{e.personnel}</td>
                      <td>{e.ammo}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
          <div className="ledger-residual">
            {Object.entries(current.invariants).map(([k, v]) => (
              <span key={k}>
                {k} 残差{" "}
                <b className={Math.abs(v) < 1e-8 ? "teal-text" : "danger-text"}>
                  {format(v)}
                </b>
              </span>
            ))}
          </div>
        </section>
        <section className="panel">
          <div className="section-line">
            <h2>事件日志</h2>
            <select
              aria-label="事件追踪对象"
              value={trace}
              onChange={(e) => setTrace(e.target.value)}
            >
              <option value="">全部主体 / 订单</option>
              {[...entities].map((id) => (
                <option key={id} value={id}>
                  {id}
                </option>
              ))}
            </select>
          </div>
          <div className="event-scroll">
            <table>
              <thead>
                <tr>
                  <th>Tick</th>
                  <th>阶段 / 主体</th>
                  <th>实际事件</th>
                </tr>
              </thead>
              <tbody>
                {events.length ? (
                  events.map((e, i) => (
                    <tr key={`${e.tick}-${i}`}>
                      <td className="mono">{e.tick}</td>
                      <td>
                        <span className={`status ${e.status}`}>{e.stage}</span>
                        <small className="mono">{e.entityId}</small>
                      </td>
                      <td>{e.message}</td>
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td colSpan={3} className="muted">
                      单步执行后记录真实事件
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </section>
      </div>
      <section className="panel replay">
        <label>
          结果回放 · tick {current.tick}
          <input
            aria-label="结果回放 tick"
            type="range"
            min={0}
            max={history.length - 1}
            value={replayTick ?? history.length - 1}
            onChange={(e) => onReplay(Number(e.target.value))}
          />
        </label>
        <button onClick={() => onReplay(null)}>返回最新状态</button>
      </section>
      {scenario.domain === "military" && !current.observations?.battle && (
        <TerrainView
          snapshot={current}
          scenario={scenario}
          onSelectEntity={setTrace}
        />
      )}
    </>
  );
}
