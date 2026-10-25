export interface BattleEntity {
  id: string;
  label: string;
  kind: "unit" | "person";
  team: string;
  x: number;
  y: number;
  state: string;
  personnel?: number;
  ammo?: number;
  ammoSpent?: number;
  casualties?: number;
  health?: number;
  unitId?: string;
  heading?: number;
  headingBasis?: string;
  motionHeading?: number;
  movement?: { from: number[]; to: number[]; fromTick: number; toTick: number };
  weapon?: Record<string, any>;
  sourcePath: string;
  raw: Record<string, any>;
}
export interface BattleEvent {
  id: string;
  tick: number;
  kind: string;
  effectiveTime: number;
  actorId?: string;
  targetId?: string;
  causeIds: string[];
  raw: Record<string, any>;
}
export interface BattleFrame {
  schemaVersion: "wwo-battle/frame/v1";
  tick: number;
  time: number;
  view: string;
  sourceCommit: string;
  entities: BattleEntity[];
  events: BattleEvent[];
  dropped: number;
  unlocatedUnits: string[];
  nodes: Record<string, { xy: number[] }>;
  gaps: string[];
  scope: string;
  source: Record<string, any>;
}
export const eventLabel = (e: BattleEvent) =>
  ({
    personal_injury: "受伤",
    shared_fire_allocation: "火力分配",
    losses: "单位损失",
    personal_combat_intent: "本人战术意图",
    weapon_operation_finished: "武器操作完成",
    command_feedback: "命令回执",
    command_sent: "命令送达中",
    goal_state_changed: "行动状态",
    report_received: "收到报告",
    personal_observation_completed: "观察完成",
  })[e.kind] ?? e.kind;
export const fmt = (n: unknown, digits = 6) =>
  typeof n === "number"
    ? n.toLocaleString("en-US", { maximumFractionDigits: digits })
    : "未上报";
export function causalEvent(
  event: BattleEvent | undefined,
  events: BattleEvent[],
): BattleEvent | undefined {
  if (!event) return;
  if (event.kind === "shared_fire_allocation") return event;
  return events.find(
    (e) => event.causeIds.includes(e.id) && e.kind === "shared_fire_allocation",
  );
}
export function uniqueEvents(frames: BattleFrame[]): BattleEvent[] {
  const map = new Map<string, BattleEvent>();
  for (const f of frames) for (const e of f.events) map.set(e.id, e);
  return [...map.values()];
}
