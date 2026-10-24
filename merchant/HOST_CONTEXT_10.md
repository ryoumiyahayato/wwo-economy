# economy1.0 external-host continuation

## Scope and ownership

The existing merchant play scene can consume an existing legal Formal snapshot.
This is a continuation adapter, not a generic firm UI: only the existing
`firm:merchant_prototype` is supported. The explicit player and selected site must
exist in that restored world, and its actual domain manager must authorize the
player. Unsupported firms and invalid context fail closed. No authority is granted
by admission, viewing another city, or re-entry.

The external host must relinquish its mutable WorldBuildResult before starting the
runtime. The worker restores through FormalPersistence and exclusively owns that
continuation. The restoration implementation may construct its normal internal
candidate; the adapter does not call the merchant opening, inject endowments,
grant authorities, advance an opening minute, or start an independent clock.
The snapshot is encoded using FormalWorldPersistenceDocument exact-Variant encoding
before handoff. Only its primitive document fields cross threads; the worker
decodes and validates it before restoration. WorldState and other Objects never
cross the mailbox. This preserves vectors/packed arrays without widening the
mailbox type policy.
There is no distributed lease: the embedding host must not keep a second live
world advancing alongside the worker.

## API

- Runtime.host_context(snapshot, person_id, firm_id, site_id, plans={},
  quote_authority_id="", save_metadata={}) constructs the value envelope. Its
  snapshot_document is the encoded Formal document, not a raw snapshot.
- runtime.start_external(context) rejects an empty context. Nonempty invalid
  contexts produce an unsuccessful init response with an empty view.
- runtime.start() retains all existing standalone slots 1–4 unchanged.
- runtime.submit("observe", {"site": ...}) only browses a business site.
  It neither travels nor advances time; travel remains a legal domain command.
- External runtime.submit("advance"), submit("host_advance"), and submit("switch")
  return -1. The owner alone calls advance_from_host(minutes), bounded 0–60,
  awaiting each acknowledgement; the same SimulationStep handles every minute.
- Legal trade/plan/quote actions use the same worker and domain boundary.
  An optional quote authority must already exist; quote execution still checks
  its validity, scope and acting context. Admission never creates a grant.
- submit("export"), submit("save"), or submit("close") returns a pure-value
  result.host_context. Only close relinquishes worker ownership. A save/export
  checkpoint is not permission to run a second world concurrently.
- Wait for close acknowledgement, then finished()/join_finished(). The external
  host persists the returned envelope and decodes snapshot_document before
  restoring its snapshot, or passes the whole envelope back for re-entry.
  No external action writes merchant standalone slots or slot preferences.
- Forced shutdown_and_join() queues a host_detached response containing the final
  context. The host must drain poll() afterward and persist it; discarding the
  runtime also discards uncollected output. Prefer acknowledged close.

`HOST_OWNED_EXPORT_REQUIRED` explicitly means the host must persist exported
values; it is not a claim that an external file save was completed.

## Identity projection

view.person_id and view.identity.person_id identify the actual current player.
identity.personal is the existing legal LivelihoodAction.query result;
firm_id/site_id identify the business under inspection. manager_person_id comes
from firm_manager_at at the current world minute; can_manage comes from the legal
query_firm result. management_basis comes from the selected site's domain
operation, and management_summary is its human label. Personal and company cash
remain separate views of original accounts, never a new wallet.
personal_cash is the account balance; personal_reserved is the reservation and
personal_available is their difference only when both legal values are known.
An unavailable personal query yields null, not a fabricated zero.

## Probe

`godot --headless --path . --script res://merchant/qa10_host_context.gd`

The probe independently constructs a host world, snapshots and relinquishes it,
starts the existing runtime, buys using a real executable quote, exports on
leave, legally restores the returned world, and re-enters. It checks unchanged
unresolved order IDs and reserved money, no extra opening minute, one explicit
host clock step, remote browsing without travel, rejection of unsupported
identity/site/firm, unknown grants, an existing unauthorized person, corrupt
exact payloads, unsupported schemas, and Object/Node/Resource/empty input.
Standalone slot and preference fingerprints must remain unchanged. The re-entry
uses the actual main.tscn scene and its continuation signal. It is integration
coverage, not an automated claim of human UI experience acceptance.

## Verified result (2026-10-18)

The parent ran the final host probe serially: QA10_HOST_PASS, exit 0, no errors.
The exact play scene returned its continuation at minute 2 / slot 0. The probe
covered real purchase, unresolved order and reservation continuity, sole-host
clock control, all listed invalid contexts, and unchanged standalone slots.
The old 09 day-8 compatibility probe also returned QA10_LEGACY_PASS: exact ledger,
native economy, time and plans survived restoration/save/reload; observation was
read-only, corrupt envelopes were rejected, and the source hash was unchanged.
These are automated integration results, not Android-device performance or
human-play acceptance results.

An initial test correctly rejected a raw snapshot at the strict primitive-only
mailbox because legal Formal snapshots contain non-primitive Variant values.
The adapter was corrected to use the existing exact-Variant persistence document
before crossing the thread boundary, and to decode only inside the worker. No
Object/Node/Resource exception was added to the mailbox.

The unauthorized-person fixture is materialized only by qa10_host_context.gd in
its independently built QA world. The production runtime, opening and play scene
do not create that resident or inject any NPC. Support remains explicitly limited
to the existing firm:merchant_prototype and its authorized sites; this result does
not establish arbitrary-firm or arbitrary-world support.
