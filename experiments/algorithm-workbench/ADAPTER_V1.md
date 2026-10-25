# Adapter v1: calls and committed observations

The public contract is `wwo-sandbox/adapter/v1`, defined in `src/core/types.ts`.
Optional commands, display frames and event identities are additive v1 fields. The demos
are original game fixtures; a real provider must identify its actual version and
source in metadata and stay in an external private path.

`create(scenario)` returns one complete tick-0 snapshot and a session. A completed
`session.step()` returns the next complete snapshot at exactly tick + 1. The host
never estimates the result or performs a second simulation in the adapter.
`close()` releases the underlying instance.

## Optional runtime commands

Metadata `supportsCommands: true` declares a legal source operation entry.
`session.command(request)` returns `{snapshot, receipt}` at the current committed
tick. The bridge endpoint is `POST /api/v1/sessions/{id}/command` with
`{expectedTick, command}`. Unsupported providers remain read-only.

The request contains `id`, lawful source `target`, original `intent`
(`advance`, `hold`, `withdraw`, `cancel`), destination `node` and source-known
`path`. The host forwards them; it does not calculate movement or invent a
receipt. `receipt` contains `id`, `accepted`, `status`, `reason` and the original
`source` response. Accepted input and successful execution are separate facts.
Source rejections are normal receipts. A call exception retains the last
committed observation, discards the possibly changed bridge session and requires
reset; optional `executionError.command` records the failed input for reproduction.

Commands are disabled while a step is busy/PENDING, during historical playback,
and for imported results. Same-tick authoritative observations replace that tick,
with original event identities retained. Optional result `commands` records each
request/receipt and `atTick`, in submission order. Reproduction creates the same
source version and reissues them at those ticks, comparing receipts and history.
Automatic A/B runs use initial scenes and do not copy a live operation sequence.

Optional `initialConditions` stores explicit source input or an external fixture
reference. Metadata may provide `scenarios`, displayed `metrics`, `seedNote`,
`unavailableReason` and `lockedDependencies`. The UI keeps source constraints
locked. A missing provider stays visible with its real reason alongside working
providers; it never substitutes demo logic.

A provider with bounded computation can return:

```json
{
  "kind": "pending",
  "committedTick": 0,
  "reason": "Original continuation example"
}
```

This is an unfinished call, not a partial snapshot. Keep the last committed tick,
state and history unchanged; resume the same session and the same requested
target under the provider's original policy. The HTTP bridge wraps this as
`{"pending": ...}`; a complete result is `{"snapshot": ...}`. `expectedTick`
remains at the committed value across pending calls. Once committed, duplicate
or out-of-order requests are rejected. Empty pending reasons are invalid.

Result JSON exports observation history only. It is not an engine checkpoint:
internal continuation state, half-settled stocks and private engine cursor data
do not belong in the public result format. Reproduction creates a new instance
from the original scenario and requires the exact metadata version and source.
Batch comparison and reproduction stop after 100 consecutive pending responses
with an incomplete-check message, not an invented failure verdict.

## Observations and independent expectations

Snapshot metrics, invariants and injections are finite numeric values. Missing
observations are omitted and remain undefined. Entities and orders use stable
source IDs. `Entity.granularity` optionally declares `formation`, `squad` or
`person`; the renderer never creates people from a headcount.

Optional `Snapshot.observations` retains finite JSON from the lawful source view,
not hidden-world truth. Orders can omit loss, cancellation or status when the
source does not provide them; missing fields stay undefined to rules and unknown
in the UI. Glyphs handle sources without demo-specific distance/count parameters.

Events may supply optional string `id` and `causeId`. The inspector follows only
declared links, using a visited set to stop cycles. Without links it displays the
actual event sequence and says the causal assignment is unknown. Missing IDs or
unavailable subjects do not cause invented objects or pass verdicts.

Independent rules support these targets:

| Target                | Observation                                                                                     |
| --------------------- | ----------------------------------------------------------------------------------------------- |
| `metric`, `invariant` | Snapshot numeric field named by `key`                                                           |
| `entity`, `order`     | Scalar `key` on the object named by `subjectId`                                                 |
| `stage`               | Stage `status`, with stage ID in `key`                                                          |
| `eventCount`          | Events with matching `stage=key`, optionally filtered by `subjectId`, through the selected tick |

Numeric values support `eq`, `gte`, `lte`; strings and booleans support `eq` only.
Rules are scenario inputs, never generated from the resulting observations.
For `byTick: "always"`, an observed violation remains a failure even if another
sample is unavailable. Before a deadline rules remain pending; absent data at a
due deadline remains undefined.

If a source call fails, retain the last committed snapshot and discard the
possibly mutated instance. Closing an absent/discarded bridge session succeeds,
so reset can create a fresh instance. Saved results are read-only observations;
re-execution requires the same real source version.

Optional `Result.executionError` records the last committed tick and original
call error. Execution failure is distinct from an independent-rule mismatch:
the UI freezes playback until reset, preserves the error in saved/imported
results, and reruns the failed call when checking reproduction. An unfinished
PENDING reproduction stays unjudged.

## Geographic display ownership

An optional scenario display declaration looks like:

```json
{
  "crs": "EPSG:2154",
  "origin": [650000, 6150000],
  "cellM": 5000,
  "label": "Original demo display mapping only; terrain is not consumed by the algorithm"
}
```

Projected position equals origin + source x/y × cellM. No declaration means no
geographic placement; positions outside the tile are omitted rather than clamped
or teleported. The 500 km tile has one authoritative 5 km source, aggregated for
25 and 50 km displays. Changing display level does not create a new simulation.
2D and 3D share projected points, scalar samples, cover and vector records.

3D uses cell means, with meters converted to kilometers and an explicitly
display-only height multiplier. Unknown height remains null in data even when
drawn flat. Vector segments are clipped at the tile boundary without joining
separated river fragments. Camera movement, layer selection, mesh interpolation
and symbol size never mutate source snapshots or terrain.

### Military observation extension

The optional `observations.battle` field uses `wwo-battle/frame/v1`, documented in
[BATTLE_INTERFACE.md](BATTLE_INTERFACE.md). Existing v1 snapshots without this
field continue to work. An advertised military command session may also accept
`{id, op: "body", parameters: {...}}` for the source-supported `observe`, `reload`,
`fire`, `cease_fire`, or `take_cover` action. This is an attempt sent to the original
body entry, with the same `CommandReceipt` and recorded-command semantics; it
cannot set health, position, ammo or the simulation clock. Consumers must not
assume every `CommandRequest` is a goal intent. Goal requests retain their
existing `{id,target,intent,node,path}` shape.
