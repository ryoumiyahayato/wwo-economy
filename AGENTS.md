# Algorithm Sandbox agent guidance

Primary app: `algorithm-sandbox/`. Keep this repository PRIVATE because its
history and `legacy/` contain private research. Only the standalone original
sandbox source may be distributed publicly after checking its package boundary.

1. Use versioned adapter interfaces; adapters translate input, call algorithms,
   advance time and read output. Never reimplement private algorithms in the UI.
2. Declare test boundaries. Idealize only external dependencies and record every
   finite injection; never write Infinity or stub tested behavior to success.
3. Independent expectations belong to experiment configuration, not adapter
   output. Missing expectations or observations remain undefined.
4. Keep synthetic demos labelled demo and historical private versions labelled
   with their actual source commit. Do not claim uncommitted versions are tested.
5. Preserve all frozen research bytes/manifests under `legacy/`. Its AGENTS.md
   governs work inside that archive; this scope change does not authorize editing
   its algorithms, fixtures or historical results.
6. Current research destination is private WWO's
   `research/economy-lab-20261007/`, branch
   `research/economy-lab-migration-20261014`, draft PR #115. It is not enabled in
   gameplay. Retain the legacy copy while that PR is awaiting review.
7. Validate sandbox changes with build and appropriate core/bridge tests. Check
   rendered workflows when UI changes. Do not impose unrelated global audits.
8. Terrain must preserve CRS, units, common origin and same-source aggregation.
   Missing real terrain remains unknown; synthetic terrain must be explicit.
9. Do not publish services, spend money, expose credentials, or change repository
   visibility. The authorized name-only repository rename was rejected by the
   current service. Do not retry it through different credentials or interfaces.
10. Use isolated branches and draft PRs. Do not merge, force push or rewrite history.
