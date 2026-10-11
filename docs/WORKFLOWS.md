# Cotterpin workflows

Which of the first customer's workflows and harness manifests became product routes, and which stay with the
customer. Each input is classified exactly once:

- **PRODUCT** — generic, language-neutral: a kernel route (the kernel section of this page);
- **PACK** — useful to any repository in that language: a route of the language pack;
- **CONSUMER** — encodes the customer's own conventions, governance or infrastructure: it stays the customer's, run
  through its own `.cotterpin/` declarations if it wants it, and the product ships nothing for it;
- **SUPERSEDED** — the product already ships the behaviour under another route; nothing is ported.

## The kernel's own routes: governance and audit

Cotterpin ships seven generic routes that any repository can run, whatever its language. They live with the kernel:

| task | manifest | what it does | lands |
|---|---|---|---|
| `delivery_audit` | `KERNEL-DELIVERY-AUDIT` | audits whether one declared scope's capabilities are really delivered | the scope's ledger and register |
| `delivery_audit_fix` | `KERNEL-DELIVERY-AUDIT-FIX` | delivers the capabilities the audit found not delivered, each to its specification | the changed source and tests |
| `doc_maintain` | `KERNEL-DOC-MAINTAIN` | keeps one declared document current with its sources of truth | the document |
| `okf_refresh` | `KERNEL-OKF-REFRESH` | refreshes knowledge concepts, or migrates the knowledge bundle one OKF version | the bundle files |
| `route_governance` | `KERNEL-ROUTE-GOVERNANCE` | reviews every route the repository can run, reading only the routes that changed | the review receipt |
| `release_triage` | `KERNEL-RELEASE-TRIAGE` | sorts one scope's not-delivered capabilities into release-blocking and post-launch | nothing (read-only) |
| `guard_review` | `KERNEL-GUARD-REVIEW` | attacks every guard, hook, scanner, check module and enforcement setting a change touches, one adversary per file, before the change is trusted | nothing (read-only; measuring edits are put back) |
| `gate_port` | `KERNEL-GATE-PORT` | ports a repository's own scanners into pack gates, each proven at least as good as the scanner it replaces (fixtures, calibration, coverage parity) and accepted by an independent reviewer | the gates, their fixtures and registrations, inside the declared paths |
| `test_behaviour` | `KERNEL-TEST-BEHAVIOUR` | rewrites tests that assert wording so they assert what the code does, in any language an installed pack's test adapter covers: each unit verified against the baseline commit and accepted by an independent reviewer | the accepted units' test files |

Each is made of files under `cotterpin/kernel/`: the task manifest (`manifests/`), the route declaration
(`routes/<task>.json`: route, contract, personas), the workflow (`workflows/cotterpin-*.js`), the runbook
(`runbooks/cotterpin-*.md`) and the persona definitions (`agents/cotterpin-*.md`). The kernel resolves a kernel route
exactly as it resolves a language pack's: entirely from the installed runtime, keyed `product:<path>`, so a fresh
repository needs no routing, contracts, workflow or runbook of its own. They run in developer mode (the lock
`cotterpin init` writes) as well as hardened mode (SECURITY-MODEL.md, *Runs of the product's routes*); a route a
repository registers itself needs hardened mode. A repository that ALSO registers one of these
tasks is refused (`route-duplicated`): delete your own copy. Each runbook says how to start a run and what the kernel
dispatches.

### What you declare

Nothing is hard-coded about your repository. Each route reads a small declaration you commit:

| route | declaration | example |
|---|---|---|
| `delivery_audit`, `delivery_audit_fix`, `release_triage` | `.cotterpin/audit/scopes/<SCOPE>.json` | `{"scope": "PAYMENTS", "severity": "S1", "paths": ["src/payments/**"], "docs": ["docs/payments/**"], "policyDocs": ["docs/payments/POLICY.md"], "planningDocs": ["plans/**"], "reviewBeforeEdit": true}` — `planningDocs` (optional) names further planning documents, which, like any `docs/backlog/` file or `*BACKLOG.md`, a verdict may never cite as evidence (CLOSURE-PLANNING-1) |
| `doc_maintain` | `.cotterpin/docs/<ID>.json` | `{"id": "SERVICE_STATUS", "path": "docs/SERVICE_STATUS.md", "mode": "project", "sources": ["git ls-files src/services"], "requiredCaveats": ["Counts are directories."], "projectionHeader": true, "method": {"deterministic": true}, "verification": ["the count equals the directories under src/services"]}` |
| `okf_refresh` | your `.okf/` bundle (OKF 0.1 or 0.2) | — |
| `guard_review` | `toolRules.guardPaths` in `.cotterpin/policy.yaml` (optional: the `.cotterpin` settings and your declared checks' modules are always reviewed) | `guardPaths: ["src/security/**", "scripts/checks/*.py"]` |
| `delivery_audit_fix` (verification) | `.cotterpin/checks.yaml` — the checks `cotterpin check` runs | see RESUME-AND-DRY-RUN.md |
| `gate_port` | the run's arguments: the batch's name (it names the run's shard), the repository whose scanners are ported, the scanners and their packs, the paths the port may change | `{"id": "batch-1", "sourceRepository": "/path/to/repo", "ports": [{"native": "tools/scan_x.py", "pack": "<pack id>"}], "within": ["cotterpin_pack_<pack id>/**"]}` |
| `test_behaviour` | `.cotterpin/tests.yaml` (optional): globs never judged, test files that must stay green, a runner of your own per pack, the unit size; and the run's arguments: the batch's name and the test globs it may change | `exclude: ["tests/generated/**"]`, `also: ["tests/conformance/test_no_mocks.py"]`, `runners: {python: ["uv", "run", "pytest", "--junitxml={report}", "{files}"]}`, `unitFindings: 30` |

The routes write `.cotterpin/audit/ledger/<SCOPE>.json`, `.cotterpin/audit/register/<SCOPE>.md` and
`.cotterpin/governance/routes.json`. Commit them through the run; never edit them by hand. With every
`VERIFIED-DELIVERED` verdict, `audit-record` also keeps `testMethods`: the test methods each test file of the evidence
declares at that moment (read through the installed packs). The kernel's ledger gates read it: CITED-TEST-1 reports a
recorded proving method that has since disappeared, GREEN-NEEDS-TEST-1 a delivered row with no live test in its
evidence (GATES.md, *The kernel's own gates*).

### The deterministic steps are tools: `cotterpin tool <command>`

Every step that needs no judgement is a tool the route's relay agent runs and copies back verbatim — never a script in
your repository, never a model retyping a list. Each prints exactly one JSON line and exits 0 (done), 1 (done, with a
negative answer) or 2 (refused, with the reason and the next command; `cotterpin explain <code>`).

| command | used by | does |
|---|---|---|
| `frontier`, `revert` | every writing route | the exact changed paths with their byte states and digest, for the kernel to commit; or put exactly those paths back |
| `audit-plan`, `audit-census`, `audit-record` | `delivery_audit` | which files changed since the last census and which capabilities need a verdict; record the census; validate and record a wave's verdicts, render the register |
| `audit-fix-list` | `delivery_audit_fix` | the not-delivered capabilities with their fix tier, grouped into file-disjoint bins; the ones that need your decision |
| `audit-triage-plan`, `audit-triage` | `release_triage` | deterministic slices of the not-delivered capabilities; merge the classified slices and report what is unsettled |
| `doc-plan` | `doc_maintain` | validate each document's declaration and plan its tier |
| `okf-plan`, `okf-validate`, `okf-migrate` | `okf_refresh` | the bundle's version and registered edge; strict validation with the validator the product pins; one proven migration or a byte-for-byte rollback |
| `okf-coverage` | `okf_refresh` | every asset `.cotterpin/okf.yaml` declares that no concept covers, and every concept that restates a product document |
| `okf-init`, `okf-produce-plan`, `okf-index` | `okf_produce` | a knowledge bundle for a repository that has none, only after asking you (consent `knowledge.bundle`; declined, nothing is created); the uncovered assets grouped into one concept per folder; new concepts added to the indexes and the log |
| `route-list`, `route-check`, `route-scope`, `route-receipt` | `route_governance` | every route and its files; every structural rule; the routes changed since the last review; record the review |
| `guard-scope` | `guard_review` | the guard, hook, scanner, check-module and enforcement-setting files the change since `--base` touches, deleted ones included |
| `gate-port-check`, `gate-port-diff` | `gate_port` | a ported gate's fixtures and every finding it makes on the source repository; its coverage parity with the repository's own scanner (a native finding it misses is a gap) |
| `test-plan`, `test-verify` | `test_behaviour` | every assertion that asserts wording, grouped into units of whole files, each with its findings as its brief; a unit's files judged against the baseline commit (no finding left, no test failing anew, every conformance check named still green) |

Hand-off files (census rows, verdicts, slices) live in the repository's shared git directory
(`<git common dir>/cotterpin/route-runs/<run id>/`), never in the checkout, so they can never be committed by
accident and every linked worktree finds the same run's files.

`cotterpin tool route-check` is also the quickest way to check a route you are writing: it runs every rule below on
the kernel's routes, every installed pack's, and your repository's own.

### Speed review (ADR-005 F13)

| route | unit boundary (shards) | folded into a tool | reads instead of rediscovering | build checks | landing |
|---|---|---|---|---|---|
| `delivery_audit` | census: 20 changed files per shard; audit: one capability per agent; both at the Box Budget width | plan, census record, verdict record, register, sample choice, revert | the ledger: a verdict whose evidence files are byte-identical is never re-audited; unchanged files are never re-censused | none: it reads | kernel commit of ledger + register |
| `delivery_audit_fix` | file-disjoint bins (capabilities sharing an evidence file share a bin), bins in parallel | fix list, tiers, bins, frontier, revert | the ledger's specification, evidence and work class per capability | `cotterpin check` once per pass, one repair round (`verification: affected/test`) | kernel commit of the changed files |
| `doc_maintain` | one document per run (one writer per document, in parallel for a direct run) | declaration reading and tier planning, frontier, revert | the declaration | the declaration's own checks, run by an independent verifier | kernel commit of the document |
| `okf_refresh` | one concept per agent; log.md groups in parallel | plan, strict validation, the whole migration and its rollback, frontier, revert | the product's OKF registry | strict validation | kernel commit of bundle files |
| `route_governance` | one route per curator, in parallel | enumeration, every structural rule, delta scope, receipt | the receipt: a route whose files are byte-identical is never re-reviewed | none: it reads | kernel commit of the receipt |
| `release_triage` | slices by position, in parallel | partition, merge, conflict/missing/total checks | the ledger's recorded harm statements | none | none |

Model tiers follow the work, never a blanket tier: every relay is haiku/low; judgement that could silently pass a
harmful result (an S1 audit, the delivered-verdict sample, a policy disposition review) runs opus/high; the rest is
sonnet at the effort its work needs. Each route's runbook lists them.

### The structural rules every route passes (`cotterpin tool route-check`)

1. The result envelope names the run identity, `stages` and `verificationEvidence`; every field is one the kernel can
   accept; every field appears in the workflow.
2. The workflow ends in a top-level `return` of its result.
3. **Every `verificationEvidence` row is an object** (CONTRACT-6). A route run by the native workflow runtime has its
   result refused at the very last step when a row is a string — after every agent has already run. The check reads
   the source before any run: a string row, an object in place of the list, or rows mapped to strings.
4. The runbook names its workflow and states its findings policy.
5. Every persona the route names ships as an agent definition naming itself; every persona role has a model tier.
6. Every `cotterpin tool` / `cotterpin pack` command the workflow runs exists, and every one the contract declares is
   run.
7. Every task manifest for the route passes the kernel's load-time checks.

`tests/kernel/test_kernel_product_routes.py` holds every shipped route (kernel and packs) to these rules. Building them
found two real defects, both fixed: the kernel could not accept the `stages` ledger it requires of every route (every
product route would have been refused at its first dispatch), and the Java pack's migration and generator routes
returned fields the kernel did not know (refused the same way). Each kernel route also has a simulation test
(`tests/kernel/test_route_*.py`) that runs the workflow under node against a real git repository with the real
`cotterpin tool` commands, and asserts that every terminal — success, refusal, failure, revert — is accepted by the
kernel's own result check.

### How the first customer's workflows were classified

The first customer's thirteen governance and audit workflows were the source. Each was classified as:

- **PRODUCT** — any repository benefits: ported as (or folded into) a kernel route above, with every command rewritten
  to a `cotterpin` verb;
- **CONSUMER** — it encodes that customer's own conventions: it is not shipped; the section after the table shows how a
  repository keeps such a workflow as its own route.

| input | decision | shipped as | reason |
|---|---|---|---|
| `delivery-audit-shard` | PRODUCT | `delivery_audit` | the census, audit, refute, sample, record loop is the product's delivery-audit doctrine; the customer's ledger engine, shard map and medical-boundary field became a generic ledger tool, per-repository scope declarations and the scope's `policyDocs` |
| `delivery-audit-drive` | PRODUCT (folded) | `delivery_audit`, one run per scope | driving scopes in sequence, S1 first, is the kernel's own loop: one run per scope, each committing and re-planning until no capability needs a verdict; the completeness critic is replaced by a census of every declared scope file |
| `delivery-audit-grind` | PRODUCT (folded) | `delivery_audit_fix` with `reviewBeforeEdit` and `decisions` | a read-only disposition review before edits, and decisions supplied by the developer, are generic; the customer's per-shard contention cap and named leftover directories are its own history, replaced by leases and file-disjoint bins |
| `delivery-audit-fix-shard` | PRODUCT | `delivery_audit_fix` | spec-anchored fixes, validate-never-guess, no destructive change, an independent review, one verification: generic; its build commands and architecture rules belong to the customer and its language pack |
| `delivery-audit-fix-shard-parallel` | PRODUCT (folded) | `delivery_audit_fix` bins | file-disjoint bins in parallel are now the fix route's own shape, in one checkout, at the Box Budget width |
| `doc-maintain` | PRODUCT | `doc_maintain` | config-driven managed documents (project, refresh, audit) with generated numbers and independent verification apply to any repository |
| `okf-refresh` (+ its `KERNEL-OKF-REFRESH` manifest) | PRODUCT | `okf_refresh` | the OKF library ships in the product; refresh and version migration are the same in every repository |
| `workflow-governance-audit` | PRODUCT | `route_governance` | every repository that runs routes needs them reviewed; the structural checklist became `cotterpin tool route-check`, the hand-maintained route list became enumeration, the receipt became `route-scope`/`route-receipt` |
| `release-triage-shard` | PRODUCT | `release_triage` | classifying not-delivered capabilities by recorded harm before a release is generic once the ledger is the product's; the merge agent became a tool |
| `operator-instruction-audit` | CONSUMER | — | it reads one operator's private session transcripts from the provider's store outside the repository, against that customer's watermark and queue files, and dispatches into that customer's routes; sending private conversations to a provider needs its own consent design before any product version |
| `queue-staleness-adversary` | CONSUMER | — | it re-measures rows of the customer's own operator-queue file format; the generic doctrine (re-derive a claim at HEAD, "moved" is not "gone") ships in the `claim-verification` skill |
| `queue-config-mapper` | CONSUMER | — | it maps the customer's queue rows onto the customer's own check-configuration corpus |
| `author-new-refuter` | CONSUMER | — | it searches the customer's own check-configuration corpus; the generic rule (look for an existing check before authoring a new one) ships in the `gate-authoring` skill |

### Keeping a workflow of your own (extension example)

A CONSUMER workflow stays in your repository as your own route, registered in the standard layout and run by the same
kernel. For example, a backlog-staleness review of your own backlog file:

```text
.claude/workflow-routing.json      {"routes": [{"task": "backlog_staleness", "workflow": "backlog-staleness.js",
                                                 "runbook": "backlog-staleness.md"}]}
.claude/workflow-contracts.json    {"routes": {"backlog_staleness": {"resultEnvelope": ["runId", "worktreeRealpath",
                                     "branch", "baseHead", "stages", "verificationEvidence", "complete", "blockers"],
                                     "skills": ["claim-verification"]}}}
.claude/workflows/backlog-staleness.js
.codex/workflows/backlog-staleness.md
.claude/workflows/harness-config/ACME-BACKLOG-STALENESS.json
```

Use a task name the product does not ship. Run `cotterpin tool route-check --task backlog_staleness` before the first
run: it applies the same rules as above to your route — including the object `verificationEvidence` rows — and
`route_governance` reviews it alongside the product's routes from then on.

### Limits

- The route tools read a repository's own routes from the standard layout (`cotterpin.sdk.STANDARD_LAYOUT`); a
  repository that overrides its layout is reviewed for the product's routes only.
- `delivery_audit` audits what a scope declares. A capability in a file no scope's `paths` or `docs` match is never
  enumerated: declare scopes that cover the code you ship.
- A verdict's staleness is the byte digest of the files it rests on. A behaviour change that does not touch any of
  them (a configuration in an undeclared file) does not reopen it; list every file a verdict rests on in its evidence.
- `delivery_audit_fix` verifies with the checks `.cotterpin/checks.yaml` declares. With no declared checks the pass is
  refused, never assumed green.
- The website verbs start the audit routes: `cotterpin audit --scope <SCOPE>` starts `delivery_audit` and
  `cotterpin fix --scope <SCOPE>` (after you approve, or with `--yes`) starts `delivery_audit_fix`, each in its own
  checkout, and print the `drive` command; `--dry-run` shows the run without starting it. Without `--scope` they stay
  the read-only report and the mechanical fixes. The other kernel routes start through the kernel as each runbook
  shows.

### Routes first: what the agent hook says about dispatching work

The agent hook ([hooks/coordination-rules.md](hooks/coordination-rules.md)) holds an agent to these routes:

- **A route runs as a run.** Starting a shipped route's workflow directly (its `cotterpin-*.js` as a Workflow call), or
  a long fan-out of sub-agents, outside a Cotterpin run is refused (`route-outside-harness`): nothing reserves the
  machine's capacity for it, resumes it, or lands its work. Start it with `cotterpin audit --scope <SCOPE>` /
  `cotterpin fix --scope <SCOPE>`, or as a campaign: `cotterpin campaign run --agent claude|codex|grok
  --verify-command "<command> {modules}"` runs the fan-out itself, one agent per unit in its own run worktree.
- **A workflow is started by its path.** A Workflow call by `name` alone runs the copy of the script last committed,
  not the one on disk; it is refused until `scriptPath` is given (`workflow-requires-scriptPath`).
- **Routes before custom agents.** A writing sub-agent with a hand-written brief is refused (`workflow-first`) unless
  a product route's persona is dispatched or the agent runs inside a Cotterpin run. Nothing the agent can write itself
  — a file, a line in its brief — is an exception: record the missing route with `cotterpin decisions append`, and only
  a person's signed approval of that exact dispatch (`cotterpin approve <id>`) lets it run.
- **Never into a staged commit.** A writing sub-agent or a workflow is refused while files are staged
  (`dispatch-while-staged`): its writes would land in that commit, or the route would see the dirty index and spend its
  wave writing nothing. Land or unstage the commit first, or give one Agent `isolation: "worktree"` (a path named in
  the brief isolates nothing).
## Angular pack workflows

Written for the product (no customer input): ten routes in `cotterpin_pack_angular` (`angular_upgrade`,
`angular_node_ts_upgrade`, `angular_standalone_migration`, `angular_add_feature`, `angular_add_api_service`,
`angular_rxjs_upgrade`, `angular_strict_fix`, `angular_lazy_bundle`, `angular_add_e2e`, `angular_npm_audit_fix`), each
with its own manifest and runbook, all run by ONE workflow, `workflows/angular-task.js` (Preflight, Apply, Judgement,
Review, Verify, Closure), whose deterministic steps are `cotterpin pack angular task-apply|task-check|task-verify|
task-revert`. Every route passes `cotterpin tool route-check`; each is run end to end on a real workspace in the
deferred tier. How to run them, and what each one verifies: [PACK-ANGULAR.md](PACK-ANGULAR.md).

## Java pack workflows

Ported to `cotterpin_pack_java` as product routes (each: `routes/<task>.json`, `manifests/<ID>.json`,
`workflows/<name>.js`, `runbooks/<name>.md`, its personas under `agents/`, and its deterministic tools as
`cotterpin pack java <command>`). How to run them: [JAVA-WORK-ROUTES.md](JAVA-WORK-ROUTES.md).

### Classification

| Input (first customer) | Decision | Product route / reason |
|---|---|---|
| `confirmed-bug-fix.js` + manifest `JAVA-BUG-FIX` | **PACK** | `java_bug_fix` / `JAVA-BUG-FIX`. The customer's route produced unapplied patch candidates and left RED/GREEN proof and landing to a human; the product folds both into one deterministic lane (`bugfix-lane`: RED without the fix, GREEN with it) and the kernel commit. The haiku artifact validator became a pack tool (`bugfix-check`). Python-unittest bugs are not ported: the Java pack fixes Java. |
| `refactor-integration-validate.js` | **PACK** | `java_refactor_integration` / `JAVA-REFACTOR-INTEGRATION`. The customer's fixed two-module reactor became a scope planned from the Facts store's build model (changed modules plus every dependent); its route check and three relays became ONE tool (`refactor-verify`) and one relay. Validate-only: landing `no-frontier`. |
| `scanner-drain.js` | **PACK** | `java_gate_drain` / `JAVA-GATE-DRAIN`, driving the gate runtime (`cotterpin gate`). The customer's scanners and baselines are its own; the product drains a shipped gate's findings, one unit per file, re-measured by `cotterpin gate` in `gate-drain-check` and in the lane. |
| `codex-destub-convert.js` | **SUPERSEDED** | A thin delegate to de-stub convert mode. The shipped de-stub route `java_test_destub` (`JAVA-TEST-DESTUB`) runs convert and repair itself; nothing is ported. |
| `audited-defect-fix.js` | **SUPERSEDED** | A thin delegate to de-stub repair mode: `java_test_destub` with `mode: repair`. |
| `codex-test-audit.js` | **SUPERSEDED** | A thin delegate to de-stub audit mode. The product audits a de-stub branch with its immutable receipts (`cotterpin pack java destub-receipt closure`); a fresh Maven rerun can never replace a receipt. |
| `svc6-drain-shard.js` | **CONSUMER** | Drains the customer's controller-layering rule, which encodes its conventions rather than a universal defect (`GATE-PACK-V1.md` §5 lists it as a customer convention). The product's generic equivalent is `java_gate_drain` over any shipped per-file gate. |
| `gate-crystallise.js` + manifest `JAVA-GATE-FROM-FINDINGS` | **CONSUMER** | Authors scanners from the customer's gate configurations into its own `scripts/`. Product gates are pack modules authored by the pack (`GATES.md`, "Adding a gate") and run by `cotterpin gate`; there is no repository-authored gate surface to port onto. |
| `tooling-build.js` + manifest `JAVA-GATE-BUILD` | **CONSUMER** | The customer's seven-stage landing of its own gate-configuration backlog (its index, archive custody and commit manager). Same reason as above. |
| `scanner-cache-retrofit.js` + manifest `JAVA-SCANNER-CACHE-ADD` | **SUPERSEDED** | Retrofitted result caching onto the customer's scanners. The gate runtime caches every gate's results itself, content-addressed (`GATES.md`, "Result cache"); nothing is ported. |
| `pre-deploy-validate.js` | **CONSUMER** | The customer's deployment gate, schema-migration ratchet and held-path parser: deployment is outside the product. |
| manifest `JAVA-SHARD-AUDIT` | **CONSUMER** | The customer's capability delivery audit (its ledger, knowledge bundle and audit register), driven by a customer harness profile. |
| manifests `JAVA-SHARD-FIX`, `JAVA-SHARD-FIX-SEQUENTIAL` | **CONSUMER** | The fix lanes of that same audit register and its per-shard configuration. |
| manifest `JAVA-CANDIDATE-LAND` | **CONSUMER** (the behaviour is already PACK) | The manifest pins the customer's registered repository id and action for the hardened-mode root supervisor. The product behaviour — the static-result bridge and its commit/finalise lifecycle — already ships as `cotterpin_pack_java/bridge.py`; a hardened-mode repository registers its own manifest naming its own repository id. |

### Speed review (ADR-005 F13)

Every ported route passed the review before it shipped:

| Check | `java_bug_fix` | `java_gate_drain` | `java_refactor_integration` |
|---|---|---|---|
| Shards on a declared unit boundary | one bug (`units.by: class`), file-disjoint by plan | one flagged file (`units.by: file`) | one validation (`units.by: module`) |
| Fan-out width | the Box Budget's `agent` width (serial without consent) | the same | none needed |
| Single-command agents folded into pack tools | artifact validator → `bugfix-check`; RED/GREEN proof → `bugfix-lane` | scanner re-measure → `gate-drain-check`; measure + compile → `gate-drain-lane` | route check + compile + test + ran-proof (four agents) → `refactor-verify` (one relay) |
| Reads facts instead of rediscovering | module, type, existing tests of the class | module of each flagged file | build model (reactor dependents), test index |
| Verification scope declared for batching | `test`, affected modules | `compile`, affected modules | `test`, the planned reactor |
| Fail fast | one targeted retry of failing bugs; unconfirmed diagnoses refused and excluded | one targeted retry; refused files excluded | unknown/ambiguous/empty tests refused at plan time |
| Lands through | the kernel commit route (`"commitRoute": "product"`) | the kernel commit route | nothing to land (`no-frontier`) |

### Receipt transport (CONTRACT-6)

Every terminal of every shipped Java workflow returns `verificationEvidence` as OBJECT rows — the registered transport
for `claude-cli-workflow`. `tests/packs/java/test_java_work_route_transport.py` drives each work route to every kind of
terminal under node and passes each result through the kernel's own receipt normaliser, and statically scans every
shipped Java workflow, so a string row fails before any run instead of losing a run's work at the last step.

## Terraform / AWS pack workflows

Written for the product (no customer input): ten task routes in `cotterpin_pack_terraform` — `terraform_eks_upgrade`,
`terraform_ec2_patch`, `terraform_redis_create`, `terraform_rds_postgres_create`, `terraform_aws_provider_upgrade`,
`terraform_s3_secure_bucket`, `terraform_vpc_create`, `terraform_iam_oidc_role`, `terraform_import`,
`terraform_moved_refactor` — share ONE workflow, `terraform-task.js`, with one route stage vocabulary and three
personas. How to run them, what each changes and what its offline plan must show: [PACK-TERRAFORM.md](PACK-TERRAFORM.md).

| Check | the ten Terraform task routes |
|---|---|
| Shards on a declared unit boundary | one module directory per run (`units.by: module`); one writer per judgement file, file-disjoint |
| Fan-out width | the Box Budget's `agent` width fitted to the routing budget (serial without consent) |
| Single-command agents folded into pack tools | identity preflight + recipe → `task-apply` (one relay, no separate preflight agent); scope + residue + gates + fmt + init + validate + tflint + test + offline plan + frontier → `task-verify` (one relay, resumable with exit 3) |
| Reads the plan instead of rediscovering | the sealed plan by digest (the base commit's files, never the working tree) |
| Verification scope declared for batching | `compile`, affected (validate, lint and the offline plan are static proof; the unit's own `terraform test` files run when it has any) |
| Fail fast | a skipped EKS minor, an unapproved instance replacement, a wildcard OIDC subject or action, and malformed parameters refuse at plan time; one targeted repair round for `terraform validate` errors |
| Lands through | the kernel commit route (`"commitRoute": "product"`), trailer `COTTERPIN-TERRAFORM-TASK` |

Every terminal returns object `verificationEvidence` rows; `tests/packs/terraform/test_terraform_task_route.py` drives
the workflow under real node to each terminal and checks its stage ledger and envelope against the manifest and route.
