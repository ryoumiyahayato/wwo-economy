import {
  ADAPTER_VERSION,
  type AdapterMetadata,
  type AlgorithmAdapter,
  type Scenario,
  type Snapshot,
  type PendingStep,
} from "../core/types";
async function request<T>(path: string, body?: unknown): Promise<T> {
  const response = await fetch(`/api/v1/${path}`, {
    method: body ? "POST" : "GET",
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(20000),
  });
  const data = await response.json();
  if (!response.ok)
    throw new Error(data.error || `Bridge HTTP ${response.status}`);
  return data as T;
}
export async function discoverBridge(): Promise<AlgorithmAdapter[]> {
  const { adapters } = await request<{ adapters: AdapterMetadata[] }>(
    "adapters",
  );
  return adapters.map((metadata) => {
    if (metadata.protocolVersion !== ADAPTER_VERSION)
      throw new Error("本地适配器版本不兼容");
    return {
      metadata,
      async create(scenario: Scenario) {
        const data = await request<{ sessionId: string; snapshot: Snapshot }>(
          "sessions",
          { adapterId: metadata.id, scenario },
        );
        let tick = 0;
        return {
          snapshot: data.snapshot,
          session: {
            async step() {
              const next = await request<{
                snapshot?: Snapshot;
                pending?: PendingStep;
              }>(`sessions/${data.sessionId}/step`, { expectedTick: tick });
              if (next.pending) return next.pending;
              if (!next.snapshot)
                throw new Error("Bridge 返回缺少已提交 snapshot");
              tick = next.snapshot.tick;
              return next.snapshot;
            },
            async close() {
              await request(`sessions/${data.sessionId}/close`, {});
            },
          },
        };
      },
    };
  });
}
