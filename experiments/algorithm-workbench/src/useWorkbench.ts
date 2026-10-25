import { useEffect, useRef, useState } from "react";
import { economyAdapter } from "./adapters/economy";
import { militaryAdapter } from "./adapters/military";
import { discoverBridge } from "./adapters/bridge";
import { Run, parseResult, runToEnd } from "./core/runtime";
import {
  clone,
  RESULT_VERSION,
  type AlgorithmAdapter,
  type Result,
  type Scenario,
  type Snapshot,
} from "./core/types";
import { economyScenario, validateScenario } from "./core/scenario";

export const demoAdapters = [economyAdapter, militaryAdapter];
export interface Comparison {
  a: Result;
  b: Result;
  variable: string;
  value: string;
}
export function downloadJson(name: string, value: unknown) {
  const url = URL.createObjectURL(
    new Blob([JSON.stringify(value, null, 2)], { type: "application/json" }),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
export function useWorkbench() {
  const [adapters, setAdapters] = useState<AlgorithmAdapter[]>(demoAdapters);
  const [draft, setDraft] = useState<Scenario>(() => clone(economyScenario));
  const [active, setActive] = useState<Scenario>(() => clone(economyScenario));
  const [history, setHistory] = useState<Snapshot[]>([]);
  const [running, setRunning] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const [bridge, setBridge] = useState("未连接"),
    [imported, setImported] = useState<Result | null>(null),
    [comparison, setComparison] = useState<Comparison | null>(null);
  const [saved, setSaved] = useState<Result[]>([]),
    [replayTick, setReplayTick] = useState<number | null>(null);
  const [reproduction, setReproduction] = useState<{
    equal: boolean;
    ticks: number;
    adapterId: string;
  } | null>(null);
  const runRef = useRef<Run | null>(null),
    busyRef = useRef(false),
    requestRef = useRef(0),
    runningRef = useRef(false);
  const metadata =
    adapters.find((a) => a.metadata.id === draft.adapterId)?.metadata ??
    imported?.adapter;
  const activeMetadata =
    adapters.find((a) => a.metadata.id === active.adapterId)?.metadata ??
    imported?.adapter;
  function stop() {
    runningRef.current = false;
    setRunning(false);
  }
  async function apply(scenario = draft) {
    stop();
    if (busyRef.current) return;
    setReproduction(null);
    const request = ++requestRef.current;
    setError("");
    setBusy(true);
    busyRef.current = true;
    try {
      const adapter = adapters.find(
        (a) => a.metadata.id === scenario.adapterId,
      );
      if (!adapter)
        throw new Error(
          "此算法尚未接入。请先连接本地适配器；不会自动替换成 demo。",
        );
      const checked = validateScenario(scenario, adapter.metadata);
      const next = await Run.create(adapter, checked);
      if (request !== requestRef.current) {
        await next.close();
        return;
      }
      if (runRef.current) await runRef.current.close();
      runRef.current = next;
      setActive(checked);
      setDraft(clone(checked));
      setHistory([...next.history]);
      setImported(null);
      setReplayTick(null);
      setComparison(null);
    } catch (e) {
      setError(String(e instanceof Error ? e.message : e));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  useEffect(() => {
    void apply(economyScenario);
    return () => {
      requestRef.current++;
      runningRef.current = false;
      void runRef.current?.close();
    };
  }, []);
  async function step() {
    const run = runRef.current;
    if (!run || busyRef.current || imported) return;
    setReproduction(null);
    busyRef.current = true;
    setBusy(true);
    setError("");
    try {
      await run.step();
      setHistory([...run.history]);
      setReplayTick(null);
      if (run.current.done) stop();
    } catch (e) {
      stop();
      setError(String(e instanceof Error ? e.message : e));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  function toggle() {
    if (running) {
      stop();
      return;
    }
    if (!runRef.current || imported) return;
    runningRef.current = true;
    setRunning(true);
  }
  useEffect(() => {
    if (!running) return;
    const timer = setInterval(() => {
      if (runningRef.current && !busyRef.current) void step();
    }, 350);
    return () => clearInterval(timer);
  }, [running, imported]);
  async function reset() {
    stop();
    if (busyRef.current) return;
    setReproduction(null);
    if (imported) {
      await apply(active);
      return;
    }
    busyRef.current = true;
    setBusy(true);
    try {
      await runRef.current?.reset();
      setHistory([...(runRef.current?.history ?? [])]);
      setReplayTick(null);
      setError("");
    } catch (e) {
      setError(String(e instanceof Error ? e.message : e));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  async function command(request: import("./core/types").CommandRequest) {
    stop();
    const run = runRef.current;
    if (!run || busyRef.current || imported) return;
    busyRef.current = true;
    setBusy(true);
    setError("");
    setReproduction(null);
    try {
      const receipt = await run.command(request);
      setHistory([...run.history]);
      setReplayTick(null);
      return receipt;
    } catch (e) {
      setHistory([...run.history]);
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  async function connect() {
    setError("");
    try {
      const local = await discoverBridge();
      setAdapters([...demoAdapters, ...local]);
      setBridge(`已连接 ${local.length} 个本地适配器`);
    } catch (e) {
      setBridge("本地桥接离线");
      setError(
        `本地桥接未连接：${e instanceof Error ? e.message : e}。公开 demo 可继续运行。`,
      );
    }
  }
  function currentResult(): Result | undefined {
    return imported ?? runRef.current?.result();
  }
  async function importFile(file: File) {
    stop();
    if (busyRef.current) {
      setError("请等待当前步骤完成后再导入");
      return;
    }
    try {
      setReproduction(null);
      if (file.size > 5_000_000) throw new Error("文件上限为 5 MB");
      const value = JSON.parse(await file.text());
      if (value.schemaVersion === RESULT_VERSION) {
        const result = parseResult(value);
        if (runRef.current) await runRef.current.close();
        runRef.current = null;
        setImported(result);
        setActive(result.scenario);
        setDraft(clone(result.scenario));
        setHistory(result.history);
        setReplayTick(null);
        setComparison(null);
      } else if (value.schemaVersion === "wwo-sandbox/comparison/v1") {
        const a = parseResult(value.a),
          b = parseResult(value.b);
        setComparison({
          a,
          b,
          variable: String(value.variable),
          value: String(value.value),
        });
      } else {
        const s = validateScenario(value);
        setDraft(s);
        await apply(s);
        return;
      }
      setError("");
    } catch (e) {
      setError(`导入失败：${e instanceof Error ? e.message : e}`);
    }
  }
  async function compare(variable: string, value: string) {
    stop();
    if (busyRef.current) return;
    setError("");
    setBusy(true);
    busyRef.current = true;
    try {
      const adapter = adapters.find((a) => a.metadata.id === draft.adapterId);
      if (!adapter) throw new Error("场景的适配器未接入");
      const a = validateScenario(draft, adapter.metadata),
        b = clone(a);
      if (variable.startsWith("dependencies."))
        b.dependencies[
          variable.split(".")[1] as keyof Scenario["dependencies"]
        ] = value as never;
      else b.params[variable] = Number(value);
      validateScenario(b, adapter.metadata);
      const aResult = await runToEnd(adapter, a),
        bResult = await runToEnd(adapter, b);
      setComparison({ a: aResult, b: bResult, variable, value });
    } catch (e) {
      setError(`对照失败：${e instanceof Error ? e.message : e}`);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  function save() {
    const result = currentResult();
    if (result) setSaved((old) => [...old.slice(-5), result]);
  }
  const current = history[replayTick ?? history.length - 1];
  const pendingReason = runRef.current?.pendingReason ?? "";
  async function reproduce() {
    stop();
    if (busyRef.current) return;
    setReproduction(null);
    const original = currentResult();
    if (!original) return;
    const adapter = adapters.find(
      (a) => a.metadata.id === original.scenario.adapterId,
    );
    if (!adapter) {
      setError("复现需要相同真实适配器；不会替换成demo");
      return;
    }
    if (
      adapter.metadata.version !== original.adapter.version ||
      adapter.metadata.sourceRef !== original.adapter.sourceRef
    ) {
      setError("复现来源版本与存档不一致。请加载原版本适配器后重试。");
      return;
    }
    busyRef.current = true;
    setBusy(true);
    setError("");
    try {
      const replay = await Run.create(adapter, original.scenario);
      try {
        let polls = 0;
        const replayed = new Set<number>();
        const replayCommands = async () => {
          for (const [index, c] of (original.commands ?? []).entries())
            if (c.atTick === replay.current.tick && !replayed.has(index)) {
              await replay.command(c.request);
              replayed.add(index);
            }
        };
        while (
          replay.current.tick < original.history.at(-1)!.tick &&
          !replay.current.done
        ) {
          if (!replay.pendingReason) await replayCommands();
          await replay.step();
          polls = replay.pendingReason ? polls + 1 : 0;
          if (polls >= 100) throw new Error("复现仍在PENDING，未作通过判断");
        }
        await replayCommands();
        if (original.executionError) {
          for (let i = 0; i < 100 && !replay.executionError; i++) {
            try {
              if (original.executionError.command)
                await replay.command(original.executionError.command);
              else await replay.step();
            } catch {
              if (!replay.executionError)
                throw new Error("失败调用未产生可记录错误");
            }
            if (replay.current.tick > original.history.at(-1)!.tick) break;
          }
          if (replay.pendingReason && !replay.executionError)
            throw new Error("失败调用复现仍在 PENDING，未作通过判断");
        }
        const regenerated = replay.result();
        const equal =
          JSON.stringify(regenerated.history) ===
            JSON.stringify(original.history) &&
          JSON.stringify(regenerated.executionError) ===
            JSON.stringify(original.executionError) &&
          JSON.stringify(regenerated.commands) ===
            JSON.stringify(original.commands);
        setReproduction({
          equal,
          ticks: regenerated.history.length - 1,
          adapterId: adapter.metadata.id,
        });
      } finally {
        await replay.close();
      }
    } catch (e) {
      setError(String(e instanceof Error ? e.message : e));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  return {
    adapters,
    draft,
    setDraft,
    active,
    metadata,
    activeMetadata,
    history,
    current,
    running,
    busy,
    error,
    setError,
    bridge,
    imported,
    comparison,
    saved,
    replayTick,
    setReplayTick,
    apply,
    step,
    toggle,
    reset,
    command,
    connect,
    importFile,
    compare,
    save,
    currentResult,
    pendingReason,
    failed: !!runRef.current?.executionError,
    reproduce,
    reproduction,
    pause: stop,
  };
}
