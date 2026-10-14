# External WWO adapters

This directory contains input/call/observation wrappers only. It contains no
real simulation implementation, private fixture, historical result or data set.
The sandbox itself remains runnable without WWO using explicitly labelled demos.

## Economy: runnable historical quantity adapter

`wwo_quantity.py` reads an external WWO checkout, calls its original
`research/economy-lab-20261007/economy_quantity_lab/economy.py` implementation,
and reads the external fixture. It has no fallback to an algorithm inside Lab.

Use a separate WWO worktree on `research/economy-lab-migration-20261014`, commit
`07deb15e2ad4e75e5feead00621893e53eaf7c8a`. Do not switch or modify another
active/uncommitted WWO worktree. From `experiments/algorithm-workbench/`:

```sh
WWO_REPO_PATH=/absolute/path/to/separate-wwo-checkout \
SANDBOX_ADAPTER_PATH="$PWD/external/wwo_quantity.py" \
python3 bridge/server.py
```

Run the web app separately from this experiment directory, then connect the local
private adapter and select `private.wwo.quantity.v1`. Only the historical model's
actual observations are supplied. Missing wallets/prices remain unavailable.
Seed is recorded but this deterministic quantity model has no RNG. Source Git
commit is recorded; uncommitted research changes are
rejected for this historical adapter.

```sh
WWO_REPO_PATH=/absolute/path/to/separate-wwo-checkout \
python3 -m unittest discover -s external -p 'test_*.py'
```

## Current cloud source and military ownership

The latest supplied native economy/research integration is WWO
`integration/formal-economy-20261014` at
`b5bfcdd870da5d2b54f8a27e2abbfb9d511c502d`. Native `scripts/world/` and
`research/economy/fifteen-algorithms/` are present there, separate from this
historical quantity wrapper. They require their own provider and are not
claimed connected by this experiment. Migration details remain in WWO at
`docs/research/economy/REPOSITORY_MIGRATION.md`.

## Military: WWO ownership and explicit protocol entry

Real military source already belongs to WWO. At the verified default commit
`2933bc958487006e363b56e920f7c972d0966749`:

- `scripts/vnext/military/military_service.gd` exposes formation creation,
  `move`, `attack`, and `advance_to_hour`, with military state, map and Spatial
  dependencies in the same WWO project.
- `experiments/war_resolver/resolver.gd` exposes
  `resolve_until(state, target_game_time, resolution_policy)`; its state, data,
  synthetic research scenarios, tests and validation runner are in the same
  `experiments/war_resolver/` directory. Its own README labels v0 research and
  production integration NONE; it must not be confused with the newer backup.

The latest supplied cloud military backup is separately available on
`backup/military-person-attachment-20261014-v1`, commit
`04ab3cc9ffb2233fa0ab5290e0ec0a952f229630`. Its gameplay image schema is
`war-environment-runtime-v5`. Read-only inspection confirms that bounded
settlement can be `PENDING`, and that reads retain the old committed state.
The workbench contract now supports that behavior without exporting internal
continuation cursor state. A real provider must keep the same requested target
and policy while continuing; it must not increment the UI tick until settlement
commits. This backup is not merged into the default branch and has no matching
PR in the checked remote state.

A real military provider must live in an external private path selected via
`SANDBOX_ADAPTER_PATH`, use `WWO_REPO_PATH` to run Godot against that WWO project,
call those real entry points and translate their state/events to
`wwo-sandbox/adapter/v1`. Declare the mapping of one workbench tick to game time
and the test boundary. Do not compute movement, hits or casualties in the
adapter, or copy military source/maps into Lab.

This delivery verifies military ownership and the callable source entry, **not
an implemented live military provider**. The current military UI uses only the
originally labelled `demo.military.v1` fixture. The v5 source was inspected, but
not called or claimed validated. No user-computer worktree was accessed.
