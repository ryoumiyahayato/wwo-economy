import { useEffect, useState } from "react";
import {
  clone,
  type AdapterMetadata,
  type AlgorithmAdapter,
  type Scenario,
} from "../core/types";
import { presets } from "../core/scenario";

const labels = {
  supply: "供应侧库存",
  transport: "外部运输",
  funding: "买方资金",
  path: "路径服务",
  resupply: "弹药补给",
};
const choices = {
  supply: [
    ["on-demand", "按需供应（理想）"],
    ["finite", "有限库存"],
  ],
  transport: [
    ["instant", "即时 / 无限容量"],
    ["bounded", "有限容量 / 时延"],
  ],
  funding: [
    ["normal", "按需资金（理想）"],
    ["finite", "有限资金"],
  ],
  path: [
    ["direct", "通行路径（理想）"],
    ["blocked", "路径阻断"],
  ],
  resupply: [
    ["on-demand", "按需补给（理想）"],
    ["finite", "有限弹药"],
  ],
};
export const dependencyOptions = choices;
export function ScenarioEditor({
  draft,
  metadata,
  adapters,
  busy,
  onChange,
  onApply,
}: {
  draft: Scenario;
  metadata?: AdapterMetadata;
  adapters: AlgorithmAdapter[];
  busy: boolean;
  onChange: (s: Scenario) => void;
  onApply: () => void;
}) {
  const [json, setJson] = useState(""),
    [expectationText, setExpectationText] = useState(""),
    [initialText, setInitialText] = useState(""),
    [localError, setLocalError] = useState("");
  useEffect(() => {
    setJson("");
    setExpectationText("");
    setInitialText("");
    setLocalError("");
  }, [draft.adapterId, draft.name]);
  const boundary = metadata?.boundaries.find((b) => b.id === draft.boundary);
  const templates =
    metadata?.scenarios ??
    presets.filter((p) => p.adapterId === draft.adapterId);
  function setBoundary(id: string) {
    const s = clone(draft);
    s.boundary = id;
    if (id === "inventory") s.dependencies.supply = "finite";
    if (id === "transport") s.dependencies.transport = "bounded";
    if (id === "ammunition") s.dependencies.resupply = "finite";
    onChange(s);
  }
  const fields =
    draft.domain === "economy"
      ? ["supply", "transport", "funding"]
      : ["path", "resupply"];
  return (
    <aside className="left-rail">
      <section className="panel editor">
        <h2>实验条件</h2>
        <label>
          实验模板
          <select
            aria-label="实验模板"
            value={templates.findIndex((p) => p.name === draft.name)}
            onChange={(e) => {
              const p = templates[Number(e.target.value)];
              if (p) onChange(clone(p));
            }}
          >
            <option value={-1}>自定义 / 私有场景</option>
            {templates.map((p, i) => (
              <option value={i} key={p.name}>
                {p.domain === "economy" ? "经济" : "军事"} · {p.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          被测适配器
          <select
            aria-label="被测适配器"
            value={draft.adapterId}
            onChange={(e) => {
              const a = adapters.find((a) => a.metadata.id === e.target.value);
              if (a) onChange(clone(a.metadata.defaultScenario));
            }}
          >
            {adapters.map((a) => (
              <option value={a.metadata.id} key={a.metadata.id}>
                {a.metadata.kind === "demo" ? "DEMO" : "PRIVATE"} ·{" "}
                {a.metadata.id}
                {a.metadata.unavailableReason ? "（未就绪）" : ""}
              </option>
            ))}
            {!adapters.some((a) => a.metadata.id === draft.adapterId) && (
              <option>{draft.adapterId}</option>
            )}
          </select>
        </label>
        <div className="input-pair">
          {metadata?.unavailableReason && (
            <p role="alert" className="error">
              真实适配器未就绪：{metadata.unavailableReason}
            </p>
          )}
          <label>
            固定种子
            <input
              aria-label="固定种子"
              type="number"
              min={0}
              max={4294967295}
              value={draft.seed}
              onChange={(e) =>
                onChange({ ...draft, seed: Number(e.target.value) })
              }
            />
          </label>
          <label>
            最多 ticks
            <input
              aria-label="最多 ticks"
              type="number"
              min={1}
              max={1000}
              value={draft.maxTicks}
              onChange={(e) =>
                onChange({ ...draft, maxTicks: Number(e.target.value) })
              }
            />
          </label>
        </div>
        <div className="separator" />
        {metadata?.seedNote && (
          <p className="small muted">{metadata.seedNote}</p>
        )}
        <label>
          测试边界
          <select
            aria-label="测试边界"
            value={draft.boundary}
            onChange={(e) => setBoundary(e.target.value)}
          >
            {metadata?.boundaries.map((b) => (
              <option key={b.id} value={b.id}>
                {b.label}
              </option>
            ))}
          </select>
        </label>
        <p className="boundary-copy">
          <strong>算法计算</strong>
          {boundary?.internal ?? "该私有版本的边界尚未定义"}
        </p>
        <h3>外部依赖策略</h3>
        {fields.map((raw) => {
          const key = raw as keyof typeof choices;
          const locked =
            metadata?.lockedDependencies?.[key] !== undefined ||
            (draft.boundary === "inventory" && key === "supply") ||
            (draft.boundary === "transport" && key === "transport") ||
            (draft.boundary === "ammunition" && key === "resupply");
          return (
            <label key={key}>
              {labels[key]}
              {locked ? (
                <span className="subtle">属于被测机制，保持约束</span>
              ) : null}
              <select
                aria-label={labels[key]}
                disabled={locked}
                value={draft.dependencies[key]}
                onChange={(e) =>
                  onChange({
                    ...draft,
                    dependencies: {
                      ...draft.dependencies,
                      [key]: e.target.value,
                    },
                  })
                }
              >
                {choices[key].map(([value, label]) => (
                  <option value={value} key={value}>
                    {metadata?.lockedDependencies?.[key] !== undefined
                      ? `真实源约束 · ${value}`
                      : label}
                  </option>
                ))}
              </select>
            </label>
          );
        })}
        <p className="muted small">
          {metadata?.lockedDependencies
            ? "此真实闭环未注入理想替身；所有目标依赖保留源配置，协议标签不会启用 demo 逻辑。"
            : "“无限”按请求提供有限数量，记录注入；不会向余额或 JSON 写入 Infinity。"}
        </p>
        <div className="separator" />
        <h3>输入参数</h3>
        {metadata?.parameters.map((p) => (
          <label className="param-row" key={p.key}>
            {p.label}
            <input
              aria-label={p.label}
              type="number"
              min={p.min}
              max={p.max}
              step={p.step}
              value={draft.params[p.key] ?? ""}
              onChange={(e) =>
                onChange({
                  ...draft,
                  params: { ...draft.params, [p.key]: Number(e.target.value) },
                })
              }
            />
          </label>
        ))}
        {draft.initialConditions && (
          <details>
            <summary>初始条件（源输入）</summary>
            <textarea
              aria-label="初始条件 JSON"
              rows={8}
              value={
                initialText || JSON.stringify(draft.initialConditions, null, 2)
              }
              onChange={(e) => setInitialText(e.target.value)}
            />
            <button
              className="full"
              onClick={() => {
                try {
                  const initialConditions = JSON.parse(
                    initialText || JSON.stringify(draft.initialConditions),
                  );
                  if (
                    !initialConditions ||
                    typeof initialConditions !== "object" ||
                    Array.isArray(initialConditions)
                  )
                    throw new Error("初始条件必须为对象");
                  onChange({ ...draft, initialConditions });
                  setLocalError("");
                } catch (e) {
                  setLocalError(String(e));
                }
              }}
            >
              更新初始条件草稿
            </button>
            <p className="small muted">
              fixture
              为外部源码中的明确入口；修改后应用并重置。不会导入私有源码。
            </p>
          </details>
        )}
        <button className="primary full" disabled={busy} onClick={onApply}>
          应用条件并重置
        </button>
        <p className="small muted">编辑只改变草稿，点击应用后进入运行。</p>
      </section>
      <details className="panel">
        <summary onClick={() => setJson(JSON.stringify(draft, null, 2))}>
          场景 JSON
        </summary>
        <textarea
          aria-label="场景 JSON"
          value={json}
          onChange={(e) => setJson(e.target.value)}
          rows={16}
        />
        <button
          className="full"
          onClick={() => {
            try {
              onChange(JSON.parse(json));
              setLocalError("");
            } catch (e) {
              setLocalError(String(e));
            }
          }}
        >
          载入为草稿
        </button>
      </details>
      <details className="panel">
        <summary
          onClick={() =>
            setExpectationText(JSON.stringify(draft.expectations, null, 2))
          }
        >
          独立预期配置
        </summary>
        <p className="small muted">由实验作者定义。算法输出不会反写预期。</p>
        <textarea
          aria-label="独立预期 JSON"
          value={expectationText || JSON.stringify(draft.expectations, null, 2)}
          onChange={(e) => setExpectationText(e.target.value)}
          rows={9}
        />
        <button
          className="full"
          onClick={() => {
            try {
              onChange({
                ...draft,
                expectations: JSON.parse(
                  expectationText || JSON.stringify(draft.expectations),
                ),
              });
              setLocalError("");
            } catch (e) {
              setLocalError(String(e));
            }
          }}
        >
          更新预期草稿
        </button>
      </details>
      {localError && (
        <p role="alert" className="error">
          {localError}
        </p>
      )}
    </aside>
  );
}
