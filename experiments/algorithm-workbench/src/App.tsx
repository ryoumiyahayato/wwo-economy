import { useRef, useState } from "react";
import { useWorkbench, downloadJson } from "./useWorkbench";
import { ScenarioEditor } from "./components/ScenarioEditor";
import { RunView } from "./components/RunView";
import { ComparisonPanel } from "./components/ComparisonPanel";
import { ExperimentScene } from "./components/ExperimentScene";
import { evaluateExpectations } from "./core/expectations";
import { clone } from "./core/types";
import { economyScenario, militaryScenario } from "./core/scenario";

export default function App() {
  const w = useWorkbench(),
    fileRef = useRef<HTMLInputElement>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [toolsOpen, setToolsOpen] = useState(false);
  const result = w.currentResult();
  const verdicts = w.history.length
    ? evaluateExpectations(w.active, w.history)
    : [];
  const failed = verdicts.filter((v) => v.status === "fail").length,
    unknown = verdicts.filter((v) => v.status === "undefined").length,
    pending = verdicts.filter((v) => v.status === "pending").length;
  const resultLabel = result?.executionError
    ? "算法调用失败 · 结果未完成"
    : failed
      ? `${failed} 项与预期不符`
      : unknown
        ? "预期未定义 · 待判断"
        : pending
          ? "等待判定时点"
          : verdicts.length
            ? "符合已定义规则"
            : "尚未执行";
  const dirty = JSON.stringify(w.draft) !== JSON.stringify(w.active);
  return (
    <div className="app">
      <header>
        <h1>
          WWO <span>/</span> Algorithm Sandbox
        </h1>
        <nav aria-label="实验分区">
          {(["economy", "military"] as const).map((domain) => (
            <button
              key={domain}
              className={w.draft.domain === domain ? "selected" : ""}
              disabled={w.busy}
              onClick={() => {
                const next = clone(
                  w.adapters.find(
                    (a) =>
                      a.metadata.domain === domain &&
                      a.metadata.kind === "private" &&
                      !a.metadata.unavailableReason,
                  )?.metadata.defaultScenario ??
                    (domain === "economy" ? economyScenario : militaryScenario),
                );
                w.setDraft(next);
                void w.apply(next);
              }}
            >
              {domain === "economy" ? "经济" : "军事"}
            </button>
          ))}
        </nav>
        <span className="provenance">
          {w.activeMetadata?.kind === "private"
            ? "PRIVATE · 外部算法"
            : "DEMO · 原创合成场景"}
        </span>
        <div className="scene-drawer-controls">
          <button
            aria-controls="scene-settings"
            aria-expanded={settingsOpen}
            onClick={() => setSettingsOpen(!settingsOpen)}
          >
            场景设置
          </button>
          <button
            aria-controls="scene-tools"
            aria-expanded={toolsOpen}
            onClick={() => setToolsOpen(!toolsOpen)}
          >
            实验工具
          </button>
        </div>
      </header>
      <div
        className={`workspace scene-workspace ${settingsOpen ? "settings-open" : ""} ${toolsOpen ? "tools-open" : ""}`}
      >
        <div
          id="scene-settings"
          className="settings-drawer"
          hidden={!settingsOpen}
        >
          <ScenarioEditor
            draft={w.draft}
            metadata={w.metadata}
            adapters={w.adapters}
            busy={w.busy}
            onChange={w.setDraft}
            onApply={() => void w.apply()}
          />
        </div>
        <main>
          <section className="panel transport">
            <button disabled={w.busy} onClick={() => void w.connect()}>
              加载 / 刷新真实算法
            </button>
            <div className="playback">
              <button
                className="primary"
                aria-label={w.running ? "暂停" : "开始"}
                disabled={
                  !!w.imported ||
                  w.failed ||
                  !w.current ||
                  (!w.running && w.current.done) ||
                  (w.busy && !w.running)
                }
                onClick={w.toggle}
              >
                {w.running ? "Ⅱ 暂停" : "▷ 开始"}
              </button>
              <button
                disabled={
                  w.running ||
                  w.failed ||
                  w.busy ||
                  !!w.imported ||
                  !w.current ||
                  w.current.done
                }
                onClick={() => void w.step()}
              >
                单步
              </button>
              <button disabled={w.busy} onClick={() => void w.reset()}>
                重置
              </button>
            </div>
            <div className="run-status">
              <span className={`status ${w.running ? "success" : "pending"}`}>
                {w.imported
                  ? "导入结果 · 回放"
                  : w.failed
                    ? "调用失败 · 需重置"
                    : w.running
                      ? "运行中"
                      : w.current?.done
                        ? "已结束"
                        : "已暂停"}
              </span>
              <span className="mono" data-testid="tick-counter">
                Tick {String(w.current?.tick ?? 0).padStart(3, "0")} /{" "}
                {w.active.maxTicks}
              </span>
            </div>
          </section>
          {dirty && (
            <div className="draft-notice">
              条件或预期有未应用的编辑；当前结果仍属于上一份运行场景。
            </div>
          )}
          {w.pendingReason && (
            <div className="draft-notice" role="status">
              内核结算中 · 仍显示已提交 tick {w.current?.tick}：
              {w.pendingReason}
            </div>
          )}
          {w.error && (
            <div className="error" role="alert">
              {w.error}
              <button aria-label="关闭错误" onClick={() => w.setError("")}>
                ×
              </button>
            </div>
          )}
          {result?.executionError && (
            <div className="error" role="status">
              保留最后有效 tick {result.executionError.lastCommittedTick}：
              {result.executionError.message}
              。重置或修正条件后应用；保存结果会保留此调用错误。
            </div>
          )}
          {w.current ? (
            <>
              <ExperimentScene
                scenario={w.active}
                snapshot={w.current}
                history={w.history}
                replayTick={w.replayTick}
                onReplay={(tick) => {
                  w.pause();
                  w.setReplayTick(tick);
                }}
                metadata={w.activeMetadata}
                commands={result?.commands ?? []}
                onCommand={w.command}
                onStep={() => void w.step()}
                stepDisabled={
                  w.busy ||
                  w.running ||
                  w.failed ||
                  !!w.imported ||
                  w.replayTick !== null
                }
                disabled={
                  w.busy ||
                  w.running ||
                  w.failed ||
                  !!w.pendingReason ||
                  !!w.imported ||
                  w.replayTick !== null
                }
              />
              <details className="scene-diagnostics">
                <summary>状态、事件日志与独立预期 · {resultLabel}</summary>
                <RunView
                  scenario={w.active}
                  history={w.history}
                  current={w.current}
                  metadata={w.activeMetadata}
                  replayTick={w.replayTick}
                  onReplay={(tick) => {
                    w.pause();
                    w.setReplayTick(tick);
                  }}
                />
              </details>
            </>
          ) : (
            <section className="panel">正在创建实验会话…</section>
          )}
        </main>
        <aside id="scene-tools" className="right-rail" hidden={!toolsOpen}>
          <section className="panel scene-summary">
            <h2>当前源与观察</h2>
            <p className="small source-ref">
              {w.activeMetadata?.name} · {w.activeMetadata?.version}
            </p>
            {w.activeMetadata?.metrics?.map((m) => (
              <p key={m.key}>
                <span>{m.label}</span>
                <strong>{w.current?.metrics[m.key] ?? "未提供"}</strong>
              </p>
            ))}
            <p className="small">
              {w.pendingReason || w.current?.blockedReason || resultLabel}
            </p>
          </section>
          <details className="panel">
            <summary>对照与保存结果</summary>
            <ComparisonPanel
              scenario={w.draft}
              metadata={w.metadata}
              comparison={w.comparison}
              busy={w.busy}
              saved={w.saved}
              current={result}
              onCompare={(key, value) => void w.compare(key, value)}
              onSave={w.save}
            />
          </details>
          <details className="panel">
            <summary>固定输入再次复现</summary>
            <p className="small muted">
              重新调用同一适配器至当前结果时点，逐步比较全部快照；不会只播放存档冒充重算。
            </p>
            <button
              className="full"
              disabled={w.busy || !result}
              onClick={() => void w.reproduce()}
            >
              重新运行并比对历史
            </button>
            {w.reproduction && (
              <p
                className={`status ${w.reproduction.equal ? "pass" : "fail"}`}
                data-testid="reproduction-result"
              >
                {w.reproduction.equal ? "逐步一致" : "发现不一致"} ·{" "}
                {w.reproduction.ticks} ticks · {w.reproduction.adapterId}
              </p>
            )}
          </details>
          <details className="panel files">
            <summary>实验文件</summary>
            <button
              className="full"
              onClick={() => downloadJson("scenario.json", w.draft)}
            >
              导出场景 JSON
            </button>
            <button
              className="full"
              disabled={!result}
              onClick={() => result && downloadJson("result.json", result)}
            >
              导出结果 JSON
            </button>
            <button
              className="full"
              disabled={w.busy}
              onClick={() => fileRef.current?.click()}
            >
              导入场景 / 结果
            </button>
            <input
              ref={fileRef}
              className="visually-hidden"
              type="file"
              accept=".json,application/json"
              aria-label="导入 JSON 文件"
              onChange={(e) => {
                if (e.target.files?.[0]) void w.importFile(e.target.files[0]);
                e.target.value = "";
              }}
            />
            <p className="small muted">
              结果包含算法版本、固定种子、独立预期、全部状态与事件。私有结果请留在私有路径。
            </p>
          </details>
          <details className="panel adapter-info">
            <summary>适配器来源与边界</summary>
            <p className="mono">{w.activeMetadata?.id ?? w.active.adapterId}</p>
            <p className="small">版本 {w.activeMetadata?.version ?? "未知"}</p>
            <p className="small muted source-ref">
              {w.activeMetadata?.sourceRef}
            </p>
            <div className="notice">
              {w.activeMetadata?.kind === "private"
                ? "真实外部算法通过桥接调用；以列示版本和 sourceRef 为准。"
                : "公开 demo 验证实验台与检查器。当前 WWO 算法的功能和市场行为尚未验证。"}
            </div>
            <button
              className="full"
              disabled={w.busy}
              onClick={() => void w.connect()}
            >
              连接本地私有适配器
            </button>
            <p className="small muted">{w.bridge} · 接口 v1</p>
          </details>
          <details className="panel matrix">
            <summary>外部依赖与假设</summary>
            <p className="small">
              <strong>用户指定：</strong>
              测试边界外的库存供应、运输和其他依赖先理想化。
            </p>
            <p className="small">
              <strong>设计假设：</strong>
              资金、路径与补给按需正常；注入、许可和时钟必须可观测。
            </p>
            <p className="small">
              <strong>待对应版本接入：</strong>
              正式接口、阶段职责和可安全替换的服务。未知项不会默认通过。
            </p>
            <p className="small muted">
              在测试边界内的库存、运输或弹药约束不能被外部策略短路。详细通用矩阵见
              README。
            </p>
          </details>
        </aside>
      </div>
      <footer>
        <span
          className={`status ${result?.executionError || failed ? "fail" : unknown ? "undefined" : pending ? "pending" : "pass"}`}
        >
          {resultLabel}
        </span>
        <span>
          {w.activeMetadata?.kind === "private"
            ? "外部源固定版本实验"
            : "Demo 判定仅适用于声明的合成实验"}{" "}
          · seed {w.active.seed}
        </span>
      </footer>
    </div>
  );
}
