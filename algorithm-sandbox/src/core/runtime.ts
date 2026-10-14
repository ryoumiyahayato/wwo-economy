import {
  ADAPTER_VERSION,
  RESULT_VERSION,
  clone,
  type AlgorithmAdapter,
  type AdapterSession,
  type Result,
  type Scenario,
  type Snapshot,
} from "./types";
import { assertFiniteJson, validateScenario } from "./scenario";
import { evaluateExpectations } from "./expectations";

export function validateSnapshot(value: unknown): Snapshot {
  assertFiniteJson(value);
  const s = value as Snapshot;
  if (
    !s ||
    !Number.isInteger(s.tick) ||
    s.tick < 0 ||
    !s.metrics ||
    !Array.isArray(s.stages) ||
    !Array.isArray(s.events) ||
    !Array.isArray(s.entities) ||
    !Array.isArray(s.orders) ||
    !s.invariants ||
    !s.injections ||
    typeof s.done !== "boolean" ||
    typeof s.blockedReason !== "string" ||
    !["pending", "pass", "fail"].includes(s.completion?.status)
  )
    throw new Error("适配器返回了无效 snapshot");
  for (const group of [s.metrics, s.invariants, s.injections])
    if (Object.values(group).some((v) => typeof v !== "number"))
      throw new Error("指标必须为有限数值");
  const statuses = ["success", "pending", "blocked", "not-implemented"];
  if (
    s.stages.some(
      (x) =>
        !x ||
        typeof x.id !== "string" ||
        typeof x.label !== "string" ||
        typeof x.detail !== "string" ||
        !statuses.includes(x.status),
    )
  )
    throw new Error("阶段记录无效");
  if (
    s.events.some(
      (x) =>
        !x ||
        !Number.isInteger(x.tick) ||
        typeof x.stage !== "string" ||
        typeof x.message !== "string" ||
        !statuses.includes(x.status) ||
        (x.entityId !== undefined && typeof x.entityId !== "string"),
    )
  )
    throw new Error("事件记录无效");
  if (
    s.entities.some(
      (x) =>
        !x ||
        typeof x.id !== "string" ||
        typeof x.label !== "string" ||
        typeof x.x !== "number" ||
        typeof x.y !== "number",
    )
  )
    throw new Error("实体记录无效");
  if (
    s.orders.some(
      (x) =>
        !x ||
        typeof x.id !== "string" ||
        typeof x.status !== "string" ||
        ["quantity", "pending", "inTransit", "delivered", "lost"].some(
          (k) => typeof x[k as keyof typeof x] !== "number",
        ),
    )
  )
    throw new Error("订单记录无效");
  if (
    typeof s.completion.condition !== "string" ||
    typeof s.completion.reason !== "string"
  )
    throw new Error("完成条件无效");
  return clone(s);
}
export class Run {
  private constructor(
    public adapter: AlgorithmAdapter,
    public scenario: Scenario,
    private session: AdapterSession,
    public history: Snapshot[],
  ) {}
  private busy = false;
  static async create(adapter: AlgorithmAdapter, input: Scenario) {
    if (adapter.metadata.protocolVersion !== ADAPTER_VERSION)
      throw new Error("适配器协议版本不兼容");
    const scenario = validateScenario(input, adapter.metadata);
    const { session, snapshot } = await adapter.create(scenario);
    try {
      const first = validateSnapshot(snapshot);
      if (first.tick !== 0) throw new Error("初始 tick 必须为 0");
      return new Run(adapter, scenario, session, [first]);
    } catch (e) {
      await session.close();
      throw e;
    }
  }
  get current() {
    return this.history[this.history.length - 1];
  }
  async step() {
    if (this.busy) throw new Error("上一个步骤尚未完成");
    if (this.current.done || this.current.tick >= this.scenario.maxTicks)
      return this.current;
    this.busy = true;
    try {
      const next = validateSnapshot(await this.session.step());
      if (next.tick !== this.current.tick + 1)
        throw new Error("适配器必须每次单步推进恰好 1 tick");
      this.history.push(next);
      return next;
    } finally {
      this.busy = false;
    }
  }
  async reset() {
    if (this.busy) throw new Error("步骤正在执行");
    await this.session.close();
    const fresh = await Run.create(this.adapter, this.scenario);
    this.session = fresh.session;
    this.history = fresh.history;
    return this.current;
  }
  async close() {
    await this.session.close();
  }
  result(): Result {
    return clone({
      schemaVersion: RESULT_VERSION,
      scenario: this.scenario,
      adapter: this.adapter.metadata,
      history: this.history,
      outcome: this.current.completion,
      verdicts: evaluateExpectations(this.scenario, this.history),
    });
  }
}
export async function runToEnd(adapter: AlgorithmAdapter, scenario: Scenario) {
  const run = await Run.create(adapter, scenario);
  try {
    while (!run.current.done && run.current.tick < scenario.maxTicks)
      await run.step();
    return run.result();
  } finally {
    await run.close();
  }
}
export function parseResult(value: unknown): Result {
  assertFiniteJson(value);
  const r = value as Result;
  if (
    !r ||
    r.schemaVersion !== RESULT_VERSION ||
    r.adapter?.protocolVersion !== ADAPTER_VERSION ||
    !Array.isArray(r.history) ||
    r.history.length < 1 ||
    r.history.length > 1001
  )
    throw new Error("不支持或无效的结果版本");
  validateScenario(r.scenario, r.adapter);
  if (r.adapter.id !== r.scenario.adapterId)
    throw new Error("结果来源与场景不匹配");
  r.history.forEach((s, i) => {
    validateSnapshot(s);
    if (s.tick !== i || s.tick > r.scenario.maxTicks)
      throw new Error("结果历史不连续或超过场景运行长度");
  });
  if (
    JSON.stringify(r.outcome) !== JSON.stringify(r.history.at(-1)!.completion)
  )
    throw new Error("结果结论与最后状态不一致");
  return clone({ ...r, verdicts: evaluateExpectations(r.scenario, r.history) });
}
export function stateDifferences(
  before: Snapshot | undefined,
  after: Snapshot,
) {
  if (!before) return [];
  return Object.entries(after.metrics)
    .filter(([k, v]) => v !== before.metrics[k])
    .map(([key, to]) => ({ key, from: before.metrics[key] ?? 0, to }));
}
