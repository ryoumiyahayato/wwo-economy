import { useState } from "react";
import {
  type AdapterMetadata,
  type CommandRequest,
  type CommandReceipt,
  type RecordedCommand,
  type Scenario,
  type Snapshot,
} from "../core/types";
import {
  SoldierFigure,
  BuildingFigure,
  GoodFigure,
  goodLabels,
} from "../presentation/SceneFigures";

type ObjectMap = Record<string, any>;
const number = (n: unknown) =>
  typeof n === "number"
    ? new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 6 }).format(n)
    : "未知";

export function ExperimentScene(props: {
  scenario: Scenario;
  snapshot: Snapshot;
  history: Snapshot[];
  metadata?: AdapterMetadata;
  commands: RecordedCommand[];
  onCommand: (r: CommandRequest) => Promise<CommandReceipt | undefined>;
  disabled: boolean;
}) {
  const key = props.scenario.name + props.scenario.adapterId;
  return props.scenario.domain === "military" ? (
    <MilitaryScene key={key} {...props} />
  ) : (
    <MarketScene key={key} snapshot={props.snapshot} />
  );
}

function MilitaryScene({
  scenario,
  snapshot,
  history,
  metadata,
  commands,
  onCommand,
  disabled,
}: {
  scenario: Scenario;
  snapshot: Snapshot;
  history: Snapshot[];
  metadata?: AdapterMetadata;
  commands: RecordedCommand[];
  onCommand: (r: CommandRequest) => Promise<CommandReceipt | undefined>;
  disabled: boolean;
}) {
  const p = (snapshot.observations?.person ?? {}) as ObjectMap;
  const [selected, setSelected] = useState("");
  const [node, setNode] = useState("B");
  const [path, setPath] = useState("AB");
  const targets: string[] = p.known_targets ?? [];
  const [targetChoice, setTarget] = useState("");
  const target = targetChoice || targets[0] || "";
  const nodes = Object.keys(p.known_map ?? {});
  const paths: string[][] = p.known_map?.[node] ?? [];
  const entity = snapshot.entities.find((e) => e.id === selected);
  const receipt = commands.at(-1)?.receipt;
  const lastReceipt = p.own_receipts?.find(
    (r: ObjectMap) => r.id === receipt?.id,
  );
  // Bounds depend only on the initial scenario/source, never on the current position.
  const privateSource = metadata?.kind === "private";
  const span = privateSource
    ? 0.3
    : Math.max(1, scenario.params.distance ?? 10) * 1.2;
  const x = (value: number) => 80 + ((value + span / 6) / span) * 860;
  const y = (value: number) =>
    privateSource ? 275 - (value / 0.15) * 180 : 400 - (value / 5) * 220;
  async function send(intent: CommandRequest["intent"]) {
    await onCommand({
      id: `player_${commands.length + 1}`,
      target,
      intent,
      node:
        intent === "cancel"
          ? ""
          : intent === "hold"
            ? (p.personal?.anchor_node ?? node)
            : node,
      path:
        intent === "cancel" || intent === "hold"
          ? []
          : path
              .split(",")
              .map((v) => v.trim())
              .filter(Boolean),
    });
  }
  return (
    <section
      className="experiment-scene military-scene"
      aria-label="军事行动场景"
    >
      <div className="scene-heading">
        <div>
          <h2>行动场景</h2>
          <p>
            固定视野 · 抽象坐标{privateSource ? " km" : ""} · 不对应法国地理
          </p>
        </div>
        <span>
          {number(snapshot.metrics.elapsedSeconds ?? snapshot.tick)}{" "}
          {privateSource ? "游戏秒" : "tick"}
        </span>
      </div>
      <div className="scene-stage">
        <svg
          viewBox="0 0 1040 520"
          className="scene-canvas"
          role="group"
          aria-label="兵模与真实位置"
        >
          <rect width={1040} height={520} fill="#e9eee1" />
          <rect x={80} y={90} width={860} height={310} rx={8} fill="#e0e7d7" />
          {[0, 1, 2, 3, 4, 5].map((i) => {
            const t = (i * span) / 6;
            return (
              <g key={i}>
                <line
                  x1={x(t)}
                  y1={90}
                  x2={x(t)}
                  y2={400}
                  stroke="#cbd5c4"
                  strokeDasharray="3 9"
                />
                <text
                  x={x(t)}
                  y={445}
                  textAnchor="middle"
                  className="coordinate-label"
                >
                  {number(t)}
                  {privateSource ? " km" : ""}
                </text>
              </g>
            );
          })}
          <line x1={80} y1={275} x2={940} y2={275} stroke="#bac8b3" />
          <text x={40} y={40} className="scene-hint">
            点选兵模{metadata?.supportsCommands ? "下令" : "查看详情"}
          </text>
          {snapshot.entities.map((e) => {
            const trail = history.flatMap((s) =>
              s.entities
                .filter((v) => v.id === e.id)
                .map((v) => `${x(v.x)},${y(v.y)}`),
            );
            return (
              <g key={e.id}>
                <polyline
                  points={trail.join(" ")}
                  fill="none"
                  stroke="#7b9b7f"
                  strokeWidth={3}
                />
                <g
                  data-scene-entity-id={e.id}
                  role="button"
                  tabIndex={0}
                  aria-label={`选择人物 ${e.id}`}
                  aria-expanded={selected === e.id}
                  onClick={() => setSelected(e.id)}
                  onKeyDown={(v) => {
                    if (v.key === "Enter" || v.key === " ") {
                      v.preventDefault();
                      setSelected(e.id);
                    }
                  }}
                  transform={`translate(${x(e.x)},${y(e.y)})`}
                >
                  <rect
                    x={-45}
                    y={-110}
                    width={90}
                    height={180}
                    fill="transparent"
                  />
                  <SoldierFigure
                    selected={selected === e.id}
                    wounded={e.state === "WOUNDED"}
                    dead={e.state === "DEAD"}
                  />
                  <text y={36} textAnchor="middle" fontWeight="bold">
                    {e.label}
                  </text>
                  <text y={57} textAnchor="middle" className="entity-state">
                    {e.state ?? "状态未上报"}
                  </text>
                </g>
              </g>
            );
          })}
          {!snapshot.entities.length && (
            <text x={520} y={270} textAnchor="middle">
              源尚未上报可定位实体
            </text>
          )}
          <text x={40} y={495} className="scene-hint">
            兵模为源实体的显示符号；尺寸不参与计算，轨迹只含已提交位置。
          </text>
        </svg>
      </div>
      {entity && (
        <div
          className="object-inspector military-inspector"
          aria-label="人物详情"
        >
          <div className="object-inspector-heading">
            <strong>
              {entity.id} · {entity.granularity ?? "粒度未声明"}
            </strong>
            <button aria-label="收起人物详情" onClick={() => setSelected("")}>
              收起
            </button>
          </div>
          <p className="object-facts">
            x {number(entity.x)}
            {privateSource ? " km" : ""} · y {number(entity.y)}
            {privateSource ? " km" : ""} · 健康{" "}
            {number(snapshot.metrics.health)} · 精确弹药/全军伤亡未上报
          </p>
          {metadata?.supportsCommands ? (
            <div className="scene-orders">
              <label>
                目标
                <select
                  aria-label="军事命令目标"
                  value={target}
                  onChange={(e) => setTarget(e.target.value)}
                >
                  {targets.map((t) => (
                    <option key={t}>{t}</option>
                  ))}
                </select>
              </label>
              <label>
                目的地
                <select
                  aria-label="军事目的地"
                  value={node}
                  onChange={(e) => {
                    setNode(e.target.value);
                    setPath(
                      (p.known_map[e.target.value] as string[][])
                        ?.find((v) => v.length)
                        ?.join(",") ?? "",
                    );
                  }}
                >
                  {nodes.map((n) => (
                    <option key={n}>{n}</option>
                  ))}
                </select>
              </label>
              <label>
                源已知路径
                <select
                  aria-label="军事路径"
                  value={path}
                  onChange={(e) => setPath(e.target.value)}
                >
                  {paths.map((v, i) => (
                    <option value={v.join(",")} key={i}>
                      {v.length ? v.join(" → ") : "不指定路径"}
                    </option>
                  ))}
                </select>
              </label>
              <div className="action-buttons">
                {(
                  [
                    ["advance", "前进"],
                    ["hold", "驻守"],
                    ["withdraw", "撤回"],
                    ["cancel", "取消意图"],
                  ] as const
                ).map(([intent, label]) => (
                  <button
                    disabled={disabled || !target}
                    key={intent}
                    onClick={() => void send(intent)}
                  >
                    {label}
                  </button>
                ))}
              </div>
              <p>地点和路径为原已知目录；不推测节点地理位置。</p>
              {receipt && (
                <div
                  className={`command-receipt ${receipt.accepted ? "accepted" : "rejected"}`}
                  data-testid="command-receipt"
                >
                  <strong>
                    {receipt.id} · 目标 {commands.at(-1)?.request.target} →{" "}
                    {commands.at(-1)?.request.node || "取消"}
                  </strong>
                  <span>
                    {receipt.accepted
                      ? "原决策已受理；尚不等于完成"
                      : "原入口拒绝/未受理"}{" "}
                    · {lastReceipt?.status ?? receipt.status}
                  </span>
                  <span>
                    {lastReceipt?.reason ||
                      receipt.reason ||
                      "推进后查看原送达与实际后果"}
                  </span>
                </div>
              )}
              {commands.length > 0 && (
                <details>
                  <summary>本次操作记录（{commands.length}）</summary>
                  {commands.map((c) => (
                    <p key={c.request.id}>
                      {c.request.id} · tick {c.atTick} · {c.request.intent}{" "}
                      {c.request.target} → {c.request.node} ·{" "}
                      {p.own_receipts?.find(
                        (r: ObjectMap) => r.id === c.request.id,
                      )?.status ?? c.receipt.status}
                    </p>
                  ))}
                </details>
              )}
            </div>
          ) : (
            <p className="scene-readonly">此适配器未提供合法运行中命令入口。</p>
          )}
        </div>
      )}
    </section>
  );
}

function MarketScene({ snapshot }: { snapshot: Snapshot }) {
  const raw = (snapshot.observations ?? {}) as ObjectMap;
  const demo = !raw.stock && snapshot.entities.length > 0;
  const stock: ObjectMap =
    raw.stock ??
    Object.fromEntries(
      snapshot.entities
        .filter((e) => typeof e.stock === "number")
        .map((e) => [e.id, { goods: e.stock }]),
    );
  const cash: ObjectMap =
    raw.cash ??
    (demo
      ? {
          supplier: { balance: snapshot.metrics.sellerCash },
          buyer: { balance: snapshot.metrics.buyerCash },
        }
      : {});
  const sourceOrders: ObjectMap = raw.orders ?? {};
  const [selectedActor, setSelectedActor] = useState("");
  const [selectedOrder, setSelectedOrder] = useState("");
  const [showOrders, setShowOrders] = useState(false);
  const ids = Object.keys(stock);
  const positions = new Map(
    ids.map((id, i) => [
      id,
      { x: 190 + (i % 3) * 330, y: 175 + Math.floor(i / 3) * 240 },
    ]),
  );
  const height = Math.max(
    600,
    175 + Math.floor((ids.length - 1) / 3) * 240 + 185,
  );
  const payments = snapshot.events.flatMap((e) => {
    if (e.stage !== "cash_transfer") return [];
    try {
      return [JSON.parse(e.message)];
    } catch {
      return [];
    }
  });
  const chosen = snapshot.orders.find((o) => o.id === selectedOrder);
  const relation = (id: string) => {
    const route = String(sourceOrders[id]?.route ?? "");
    const match = route.match(/^(.+?)>(.+?):(.+)$/);
    return match
      ? { from: match[1], to: match[2], good: match[3], label: route }
      : demo
        ? {
            from: "supplier",
            to: "buyer",
            good: "goods",
            label: "供应方 → 需求方（demo）",
          }
        : undefined;
  };
  return (
    <section
      className="experiment-scene market-scene"
      aria-label="市场实验场景"
    >
      <div className="scene-heading">
        <div>
          <h2>市场场景</h2>
          <p>抽象布局 · 原状态数量 · 点击建筑或商品查看详情</p>
        </div>
        <span>
          {demo ? "Demo tick" : "研究日"} {snapshot.tick}
        </span>
      </div>
      <div className="market-hud">
        <span>只读市场 · 算法自动交易</span>
        <span>库存 {number(snapshot.metrics.inventory)}</span>
        <span>在途 {number(snapshot.metrics.inTransit)}</span>
        <span className={snapshot.metrics.unmet > 0 ? "danger-text" : ""}>
          缺口 {number(snapshot.metrics.unmet)}
        </span>
        <button
          aria-expanded={showOrders}
          onClick={() => setShowOrders(!showOrders)}
        >
          订单 {snapshot.orders.length}
        </button>
      </div>
      <div className="scene-stage">
        <svg
          viewBox={`0 0 1040 ${height}`}
          className="scene-canvas market-canvas"
          role="group"
          aria-label="建筑商品与真实库存"
        >
          <rect width={1040} height={height} fill="#f1eee1" />
          {snapshot.orders.slice(-12).map((o) => {
            const r = relation(o.id),
              a = r && positions.get(r.from),
              b = r && positions.get(r.to);
            if (!a || !b) return null;
            return (
              <g
                key={o.id}
                role="button"
                tabIndex={0}
                aria-label={`选择订单 ${o.id}`}
                onClick={() => {
                  setSelectedOrder(o.id);
                  setSelectedActor("");
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    setSelectedOrder(o.id);
                    setSelectedActor("");
                  }
                }}
              >
                <line
                  x1={a.x}
                  y1={a.y + 25}
                  x2={b.x}
                  y2={b.y + 25}
                  stroke={selectedOrder === o.id ? "#067c78" : "#c7ccbb"}
                  strokeWidth={selectedOrder === o.id ? 4 : 2}
                  strokeDasharray={o.inTransit > 0 ? "6 9" : undefined}
                />
                <line
                  x1={a.x}
                  y1={a.y + 25}
                  x2={b.x}
                  y2={b.y + 25}
                  stroke="transparent"
                  strokeWidth={16}
                />
              </g>
            );
          })}
          {ids.map((id) => {
            const at = positions.get(id)!,
              needs = raw.needs?.[id],
              values = Object.entries(stock[id]) as [string, number][];
            const kind =
              raw.households?.[id] || needs || id === "buyer"
                ? "home"
                : /farm/i.test(id)
                  ? "farm"
                  : /baker/i.test(id)
                    ? "bakery"
                    : "store";
            return (
              <g
                key={id}
                data-market-actor={id}
                transform={`translate(${at.x},${at.y})`}
              >
                <g
                  role="button"
                  tabIndex={0}
                  aria-label={`查看建筑 ${id}`}
                  aria-expanded={selectedActor === id}
                  onClick={() => {
                    setSelectedActor(id);
                    setSelectedOrder("");
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      setSelectedActor(id);
                      setSelectedOrder("");
                    }
                  }}
                >
                  <ellipse
                    cy={24}
                    rx={106}
                    ry={25}
                    fill={selectedActor === id ? "#d7e2b9" : "#dfe2c8"}
                    stroke={selectedActor === id ? "#067c78" : "none"}
                    strokeWidth={2}
                  />
                  <BuildingFigure kind={kind} />
                  <text y={57} textAnchor="middle" fontWeight="bold">
                    {snapshot.entities.find((e) => e.id === id)?.label ?? id}
                  </text>
                </g>
                {values.slice(0, 4).map(([good, quantity], i) => (
                  <g
                    key={good}
                    role="button"
                    tabIndex={0}
                    data-good={good}
                    aria-label={`${id} ${goodLabels[good] ?? good} 库存 ${number(quantity)}`}
                    transform={`translate(${(i - (Math.min(values.length, 4) - 1) / 2) * 58},93)`}
                    opacity={quantity === 0 ? 0.45 : 1}
                    onClick={() => {
                      setSelectedActor(id);
                      setSelectedOrder("");
                    }}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        setSelectedActor(id);
                        setSelectedOrder("");
                      }
                    }}
                  >
                    <rect x={-27} y={-35} width={54} height={85} fill="transparent" />
                    <title>
                      {goodLabels[good] ?? good} · 原库存 {number(quantity)}
                    </title>
                    <GoodFigure good={good} />
                    <text y={39} textAnchor="middle" className="stock-quantity">
                      {number(quantity)}
                    </text>
                  </g>
                ))}
                {needs && (
                  <text
                    y={161}
                    textAnchor="middle"
                    style={{ fill: needs.unmet > 0 ? "#a54132" : "#526a49" }}
                  >
                    消费满足 {number(needs.consumed)} · 缺口{" "}
                    {number(needs.unmet)}
                  </text>
                )}
              </g>
            );
          })}
          {!ids.length && (
            <text x={520} y={270} textAnchor="middle">
              源未上报具名库存；不编造建筑
            </text>
          )}
          <text x={30} y={height - 17} className="scene-hint">
            建筑与商品是显示符号；连线只表示订单关系，未提供运输位置。
          </text>
        </svg>
      </div>
      <div className="goods-legend" aria-label="商品图例">
        {[
          ...new Set(
            Object.values(stock).flatMap((v) => Object.keys(v as object)),
          ),
        ]
          .slice(0, 8)
          .map((g) => (
            <span key={g}>
              <svg viewBox="-30 -32 60 60" aria-hidden="true">
                <GoodFigure good={g} />
              </svg>
              {goodLabels[g] ?? g}
            </span>
          ))}
        <span>数字为原库存数量</span>
      </div>
      {selectedActor && (
        <div
          className="object-inspector"
          aria-label="建筑详情"
          data-testid="market-actor-inspector"
        >
          <div className="object-inspector-heading">
            <strong>{selectedActor}</strong>
            <button
              aria-label="收起建筑详情"
              onClick={() => setSelectedActor("")}
            >
              收起
            </button>
          </div>
          <p>
            原余额 {number(cash[selectedActor]?.balance)} · 预留{" "}
            {number(cash[selectedActor]?.reserved)}
          </p>
          <p>
            {Object.entries(stock[selectedActor] ?? {})
              .map(([g, q]) => `${goodLabels[g] ?? g} ${number(q)}`)
              .join(" · ")}
          </p>
          <div className="actor-order-list">
            {snapshot.orders
              .filter((o) => {
                const r = relation(o.id);
                return r?.from === selectedActor || r?.to === selectedActor;
              })
              .slice(-12)
              .map((o) => (
                <button key={o.id} onClick={() => setSelectedOrder(o.id)}>
                  订单 #{o.id} · 待发 {o.pending} · 在途 {o.inTransit} · 收货{" "}
                  {o.delivered}
                </button>
              ))}
          </div>
          {payments
            .filter(
              (e) => e.buyer === selectedActor || e.seller === selectedActor,
            )
            .map((e, i) => (
              <p key={i}>
                原付款 {e.buyer} → {e.seller} · {number(e.amount)} ·{" "}
                {e.event_id}
              </p>
            ))}
        </div>
      )}
      {showOrders && (
        <div className="market-orders" aria-label="订单阶段">
          {snapshot.orders.length ? (
            snapshot.orders.slice(-12).map((o) => (
              <button
                key={o.id}
                aria-pressed={selectedOrder === o.id}
                onClick={() => {
                  setSelectedOrder(o.id);
                  setSelectedActor("");
                }}
              >
                #{o.id} · 待发 {o.pending} → 在途 {o.inTransit} → 收货{" "}
                {o.delivered}
              </button>
            ))
          ) : (
            <p>原算法尚未上报订单</p>
          )}
        </div>
      )}
      {chosen && (
        <div className="object-inspector" data-testid="market-order-inspector">
          <div className="object-inspector-heading">
            <strong>
              订单 #{chosen.id} · {relation(chosen.id)?.label ?? "源未提供路线"}
            </strong>
            <button
              aria-label="收起订单详情"
              onClick={() => setSelectedOrder("")}
            >
              收起
            </button>
          </div>
          <p>
            原数量 {chosen.quantity} · 待发 {chosen.pending} · 在途{" "}
            {chosen.inTransit} · 已交付 {chosen.delivered} · 损耗{" "}
            {chosen.lost ?? "未提供"}
          </p>
        </div>
      )}
    </section>
  );
}
