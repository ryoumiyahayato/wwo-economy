import { type Scenario, type Snapshot, type Verdict } from "./types";
/** Expectations are supplied by the experiment author, never derived from adapter output. */
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
    const group = (s: Snapshot) =>
      rule.target === "metric" ? s.metrics : s.invariants;
    const compare = (v: number) =>
      rule.operator === "eq"
        ? Math.abs(v - rule.value) < 1e-8
        : rule.operator === "gte"
          ? v >= rule.value
          : v <= rule.value;
    const samples =
      rule.byTick === "always"
        ? history
        : [history.find((s) => s.tick === rule.byTick) ?? last];
    const unknown = samples.some((s) => typeof group(s)[rule.key] !== "number");
    const mismatch =
      !unknown && samples.some((s) => !compare(group(s)[rule.key]));
    const due =
      rule.byTick === "always" || last.tick >= rule.byTick || last.done;
    const status = unknown
      ? "undefined"
      : due
        ? mismatch
          ? "fail"
          : "pass"
        : "pending";
    const failedSample = samples.find(
      (s) =>
        typeof group(s)[rule.key] === "number" && !compare(group(s)[rule.key]),
    );
    const actual = unknown
      ? null
      : group(
          rule.byTick === "always" && failedSample
            ? failedSample
            : samples.at(-1)!,
        )[rule.key];
    return {
      id: rule.id,
      label: rule.label,
      status,
      expected: `${rule.key} ${rule.operator === "eq" ? "=" : rule.operator === "gte" ? "≥" : "≤"} ${rule.value} · ${rule.byTick === "always" ? "每一步" : `tick ${rule.byTick}`}`,
      actual,
      difference: actual === null ? null : actual - rule.value,
      detail: unknown
        ? "适配器没有提供此观测量"
        : status === "pending"
          ? "尚未到判定时点"
          : status === "fail"
            ? `tick ${failedSample!.tick} 不符合独立预期`
            : "符合已定义规则；不是算法总体正确性的证明",
    };
  });
}
