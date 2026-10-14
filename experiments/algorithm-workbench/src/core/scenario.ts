import {
  ADAPTER_VERSION,
  SCENARIO_VERSION,
  clone,
  type AdapterMetadata,
  type Scenario,
} from "./types";

const dependencies = {
  supply: "on-demand",
  transport: "instant",
  funding: "normal",
  path: "direct",
  resupply: "on-demand",
} as const;
export const economyScenario: Scenario = {
  schemaVersion: SCENARIO_VERSION,
  name: "市场循环 · 理想外部依赖",
  domain: "economy",
  adapterId: "demo.economy.v1",
  seed: 42,
  maxTicks: 60,
  boundary: "market-cycle",
  dependencies: { ...dependencies },
  params: {
    demand: 10,
    price: 12,
    buyerCash: 600,
    income: 0,
    stock: 60,
    capacity: 18,
    leadTicks: 3,
    lossRate: 0.08,
  },
  expectations: {
    rules: [
      {
        id: "consumption",
        label: "第 3 轮累计消费至少 30",
        target: "metric",
        key: "fulfilled",
        operator: "gte",
        value: 30,
        byTick: 3,
      },
      {
        id: "unmet",
        label: "第 3 轮未满足需求为 0",
        target: "metric",
        key: "unmet",
        operator: "eq",
        value: 0,
        byTick: 3,
      },
      {
        id: "continuation",
        label: "最多连续 2 轮无消费",
        target: "metric",
        key: "stallTicks",
        operator: "lte",
        value: 2,
        byTick: "always",
      },
      ...["goods", "funds", "orders"].map((key) => ({
        id: key,
        label: `${key} 守恒残差始终为 0`,
        target: "invariant" as const,
        key,
        operator: "eq" as const,
        value: 0,
        byTick: "always" as const,
      })),
    ],
    observation:
      "固定挂牌价 demo：不判断价格收敛。当前 WWO 市场行为未定义、未验证。",
  },
};
export const militaryScenario: Scenario = {
  schemaVersion: SCENARIO_VERSION,
  name: "移动任务 · 理想补给与路径",
  domain: "military",
  adapterId: "demo.military.v1",
  seed: 42,
  maxTicks: 30,
  boundary: "movement",
  dependencies: { ...dependencies },
  params: {
    speed: 1,
    distance: 10,
    personnel: 12,
    targetPersonnel: 8,
    ammo: 24,
    hitChance: 0.65,
    fireRate: 2,
  },
  displayFrame: {
    crs: "EPSG:2154",
    origin: [650000, 6150000],
    cellM: 5000,
    label: "原创 demo 显示映射：x/y 为5km格坐标；地形未进入算法",
  },
  expectations: {
    rules: [
      {
        id: "arrival",
        label: "10 ticks 内位置达到 10",
        target: "metric",
        key: "position",
        operator: "eq",
        value: 10,
        byTick: 10,
      },
      {
        id: "unit-arrival",
        label: "蓝方实体到达 x=10",
        target: "entity",
        subjectId: "blue",
        key: "x",
        operator: "eq",
        value: 10,
        byTick: 10,
      },
      {
        id: "personnel",
        label: "人员守恒残差始终为 0",
        target: "invariant",
        key: "personnel",
        operator: "eq",
        value: 0,
        byTick: "always",
      },
      {
        id: "ammo",
        label: "弹药守恒残差始终为 0",
        target: "invariant",
        key: "ammo",
        operator: "eq",
        value: 0,
        byTick: "always",
      },
    ],
    observation: "移动任务不要求获胜；交火结果由游戏模拟函数计算，不保证命中。",
  },
};
const integer = (key: string, label: string, min: number, max: number) => ({
  key,
  label,
  min,
  max,
  step: 1,
});
export const economyMetadata: AdapterMetadata = {
  protocolVersion: ADAPTER_VERSION,
  id: "demo.economy.v1",
  name: "Demo · posted-price allocation",
  domain: "economy",
  kind: "demo",
  version: "1.0.0",
  sourceRef: "original synthetic demo; no WWO source",
  parameters: [
    integer("demand", "每轮需求", 0, 500),
    integer("price", "固定挂牌价", 1, 1000),
    integer("buyerCash", "初始买方资金", 0, 1000000),
    integer("income", "每轮外部资金注入", 0, 100000),
    integer("stock", "初始供应库存", 0, 100000),
    integer("capacity", "每轮运输容量", 0, 10000),
    integer("leadTicks", "运输时延", 1, 100),
    { key: "lossRate", label: "运输损耗率", min: 0, max: 1, step: 0.01 },
  ],
  boundaries: [
    {
      id: "market-cycle",
      label: "需求 → 分配 → 结算 → 消费",
      internal:
        "需求生成、FIFO 匹配、挂牌价分配、资金结算、消费与再循环。没有价格发现机制。",
      external: "供应侧按需补货；运输即时无限容量；资金不足时按需注入。",
    },
    {
      id: "inventory",
      label: "库存与有限供应",
      internal: "库存扣减、订单分配与守恒。供应有限，不能补满被测库存。",
      external: "运输与非库存系统保持理想条件。",
    },
    {
      id: "transport",
      label: "运输容量 / 时延 / 损耗",
      internal: "有限容量、运输时延、逐单位损耗与退款。保持实际运输执行。",
      external: "供应侧按需补货；其他系统保持正常。",
    },
  ],
  defaultScenario: economyScenario,
};
export const militaryMetadata: AdapterMetadata = {
  protocolVersion: ADAPTER_VERSION,
  id: "demo.military.v1",
  name: "Demo · abstract game task",
  domain: "military",
  kind: "demo",
  version: "1.1.0",
  sourceRef: "original synthetic demo; no WWO source",
  parameters: [
    integer("distance", "目标距离", 1, 20),
    { key: "speed", label: "移动速度 / tick", min: 0, max: 5, step: 0.25 },
    integer("personnel", "蓝方人数", 1, 100),
    integer("targetPersonnel", "橙方人数", 1, 100),
    integer("ammo", "初始弹药", 0, 10000),
    { key: "hitChance", label: "每发命中概率", min: 0, max: 1, step: 0.05 },
    integer("fireRate", "每轮射击数量", 0, 20),
  ],
  boundaries: [
    {
      id: "movement",
      label: "移动至目标位置",
      internal:
        "速度与位置推进。完成条件：蓝方到达目标；位置不能被外部替身直接设置。",
      external: "提供可通行路径；补给按需提供；没有交火。",
    },
    {
      id: "engagement",
      label: "抽象交火任务",
      internal: "移动、随机命中、弹药扣减、伤亡与结果。没有保证获胜。",
      external: "路径可通行；弹药补给可按需提供，所有注入明确入账。",
    },
    {
      id: "ammunition",
      label: "有限弹药与交火",
      internal: "弹药库存、每发扣减、命中与伤亡。不能用补给替身解除弹药约束。",
      external: "路径与非弹药系统保持正常。",
    },
  ],
  defaultScenario: militaryScenario,
};
export const presets: Scenario[] = [
  economyScenario,
  {
    ...clone(economyScenario),
    name: "运输功能 · 容量 / 时延 / 损耗",
    boundary: "transport",
    dependencies: { ...dependencies, transport: "bounded" },
  },
  {
    ...clone(economyScenario),
    name: "无资金 · 阻塞原因实验",
    dependencies: { ...dependencies, funding: "finite" },
    params: { ...economyScenario.params, buyerCash: 0 },
  },
  {
    ...clone(economyScenario),
    name: "库存功能 · 有限供应",
    boundary: "inventory",
    dependencies: { ...dependencies, supply: "finite" },
  },
  militaryScenario,
  {
    ...clone(militaryScenario),
    name: "交火功能 · 固定种子",
    boundary: "engagement",
  },
  {
    ...clone(militaryScenario),
    name: "弹药功能 · 零弹药反例",
    boundary: "ammunition",
    dependencies: { ...dependencies, resupply: "finite" },
    params: { ...militaryScenario.params, ammo: 0 },
  },
  {
    ...clone(militaryScenario),
    name: "故意不符 · 零速度检查器验证",
    params: { ...militaryScenario.params, speed: 0 },
  },
];

export function assertFiniteJson(value: unknown): void {
  if (
    typeof value === "number" &&
    (!Number.isFinite(value) || Math.abs(value) > Number.MAX_SAFE_INTEGER)
  )
    throw new Error("JSON 必须仅包含安全范围内的有限数值");
  if (Array.isArray(value)) value.forEach(assertFiniteJson);
  else if (value && typeof value === "object")
    Object.values(value).forEach(assertFiniteJson);
}
export function validateScenario(
  value: unknown,
  metadata?: AdapterMetadata,
): Scenario {
  assertFiniteJson(value);
  const s = value as Scenario;
  if (!s || s.schemaVersion !== SCENARIO_VERSION)
    throw new Error("不支持的场景版本");
  if (
    !["economy", "military"].includes(s.domain) ||
    typeof s.adapterId !== "string" ||
    typeof s.name !== "string" ||
    s.name.length > 200
  )
    throw new Error("场景名称、分区或适配器无效");
  if (!Number.isInteger(s.seed) || s.seed < 0 || s.seed > 4294967295)
    throw new Error("种子须为 0–4294967295 整数");
  if (!Number.isInteger(s.maxTicks) || s.maxTicks < 1 || s.maxTicks > 1000)
    throw new Error("运行长度须为 1–1000 ticks");
  if (
    !s.dependencies ||
    !s.params ||
    typeof s.params !== "object" ||
    Array.isArray(s.params)
  )
    throw new Error("缺少依赖策略或参数");
  if (
    s.initialConditions !== undefined &&
    (!s.initialConditions ||
      typeof s.initialConditions !== "object" ||
      Array.isArray(s.initialConditions))
  )
    throw new Error("初始条件必须为 JSON 对象");
  if (
    !s.expectations ||
    !Array.isArray(s.expectations.rules) ||
    s.expectations.rules.length > 50 ||
    typeof s.expectations.observation !== "string"
  )
    throw new Error("缺少独立预期配置");
  const ruleIds = new Set<string>();
  for (const r of s.expectations.rules) {
    if (
      !r ||
      typeof r.id !== "string" ||
      ruleIds.has(r.id) ||
      typeof r.label !== "string" ||
      typeof r.key !== "string" ||
      ![
        "metric",
        "invariant",
        "entity",
        "order",
        "stage",
        "eventCount",
      ].includes(r.target) ||
      !["eq", "gte", "lte"].includes(r.operator) ||
      !["number", "string", "boolean"].includes(typeof r.value) ||
      (typeof r.value !== "number" && r.operator !== "eq") ||
      (["entity", "order"].includes(r.target) &&
        typeof r.subjectId !== "string") ||
      (r.byTick !== "always" &&
        (!Number.isInteger(r.byTick) || r.byTick < 0 || r.byTick > s.maxTicks))
    )
      throw new Error("预期规则无效或 deadline 超过运行长度");
    ruleIds.add(r.id);
  }
  if (
    s.displayFrame &&
    (s.displayFrame.crs !== "EPSG:2154" ||
      !Array.isArray(s.displayFrame.origin) ||
      s.displayFrame.origin.length !== 2 ||
      s.displayFrame.origin.some((x) => typeof x !== "number") ||
      typeof s.displayFrame.cellM !== "number" ||
      s.displayFrame.cellM <= 0 ||
      typeof s.displayFrame.label !== "string")
  )
    throw new Error("显示坐标声明无效");
  const options = {
    supply: ["on-demand", "finite"],
    transport: ["instant", "bounded"],
    funding: ["normal", "finite"],
    path: ["direct", "blocked"],
    resupply: ["on-demand", "finite"],
  };
  for (const [key, allowed] of Object.entries(options))
    if (!allowed.includes(s.dependencies[key as keyof typeof options]))
      throw new Error(`无效依赖策略 ${key}`);
  if (metadata) {
    if (metadata.id !== s.adapterId || metadata.domain !== s.domain)
      throw new Error("场景与适配器分区不一致");
    if (!metadata.boundaries.some((b) => b.id === s.boundary))
      throw new Error("适配器不支持此测试边界");
    for (const [key, value] of Object.entries(
      metadata.lockedDependencies ?? {},
    ))
      if (s.dependencies[key as keyof typeof s.dependencies] !== value)
        throw new Error(
          `真实目标依赖 ${key} 已锁定为源约束，不能用外部替身覆盖`,
        );
    for (const p of metadata.parameters) {
      const v = s.params[p.key];
      if (
        typeof v !== "number" ||
        !Number.isFinite(v) ||
        v < p.min ||
        v > p.max ||
        (p.step === 1 && !Number.isInteger(v))
      )
        throw new Error(`${p.label} 超出范围 ${p.min}–${p.max}`);
    }
  }
  if (s.boundary === "inventory" && s.dependencies.supply !== "finite")
    throw new Error("库存属于被测机制：供应必须有限");
  if (s.boundary === "transport" && s.dependencies.transport !== "bounded")
    throw new Error("运输属于被测机制：不能设置即时运输");
  if (s.boundary === "ammunition" && s.dependencies.resupply !== "finite")
    throw new Error("弹药属于被测机制：不能按需补给");
  return clone(s);
}
