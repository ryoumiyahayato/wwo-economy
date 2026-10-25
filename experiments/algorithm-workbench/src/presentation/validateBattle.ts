import type { BattleFrame } from "./battle";
export function validateBattle(value: unknown): asserts value is BattleFrame {
  const f = value as BattleFrame;
  if (
    !f ||
    f.schemaVersion !== "wwo-battle/frame/v1" ||
    !Number.isInteger(f.tick) ||
    f.tick < 0 ||
    typeof f.time !== "number" ||
    f.view !== "DEBUG_TRUTH" ||
    !Array.isArray(f.entities) ||
    !Array.isArray(f.events) ||
    !Array.isArray(f.gaps) ||
    !Array.isArray(f.unlocatedUnits) ||
    typeof f.sourceCommit !== "string" ||
    !f.nodes ||
    !f.source ||
    typeof f.dropped !== "number"
  )
    throw new Error("无效战场观测帧");
  if (
    f.entities.some(
      (e) =>
        !e ||
        typeof e.id !== "string" ||
        !["unit", "person"].includes(e.kind) ||
        typeof e.team !== "string" ||
        typeof e.x !== "number" ||
        typeof e.y !== "number" ||
        typeof e.state !== "string" ||
        !e.raw ||
        typeof e.sourcePath !== "string",
    ) ||
    new Set(f.entities.map((e) => e.id)).size !== f.entities.length
  )
    throw new Error("无效战场实体");
  if (
    f.events.some(
      (e) =>
        !e ||
        typeof e.id !== "string" ||
        typeof e.kind !== "string" ||
        e.tick !== f.tick ||
        typeof e.effectiveTime !== "number" ||
        !Array.isArray(e.causeIds) ||
        e.causeIds.some((id) => typeof id !== "string") ||
        !e.raw ||
        e.raw.event_id !== e.id,
    ) ||
    new Set(f.events.map((e) => e.id)).size !== f.events.length
  )
    throw new Error("无效战场因果事件");
  if (
    Object.values(f.nodes).some(
      (n) =>
        !n ||
        !Array.isArray(n.xy) ||
        n.xy.length !== 2 ||
        n.xy.some((v) => typeof v !== "number"),
    )
  )
    throw new Error("无效战场坐标");
}
