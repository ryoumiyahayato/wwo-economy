import { type Snapshot } from "../core/types";

/** Missing measurements create gaps. A missing value is never a measured zero. */
export function metricSegments(history: Snapshot[], key: string) {
  const segments: { tick: number; value: number }[][] = [];
  let current: { tick: number; value: number }[] = [];
  for (const snapshot of history) {
    const value = snapshot.metrics[key];
    if (value === undefined) {
      if (current.length) segments.push(current);
      current = [];
    } else current.push({ tick: snapshot.tick, value });
  }
  if (current.length) segments.push(current);
  return segments;
}
