# Battle observation interface v1

This is a sandbox display adapter, not a military resolver. The source remains the
private WWO cloud backup `04ab3cc9ffb2233fa0ab5290e0ec0a952f229630` (Godot 4.6.3).
The local/latest military version is not available in this task. PR #11 remains a
draft targeting `sandbox/main@64e6022`; no formal WWO integration or merge is implied.

## What the diagnosis actually found

- Original `Connection` + `attachment_continuity/session.gd` already produces
  personal injury, received ground contacts and delayed unit reports. The old
  sandbox exported only the controlled person's coordinates, ignored reported
  entities, retained only the most recent 20 events, and consumed event IDs while
  reading snapshots. A repeated read could therefore lose the current event batch.
- The original `gameplay/observation.gd` and `participants.gd` diagnostic switches
  expose shared-fire allocations and their links to personal injuries. The
  sandbox research host enables those existing switches; original `Session`
  still handles all input admission, time advancement, decisions and settlement.
- The model reports aggregate fire and fractional damage over time intervals.
  There is no verified per-bullet muzzle, ballistic or individual-hit stream.
  Yellow links show `prepared_contacts` attached to an actual damage allocation;
  those rates are planned contact rates, **not exact rounds delivered per target**.
  Losses and personal before/after health come directly from source records.
- Body/weapon heading is not reported in this source. The display shows a movement
  arrow only when committed coordinates change. Static body heading stays unknown.
- Native local positions exist for 4 units and 6 named people. Two remote sparse
  units have no local `spatial` coordinate declaration; they remain in raw source
  and `unlocatedUnits`, not placed at the coordinate fallback `(0,0)`.

## Two explicit read boundaries

`private.wwo.military.v5` continues the PERSON_VISIBLE entry, now with retained
report/entity pages and idempotent snapshots. Each report entity retains its
`observedAt`, `receivedAt`, `reportId` and `factKind`. It does not gain truth-side
ammunition, team or casualties. Reports are observations, not omniscient current
positions.

`private.wwo.military.observer.v1` is a separate, clearly labelled DEBUG_TRUTH
research view of the same original instance. Its new default is 36 × 5 game
seconds without a preset player order or success expectation. The existing
movement/counterexample templates retain their own explicit 30-second steps and
expectations. It displays local sides, named bodies, original state and causal
records. Aircraft/ships and remote sparse-group detail are outside this viewport.
Research data never enters person knowledge, command context or the shot-target
picker. The picker uses only the controlled person's received `ground_contact`.

## JSON frame

The existing adapter/result protocol remains v1. A military research snapshot
adds `observations.battle` with schema `wwo-battle/frame/v1`. Use **导出当前帧**
to export that complete frame, or consume it from an existing bridge snapshot.

- `sourceCommit`, `view`, `tick`, `time`: source identity and committed game time.
- `entities[]`: original `id`, `kind`, `team`, `x/y` (source km), state and optional
  health/personnel/ammo/casualties. Missing values remain missing. `raw` and
  `sourcePath` retain the original record. Display callout offsets are SVG-only.
- `movement`: explicit difference of two committed positions with both ticks.
  `motionHeading` is derived from that displacement, not asserted body facing.
- `events[]`: original `id`, `kind`, `effectiveTime`, `actorId`, `targetId`,
  `causeIds`, unchanged original `raw` record, and the tick where it was collected.
  Event IDs are scoped to one simulation run; reset your deduplication on a new
  run. `causeIds` can refer to entities or not-exported records, not only events.
- `dropped`, `unlocatedUnits`, `gaps`, `scope`: source loss/coverage disclosures.
- `source`: original committed units/people/nodes/totals/RNG and collected records.
  This is private diagnostic output, not a player-facing save or command payload.

Records are fetched in pages of at most 128 using the last native event identity.
This avoids the original Python client's 512 KiB per-response bound. A lost
continuation or more than 64 required pages fails the request and preserves the
last valid snapshot. Original observation storage remains bounded at 4096 records;
its `dropped` count is retained (it counts the source's combined buffers).
Person views use their original 20-item backward cursors, up to 64 pages, and
retain native cursor/drop metadata. No clock advance occurs during these reads.
Snapshots are pure reads of an already-collected frame. PENDING never exposes
half-settled truth and never advances the displayed tick.

## Minimal Godot consumer

`examples/godot/battle_frame_consumer.gd` loads an exported frame and updates only
existing display nodes keyed by original entity ID. It maps source kilometres to
metres on Godot XZ (`[x,y] -> [1000*x,0,-1000*y]`) and emits the original event
record through `source_event`. `reset_replay()` is required before backward seeks
or a new run. Connect that signal to your own inspector; do not interpret a
`personal_injury` as a projectile hit or recompute damage. This is an isolated
example; it is not installed into the WWO host.

Run the sandbox using `external/README.md`. Choose the research adapter after
loading available real algorithms. Step/Pause controls call the source; the
visible timeline replays committed snapshots without calling the algorithm.
Historical replay disables commands. Raw JSON is collapsed by default.

## Private asset integration

Three user-authorized files were actually downloaded (924,430 bytes total),
archive entries inspected, GLB headers/materials/bounds parsed, WebP dimensions
and frame counts decoded, both atlases visually inspected, and the GLB rendered
in Chromium. No bulk Drive traversal or sharing changes were made.

| Drive file | Verified contents | Selection and limitations |
| --- | --- | --- |
| `1ikJhtvJ_zKXFKcCGIk4xYCe5QFGDlmhT` | GLB v2, 49,172 bytes, 3 meshes, vertex colors, 8×8 m nominal tile | Reused byte-for-byte as a Three.js scenery layer. Rescaled for display only. `-col` names/navmesh hints are not browser collision or algorithm terrain. |
| `1jpW8-P77w7_qAu1yxCLR4fPJc_-2za6U` | ZIP 330,660 bytes; 512/1024 albedo, 512 normal/heat, 256 optical flow, 16-frame animated preview, GLB, TSCN, shader | Reuse only the 512 RGBA 4×4 atlas in the labelled independent test bench. Texture visibly includes a barrel. TSCN references `explosion_controller.gd` and `explosion_3d_optical_flow.gdshader`, absent from this ZIP; supplied shader is instead `missile_mach_plume_3d.gdshader`. Not self-contained as delivered. |
| `1OmhFmzmhMdUxaTewrD8h7D7viE-YAAMu` | ZIP 544,598 bytes; same texture resolutions, 16-frame preview; GLB, TSCN, 3 shaders, controller | Reuse 512 RGBA 4×4 atlas in independent test bench. No verified metal-hit event exists here, so not attached to personal injuries. |

Web reuse crops original atlas cells in row-major order; frames are selected
explicitly with a 0–15 slider and do not run while inspecting paused facts.
No image generation, redrawing or baking of fake combat screenshots was used.
Godot shaders/scripts/TSCN cannot execute in Three.js. Source explosion controller
uses 1.30 s lifetime and time exponent 0.55; the animated previews declare 24 fps
and contain 16 frames. Optical flow blending, normal/heat lighting, HDR emission,
soft particles, shockwave refraction and ballistic particles are not ported.
The shader filename for the muzzle pack suggests a sustained plume and its
parameters differ from the explosion controller; do not infer compatibility from
filenames alone. Only the three chosen assets are copied into this **private**
repository. Serving path `public/private-assets` is a local Vite convention, not
permission to publish them; the bridge remains loopback-only.

## Validation scope

Scoped tests cover original movement/cooldown/shortage behavior, idempotent reads,
visible pagination, exact injury-to-allocation linkage, missing/malformed causal
records, and observation-on versus original-server physical state/totals/RNG for
the same inputs. Godot consumer parse/run and browser checks are separate from
algorithm correctness. Generated screenshots, recording, result frames and timing
samples live outside versioned source and are delivered privately.

## Same-map perspective and camera experiments

The default military view is one persistent Three.js perspective scene. It never
opens a battle inset or returns to the old 500km terrain inspector. The source
A3 abstract plane is embedded in a **display-only** 50×50km parent with origin
(-2.5,-2.5) km: four 25×25km theatres, each containing 25 of the 100 5×5km cells.
This is not a claim that the military resolver simulates these 100 cells or that
the plane is georeferenced. Unpopulated cells explicitly have no battle output.
Click a cell to continuously move the same camera to its child area; “本人附近”
returns to the same A3 source coordinates. Grid navigation does not create a new
session, advance time, issue commands, change knowledge or expose new authority.
The actor remains `squad`; research truth is for review and never grants control
of red-side or other bodies.

500/300/200m are **experimental camera presets**, not a user-finalized limit.
The width means the distance between left/right centre-screen rays intersecting
the horizontal ground plane, using the current viewport aspect and oblique angle.
The actual measured width is shown. It changes with manual orbit/zoom and resizing;
no fixed “zoom multiplier” is advertised. Far views suppress nearby meshes,
art and event lines at a measured width of 1800m; the 50/25/5 grid remains. Normal
Three.js frustum culling applies. Only the ten source-local entities get models;
there is no fake population expansion, off-screen animation or full-world streaming
claim. Camera transitions use elapsed time, independently of render frame count.

`presentation/battleModels.ts` is the replacement point for future GLTF assets.
Each named person gets one simple human model. Each aggregate infantry unit gets
one formation standard, not twelve invented people. Same-position objects are
spread **for display only**, with leader lines to exact native anchors. Body scale
is exaggerated; a band marks native WOUNDED, and an inactive pose is reserved for
explicit INCAPACITATED/DEAD states. Those inactive branches were not observed in
the selected A3 run. Weapon FIRE and target ID come from the original weapon state;
no per-round animation is synthesized. Vehicle geometry is available in the
explicitly independent model bench. This source A3 has no verified vehicle or
passenger relationship stream; the local screenshot's in-vehicle state cannot be
recreated as an algorithm result from this pinned source.

## Economy presentation is actually source-driven

The existing pinned `b5bfcdd` Python `ProgrammeWorld` is run afresh. The market scene
now puts native `produced` and `household_consumed` quantities on the corresponding
building, offers a day timeline, before/after inventory and cash, and selects
native sequence-numbered business events with complete original payloads.
Cash transfer, dispatch, arrival and payment come from the original trace.
For example J1 day 1 emits seq 13: Beaner produces 4 beans; seq 27: Household consumes
6 bread. The day 0→1 source inventory is 103→98, cash total stays 4000, and in-transit
quantity becomes 3. These are actual research-source results, not acceptance
expectations or formal Godot economy verification. No geographical shipment
positions are reported, so no cart or truck animation is invented.

## User screenshot and asset limitations

The six supplied Library image IDs were read through the connector. This runtime
received image pointers and extracted descriptions/OCR, but signed pixel downloads
failed with transport proxy 403 even with network permission. They were **not**
visually inspected as pixels here. In particular the local in-vehicle/incapacitated
scene is newer/different than this cloud A3 source. Remote military backup was
rechecked and still points to `04ab3cc`; no matching newer source was located.
Smoke candidates were not downloaded: there is no verified smoke event to bind.
The supplied v8 terrain note is not evidence of a seasonal/hydrology algorithm;
no such simulation is claimed or added.
