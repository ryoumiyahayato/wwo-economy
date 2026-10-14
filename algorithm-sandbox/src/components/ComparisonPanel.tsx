import { useEffect, useState } from "react";
import {
  type AdapterMetadata,
  type Result,
  type Scenario,
} from "../core/types";
import { type Comparison, downloadJson } from "../useWorkbench";
import { dependencyOptions } from "./ScenarioEditor";

export function ComparisonPanel({
  scenario,
  metadata,
  comparison,
  busy,
  saved,
  current,
  onCompare,
  onSave,
}: {
  scenario: Scenario;
  metadata?: AdapterMetadata;
  comparison: Comparison | null;
  busy: boolean;
  saved: Result[];
  current?: Result;
  onCompare: (key: string, value: string) => void;
  onSave: () => void;
}) {
  const defaultField =
    scenario.domain === "economy"
      ? "dependencies.funding"
      : "dependencies.path";
  const [field, setField] = useState(defaultField),
    [value, setValue] = useState("finite");
  useEffect(() => {
    setField(defaultField);
    setValue(scenario.domain === "economy" ? "finite" : "blocked");
  }, [scenario.domain, scenario.adapterId]);
  const externalKeys =
    scenario.domain === "economy"
      ? ["supply", "transport", "funding"]
      : ["path", "resupply"];
  const currentValue = field.startsWith("dependencies.")
    ? scenario.dependencies[
        field.split(".")[1] as keyof Scenario["dependencies"]
      ]
    : scenario.params[field];
  const pairs = field.startsWith("dependencies.")
    ? dependencyOptions[field.split(".")[1] as keyof typeof dependencyOptions]
    : null;
  const keys =
    scenario.domain === "economy"
      ? ["fulfilled", "unmet", "buyerCash", "inTransit", "lost"]
      : ["position", "ammo", "casualties", "enemyCasualties"];
  const a = comparison?.a.history.at(-1),
    b = comparison?.b.history.at(-1);
  return (
    <section className="panel compare">
      <h2>单变量对照</h2>
      <p className="small muted">
        A / B 使用相同场景、种子与独立预期，只改变下面一个条件。
      </p>
      <label>
        唯一变化
        <select
          aria-label="对照变量"
          value={field}
          onChange={(e) => {
            const next = e.target.value;
            setField(next);
            setValue(
              next.startsWith("dependencies.")
                ? dependencyOptions[
                    next.split(".")[1] as keyof typeof dependencyOptions
                  ][1][0]
                : String(scenario.params[next]),
            );
          }}
        >
          {externalKeys.map((k) => (
            <option key={k} value={`dependencies.${k}`}>
              外部 · {k}
            </option>
          ))}
          {metadata?.parameters.map((p) => (
            <option key={p.key} value={p.key}>
              参数 · {p.label}
            </option>
          ))}
        </select>
      </label>
      <div className="input-pair">
        <label>
          A · 当前
          <input readOnly value={String(currentValue)} />
        </label>
        <label>
          B · 对照
          {pairs ? (
            <select
              aria-label="对照值 B"
              value={value}
              onChange={(e) => setValue(e.target.value)}
            >
              {pairs.map(([v, l]) => (
                <option value={v} key={v}>
                  {l}
                </option>
              ))}
            </select>
          ) : (
            <input
              aria-label="对照值 B"
              type="number"
              value={value}
              step={
                metadata?.parameters.find((p) => p.key === field)?.step ?? 1
              }
              onChange={(e) => setValue(e.target.value)}
            />
          )}
        </label>
      </div>
      <button
        className="primary full"
        disabled={busy}
        onClick={() => onCompare(field, value)}
      >
        {busy ? "执行中…" : "运行 A / B 对照"}
      </button>
      {comparison && a && b ? (
        <>
          <p className="small mono">
            {comparison.variable} → {comparison.value}
          </p>
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>实际指标</th>
                  <th>A</th>
                  <th>B</th>
                  <th>Δ</th>
                </tr>
              </thead>
              <tbody>
                {keys
                  .filter(
                    (k) =>
                      a.metrics[k] !== undefined || b.metrics[k] !== undefined,
                  )
                  .map((k) => (
                    <tr key={k}>
                      <td>{k}</td>
                      <td>{a.metrics[k]}</td>
                      <td>{b.metrics[k]}</td>
                      <td>{(b.metrics[k] ?? 0) - (a.metrics[k] ?? 0)}</td>
                    </tr>
                  ))}
                <tr>
                  <td>预期不符数</td>
                  <td>
                    {
                      comparison.a.verdicts.filter((v) => v.status === "fail")
                        .length
                    }
                  </td>
                  <td>
                    {
                      comparison.b.verdicts.filter((v) => v.status === "fail")
                        .length
                    }
                  </td>
                  <td>—</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p className="small muted">
            A tick {a.tick} / B tick {b.tick}；终止原因保留在完整结果中。
          </p>
          <button
            className="full"
            onClick={() =>
              downloadJson("comparison.json", {
                schemaVersion: "wwo-sandbox/comparison/v1",
                ...comparison,
              })
            }
          >
            导出完整对照
          </button>
        </>
      ) : (
        <p className="empty small">尚未运行对照。</p>
      )}
      <div className="separator" />
      <h3>保存的结果（会话内）</h3>
      <button className="full" disabled={!current || busy} onClick={onSave}>
        保存当前结果
      </button>
      {saved.map((r, i) => (
        <div className="saved" key={i}>
          <span>
            {r.scenario.name}
            <small>
              seed {r.scenario.seed} · tick {r.history.at(-1)?.tick}
            </small>
          </span>
          <button onClick={() => downloadJson(`saved-run-${i + 1}.json`, r)}>
            导出
          </button>
        </div>
      ))}
    </section>
  );
}
