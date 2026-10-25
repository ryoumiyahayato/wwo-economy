import {
  type Scenario,
  type Snapshot,
  type Verdict,
  type Expectation,
  type Event,
} from "./types";
type Scalar = number | string | boolean;
export function readObservation(
  rule: Expectation,
  snapshot: Snapshot,
  history: Snapshot[],
): Scalar | undefined {
  let value: unknown;
  if (rule.target === "metric") value = snapshot.metrics[rule.key];
  else if (rule.target === "invariant") value = snapshot.invariants[rule.key];
  else if (rule.target === "entity")
    value = (
      snapshot.entities.find((e) => e.id === rule.subjectId) as unknown as
        | Record<string, unknown>
        | undefined
    )?.[rule.key];
  else if (rule.target === "order")
    value = (
      snapshot.orders.find((e) => e.id === rule.subjectId) as unknown as
        | Record<string, unknown>
        | undefined
    )?.[rule.key];
  else if (rule.target === "stage")
    value = snapshot.stages.find((s) => s.id === rule.key)?.status;
  else
    value = history
      .filter((s) => s.tick <= snapshot.tick)
      .flatMap((s) => s.events)
      .filter(
        (e) =>
          e.stage === rule.key &&
          (!rule.subjectId || e.entityId === rule.subjectId),
      ).length;
  return ["number", "string", "boolean"].includes(typeof value)
    ? (value as Scalar)
    : undefined;
}
/** Rules remain experiment inputs. No expected value is inferred from adapter output. */
export function evaluateExpectations(
  scenario: Scenario,
  history: Snapshot[],
): Verdict[] {
  const last = history.at(-1)!;
  if (!scenario.expectations.rules.length)
    return [
      {
        id: "undefined",
        label: "自动预期未定义",
        status: "undefined",
        expected: "待用户定义",
        actual: null,
        difference: null,
        detail: "没有独立判定规则，不能默认通过",
      },
    ];
  return scenario.expectations.rules.map((rule) => {
    const compare = (v: Scalar) =>
      rule.operator === "eq"
        ? typeof v === "number" && typeof rule.value === "number"
          ? Math.abs(v - rule.value) < 1e-8
          : v === rule.value
        : typeof v === "number" &&
          typeof rule.value === "number" &&
          (rule.operator === "gte" ? v >= rule.value : v <= rule.value);
    const samples =
      rule.byTick === "always"
        ? history
        : [history.find((s) => s.tick === rule.byTick) ?? last];
    const unknown = samples.find(
      (s) => readObservation(rule, s, history) === undefined,
    );
    const failed = samples.find((s) => {
      const v = readObservation(rule, s, history);
      return v !== undefined && !compare(v);
    });
    const due =
      rule.byTick === "always" || last.tick >= rule.byTick || last.done;
    const status = !due
      ? "pending"
      : failed
        ? "fail"
        : unknown
          ? "undefined"
          : "pass";
    const sample =
      rule.byTick === "always" && failed
        ? failed
        : (unknown ?? samples.at(-1)!);
    const actual = readObservation(rule, sample, history) ?? null;
    return {
      id: rule.id,
      label: rule.label,
      status,
      tick: sample.tick,
      ...(rule.subjectId ? { subjectId: rule.subjectId } : {}),
      expected: `${rule.subjectId ? rule.subjectId + "." : ""}${rule.key} ${rule.operator === "eq" ? "=" : rule.operator === "gte" ? "≥" : "≤"} ${String(rule.value)} · ${rule.byTick === "always" ? "每一步" : `tick ${rule.byTick}`}`,
      actual,
      difference:
        typeof actual === "number" && typeof rule.value === "number"
          ? actual - rule.value
          : null,
      detail:
        status === "pending"
          ? "尚未到判定时点"
          : status === "undefined"
            ? "未提供对象或观测量；保持待判断"
            : status === "fail"
              ? `tick ${failed!.tick} 不符合独立预期`
              : "符合已定义规则；不是算法总体正确性的证明",
    };
  });
}
export function diagnoseVerdict(verdict: Verdict, history: Snapshot[]) {
  const tick = verdict.tick ?? history.at(-1)!.tick,
    snapshot = history.find((s) => s.tick === tick) ?? history.at(-1)!;
  const all = history.flatMap((s) => s.events),
    events = all.filter(
      (e) =>
        e.tick <= tick &&
        e.tick >= Math.max(0, tick - 3) &&
        (!verdict.subjectId || e.entityId === verdict.subjectId),
    );
  const ids = new Map(all.filter((e) => e.id).map((e) => [e.id!, e]));
  const seen = new Set(events.map((e) => e.id).filter(Boolean));
  const linked: Event[] = [...events];
  for (let i = 0; i < linked.length; i++) {
    const cause = linked[i].causeId;
    if (cause && !seen.has(cause) && ids.has(cause)) {
      seen.add(cause);
      linked.push(ids.get(cause)!);
    }
  }
  return {
    tick,
    snapshot,
    before: history.find((s) => s.tick === tick - 1),
    subject:
      snapshot.entities.find((e) => e.id === verdict.subjectId) ??
      snapshot.orders.find((e) => e.id === verdict.subjectId),
    events: linked.sort((a, b) => a.tick - b.tick),
    explicitCausalLinks: linked.some((e) => e.causeId),
  };
}
