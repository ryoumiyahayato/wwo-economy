# Original personal economy interface

The default `private.wwo.formal-economy.v1` runs **Godot formal economy at integration/formal-economy-20261014@b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d**. The older Python `ProgrammeWorld` remains a separate diagnostic option. No economic settlement rules are copied into this repository.

## Source diagnosis, 2026-10-15

The old sandbox called only `ProgrammeWorld.step`, and its market component could not submit personal commands. That was an adapter/UI gap, not evidence that WWO lacked personal economic actions. The integration source already owns `LivelihoodAction.query/execute`, current-player/alive checks, personal observations, work, travel, orders, cargo custody, consumption and Ledger.

Remote military backup remains `04ab3cc9ffb2233fa0ab5290e0ec0a952f229630`; integration economy remains `b5bfcdd…`. Default `canonical/current-world@28cdc2dc37c68161dc7b3a3254692980cc75e972` and `local-sync/current-world@b3b8611a740edc81d79fcba1b5e1181fab00b7b7` also exist. Canonical and integration diverged: integration contains Liquidity configuration/rules absent from canonical. A newer commit date does not establish compatibility. Preliminary canonical captures are superseded by the explicitly b5bfcdd integration recordings; no unuploaded local update, dining/rent system, long-run financial correctness or 50/60-day completion is claimed.

## Original execution and authority

`WorldBootstrap.build(..., EconomyDevelopmentConfig.formal_limited())` creates the original WorldState, current player, Ledger, GameClock, SimulationStep and native economy. The second selectable scenario uses the original `formal_liquidity_request()` unchanged. Both are original **development configurations**, not historical enterprise facts. Firms, recipes, opening cash, route capacities, delay and populations retain that qualification.

Each adapter `step()` calls original `SimulationStep.advance_minutes(stepMinutes)`; the default is 720 minutes, selectable 60–1440. `snapshot.tick` counts committed adapter steps, while `minute` and `native.day` retain the original clock. Commands do not advance either clock. Day settlement, work records, wage maturity/payment, production, transport, consumption and funding remain in their original owners.

Commands use the actual current player through `LivelihoodAction.execute`; no alternate actor is accepted. Supported requests:

```json
{"id":"client:unique-action-id","op":"livelihood","parameters":{"kind":"apply","payload":{"job_id":"job:development_workshop"}}}
```

| kind | Original payload used by the UI |
| --- | --- |
| apply | `job_id` from own `known_jobs` |
| work | integer `hours` |
| travel | `destination_place_id` from original travel quotes |
| buy | `quote_id`, `seller`, `seller_site`, `good`, `quantity`, `denomination`, `max_price`, `need_category` from own offers |
| collect | `shipment_id`, shown only when original `can_collect` is true |
| consume | `commodity_id: native:<good>`, `quantity: 1`, original quoted `need_category`, `source: manual` |

The first submitted minute is retained for repeated action IDs. Original idempotence returns the original result without repeating work/payment; changing a payload under the same ID returns `ACTION_ID_CONFLICT`. Job notices may be stale or fully occupied; work may be refused during travel or away from the workplace. Receipt reasons and full original results are retained, not translated into invented success.

## Observation contract and display

`observations.nativeEconomy` / “导出原帧” contains:

- `schemaVersion: wwo-native-economy/frame/v1`, `sourceCommit`, `stepMinutes`, `revision`.
- `minute`, `playerId`, `personal`: original clock and lawful player query; `destinations` and `consumptionQuotes` are original query results.
- `native`, `ledger`, `living`: original snapshots and recent-100 living records. Full native inventory is research truth; it does not enter the player's knowledge or permissions.
- `previous`: previous submitted personal/stock/ledger observation. Before/after totals cover all transactions in that submission.
- `changes[]`: original record observations retaining `nativeRecordId`, `sourcePath`, `raw`, optional `before`, and an explicitly **adapter-owned** `observed:<revision>:…` ID. These are not a native event bus.

New root stock portions whose source is `production:…` represent production; transferred child portions are not counted again. Consumption is the change in cumulative original `consumed`; site material use and personal consumption remain distinct. Payment retains original transaction IDs. Order, shipment, wage, work, action and journey observations retain their original business records. A common settlement boundary is not proof of an unreported batch-to-input causal link.

The process view shows submitted records and whole-submission stock/account changes. Its short movement of a quantity symbol is presentation only; it does not execute logistics or settlement. Personal action symbols show contract/travel/work state, not unreported physical animation. Pausing, selecting a cause, and seeking committed ticks do not call source write APIs. Multiple commands at a tick are retained in command history and native command records; the tick replay shows the last committed snapshot for that tick, not every intermediate command revision.

## Geography and missing integrations

Original Paris/Lyon place references, host connections and cargo stages exist. Local transport edges and timing are development assumptions. There are no firm-level georeferenced buildings, moving vehicles, workshop body actions or second-by-second economic player coordinates in this interface. The view is an explicitly labelled relation diagram, not a geographic railway animation. R12 presentation buildings cannot be joined to firms by visual proximity. Military A3 `squad` and the formal economic player are separate native instances.

Liquidity startup and days 0–3 were executed from b5bfcdd, and the original configuration is selectable. The current UI exposes personal actions and process observations; credit, insolvency and management interfaces are not thereby fully integrated or validated. No made-up service is substituted for missing personal dining/rent or local source updates.

## Executed checks

On b5bfcdd, the full original flow completed: job application → travel away → refusal to work at the wrong place → return to workplace → two hours recorded → wage 6 paid on original due day → own known bean quote → original shipping → `AWAITING_RECIPIENT` while away → return → manual collection (4 goods + 1 freight) → manual consumption (inventory 1→0). Browser screenshots/video preserve actual IDs and state.

Focused tests also cover same-ID retries after time advancement, changed-payload conflicts, no vacancy, work during travel, duplicate work periods, unauthorized firm procurement, wrong-place collection, automatic soap delivery/consumption, actual production and read-only repeated snapshots. The insufficient-available-cash check is an **independent negative fixture** that explicitly reserves all opening cash through original Ledger before invoking original LivelihoodAction. It is not a player action or the recorded gameplay run; no core source or gameplay opening funds are changed.

## Local start and Godot consumer

See [LOCAL_WINDOWS.md](LOCAL_WINDOWS.md). The formal and research economic adapters share the same external b5bfcdd checkout; military uses a separate 04ab3cc checkout. `WWO_FORMAL_REPO_PATH` selects the formal host, normally the same path as `WWO_ECONOMY_REPO_PATH`. No hard-coded cloud path is needed.

[Minimal Godot consumer](examples/godot/native_economy_frame_consumer.gd) emits copied observations and deduplicates adapter observation IDs. Reset it for a new run/backwards seek. It never writes WorldState or owns economy settlement. The original project must first be imported by Godot 4.6.3 to register global script classes.
