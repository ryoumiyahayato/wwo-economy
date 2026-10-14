export const SCENARIO_VERSION = "wwo-sandbox/scenario/v1" as const;
export const RESULT_VERSION = "wwo-sandbox/result/v1" as const;
export const ADAPTER_VERSION = "wwo-sandbox/adapter/v1" as const;
export type Domain = "economy" | "military";
export type Status = "success" | "pending" | "blocked" | "not-implemented";
export type Dependencies = {
  supply: "on-demand" | "finite";
  transport: "instant" | "bounded";
  funding: "normal" | "finite";
  path: "direct" | "blocked";
  resupply: "on-demand" | "finite";
};
export interface Scenario {
  schemaVersion: typeof SCENARIO_VERSION;
  name: string;
  domain: Domain;
  adapterId: string;
  seed: number;
  maxTicks: number;
  boundary: string;
  dependencies: Dependencies;
  params: Record<string, number>;
  expectations: { rules: Expectation[]; observation: string };
  displayFrame?: {
    crs: "EPSG:2154";
    origin: [number, number];
    cellM: number;
    label: string;
  };
}
export interface Expectation {
  id: string;
  label: string;
  target: "metric" | "invariant" | "entity" | "order" | "stage" | "eventCount";
  subjectId?: string;
  key: string;
  operator: "eq" | "gte" | "lte";
  value: number | string | boolean;
  byTick: number | "always";
}
export interface Verdict {
  id: string;
  label: string;
  status: "pass" | "fail" | "pending" | "undefined";
  expected: string;
  actual: number | string | boolean | null;
  difference: number | null;
  detail: string;
  tick?: number;
  subjectId?: string;
}
export interface Parameter {
  key: string;
  label: string;
  min: number;
  max: number;
  step: number;
}
export interface Boundary {
  id: string;
  label: string;
  internal: string;
  external: string;
}
export interface AdapterMetadata {
  protocolVersion: typeof ADAPTER_VERSION;
  id: string;
  name: string;
  domain: Domain;
  kind: "demo" | "private";
  version: string;
  sourceRef: string;
  parameters: Parameter[];
  boundaries: Boundary[];
  defaultScenario: Scenario;
}
export interface Stage {
  id: string;
  label: string;
  status: Status;
  detail: string;
}
export interface Event {
  tick: number;
  stage: string;
  status: Status;
  message: string;
  entityId?: string;
  id?: string;
  causeId?: string;
}
export interface Entity {
  id: string;
  label: string;
  x: number;
  y: number;
  stock?: number;
  personnel?: number;
  ammo?: number;
  team?: string;
  state?: string;
  granularity?: "formation" | "squad" | "person";
}
export interface OrderView {
  id: string;
  quantity: number;
  pending: number;
  inTransit: number;
  delivered: number;
  lost: number;
  status: string;
}
export interface Snapshot {
  tick: number;
  metrics: Record<string, number>;
  stages: Stage[];
  events: Event[];
  entities: Entity[];
  orders: OrderView[];
  invariants: Record<string, number>;
  injections: Record<string, number>;
  completion: {
    status: "pending" | "pass" | "fail";
    condition: string;
    reason: string;
  };
  done: boolean;
  blockedReason: string;
}
export interface AdapterSession {
  step(): Promise<Snapshot | PendingStep>;
  close(): Promise<void>;
}
export interface PendingStep {
  kind: "pending";
  committedTick: number;
  reason: string;
}
export interface AlgorithmAdapter {
  metadata: AdapterMetadata;
  create(
    scenario: Scenario,
  ): Promise<{ session: AdapterSession; snapshot: Snapshot }>;
}
export interface Result {
  schemaVersion: typeof RESULT_VERSION;
  scenario: Scenario;
  adapter: AdapterMetadata;
  history: Snapshot[];
  outcome: Snapshot["completion"];
  verdicts: Verdict[];
}
export const clone = <T>(value: T): T => structuredClone(value);
