import {
  clone,
  type AlgorithmAdapter,
  type Event,
  type OrderView,
  type Scenario,
  type Snapshot,
  type Stage,
} from "../core/types";
import { economyMetadata, validateScenario } from "../core/scenario";
import { SeededRandom } from "../core/random";
import {
  provideFunding,
  provideSupply,
  transportPolicy,
} from "../core/dependencies";

interface Order extends OrderView {
  consumed: number;
}
interface Shipment {
  order: string;
  quantity: number;
  arrival: number;
}
export const economyAdapter: AlgorithmAdapter = {
  metadata: economyMetadata,
  async create(input) {
    const s = validateScenario(input, economyMetadata),
      p = s.params,
      random = new SeededRandom(s.seed);
    let tick = 0,
      stock = p.stock,
      inventory = 0,
      buyerCash = p.buyerCash,
      sellerCash = 0,
      escrow = 0;
    let consumed = 0,
      lost = 0,
      requested = 0,
      injectedGoods = 0,
      injectedFunds = 0,
      stallTicks = 0;
    const orders: Order[] = [],
      shipments: Shipment[] = [];
    let events: Event[] = [],
      stages: Stage[] = [];
    let lastInjection = { goods: 0, funds: 0 },
      reason = "";
    const event = (
      stage: string,
      status: Event["status"],
      message: string,
      entityId?: string,
    ) =>
      events.push({
        tick,
        stage,
        status,
        message,
        ...(entityId ? { entityId } : {}),
      });
    const stage = (
      id: string,
      label: string,
      status: Stage["status"],
      detail: string,
    ) => stages.push({ id, label, status, detail });
    const snapshot = (): Snapshot => {
      const inTransit = shipments.reduce((n, x) => n + x.quantity, 0);
      const unmet = requested - consumed;
      const goodsResidual =
        p.stock +
        injectedGoods -
        stock -
        inventory -
        inTransit -
        consumed -
        lost;
      const fundsResidual =
        p.buyerCash + injectedFunds - buyerCash - sellerCash - escrow;
      const orderResidual = orders.reduce(
        (n, o) =>
          n + o.quantity - o.pending - o.inTransit - o.delivered - o.lost,
        0,
      );
      const passed =
        tick >= 3 &&
        consumed > 0 &&
        unmet === 0 &&
        goodsResidual === 0 &&
        fundsResidual === 0 &&
        orderResidual === 0;
      return clone({
        tick,
        metrics: {
          fulfilled: consumed,
          unmet,
          buyerCash,
          sellerCash,
          inventory: stock + inventory,
          inTransit,
          lost,
          escrow,
          requested,
          goodsResidual,
          fundsResidual,
          orderResidual,
          stallTicks,
        },
        invariants: {
          goods: goodsResidual,
          funds: fundsResidual,
          orders: orderResidual,
        },
        injections: {
          ...lastInjection,
          totalGoods: injectedGoods,
          totalFunds: injectedFunds,
        },
        stages: tick
          ? stages
          : [
              {
                id: "demand",
                label: "需求",
                status: "pending",
                detail: "点击单步开始",
              },
            ],
        events,
        entities: [
          { id: "supplier", label: "供应方", x: 2, y: 3, stock },
          { id: "buyer", label: "需求方", x: 10, y: 3, stock: inventory },
        ],
        orders: orders
          .slice(-30)
          .map((o) => ({
            ...o,
            status: o.pending
              ? "待分配"
              : o.inTransit
                ? "运输中"
                : o.lost
                  ? "有损耗"
                  : "已消费",
          })),
        completion: {
          status: passed ? "pass" : tick >= s.maxTicks ? "fail" : "pending",
          condition: "至少 3 轮发生消费、未满足需求为 0，且物资/资金/订单守恒",
          reason: passed
            ? "合成 demo 完成了声明的循环条件"
            : reason || "等待更多轮次",
        },
        done: tick >= s.maxTicks,
        blockedReason: reason,
      });
    };
    const deliver = (shipment: Shipment) => {
      const o = orders.find((x) => x.id === shipment.order)!;
      let damage = 0;
      if (s.dependencies.transport === "bounded")
        for (let i = 0; i < shipment.quantity; i++)
          if (random.next() < p.lossRate) damage++;
      const received = shipment.quantity - damage;
      o.inTransit -= shipment.quantity;
      o.delivered += received;
      o.lost += damage;
      inventory += received;
      lost += damage;
      escrow -= shipment.quantity * p.price;
      sellerCash += received * p.price;
      buyerCash += damage * p.price;
      event(
        "settlement",
        "success",
        `收货 ${received}；损耗 ${damage}；结算 ${received * p.price}；退款 ${damage * p.price}`,
        o.id,
      );
    };
    return {
      snapshot: snapshot(),
      session: {
        async step() {
          if (tick >= s.maxTicks) return snapshot();
          tick++;
          events = [];
          stages = [];
          reason = "";
          lastInjection = { goods: 0, funds: 0 };
          const beforeConsumed = consumed;
          buyerCash += p.income;
          injectedFunds += p.income;
          lastInjection.funds += p.income;
          if (p.income)
            event("external", "success", `外部资金注入 +${p.income}`);
          const arriving = shipments.filter((x) => x.arrival <= tick);
          for (const x of arriving) deliver(x);
          for (let i = shipments.length - 1; i >= 0; i--)
            if (shipments[i].arrival <= tick) shipments.splice(i, 1);
          requested += p.demand;
          if (p.demand > 0) {
            const id = `ORD-${String(tick).padStart(3, "0")}`;
            orders.push({
              id,
              quantity: p.demand,
              pending: p.demand,
              inTransit: 0,
              delivered: 0,
              lost: 0,
              consumed: 0,
              status: "pending",
            });
            event("demand", "success", `生成需求 ${p.demand}`, id);
          }
          stage(
            "demand",
            "需求",
            "success",
            `本轮 ${p.demand}；累计 ${requested}`,
          );
          const pending = orders.reduce((n, o) => n + o.pending, 0);
          const supply = provideSupply(pending, stock, s.dependencies.supply);
          stock = supply.available;
          injectedGoods += supply.injected;
          lastInjection.goods = supply.injected;
          if (supply.injected)
            event(
              "external",
              "success",
              `供应侧按需注入 +${supply.injected} 单位`,
            );
          const funding = provideFunding(
            pending * p.price,
            buyerCash,
            s.dependencies.funding,
          );
          buyerCash = funding.available;
          injectedFunds += funding.injected;
          lastInjection.funds += funding.injected;
          if (funding.injected)
            event("external", "success", `资金按需注入 +${funding.injected}`);
          stage(
            "match",
            "匹配",
            pending === 0 ? "success" : stock > 0 ? "success" : "blocked",
            stock > 0 ? "已知供应方可用；FIFO" : "供应方没有可用库存",
          );
          let capacity = transportPolicy(
              s.dependencies.transport,
              pending,
              p.capacity,
              p.leadTicks,
            ).allocated,
            dispatched = 0;
          for (const o of orders) {
            const qty = Math.min(
              o.pending,
              stock,
              capacity,
              Math.floor(buyerCash / p.price),
            );
            if (!qty) continue;
            stock -= qty;
            buyerCash -= qty * p.price;
            escrow += qty * p.price;
            o.pending -= qty;
            o.inTransit += qty;
            capacity -= qty;
            dispatched += qty;
            const shipment = {
              order: o.id,
              quantity: qty,
              arrival:
                tick +
                (s.dependencies.transport === "instant" ? 0 : p.leadTicks),
            };
            event(
              "allocation",
              "success",
              `分配 ${qty} @ ${p.price}；托管 ${qty * p.price}；ETA ${shipment.arrival}`,
              o.id,
            );
            if (shipment.arrival === tick) deliver(shipment);
            else shipments.push(shipment);
          }
          if (pending > 0 && dispatched === 0)
            reason =
              stock === 0
                ? "供应库存不足"
                : buyerCash < p.price
                  ? "买方资金不足"
                  : p.capacity === 0
                    ? "运输容量为 0"
                    : "等待分配";
          stage(
            "allocation",
            "分配",
            dispatched > 0 || !pending ? "success" : "blocked",
            `本轮发运 ${dispatched}；${reason || "固定挂牌价，无价格发现"}`,
          );
          stage(
            "settlement",
            "结算",
            inventory > 0
              ? "success"
              : shipments.length
                ? "pending"
                : reason
                  ? "blocked"
                  : "success",
            shipments.length
              ? "真实结算在到货时发生"
              : "按实际收货转账；损耗退款",
          );
          const used = inventory;
          inventory = 0;
          consumed += used;
          let remaining = used;
          for (const o of orders) {
            const q = Math.min(remaining, o.delivered - o.consumed);
            o.consumed += q;
            remaining -= q;
            if (!remaining) break;
          }
          if (used)
            event(
              "consumption",
              "success",
              `实际消费 ${used}；累计 ${consumed}`,
            );
          else if (!reason && shipments.length) reason = "等待运输到货";
          else if (!reason && lost)
            reason = "损耗需求未补运（demo 不实现补运）";
          stage(
            "consumption",
            "消费",
            used > 0 || p.demand === 0 ? "success" : "pending",
            `实际消费 ${used}`,
          );
          stage("next-tick", "下一轮", "success", `时间推进到 ${tick}`);
          event("next-tick", "success", `完成 tick ${tick}`);
          stallTicks = consumed === beforeConsumed ? stallTicks + 1 : 0;
          if (lost && !reason)
            reason = "存在货损；demo 退款但不补运，需求仍未满足";
          return snapshot();
        },
        async close() {},
      },
    };
  },
};
