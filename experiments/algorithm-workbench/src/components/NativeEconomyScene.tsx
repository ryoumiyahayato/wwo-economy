import { useState } from "react";
import type {
  CommandReceipt,
  CommandRequest,
  RecordedCommand,
  Snapshot,
} from "../core/types";
import { GoodFigure } from "../presentation/SceneFigures";
import { downloadJson } from "../useWorkbench";

type Row = Record<string, any>;
type Props = {
  snapshot: Snapshot;
  history: Snapshot[];
  commands: RecordedCommand[];
  onCommand: (r: CommandRequest) => Promise<CommandReceipt | undefined>;
  disabled: boolean;
  replayTick?: number | null;
  onReplay?: (t: number | null) => void;
  onStep?: () => void;
};
const goods: Record<string, string> = {
  beans: "豆类",
  bread: "面包",
  grain: "谷物",
  flour: "面粉",
  soap: "肥皂",
  oil: "油料",
  fiber: "纤维",
  cloth: "布料",
  clothes: "衣物",
  building_material: "建材",
  production_tool: "工具",
  machine: "机器",
};
const names: Record<string, string> = {
  development_farm: "农场",
  development_workshop: "工作坊",
  development_soap: "皂坊",
  paris: "巴黎",
  lyon: "里昂",
  formal_generated_country_fra_0001: "本人",
};
function label(id = "") {
  return id
    .split(":")
    .map((s) => names[s] ?? s)
    .filter(
      (s) =>
        !["site", "firm", "account", "personal", "person", "place"].includes(s),
    )
    .join(" · ");
}
const kinds: Record<string, string> = {
  production: "实际生产",
  material_used: "原料消耗",
  consumed: "实际消费",
  payment: "账本转账",
  order: "订单状态",
  work: "实际工时",
  action: "本人操作结果",
  journey: "本人行程状态",
  cargo: "原货运阶段",
  wage: "本人工资责任",
};
const orderState = (o: Row) =>
  o.pending > 0
    ? "等待发出"
    : o.transit > 0
      ? "在途责任"
      : o.delivered > 0 && o.cancelled > 0
        ? "部分交付 / 部分取消"
        : o.delivered >= o.quantity
          ? "已交付"
          : o.cancelled >= o.quantity
            ? "已取消"
            : "状态见原记录";
function money(ledger: Row | undefined, account: string) {
  return (
    ledger?.accounts?.find((a: Row) => a.account_id === account)?.balance ??
    "未知"
  );
}

function Process({
  change,
  before,
  ledger,
  revision,
}: {
  change?: Row;
  before: Row | null;
  ledger: Row;
  revision: number;
}) {
  const raw = change?.raw ?? {};
  if (
    change &&
    ["work", "action", "journey", "cargo", "wage"].includes(change.kind)
  ) {
    const command = raw.envelope?.command;
    return (
      <div
        className="native-process personal-process"
        data-native-process={change.kind}
      >
        <div className="process-caption">
          <span>{kinds[change.kind]}</span>
          <b>分钟 {change.minute}</b>
        </div>
        <div className="personal-process-body">
          <svg
            viewBox="0 0 100 130"
            aria-label={
              change.kind === "cargo"
                ? "货物记录符号，无地理位置"
                : "原记录主体符号，不表示身体动画"
            }
          >
            {change.kind === "cargo" ? (
              <path
                d="M10 30h80v70H10zM10 30l20-20h40l20 20M50 10v90"
                fill="none"
                stroke="currentColor"
                strokeWidth="5"
              />
            ) : (
              <>
                <circle cx="50" cy="25" r="16" />
                <path
                  d="M50 45v45m-25-24 25-15 25 15M50 90l-20 33m20-33 20 33"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="10"
                  strokeLinecap="round"
                />
              </>
            )}
          </svg>
          <div>
            <strong>
              {change.kind === "work"
                ? `${raw.hours} 小时已记录`
                : change.kind === "journey"
                  ? `${label(raw.origin)} → ${label(raw.destination)}`
                  : change.kind === "cargo"
                    ? `${change.before?.stage ?? "新增"} → ${raw.stage}`
                    : change.kind === "wage"
                      ? `工资 ${raw.amount} · 已付 ${raw.paid}`
                      : `${command?.kind} · ${raw.result.accepted ? "原领域接受" : "原领域拒绝"}`}
            </strong>
            <p>
              {change.kind === "work"
                ? `${label(raw.actor)} · ${label(raw.job)} · 原结算日 ${raw.day}`
                : change.kind === "journey"
                  ? `${raw.status} · 下一阶段剩余 ${raw.next_stage_remaining_minutes} 分钟 · 已付车费 ${raw.paid_fare}`
                  : change.kind === "cargo"
                    ? `${raw.order_id} · 数量 ${raw.quantity} · ${label(raw.place_id)}`
                    : change.kind === "wage"
                      ? `第 ${raw.work_day} 日工时 ${raw.hours} · 到期日 ${raw.due_day} · 剩余 ${raw.remaining}`
                      : raw.result.reason}
            </p>
            <code>{change.nativeRecordId}</code>
            <small>原记录状态；未接入身体动作、车间动作或人物地理坐标。</small>
          </div>
        </div>
      </div>
    );
  }
  const payment = change?.kind === "payment",
    order = change?.kind === "order";
  const left = payment
    ? label(raw.from_account_id)
    : order
      ? label(raw.seller_site ?? raw.seller)
      : change?.kind === "production"
        ? label(change.site)
        : label(change?.owner);
  const right = payment
    ? label(raw.to_account_id)
    : order
      ? label(raw.buyer)
      : change?.kind === "production"
        ? "新增产出批次"
        : change?.kind === "material_used"
          ? "已消耗用料"
          : "已实际消费";
  const qty = change?.quantity ?? raw.quantity;
  const unit = payment
    ? "模拟最小货币单位"
    : raw.unit === "development_kg"
      ? "千克（开发口径）"
      : (raw.unit ?? "原生数量单位");
  return (
    <div
      className={`native-process ${change ? "has-process" : ""}`}
      data-native-process={change?.kind ?? "none"}
      key={`${revision}:${change?.id ?? "none"}`}
    >
      <div className="process-caption">
        <span>{change ? kinds[change.kind] : "等待实际过程"}</span>
        <b>{change ? `分钟 ${change.minute}` : "尚无新生产或交易记录"}</b>
      </div>
      <svg
        viewBox="0 0 920 280"
        role="img"
        aria-label={
          change
            ? `${kinds[change.kind]} ${qty ?? ""} ${goods[change.good] ?? ""}`
            : "未发生新过程"
        }
      >
        <defs>
          <pattern
            id="native-floor"
            width="36"
            height="36"
            patternUnits="userSpaceOnUse"
          >
            <path
              d="M36 0H0V36"
              stroke="#d1d9cb"
              fill="none"
              strokeWidth=".6"
            />
          </pattern>
        </defs>
        <rect width="920" height="280" fill="url(#native-floor)" />
        <ellipse cx="225" cy="208" rx="118" ry="22" fill="#2d59451a" />
        <ellipse cx="695" cy="208" rx="118" ry="22" fill="#2d59451a" />
        <path
          d="M342 142H574"
          stroke="#8da197"
          strokeWidth="3"
          strokeDasharray={order ? "7 7" : undefined}
        />
        <path
          d="m562 133 13 9-13 9"
          fill="none"
          stroke="#71867c"
          strokeWidth="3"
        />
        <rect
          x="126"
          y="92"
          width="198"
          height="111"
          rx="12"
          fill="#e3eadc"
          stroke="#8da38b"
        />
        <rect
          x="596"
          y="92"
          width="198"
          height="111"
          rx="12"
          fill="#dae9dc"
          stroke="#70967d"
        />
        <text x="225" y="72" textAnchor="middle" className="process-name">
          {change ? left : "原状态"}
        </text>
        <text x="695" y="72" textAnchor="middle" className="process-name">
          {change ? right : "后续状态"}
        </text>
        {payment ? (
          <>
            <text
              x="225"
              y="142"
              textAnchor="middle"
              className="process-quantity"
            >
              {money(before?.ledger, raw.from_account_id)} →{" "}
              {money(ledger, raw.from_account_id)}
            </text>
            <text
              x="695"
              y="142"
              textAnchor="middle"
              className="process-quantity"
            >
              {money(before?.ledger, raw.to_account_id)} →{" "}
              {money(ledger, raw.to_account_id)}
            </text>
          </>
        ) : (
          <>
            <g transform="translate(225 133) scale(1.5)">
              <GoodFigure good={change?.good ?? raw.good ?? "goods"} />
            </g>
            <g transform="translate(695 133) scale(1.5)">
              <GoodFigure good={change?.good ?? raw.good ?? "goods"} />
            </g>
            <text x="225" y="184" textAnchor="middle">
              {change
                ? (goods[change.good ?? raw.good] ?? change.good ?? raw.good)
                : "无原事件不播放"}
            </text>
            <text x="695" y="184" textAnchor="middle">
              {order
                ? orderState(raw)
                : change
                  ? `${change.kind === "production" ? "+" : "−"}${qty}`
                  : "等待推进"}
            </text>
          </>
        )}
        {change && (
          <g className={order ? "process-order" : "process-transfer"}>
            <circle cx="460" cy="142" r="28" fill="#315f4a" />
            <text
              x="460"
              y="147"
              textAnchor="middle"
              fill="#fff"
              fontWeight="700"
            >
              {payment ? "−" : change.kind === "production" ? "+" : ""}
              {qty}
            </text>
          </g>
        )}
        <text x="460" y="242" textAnchor="middle" fill="#577064" fontSize="12">
          {change
            ? order
              ? "订单状态变化；此箭头不表示地理路线或车辆位置"
              : payment
                ? "两侧为本次提交前后余额，可能包含同期其他交易"
                : `${unit} · 动效只复述已提交记录，不计时、不结算`
            : "仅在原记录发生变化后呈现过程"}
        </text>
      </svg>
      <div className="process-source">
        {change ? (
          <>
            <code>{change.nativeRecordId}</code>
            <span>
              {change.kind === "production" || change.kind === "payment"
                ? "原记录 ID"
                : "原记录变化 · 非独立原生事件"}
            </span>
          </>
        ) : (
          <span>研究观测不赋予玩家额外权限。记录不会因播放而再执行。</span>
        )}
      </div>
    </div>
  );
}

export function NativeEconomyScene({
  snapshot,
  history,
  onReplay,
  replayTick,
  commands,
  onCommand,
  disabled,
  onStep,
}: Props) {
  const f = snapshot.observations!.nativeEconomy as Row;
  const p = f.personal,
    n = f.native;
  const [eventId, setEventId] = useState("");
  const [siteId, setSiteId] = useState("site:development_soap:paris");
  const [quoteId, setQuoteId] = useState("");
  const [jobId, setJobId] = useState("job:development_workshop");
  const [destination, setDestination] = useState("place:lyon");
  const [hours, setHours] = useState(2);
  const [quantity, setQuantity] = useState(1);
  const [details, setDetails] = useState(false);
  const changes = f.changes as Row[];
  const selected =
    changes.find((c) => c.id === eventId) ??
    changes.find((c) => c.kind === "production" && c.site === siteId) ??
    changes.find(
      (c) =>
        c.kind === "payment" &&
        c.raw.from_account_id === p.accounts?.[0]?.account_id,
    ) ??
    changes.find((c) => c.owner === f.playerId) ??
    changes[0];
  const sites: Row[] = n.config.firms.flatMap((firm: Row) =>
    firm.sites.map((s: Row) => ({
      ...s,
      firm: firm.id,
      account: firm.account_id,
    })),
  );
  const site = sites.find((s) => s.id === siteId) ?? sites[0];
  const stock: Record<string, number> = n.stock[site.id] ?? {};
  const oldStock: Record<string, number> = f.previous?.stock[site.id] ?? stock;
  const offer =
    (p.offers as Row[]).find((q) => q.quote_id === quoteId) ??
    p.offers.find((q: Row) => q.good === "soap" && q.quantity > 0) ??
    p.offers[0];
  const good = offer?.good;
  const job = p.known_jobs.find((j: Row) => j.id === jobId) ?? p.known_jobs[0];
  const route =
    f.destinations.find((d: Row) => d.to_place_id === destination) ??
    f.destinations[0];
  const receipt = commands.at(-1)?.receipt;
  const positive = Object.keys(stock).filter(
    (g) =>
      stock[g] > 0 ||
      oldStock[g] > 0 ||
      site.activities.some((a: Row) => a.outputs[g] || a.materials[g]),
  );
  async function send(kind: string, payload: Row) {
    await onCommand({
      id: `sandbox:${crypto.randomUUID()}`,
      op: "livelihood",
      parameters: { kind, payload },
    });
    setEventId("");
  }
  return (
    <section
      className="native-economy"
      aria-label="正式个人经济过程"
      data-native-minute={f.minute}
      data-native-revision={f.revision}
    >
      <header className="native-heading">
        <div>
          <span className="eyebrow">WWO / ORIGINAL FORMAL ECONOMY</span>
          <h2>
            经济现场 <small>第 {n.day} 日</small>
          </h2>
          <p>
            原正式宿主 {f.sourceCommit.slice(0, 7)} · 原开发配置 ·
            研究全量观测，操作限本人 · 关系场景，非地理布置
          </p>
        </div>
        <div className="native-clock">
          <b>{f.minute} 分钟</b>
          <button disabled={disabled || snapshot.done} onClick={onStep}>
            推进原时钟 {f.stepMinutes} 分钟
          </button>
        </div>
      </header>
      <div className="native-livelihood" aria-label="本人生活操作">
        <div>
          <b>求职与工作</b>
          <span>
            {p.employment.job
              ? `已签约 ${label(p.employment.job)}`
              : "当前无工作合同"}
          </span>
          <select
            aria-label="本人已知招聘"
            value={job?.id ?? ""}
            onChange={(e) => setJobId(e.target.value)}
          >
            {p.known_jobs.map((j: Row) => (
              <option key={j.id} value={j.id}>
                {label(j.id)} · {label(j.place)} · 公告岗位 {j.positions}
              </option>
            ))}
          </select>
          <div>
            <button
              disabled={disabled || !job}
              onClick={() => void send("apply", { job_id: job.id })}
            >
              提交本人求职
            </button>
            <input
              aria-label="本人工作小时"
              type="number"
              min="1"
              value={hours}
              onChange={(e) => setHours(+e.target.value)}
            />
            <button
              disabled={disabled || !Number.isInteger(hours) || hours < 1}
              onClick={() => void send("work", { hours })}
            >
              提交本人工作
            </button>
          </div>
          <small>
            工资待付 {p.wage_outstanding} · 到期未付 {p.wage_matured_unpaid} ·
            累计已付{" "}
            {Object.values(p.income_by_currency).reduce(
              (a: number, b) => a + Number(b),
              0,
            )}
          </small>
        </div>
        <div>
          <b>本人旅行 / {label(p.current_place_id)}</b>
          <span>
            {p.travel?.id
              ? `${p.travel.status} · 剩余 ${p.travel.next_stage_remaining_minutes} 分钟`
              : "当前无行程"}
          </span>
          <select
            aria-label="本人目的地"
            value={route?.to_place_id ?? ""}
            onChange={(e) => setDestination(e.target.value)}
          >
            {f.destinations.map((d: Row) => (
              <option key={d.to_place_id} value={d.to_place_id}>
                {label(d.to_place_id)} · {d.minutes} 分钟 · 车费 {d.fare}
              </option>
            ))}
          </select>
          <button
            disabled={disabled || !route}
            onClick={() =>
              void send("travel", { destination_place_id: route.to_place_id })
            }
          >
            提交本人旅行
          </button>
          <small>原地点与行程阶段；无逐秒人物位置。</small>
        </div>
        <div>
          <b>本人使用持有物</b>
          <span>消费资格来自原领域查询</span>
          {Object.entries(f.consumptionQuotes as Row).map(([g, q]) => (
            <button
              key={g}
              disabled={disabled || !q.success}
              title={q.error ?? ""}
              onClick={() =>
                void send("consume", {
                  commodity_id: `native:${g}`,
                  quantity: 1,
                  need_category: q.need_category,
                  source: "manual",
                })
              }
            >
              本人消费 {goods[g] ?? g} × 1
            </button>
          ))}
          {!Object.keys(f.consumptionQuotes).length && (
            <small>暂无持有物；购买尚未交付时不能消费。</small>
          )}
          <span className="native-receipt" role="status">
            {receipt
              ? `${receipt.accepted ? "原领域接受" : "原领域拒绝"} · ${receipt.reason}`
              : "等待本人操作"}
          </span>
        </div>
      </div>
      <div className="native-body">
        <aside className="native-person" aria-label="本人经济状态">
          <span className="native-scope">当前玩家 · 原权限</span>
          <h3>本人 / {label(p.current_place_id)}</h3>
          <code>{f.playerId}</code>
          <div className="native-wallet">
            <small>本人账户余额</small>
            <strong data-native-cash>{p.cash}</strong>
            <span>
              {f.previous
                ? `${f.previous.personal.cash} → ${p.cash}`
                : "开局资金：原配置"}
            </span>
            <small>
              已预留 {p.reserved} · 可用 {p.cash - p.reserved}
            </small>
          </div>
          <div className="personal-stock">
            <h4>本人持有</h4>
            {Object.entries(p.inventory as Record<string, number>)
              .filter(
                ([g, q]) =>
                  q > 0 || (f.previous?.personal.inventory[g] ?? 0) > 0,
              )
              .map(([g, q]) => (
                <div key={g}>
                  <span>{goods[g] ?? g}</span>
                  <b>
                    {f.previous?.personal.inventory[g] ?? q} → {q}
                  </b>
                </div>
              ))}
            {!Object.values(p.inventory).some((q) => Number(q) > 0) && (
              <p>当前无可用库存</p>
            )}
          </div>
          <details>
            <summary>当前需求与生活记录</summary>
            <pre>
              {JSON.stringify(
                { needs: p.need_today, living: f.living },
                null,
                2,
              )}
            </pre>
          </details>
        </aside>
        <div className="native-main">
          <div className="native-site-tabs" aria-label="原经营地点">
            {sites.map((s) => (
              <button
                key={s.id}
                aria-pressed={site.id === s.id}
                onClick={() => {
                  setSiteId(s.id);
                  setEventId("");
                }}
              >
                {label(s.id)}
              </button>
            ))}
          </div>
          <Process
            change={selected}
            before={f.previous}
            ledger={f.ledger}
            revision={f.revision}
          />
          <div className="native-stock-heading">
            <div>
              <b>{label(site.id)} · 实际库存</b>
              <code>{site.id}</code>
            </div>
            <span>
              该企业账户 {money(f.previous?.ledger ?? f.ledger, site.account)} →{" "}
              {money(f.ledger, site.account)}
            </span>
          </div>
          <p className="native-net-note">
            库存与余额为本次提交前 →
            后；净变化同时包含到货、用料、产出、发出及交易。
          </p>
          <div className="native-bins">
            {positive.map((g) => (
              <button
                className="native-bin"
                key={g}
                onClick={() => {
                  const c = changes.find(
                    (e) => e.good === g && e.site === site.id,
                  );
                  if (c) setEventId(c.id);
                }}
              >
                <svg viewBox="0 0 90 48" aria-hidden="true">
                  <path d="M8 8v33h74V8" stroke="#8d9a7f" fill="#f0f1e5" />
                  <rect
                    x="10"
                    y={40 - Math.min(30, stock[g] * 2)}
                    width="70"
                    height={Math.min(30, stock[g] * 2)}
                    fill="#bbcea6"
                  />
                  <g transform="translate(45 23) scale(.7)">
                    <GoodFigure good={g} />
                  </g>
                </svg>
                <span>{goods[g] ?? g}</span>
                <b>
                  {oldStock[g]} → {stock[g]}
                </b>
              </button>
            ))}
          </div>
          <div className="native-production-state">
            {site.activities.map((a: Row) => {
              const plan = n.plans[site.id]?.activities?.[a.id];
              return (
                <span key={a.id}>
                  {a.id.replace("activity:", "")}{" "}
                  <b>{plan?.actual ?? "未输出"}</b> 实际批次
                  {plan
                    ? ` / 计划 ${plan.schedule?.[0]?.quantity ?? "未知"}`
                    : " / 尚无本日计划"}
                </span>
              );
            })}
          </div>
        </div>
      </div>
      <div className="native-actions">
        <div>
          <b>本人购买</b>
          <small>读取已知报价；提交仍由原领域判断</small>
        </div>
        <select
          aria-label="本人已知报价"
          value={offer?.quote_id ?? ""}
          onChange={(e) => setQuoteId(e.target.value)}
        >
          {(p.offers as Row[]).map((q) => (
            <option value={q.quote_id} key={q.quote_id}>
              {goods[q.good] ?? q.good} · {label(q.seller_site)} · {q.price} /{" "}
              {q.quantity} 可供
            </option>
          ))}
        </select>
        <input
          aria-label="本人购买数量"
          type="number"
          min="1"
          max="1000000"
          value={quantity}
          onChange={(e) => setQuantity(Number(e.target.value))}
        />
        <span>
          {offer
            ? `单价 ${offer.price} · 报价可供 ${offer.quantity}`
            : "当前无可用报价"}
        </span>
        <button
          disabled={
            disabled || !offer || !Number.isInteger(quantity) || quantity < 1
          }
          onClick={() =>
            offer &&
            void send("buy", {
              quote_id: offer.quote_id,
              seller: offer.seller,
              seller_site: offer.seller_site,
              good: offer.good,
              quantity,
              max_price: offer.price,
              denomination: offer.denomination,
              need_category:
                good === "soap"
                  ? "household"
                  : ["cloth", "clothes"].includes(good)
                    ? "clothing"
                    : "food",
            })
          }
        >
          提交本人购买
        </button>
        <span className="native-receipt" role="status">
          {receipt
            ? `${receipt.accepted ? "原领域接受" : "原领域拒绝"} · ${receipt.reason}`
            : "等待本人操作"}
        </span>
      </div>
      {!!p.orders.length && (
        <div className="native-orders" aria-label="本人实际订单">
          {p.orders.map((o: Row) => (
            <div key={o.id}>
              <b>
                {o.id} · {goods[o.good] ?? o.good} × {o.quantity}
              </b>
              <span>
                {o.stage} · 已交付 {o.delivered} · 未结款 {o.reserved_amount}
              </span>
              {o.can_collect &&
                o.shipments
                  .filter((s: Row) => s.stage === "AWAITING_RECIPIENT")
                  .map((s: Row) => (
                    <button
                      key={s.id}
                      disabled={disabled}
                      onClick={() =>
                        void send("collect", { shipment_id: s.id })
                      }
                    >
                      领取 {s.id}
                    </button>
                  ))}
            </div>
          ))}
        </div>
      )}
      <div className="native-events">
        <div className="native-event-heading">
          <b>本次真实变化 · {changes.length}</b>
          <button onClick={() => setDetails(!details)} aria-expanded={details}>
            原记录与因果
          </button>
          <span>图中选择只回放观测，不执行交易</span>
        </div>
        <div className="native-change-strip">
          {changes.map((c) => (
            <button
              key={c.id}
              data-native-change={c.id}
              aria-pressed={selected?.id === c.id}
              onClick={() => setEventId(c.id)}
            >
              {kinds[c.kind]}
              {c.good ? ` · ${goods[c.good] ?? c.good} ${c.quantity}` : ""}
              <small>
                {label(c.owner ?? c.raw.from_account_id ?? c.raw.seller ?? "")}
              </small>
            </button>
          ))}
          {!changes.length && <p>无新增记录。可提交购买或推进原时钟。</p>}
        </div>
        {details && selected && (
          <div className="native-source-detail">
            <b>{selected.nativeRecordId}</b>
            <p>
              {selected.sourcePath} · tick {snapshot.tick} / minute {f.minute} ·
              适配器观察 ID {selected.id}
            </p>
            <pre>{JSON.stringify(selected, null, 2)}</pre>
          </div>
        )}
      </div>
      <footer className="native-replay">
        <button
          disabled={!snapshot.tick}
          onClick={() => onReplay?.(snapshot.tick - 1)}
        >
          经济上一帧
        </button>
        <input
          aria-label="正式经济回放"
          type="range"
          min="0"
          max={history.length - 1}
          value={snapshot.tick}
          onChange={(e) => onReplay?.(+e.target.value)}
        />
        <button
          disabled={snapshot.tick >= history.length - 1}
          onClick={() => onReplay?.(snapshot.tick + 1)}
        >
          经济下一帧
        </button>
        <button onClick={() => onReplay?.(null)}>
          {replayTick == null ? "实时提交" : "回到最新"}
        </button>
        <button
          onClick={() =>
            downloadJson(
              `native-economy-${snapshot.tick}-${f.revision}.json`,
              f,
            )
          }
        >
          导出原帧
        </button>
      </footer>
      <details className="native-boundary">
        <summary>
          来源与边界 · 正式地点引用 ≠ 厂房坐标；过程回放 ≠ 地理物流
        </summary>
        <p>
          WorldBootstrap + 原 EconomyDevelopmentConfig 配置 → SimulationStep /
          EconomyR1Slice /
          Ledger。企业、配方、资金、当地路线容量及延迟均为原开发假设；地点引用为原
          place:paris /
          place:lyon。没有企业级经纬度、车间逐秒动作或车辆坐标，不绘制这些内容。研究库存观测不进入本人知识；购买只用本人已知报价并经过原
          LivelihoodAction。原状态快照差分不会被称为原生事件流，所有批次与账本
          ID 保留。
        </p>
        <p>
          仓格填色仅提示库存量（15以上封顶，数字为准）。动效约1.6秒，只复述已提交记录，支持减少动态效果偏好。每日自动消费与自动收货属于原行为；不把它们称为手动操作。
        </p>
      </details>
    </section>
  );
}
