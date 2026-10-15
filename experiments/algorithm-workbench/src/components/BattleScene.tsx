import { useMemo, useState, lazy, Suspense } from "react";
import { downloadJson } from "../useWorkbench";
import type {
  AdapterMetadata,
  CommandReceipt,
  CommandRequest,
  RecordedCommand,
  Scenario,
  Snapshot,
} from "../core/types";
import {
  type BattleFrame,
  type BattleEvent,
  type BattleEntity,
  eventLabel,
  fmt,
  causalEvent,
  uniqueEvents,
} from "../presentation/battle";
const PlainsBackdrop = lazy(() =>
  import("./BattleAssets").then((m) => ({ default: m.PlainsBackdrop })),
);
const AssetBench = lazy(() =>
  import("./BattleAssets").then((m) => ({ default: m.AssetBench })),
);

const BattleWorld = lazy(() =>
  import("./BattleWorld").then((m) => ({ default: m.BattleWorld })),
);

type Props = {
  scenario: Scenario;
  snapshot: Snapshot;
  history: Snapshot[];
  metadata?: AdapterMetadata;
  commands: RecordedCommand[];
  onCommand: (r: CommandRequest) => Promise<CommandReceipt | undefined>;
  disabled: boolean;
  replayTick?: number | null;
  onReplay?: (t: number | null) => void;
  onStep?: () => void;
  stepDisabled?: boolean;
};
const states: Record<string, string> = {
  ABLE: "可行动",
  WOUNDED: "受伤",
  INCAPACITATED: "失能",
  DEAD: "死亡",
  hold: "驻守",
  idle: "待命",
  advance: "前进",
  withdraw: "撤回",
  UNKNOWN: "未上报",
};
const noteworthy = new Set([
  "personal_injury",
  "shared_fire_allocation",
  "losses",
  "weapon_operation_finished",
  "personal_combat_intent",
  "personal_observation_completed",
  "command_feedback",
  "goal_state_changed",
]);
export function BattleScene({
  snapshot,
  history,
  commands,
  onCommand,
  disabled,
  replayTick,
  onReplay,
  onStep,
  stepDisabled,
}: Props) {
  const frame = snapshot.observations!.battle as unknown as BattleFrame;
  const p = snapshot.observations!.person as Record<string, any>;
  const frames = useMemo(
    () =>
      history
        .slice(0, frame.tick + 1)
        .flatMap((s) =>
          s.observations?.battle
            ? [s.observations.battle as unknown as BattleFrame]
            : [],
        ),
    [history, frame.tick],
  );
  const events = useMemo(() => uniqueEvents(frames), [frames]);
  const [selected, setSelected] = useState("");
  const [eventId, setEventId] = useState("");
  const [layer, setLayer] = useState("all");
  const [wide, setWide] = useState(false);
  const [showAll, setShowAll] = useState(false);
  const [fireTarget, setFireTarget] = useState("");
  const [art, setArt] = useState(true);
  const [worldView, setWorldView] = useState(true);
  const [review, setReview] = useState(false);
  const [eventsOpen, setEventsOpen] = useState(false);
  const chosen = events.find((e) => e.id === eventId && e.tick === frame.tick);
  const allocation = causalEvent(chosen, events);
  const entity = frame.entities.find((e) => e.id === selected);
  const previous = (
    history[Math.max(0, frame.tick - 1)]?.observations?.battle as unknown as
      | BattleFrame
      | undefined
  )?.entities.find((e) => e.id === selected);
  const contacts = (
    allocation
      ? [allocation]
      : frame.events.filter((e) => e.kind === "shared_fire_allocation")
  ).flatMap((e) =>
    (e.raw.detail?.prepared_contacts ?? []).map((c: any) => ({
      ...c,
      event: e,
    })),
  );
  const latest = showAll
    ? frame.events
    : frame.events.filter((e) => noteworthy.has(e.kind));
  const x = (v: number) => (wide ? 300 + v * 2100 : 240 + v * 4200);
  const y = (v: number) => (wide ? 370 - v * 900 : 345 - v * 3100);
  const inView = (e: BattleEntity) =>
    x(e.x) > 80 && x(e.x) < 1050 && y(e.y) > 65 && y(e.y) < 440;
  const shown = frame.entities.filter(
    (e) => inView(e) && (layer === "all" || e.kind === layer),
  );
  const injuries = new Set(
    frame.events
      .filter((e) => e.kind === "personal_injury")
      .map((e) => e.actorId),
  );
  const targetOptions = (p.reports?.entries ?? [])
    .filter(
      (c: any) => c.fact_kind === "ground_contact" && c.claimed_value?.can_fire,
    )
    .map((c: any) => c.subject_ref) as string[];
  const targets = [...new Set(targetOptions)];
  const actualTarget = targets.includes(fireTarget)
    ? fireTarget
    : (targets[0] ?? "");
  function chooseEvent(e: BattleEvent) {
    if (e.tick !== frame.tick) onReplay?.(e.tick);
    setEventId(e.id);
    setSelected(e.actorId ?? e.targetId ?? "");
  }
  async function body(action: string) {
    await onCommand({
      id: `review_${commands.length + 1}`,
      op: "body",
      parameters: {
        action,
        ...(action === "observe"
          ? { node_ref: p.personal?.anchor_node ?? "A" }
          : {}),
        ...(action === "fire" ? { target_ref: actualTarget, seconds: 30 } : {}),
      },
    });
  }
  const receipt = commands.at(-1)?.receipt;
  const offset = (e: BattleEntity): [number, number] => {
    if (e.kind === "unit")
      return e.team === "blue"
        ? [-130, e.id === "unit_000" ? -48 : 52]
        : [115, e.id === "unit_002" ? -55 : 45];
    const index = [
      "squad",
      "soldier",
      "scout",
      "red_commander",
      "company",
      "platoon",
    ].indexOf(e.id);
    return e.team === "blue"
      ? [
          48 + (index === 2 ? 62 : 0),
          index === 0
            ? -50
            : index === 1
              ? 30
              : index === 2
                ? -5
                : index === 4
                  ? -30
                  : 30,
        ]
      : [-45, 55];
  };
  const nowEntities = Object.fromEntries(frame.entities.map((e) => [e.id, e]));
  return (
    <section className="battle-workbench" aria-label="实时战场观测">
      <div className="battle-title">
        <div>
          <span className="eyebrow">WWO / CAUSAL OBSERVATORY</span>
          <h2>
            实时战场 <span>A3</span>
          </h2>
          <p>
            原 Godot 实例 · {frame.sourceCommit.slice(0, 7)} · A3 局部研究场景
          </p>
        </div>
        <div className="truth-badge">
          研究真值 DEBUG_TRUTH<small>用于评阅 · 不进入人物知识或决策</small>
        </div>
      </div>
      <div className="battle-stats">
        <span>
          <i className="blue-dot" />
          蓝方{" "}
          {
            frame.entities.filter((e) => e.kind === "unit" && e.team === "blue")
              .length
          }{" "}
          单位
        </span>
        <span>
          <i className="red-dot" />
          红方{" "}
          {
            frame.entities.filter((e) => e.kind === "unit" && e.team === "red")
              .length
          }{" "}
          单位
        </span>
        <span>
          {frame.entities.filter((e) => e.kind === "person").length} 具名人物
        </span>
        <span>
          已提交 <b>{fmt(frame.time, 2)} s</b>
        </span>
        <span>
          本帧 <b>{frame.events.length}</b> 原事件
        </span>
        <span>
          源记录丢弃 <b>{frame.dropped}</b>
        </span>
      </div>
      <div
        className={`battle-layout ${entity || chosen || review ? "review-open" : "scene-only"}`}
      >
        <div className="battle-map-panel">
          <div className="battle-map-tools">
            <button onClick={() => setWorldView(!worldView)}>
              {worldView ? "坐标审阅" : "广角实地"}
            </button>
            <select
              hidden={worldView}
              aria-label="战场显示层"
              value={layer}
              onChange={(e) => setLayer(e.target.value)}
            >
              <option value="all">单位 + 具名人物</option>
              <option value="unit">单位</option>
              <option value="person">具名人物</option>
            </select>
            <button
              hidden={worldView}
              aria-pressed={wide}
              onClick={() => setWide(!wide)}
            >
              {wide ? "前线近景" : "全域视野"}
            </button>
            <button aria-pressed={art} onClick={() => setArt(!art)}>
              {art ? "美术层 开" : "美术层 关"}
            </button>
            <button aria-pressed={review} onClick={() => setReview(!review)}>
              审阅标注 {review ? "开" : "关"}
            </button>
            <button
              aria-expanded={eventsOpen}
              onClick={() => setEventsOpen(!eventsOpen)}
            >
              本帧事件 · {frame.events.length}
            </button>
            <span>点选实体查看状态 · 审阅标注显示原坐标及关联</span>
          </div>
          {worldView ? (
            <Suspense fallback={<p>载入广角战场…</p>}>
              <BattleWorld
                frame={frame}
                frames={frames}
                selected={selected}
                allocation={allocation}
                art={art}
                review={review}
                onEntity={(id) => {
                  setSelected(id);
                  setEventId("");
                }}
                onEvent={chooseEvent}
              />
            </Suspense>
          ) : (
            <div className="battle-map">
              {art && (
                <Suspense fallback={null}>
                  <PlainsBackdrop />
                </Suspense>
              )}
              <svg
                viewBox="0 0 1100 500"
                role="group"
                aria-label="双方状态与火力关联"
                className="battle-svg"
              >
                <defs>
                  <pattern
                    id="battle-grid"
                    width="55"
                    height="55"
                    patternUnits="userSpaceOnUse"
                  >
                    <path
                      d="M55 0H0V55"
                      fill="none"
                      stroke="#8aa79e"
                      strokeWidth=".5"
                      opacity=".25"
                    />
                  </pattern>
                  <marker
                    id="fire-arrow"
                    markerWidth="8"
                    markerHeight="8"
                    refX="7"
                    refY="4"
                    orient="auto"
                  >
                    <path d="M0 0L8 4L0 8" fill="#ffc66b" />
                  </marker>
                  <marker
                    id="move-arrow"
                    markerWidth="8"
                    markerHeight="8"
                    refX="7"
                    refY="4"
                    orient="auto"
                  >
                    <path d="M0 0L8 4L0 8" fill="#85ded7" />
                  </marker>
                </defs>
                <rect width="1100" height="500" fill="url(#battle-grid)" />
                <text x="28" y="37" className="map-caption">
                  {wide ? "全域" : "前线"} / 抽象道路世界 · km
                </text>
                <text x="1070" y="37" textAnchor="end" className="map-caption">
                  TICK {String(frame.tick).padStart(3, "0")} · {fmt(frame.time)}{" "}
                  s
                </text>
                {Object.entries(frame.nodes)
                  .filter(([id]) => ["A", "B", "C", "D"].includes(id))
                  .map(([id, n]) => (
                    <g key={id} opacity={0.55}>
                      <circle
                        cx={x(n.xy[0])}
                        cy={y(n.xy[1])}
                        r="6"
                        fill="none"
                        stroke="#e6eddb"
                      />
                      <text
                        x={x(n.xy[0]) + 9}
                        y={y(n.xy[1]) + 22}
                        className="map-node"
                      >
                        {id} [{n.xy.map((v) => fmt(v, 2)).join(", ")}]
                      </text>
                    </g>
                  ))}
                {shown.map((e) => {
                  const points = frames
                    .map((f) => f.entities.find((v) => v.id === e.id))
                    .filter((v): v is BattleEntity => !!v);
                  return (
                    <polyline
                      key={"trail-" + e.id}
                      points={points
                        .map((v) => `${x(v.x)},${y(v.y)}`)
                        .join(" ")}
                      fill="none"
                      stroke={e.team === "blue" ? "#81d7ec" : "#f19b98"}
                      opacity=".6"
                      strokeWidth="2"
                    />
                  );
                })}
                {contacts.map((c: any, i: number) => {
                  const a = nowEntities[c.source],
                    b = nowEntities[c.target];
                  if (!a || !b || !inView(a) || !inView(b)) return null;
                  const midX = (x(a.x) + x(b.x)) / 2,
                    midY = (y(a.y) + y(b.y)) / 2 + ((i % 4) - 1.5) * 22;
                  return (
                    <g
                      key={c.event.id + c.source + i}
                      data-fire-event={c.event.id}
                      role="button"
                      tabIndex={0}
                      aria-label={`火力关联 ${c.source} 到 ${c.target}`}
                      onClick={() => chooseEvent(c.event)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") chooseEvent(c.event);
                      }}
                    >
                      <path
                        d={`M${x(a.x)} ${y(a.y)} Q${midX} ${midY} ${x(b.x)} ${y(b.y)}`}
                        fill="none"
                        stroke="#ffc66b"
                        strokeWidth={chosen ? 2.5 : 1.6}
                        opacity={0.75}
                        strokeDasharray="7 7"
                        markerEnd="url(#fire-arrow)"
                      />
                      <path
                        d={`M${x(a.x)} ${y(a.y)} Q${midX} ${midY} ${x(b.x)} ${y(b.y)}`}
                        fill="none"
                        stroke="transparent"
                        strokeWidth="14"
                      />
                    </g>
                  );
                })}
                {contacts.length > 0 && (
                  <g>
                    <rect
                      x="404"
                      y="70"
                      width="273"
                      height="39"
                      rx="5"
                      fill="#19292b"
                      stroke="#836637"
                    />
                    <text
                      x="540"
                      y="95"
                      textAnchor="middle"
                      fill="#ffd17e"
                      fontSize="13"
                    >
                      区间火力关联 · 不是逐发弹道
                    </text>
                  </g>
                )}
                {shown.map((e) => {
                  const [dx, dy] = offset(e);
                  const px = x(e.x),
                    py = y(e.y),
                    sx = px + dx,
                    sy = py + dy;
                  const color = e.team === "blue" ? "#78d6ef" : "#ff9a90";
                  const active = selected === e.id;
                  return (
                    <g
                      key={e.id}
                      data-battle-entity={e.id}
                      role="button"
                      tabIndex={0}
                      aria-label={`选中 ${e.id}`}
                      onClick={() => {
                        setSelected(e.id);
                        setEventId("");
                      }}
                      onKeyDown={(ev) => {
                        if (ev.key === "Enter") {
                          setSelected(e.id);
                          setEventId("");
                        }
                      }}
                    >
                      <circle cx={px} cy={py} r="4" fill={color} />
                      <path
                        d={`M${px} ${py}L${sx} ${sy}`}
                        stroke={color}
                        strokeWidth="1"
                        opacity=".45"
                      />
                      {e.movement && (
                        <path
                          d={`M${x(e.movement.from[0])} ${y(e.movement.from[1])}L${px} ${py}`}
                          stroke="#9ce6d8"
                          strokeWidth="4"
                          markerEnd="url(#move-arrow)"
                        />
                      )}
                      <g transform={`translate(${sx},${sy})`}>
                        <rect
                          x={
                            e.kind === "unit"
                              ? -81
                              : e.id === "red_commander"
                                ? -57
                                : -40
                          }
                          y="-25"
                          width={
                            e.kind === "unit"
                              ? 162
                              : e.id === "red_commander"
                                ? 114
                                : 80
                          }
                          height={e.kind === "unit" ? 58 : 52}
                          rx={e.kind === "unit" ? 4 : 18}
                          fill={active ? "#344952" : "#14252b"}
                          stroke={active ? "#ffffff" : color}
                          strokeWidth={active ? 2 : 1.3}
                        />
                        {e.kind === "unit" ? (
                          <>
                            <path
                              d="M-70 -13h17v12h-17zM-70 -13l17 12M-53 -13L-70 -1"
                              stroke={color}
                              fill="none"
                            />
                            <text
                              x="-43"
                              y="-2"
                              fill={color}
                              fontSize="13"
                              fontWeight="700"
                            >
                              {e.id}
                            </text>
                            <text
                              x="0"
                              y="21"
                              textAnchor="middle"
                              fill="#e5eceb"
                              fontSize="11"
                            >
                              {states[e.state] ?? e.state} · 能力{" "}
                              {fmt(e.personnel, 3)}
                            </text>
                          </>
                        ) : (
                          <>
                            <circle cy="-12" r="4" fill={color} />
                            <path
                              d="M0 -7v10M-8 -1H8M0 3L-5 10M0 3L5 10"
                              stroke={color}
                              strokeWidth="2"
                            />
                            <text
                              y="22"
                              textAnchor="middle"
                              fill="#ecf4f4"
                              fontSize="10"
                            >
                              {e.id}
                            </text>
                          </>
                        )}
                        {injuries.has(e.id) && (
                          <g>
                            <circle
                              cx={e.kind === "unit" ? 77 : 35}
                              cy="-21"
                              r="9"
                              fill="#f2aa68"
                            />
                            <text
                              x={e.kind === "unit" ? 77 : 35}
                              y="-17"
                              textAnchor="middle"
                              fill="#27221d"
                              fontSize="12"
                            >
                              !
                            </text>
                          </g>
                        )}
                      </g>
                    </g>
                  );
                })}
                <text x="28" y="465" className="map-caption">
                  ● 精确坐标锚点　引线卡片作显示偏移，不改位置　!
                  受伤标记对应当前 tick 原事件
                </text>
                <text x="28" y="489" className="map-caption">
                  {frame.entities.filter((e) => !inView(e)).length}{" "}
                  个实体在视野外 · {frame.unlocatedUnits.length}{" "}
                  个远方稀疏单位无局部坐标，不投放到此地图
                </text>
              </svg>
            </div>
          )}
          <div className="battle-map-footer">
            {art
              ? "已复用私人平原 GLB，美术比例不代表物理米制；碰撞、掩体与障碍未接入。"
              : "坐标网格模式"}
            <span>蓝方 ▣ / 红方 ▣ · 人物 ≠ 单位数量</span>
          </div>
        </div>
        {(entity || chosen || review) && (
          <aside className="battle-inspector" aria-label="因果检查器">
            <div className="inspector-title">
              <h3>
                {chosen ? "事件因果" : entity ? "实体状态" : "本帧发生了什么"}
              </h3>
              {(entity || chosen || review) && (
                <button
                  aria-label="关闭因果详情"
                  onClick={() => {
                    setEventId("");
                    setSelected("");
                    setReview(false);
                  }}
                >
                  ×
                </button>
              )}
            </div>
            {chosen ? (
              <>
                <span className="event-kind">
                  {eventLabel(chosen)} · tick {chosen.tick} /{" "}
                  {fmt(chosen.effectiveTime)} s
                </span>
                <h4>{chosen.actorId ?? chosen.targetId}</h4>
                <code className="event-id">{chosen.id}</code>
                {chosen.kind === "personal_injury" && (
                  <>
                    <div className="state-change">
                      <span>
                        健康份额
                        <br />
                        <b>{fmt(chosen.raw.detail.before_health, 9)}</b>
                      </span>
                      <span>→</span>
                      <span>
                        健康份额
                        <br />
                        <b>{fmt(chosen.raw.detail.after_health, 9)}</b>
                      </span>
                    </div>
                    <p className="injury-note">
                      原伤害 {fmt(chosen.raw.detail.new_capacity_loss, 9)} ·{" "}
                      {states[chosen.raw.detail.life_state] ??
                        chosen.raw.detail.life_state}
                    </p>
                  </>
                )}
                {chosen.kind === "shared_fire_allocation" && (
                  <p className="injury-note">
                    本次已应用损失：
                    {fmt(chosen.raw.detail.total_loss_applied_once, 9)}
                    <br />
                    起始能力：{fmt(chosen.raw.detail.segment_start_capacity)}
                  </p>
                )}
                <h4>原 cause_refs</h4>
                {chosen.causeIds.length ? (
                  chosen.causeIds.map((id) => {
                    const cause = events.find((e) => e.id === id);
                    const obj = frame.entities.find((e) => e.id === id);
                    return (
                      <button
                        className="cause-link"
                        key={id}
                        onClick={() =>
                          cause
                            ? chooseEvent(cause)
                            : obj
                              ? (setSelected(id), setEventId(""))
                              : undefined
                        }
                      >
                        {id}
                        <small>
                          {cause
                            ? "打开原因事件"
                            : obj
                              ? "源实体引用"
                              : "原源未导出该引用的记录"}
                        </small>
                      </button>
                    );
                  })
                ) : (
                  <p>原事件没有 cause_refs</p>
                )}
                {allocation && (
                  <div className="cause-summary">
                    {allocation.causeIds.join(" + ")}
                    <br />↓ 原共享火力分配
                    <br />
                    {allocation.targetId}
                    <br />
                    <small>不把多源分配归因为某一发子弹。</small>
                  </div>
                )}
                <details>
                  <summary>原始输出 JSON</summary>
                  <pre>{JSON.stringify(chosen.raw, null, 2)}</pre>
                </details>
              </>
            ) : entity ? (
              <>
                <span className={"entity-team " + entity.team}>
                  {entity.team === "blue"
                    ? "蓝方"
                    : entity.team === "red"
                      ? "红方"
                      : "阵营未知"}{" "}
                  / {entity.kind === "person" ? "具名人物" : "原单位"}
                </span>
                <h4>{entity.id}</h4>
                <p>
                  {states[entity.state] ?? entity.state} · [{fmt(entity.x)},{" "}
                  {fmt(entity.y)}] km
                </p>
                <p>
                  身体/武器朝向：
                  {entity.heading === undefined
                    ? "未上报"
                    : fmt(entity.heading) + "°"}
                  {entity.motionHeading !== undefined
                    ? `；本段移动方向 ${fmt(entity.motionHeading, 1)}°`
                    : ""}
                </p>
                <table>
                  <thead>
                    <tr>
                      <th>字段</th>
                      <th>前 tick</th>
                      <th>当前</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(
                      [
                        "x",
                        "y",
                        "health",
                        "personnel",
                        "ammo",
                        "casualties",
                      ] as const
                    )
                      .filter((k) => entity[k] !== undefined)
                      .map((k) => (
                        <tr key={k}>
                          <td>
                            {
                              {
                                x: "x / km",
                                y: "y / km",
                                health: "健康份额",
                                personnel: "有效能力",
                                ammo: "弹药份额",
                                casualties: "累计损失",
                              }[k]
                            }
                          </td>
                          <td>{fmt(previous?.[k])}</td>
                          <td>{fmt(entity[k])}</td>
                        </tr>
                      ))}
                  </tbody>
                </table>
                {entity.weapon && (
                  <div className="weapon-readout">
                    <h4>原武器状态</h4>
                    <p>
                      模式 {entity.weapon.mode ?? "未上报"} ·{" "}
                      {entity.weapon.status ?? "未上报"}
                      <br />
                      目标 {entity.weapon.target_ref || "未指定"}
                      <br />
                      已装填 {fmt(entity.weapon.ready)} · 累计消耗{" "}
                      {fmt(entity.weapon.spent)}
                      <br />
                      意图引用 {entity.weapon.fire_owner_ref || "无"}
                    </p>
                  </div>
                )}
                <h4>相关事件</h4>
                {frame.events
                  .filter(
                    (e) => e.actorId === entity.id || e.targetId === entity.id,
                  )
                  .filter((e) => noteworthy.has(e.kind))
                  .slice(-4)
                  .map((e) => (
                    <button
                      className="cause-link"
                      key={e.id}
                      onClick={() => chooseEvent(e)}
                    >
                      {eventLabel(e)}
                      <small>{e.id}</small>
                    </button>
                  ))}
                <details>
                  <summary>原状态与来源路径</summary>
                  <code>{entity.sourcePath}</code>
                  <pre>{JSON.stringify(entity.raw, null, 2)}</pre>
                </details>
              </>
            ) : (
              <>
                <div className="review-hint">
                  点选人物、单位或下方事件，查看原 ID、原因和前后状态。
                </div>
                <div className="frame-facts">
                  <strong>
                    {
                      frame.events.filter((e) => e.kind === "personal_injury")
                        .length
                    }
                  </strong>
                  <span>个人受伤事件</span>
                  <strong>
                    {
                      frame.events.filter(
                        (e) => e.kind === "shared_fire_allocation",
                      ).length
                    }
                  </strong>
                  <span>共享火力分配</span>
                </div>
                <p>
                  黄色虚线展示原分配记录中的火力源→目标。轨迹只连接已提交位置。
                </p>
              </>
            )}
          </aside>
        )}
      </div>
      <div className="battle-timeline">
        <div className="timeline-controls">
          <b>
            {replayTick == null ? "实时提交" : "历史回放"} · tick {frame.tick}
          </b>
          <button disabled={stepDisabled || snapshot.done} onClick={onStep}>
            推进一帧
          </button>
          <button
            aria-label="回放上一步"
            disabled={!frame.tick}
            onClick={() => onReplay?.(frame.tick - 1)}
          >
            ← 上一帧
          </button>
          <input
            aria-label="战场回放时间"
            type="range"
            min={0}
            max={history.length - 1}
            value={frame.tick}
            onChange={(e) => {
              setEventId("");
              onReplay?.(+e.target.value);
            }}
          />
          <button
            aria-label="回放下一步"
            disabled={frame.tick >= history.length - 1}
            onClick={() => onReplay?.(frame.tick + 1)}
          >
            下一帧 →
          </button>
          <button onClick={() => onReplay?.(null)}>回到最新</button>
          <button
            onClick={() =>
              downloadJson(`battle-frame-${frame.tick}.json`, frame)
            }
          >
            导出当前帧
          </button>
        </div>
        {eventsOpen && (
          <div className="event-ribbon" aria-label="本帧事件">
            <button
              className="event-filter"
              onClick={() => setShowAll(!showAll)}
            >
              {showAll ? "全部原事件" : "作战事件"}
              <small>点此切换</small>
            </button>
            {latest.length ? (
              latest.map((e) => (
                <button
                  key={e.id}
                  data-event-id={e.id}
                  className={e.id === eventId ? "selected-event" : ""}
                  onClick={() => chooseEvent(e)}
                >
                  <span>
                    {eventLabel(e)} · {fmt(e.effectiveTime, 2)}s
                  </span>
                  <strong>{e.actorId ?? e.targetId ?? "world"}</strong>
                  <small>{e.id}</small>
                </button>
              ))
            ) : (
              <p>本帧没有此类事件；不播放命中或开火效果。</p>
            )}
          </div>
        )}
      </div>
      <details className="battle-boundary">
        <summary>来源与接入缺口 · A3 局部输出，未绑定正式世界地理</summary>
        {frame.gaps.map((g) => (
          <p key={g}>{g}</p>
        ))}
        <p>
          每个 tick 是 {history[1]?.metrics.elapsedSeconds ?? "配置"}{" "}
          游戏秒的提交结果；浏览器刷新频率不等于算法步长。
        </p>
        <p>
          正式世界另有个人经济和地理地点；当前 A3 的 squad 与 J1 的 Household
          未绑定正式人物、账户或经纬度。50/25/5 km
          为显示导航，不会创建战场或授予操作权限。
        </p>
      </details>
      <details className="battle-commands">
        <summary>本人操作 · squad · 原权限/冷却/送达规则</summary>
        <div className="command-row">
          <button
            disabled={disabled}
            onClick={() =>
              void onCommand({
                id: `review_${commands.length + 1}`,
                target: "node_unit_000",
                intent: "advance",
                node: "B",
                path: ["AB"],
              })
            }
          >
            前进至 B（AB）
          </button>
          <button
            disabled={disabled}
            onClick={() =>
              void onCommand({
                id: `review_${commands.length + 1}`,
                target: "node_unit_000",
                intent: "hold",
                node: p.personal?.anchor_node ?? "A",
                path: [],
              })
            }
          >
            驻守
          </button>
          <button disabled={disabled} onClick={() => void body("observe")}>
            观察当前位置
          </button>
          <button disabled={disabled} onClick={() => void body("reload")}>
            装填
          </button>
          <select
            aria-label="本人已知射击目标"
            value={actualTarget}
            onChange={(e) => setFireTarget(e.target.value)}
          >
            {targets.length ? (
              targets.map((t) => <option key={t}>{t}</option>)
            ) : (
              <option value="">本人尚无可射击接触报告</option>
            )}
          </select>
          <button
            disabled={disabled || !actualTarget}
            onClick={() => void body("fire")}
          >
            请求射击 30s
          </button>
          <button disabled={disabled} onClick={() => void body("cease_fire")}>
            停火
          </button>
        </div>
        <p>
          射击列表只使用本人已收到的
          ground_contact；研究真值不会补给玩家目标。受理不等于执行。
        </p>
        {receipt && (
          <p role="status">
            {receipt.id}：{receipt.accepted ? "已受理" : "未受理"} ·{" "}
            {receipt.status} · {receipt.reason || "无附加原因"}
          </p>
        )}
      </details>
      <Suspense fallback={null}>
        <AssetBench />
      </Suspense>
    </section>
  );
}
