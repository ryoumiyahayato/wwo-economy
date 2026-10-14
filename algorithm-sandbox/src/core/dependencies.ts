/** Ideal dependencies fulfill each finite request, never manufacture an Infinity balance. */
export function provideSupply(
  requested: number,
  available: number,
  strategy: "on-demand" | "finite",
) {
  const injected =
    strategy === "on-demand" ? Math.max(0, requested - available) : 0;
  return { available: available + injected, injected };
}
export function transportPolicy(
  strategy: "instant" | "bounded",
  requested: number,
  capacity: number,
  lead: number,
) {
  return {
    allocated:
      strategy === "instant" ? requested : Math.min(requested, capacity),
    delay: strategy === "instant" ? 0 : lead,
  };
}
export function provideFunding(
  requested: number,
  available: number,
  strategy: "normal" | "finite",
) {
  const injected =
    strategy === "normal" ? Math.max(0, requested - available) : 0;
  return { available: available + injected, injected };
}
