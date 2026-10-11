# Task profiles

Every task manifest names a **profile kind** in `profile.kind`. The profile decides how a run of that task reads a
step's result, which files the step may commit, how the run moves on after a commit, and which helper agents it may
start. Cotterpin ships every kind its own routes use, so a brand-new repository runs a product route without writing
any code of its own.

## Where a kind comes from

Cotterpin looks a kind up in this order:

1. **The product.** Kind `<kind>` is the module `cotterpin/profiles/<kind with - as _>.py`, which defines exactly one
   profile class; a language pack adds its own in `cotterpin_pack_<id>/profiles.py` (`PROFILES = {kind: class}`).
   There is ONE registry, `cotterpin.kernel.profile_registry`: `kinds()` lists every product kind and
   `resolve(kind, data)` builds one. A kind shipped twice (by the kernel and a pack, or by two packs) is refused.
2. **Your extensions**: a kind of your own is `<namespace>:<kind>`, declared in `.cotterpin/extensions.json` and
   approved into your lock (see [CONTRACT-AND-EXTENSIONS.md](CONTRACT-AND-EXTENSIONS.md)). An extension may add a kind
   but never replace one the product ships.
3. **Your repository's own registry**, only for a kind the product does not ship: the registry an adapter passes as
   `RepositoryServices(profiles=...)`. Pass `profiles=None` when you have none — the product registry then answers
   alone. A repository copy of a kind the product ships is never used; delete it.

A kind nobody ships stops the run before it starts (`control-plane-invalid`), and so does `profile.data` the kind
cannot accept: each kind checks its own data when the run loads its manifest, and the message names every missing or
malformed key.

| kind | owner | what it is for |
|---|---|---|
| `generic-manifest-frontier` | product | any task whose behaviour is data: one target per run, the step hands back the files it changed, the kernel commits them |
| `audit-scanner-frontier` | product | a shard audit whose progress is kept by your repository's audit scanner |
| `fix-remediation-frontier` | product | the fix lane: closes audited findings with independently measured proof, code and ledger in separate commits |
| `okf-version-frontier` | product | refresh or migrate your OKF knowledge bundle |
| `java-static-result-frontier` | Java pack | lands a candidate built by the root build service and hands it to the primary merge |

## What every kind reads from your layout

Profiles never spell a path of your repository. They read the layout you bind (`RepositoryServices.layout`, the
standard layout when you declare none): `control_plane`, `task_manager`, `persona_dir`, `workflow_dir` (doctrine files
cited by a workflow), `scanner_dir` (a bare planner name), `audit_staleness_scanner`, `audit_ledger`,
`capability_map_dir` and `grok_runner`. Your own harness modules — guards, adapters, lock files — reach every task's
pinned file set through `RepositoryServices.runtime_dependency_paths`, not through a profile.

## `profile.data` by kind

### `generic-manifest-frontier`

Required: `workerShapes` (`{role: {idPattern, tierRoles}}`), `ledgerNamespace`, `leaseShardFrom`,
`semanticShardFrom`, `commitSubject` (with `{shard}`), `progressCounters` (`{completed, pending, advancing?,
decisionBlocked?}`), `requiredReceiptKeys`, `closurePaths`, `allowedDirtyPaths`, `routeCheckTier` (`[model, effort]`).

Optional: `semanticShardArgKey`, `scratchRootSubdir`, `idsFrom`, `authorConfigsArg`, `carriedProveArg`,
`acknowledgedBlockersArg`, `acknowledgedBlockersMaxLength`, `acknowledgedBlockersClaimCheck` (`{path, function}` of a
predicate in your checkout), `commitTrailersFromReceipt` (`{TRAILER: resultKey}`), `terminalAfterCommit`.

The shipped de-stub route (`JAVA-TEST-DESTUB`) uses this kind; its manifest carries all of this data, so a fresh
repository needs nothing else.

### `audit-scanner-frontier`

- `frontierStateDir` (required): the folder, relative to the Git common directory, where your scanner keeps one
  frontier file per shard.
- `closurePaths`: extra files pinned for the route; `{workflowStem}` and `{nonContentionGuard}` are filled in.
- `challengeRestorePaths`: audit files a challenged pass restores from the last commit (default: your audit ledger).
  Unique bytes are kept as Git objects first.
- `rehearsalShard` (default `REHEARSAL`), `commitSubject` (default `chore(audit): persist {shard} harness frontier`).

### `fix-remediation-frontier`

- `remediationPathPattern`, `testPathPattern`, `provingTestPattern` (required regular expressions): the files a fix
  commit may carry, which of them are tests, and what one proving-test selector looks like.
- `closureFiles` (required): the exact files a ledger commit may write; it must include your audit ledger.
- `isolationArg`: the name of a yes/no task argument passed through to the workflow.
- `closurePaths`: as above.

The manifest's `landing` must declare `mode: kernel-commit`, `terminalRequiresNoParkedCode: true`, and your own
`harvest`, `reap`, `uncommittedRatchet` and `uncommittedHold` names.

`python -m cotterpin.profiles.fix_remediation_frontier --prepare-frontier remediation|closure --worktree <path>
--harness-run-id <run-id> --receipt-file <file>` measures a step's files for its workflow; it changes nothing.

### `okf-version-frontier`

- `versionManager` (required): your OKF version manager script; it answers `verify --bundle <bundle>
  --target-version <v>` and `recover --bundle <bundle> --base-head <commit>` with one JSON line.
- `bundle`: the bundle folder (default: the first folder of your layout's `capability_map_dir`).
- `closurePaths`: as above.

### `java-static-result-frontier` (Java pack)

The `generic-manifest-frontier` data, plus `driver.externalResult` = `{kind: root-supervisor-static-result,
repositoryId, action, provider}` in the manifest.

## Moving from your own profile registry

1. Delete your copies of the kinds above; keep only kinds the product does not ship.
2. Add the data each kind now requires (the run stops and names any missing key).
3. Move your guard and adapter files into `runtime_dependency_paths` if your profiles used to pin them.
4. If you have no kinds of your own left, bind `RepositoryServices(profiles=None, ...)`.
