import { useEffect, useState } from "react";
import {
  type AdapterMetadata,
  type CommandRequest,
  type CommandReceipt,
  type RecordedCommand,
  type Scenario,
  type Snapshot,
} from "../core/types";

type ObjectMap = Record<string, any>;
const number = (n: unknown) =>
  typeof n === "number"
    ? new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 6 }).format(n)
    : "未知";

export function ExperimentScene({
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
  return scenario.domain === "military" ? (
    <MilitaryScene
      key={scenario.name + scenario.adapterId}
      {...{
        scenario,
        snapshot,
        history,
        metadata,
        commands,
        onCommand,
        disabled,
      }}
    />
  ) : (
    <MarketScene
      key={scenario.name + scenario.adapterId}
      snapshot={snapshot}
      history={history}
    />
  );
}

function MilitaryScene({
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
  const [selected, setSelected] = useState(""),
    [node, setNode] = useState("B"),
    [path, setPath] = useState("AB");
  const receipt = commands.at(-1)?.receipt;
  const nodes = Object.keys(p.known_map ?? {}),
    targets: string[] = p.known_targets ?? [];
  const [target, setTarget] = useState(targets[0] ?? "");
  useEffect(() => {
    if (!selected && snapshot.entities.length)
      setSelected(snapshot.entities[0].id);
    if (!target && targets.length) setTarget(targets[0]);
  }, [snapshot]);
  const entity = snapshot.entities.find((e) => e.id === selected),
    paths: string[][] = p.known_map?.[node] ?? [];
  // A fixed, explicitly abstract window. It never follows the current position.
  const x = (value: number) => 80 + ((value + 0.05) / 0.3) * 860,
    y = (value: number) => 330 - (value / 0.15) * 220;
  const lastReceipt = p.own_receipts?.find(
    (r: ObjectMap) => r.id === receipt?.id,
  );
  const status = lastReceipt?.status ?? receipt?.status;
  async function send(intent: CommandRequest["intent"]) {
    const id = `player_${commands.length + 1}`;
    const command = {
      id,
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
    };
    await onCommand(command);
  }
  return (
    <section
      className="experiment-scene military-scene"
      aria-label="军事行动场景"
    >
      <div className="scene-heading">
        <div>
          <h2>行动场景</h2>
          <p>固定局部视野 · 原坐标 km · 抽象实验空间，未加载法国地理</p>
        </div>
        <span>{number(snapshot.metrics.elapsedSeconds)} 游戏秒</span>
      </div>
      <svg
        viewBox="0 0 1040 560"
        className="scene-canvas"
        role="img"
        aria-label="真实人物固定坐标场景"
      >
        <rect width="1040" height="560" fill="#eef2e9" />
        {[0, 0.05, 0.1, 0.15, 0.2, 0.25].map((t) => (
          <g key={t}>
            <line x1={x(t)} y1={70} x2={x(t)} y2={480} stroke="#ced8ca" />
            <text x={x(t)} y={510} textAnchor="middle">
              {t} km
            </text>
          </g>
        ))}
        <line x1={80} y1={330} x2={940} y2={330} stroke="#c3cdc1" />
        <text x={28} y={40}>
          点选真实人物，然后下令；显示只来自已提交状态
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
                stroke="#90b5a3"
                strokeWidth={3}
              />
              <g
                data-scene-entity-id={e.id}
                role="button"
                tabIndex={0}
                aria-label={`选择人物 ${e.id}`}
                onClick={() => setSelected(e.id)}
                onKeyDown={(v) => {
                  if (v.key === "Enter") setSelected(e.id);
                }}
                transform={`translate(${x(e.x)},${y(e.y)})`}
              >
                <circle
                  r={selected === e.id ? 23 : 18}
                  fill={
                    e.state === "DEAD"
                      ? "#626769"
                      : e.state === "WOUNDED"
                        ? "#b17c38"
                        : "#087d76"
                  }
                  stroke="white"
                  strokeWidth={4}
                />
                <path d="M-8 0L8 0M0 -8L0 8" stroke="white" strokeWidth={2} />
                <text y={-34} textAnchor="middle">
                  {e.label} · {e.granularity ?? "未声明粒度"}
                </text>
                <text y={48} textAnchor="middle">
                  {e.state ?? "状态未知"} · x {number(e.x)}
                </text>
              </g>
            </g>
          );
        })}
        {!snapshot.entities.length && (
          <text x={520} y={270} textAnchor="middle">
            源尚未上报可定位人物；不绘制未知单位
          </text>
        )}
      </svg>
      <div className="scene-bottom">
        <div>
          <strong>{entity ? `已选择 ${entity.id}` : "请选择人物"}</strong>
          <span>
            健康 {number(snapshot.metrics.health)} · 精确弹药/全军伤亡未上报
          </span>
        </div>
        <div className="known-nodes">
          {nodes.map((n) => (
            <button
              key={n}
              aria-pressed={node === n}
              onClick={() => {
                setNode(n);
                const first = (p.known_map[n] as string[][]).find(
                  (v) => v.length,
                );
                setPath(first?.join(",") ?? "");
              }}
            >
              {n}
            </button>
          ))}
        </div>
      </div>
      {metadata?.supportsCommands ? (
        <div className="scene-orders">
          <p>
            已知地点按钮只表示源路线目录，不编造坐标。意图受理与送达、动作完成分别显示。
          </p>
          <label>
            合法目标
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
                disabled={disabled || !entity || !target}
                key={intent}
                onClick={() => void send(intent)}
              >
                {label}
              </button>
            ))}
          </div>
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
                · {status}
              </span>
              <span>
                {lastReceipt?.reason ||
                  receipt.reason ||
                  "源没有额外原因；推进后查看真实变化与报告"}
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
                  {p.own_receipts?.find((r: ObjectMap) => r.id === c.request.id)
                    ?.status ?? c.receipt.status}
                </p>
              ))}
            </details>
          )}
        </div>
      ) : (
        <p className="scene-readonly">
          此适配器未提供合法运行中命令入口；只观察真实状态。
        </p>
      )}
    </section>
  );
}

function MarketScene({
  snapshot,
  history,
}: {
  snapshot: Snapshot;
  history: Snapshot[];
}) {
  const raw = (snapshot.observations ?? {}) as ObjectMap;
  const [selected, setSelected] = useState("");
  const stock: ObjectMap = raw.stock ?? {},
    cash: ObjectMap = raw.cash ?? {},
    orders: ObjectMap = raw.orders ?? {};
  const ids = Object.keys(stock);
  const positions = new Map(
    ids.map((id, i) => [
      id,
      { x: 130 + (i % 3) * 330, y: 125 + Math.floor(i / 3) * 250 },
    ]),
  );
  const previous = history.length > 1 ? history[history.length - 2] : undefined;
  const events = snapshot.events.flatMap((e) => {
    try {
      return [{ ...JSON.parse(e.message), kind: e.stage }];
    } catch {
      return [];
    }
  });
  const payments = events.filter((e) => e.kind === "cash_transfer");
  const chosen = snapshot.orders.find((o) => o.id === selected),
    route = orders[selected]?.route;
  return (
    <section
      className="experiment-scene market-scene"
      aria-label="市场实验场景"
    >
      <div className="scene-heading">
        <div>
          <h2>市场场景</h2>
          <p>原研究自动日循环 · 布局为抽象实验，不代表地理</p>
        </div>
        <span>研究日 {snapshot.tick}</span>
      </div>
      <div className="scene-readonly">
        只读市场：本接入没有玩家交易命令入口。下单、运输、收货、消费和付款全部由原算法执行。
      </div>
      <svg
        viewBox="0 0 1040 630"
        className="scene-canvas"
        role="img"
        aria-label="真实库存订单与运输市场场景"
      >
        <defs>
          <marker
            id="market-arrow"
            markerWidth="8"
            markerHeight="8"
            refX="7"
            refY="4"
            orient="auto"
          >
            <path d="M0 0L8 4L0 8" fill="#78938f" />
          </marker>
        </defs>
        <rect width="1040" height="630" fill="#f3f1e9" />
        {Object.entries(orders)
          .slice(-12)
          .map(([id, o]) => {
            const match = String(o.route).match(/^(.+?)>(.+?):(.+)$/),
              a = match && positions.get(match[1]),
              b = match && positions.get(match[2]);
            if (!a || !b) return null;
            const live = snapshot.orders.find((v) => v.id === id);
            return (
              <g
                key={id}
                role="button"
                tabIndex={0}
                aria-label={`选择订单 ${id}`}
                onClick={() => setSelected(id)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") setSelected(id);
                }}
              >
                <line
                  x1={a.x + 110}
                  y1={a.y + 75}
                  x2={b.x + 110}
                  y2={b.y + 75}
                  stroke={selected === id ? "#067c78" : "#b3c0b9"}
                  strokeWidth={selected === id ? 4 : 2}
                  markerEnd="url(#market-arrow)"
                />
                {live && live.inTransit > 0 && (
                  <g
                    transform={`translate(${(a.x + b.x) / 2 + 110},${(a.y + b.y) / 2 + 75})`}
                  >
                    <rect
                      x={-26}
                      y={-15}
                      width={52}
                      height={30}
                      fill="#f0bb69"
                      stroke="#ab7f36"
                    />
                    <text textAnchor="middle" y={5}>
                      {live.inTransit} 在途
                    </text>
                  </g>
                )}
              </g>
            );
          })}
        {ids.map((id) => {
          const at = positions.get(id)!;
          const needs = raw.needs?.[id];
          const stocks = Object.entries(stock[id]) as [string, number][];
          return (
            <g
              key={id}
              data-market-actor={id}
              transform={`translate(${at.x},${at.y})`}
            >
              <rect
                width={220}
                height={175}
                rx={5}
                fill={needs ? "#e3efe5" : "white"}
                stroke="#a7b6ac"
                strokeWidth={2}
              />
              <path
                d="M10 20L30 5L50 20"
                fill="none"
                stroke="#687d6d"
                strokeWidth={3}
              />
              <text x={64} y={27} fontWeight="bold">
                {id}
              </text>
              <text x={14} y={53}>
                余额 {number(cash[id]?.balance)} · 预留{" "}
                {number(cash[id]?.reserved)}
              </text>
              {stocks.slice(0, 4).map(([good, qty], i) => (
                <g key={good}>
                  <rect
                    x={14}
                    y={66 + i * 21}
                    width={Math.min(130, qty * 3)}
                    height={12}
                    fill="#bfd2bf"
                  />
                  <text x={18} y={77 + i * 21}>
                    {good} {number(qty)}
                  </text>
                </g>
              ))}
              {needs && (
                <text
                  x={14}
                  y={165}
                  fill={needs.unmet > 0 ? "#a54132" : "#067c78"}
                >
                  消费满足 {number(needs.consumed)} · 缺口 {number(needs.unmet)}
                </text>
              )}
            </g>
          );
        })}
        {!ids.length && (
          <text x={520} y={270} textAnchor="middle">
            此适配器未上报具名库存场所；状态仅在侧栏查看，不编造市场节点。
          </text>
        )}
        <text x={30} y={605}>
          在途标记只表示实际在途量，不估算车辆位置或伪造到货动画。
        </text>
      </svg>
      <div className="market-orders" aria-label="订单阶段">
        <h3>点选订单，观察原状态推进</h3>
        {snapshot.orders.slice(-12).map((o) => (
          <button
            key={o.id}
            aria-pressed={selected === o.id}
            onClick={() => setSelected(o.id)}
          >
            #{o.id} · 待发 {o.pending} → 在途 {o.inTransit} → 收货 {o.delivered}
          </button>
        ))}
      </div>
      {chosen && (
        <div className="order-inspector" data-testid="market-order-inspector">
          <strong>
            订单 #{chosen.id} · {route ?? "源未提供路线"}
          </strong>
          <span>
            原数量 {chosen.quantity} · 待发 {chosen.pending} · 在途{" "}
            {chosen.inTransit} · 已交付 {chosen.delivered} · 损耗{" "}
            {chosen.lost ?? "未提供"}
          </span>
        </div>
      )}
      <div className="market-consequences">
        <div>
          <h3>本日实际后果</h3>
          <p>
            累计食物满足 {number(snapshot.metrics.fulfilled)}
            {previous ? `（上日 ${number(previous.metrics.fulfilled)}）` : ""} ·
            本日缺口 {number(snapshot.metrics.unmet)}
          </p>
        </div>
        <div>
          <h3>原付款事件</h3>
          {payments.length ? (
            payments.slice(-4).map((e, i) => (
              <p key={i}>
                {e.buyer} → {e.seller} · {number(e.amount)} · {e.event_id}
              </p>
            ))
          ) : (
            <p>本页未提供付款事件；不补造现金流。</p>
          )}
        </div>
      </div>
    </section>
  );
}
