# The commit route's own checks, holds, hand-back scripts and the Java and Terraform pack rules (wave nine)

This page is the reference for what wave nine added to `cotterpin commit`, the hook rules, the gate runtime and the
packs. Every refusal named here has a catalogue entry: `cotterpin explain <code>`.

## `cotterpin commit`: the route's own staged-set checks

Before the consumer's commit-tier checks run, the route judges the STAGED snapshot itself. Each check has a relevance
predicate over what the route already holds (the staged paths, the message, ONE `git status`), and each prints its own
row with its milliseconds. A check whose predicate is false prints `skipped (not relevant)`; a check that needs a
consent it was not given prints `skipped (no consent)` — a skipped check never looks like a passing one.

| Check | Relevant when | Refuses |
|---|---|---|
| `commit-staged-differs` | anything is staged | a staged file edited again after `git add` (fix: `git add <paths>`) |
| `commit-untracked-leftovers` | there are untracked files | `*.bak`, `*.orig`, `*.rej`, `*~`, `*.swp`, `.#*` left beside the work |
| `commit-message-sha-unknown` | the message holds a 40/64-hex token (either case) | a full commit id that names nothing (`sha256:<hex>` digests are not ids) |
| `commit-adapter-lock-split` | an adapter or `.cotterpin.lock.json` is staged | one of the pair staged, the other changed but not staged |
| `commit-new-handoff-doc` | a `.md` is added inside any `docs/` folder | a document named as open work (`handoff`, `hand-off`, `handover`, `resume`, `next-steps`, `todo`, `worklist`, `task-list`), or any document of five or more open checkboxes (`queue`, `plan`, `tasks`, `backlog` also name designs, so they are judged by content); names the `tracker:` of `.cotterpin/policy.yaml` |
| `commit-infra-delta-trailer` | anything is staged | a new ARN, KMS alias, queue URL or `s3://` bucket without an `Infra-Delta:` trailer. Not counted: lines under `tests/` or a `fixtures/` folder, the documented placeholder accounts (`111111111111`, `222222222222`, `333333333333`, `123456789012`, `000000000000`), and a literal the same diff removes elsewhere (a moved line) |
| `ledger-row-unreachable` | a delivery-audit ledger is staged | a row id matching no configured scope prefix, or several — judged from the STAGED ledgers and scopes |
| `commit-claim-unregistered` | an HTML page is staged and the website policy applies (`claims.yaml` at HEAD or in the index, or `website: true` in `.cotterpin/policy.yaml`) | a number, badge or testimonial not in the STAGED `claims.yaml` with source and evidence; no register at all; a staged deletion of the register while pages remain |
| `commit-fix-without-redgreen` | the subject is labelled a fix (`fix:`, `fix(scope):`, `bugfix:`, `hotfix:`, "fixes …") and code is staged | no regression test staged, or an ADDED test without a red/green record (`cotterpin redgreen`) for exactly this staged set (a fix that only edits tests needs a record for one of them) |
| `commit-unselected-suite` (after the commit tier, judged first by the closures it resolved) | `.cotterpin/checks.yaml` is in the index and code is staged | a changed test, or the tests of a changed source file (siblings by name, or tests naming its module), that no check of the catalog selects (its resolver's closure, or its selector); the row says how many are covered at commit and how many before the push |
| `okf-concept-not-staged` | `.okf/` is staged, or a staged file is a concept's `resource:` | the documented file staged without its concept |
| `okf-invalid` | a concept is staged | strict validation by the shipped validator fails |
| `okf-capability-slug-collision` | `.okf/` is staged | two concepts claim one `okf_capability_id` |
| `okf-asset-uncovered` | `.cotterpin/okf.yaml` is in the index and anything is staged | an added or changed asset (inside its `coverage` globs, outside `exclude`) that no concept names exactly in `resource:`, `covers:` or a `sources:` row. A glob in `covers:` covers nothing, so a new asset always needs a concept to name it. `cotterpin tool okf-coverage` lists every uncovered asset |
| `okf-duplicates-product-doc` | `.cotterpin/okf.yaml` is in the index and anything is staged | a staged concept that shares 12 or more consecutive prose words (code blocks aside) with a document under its `productDocs`: the concept should link to the document, so each fact lives in one place |
| `commit-machine-busy` | anything is staged, with `box` consent or `.cotterpin/box.yaml` | a build or test process of this repository still running after the bounded wait (`--busy-wait S`, default 600 s; the wait is recorded in the row) |
| `commit-gate-edit-affected-tests` | a gate or hook-rule module is staged (`gates/`, `kernel_gates/`, `scanners/`, `hooks/rules/`) | a test that references the changed module (or a changed function of it) and that no check covers; a covering deferred check is run NOW and must pass (a covering commit-tier check that passed counts) |
| `door-<id>` | an installed pack's commit door judges a staged path | see "Pack doors" below |
| `commit-code-gates` | a file is added or modified | a blocking finding of a commit-tier gate (the kernel's and every installed pack's) in a file the commit adds or modifies — the same run as `cotterpin gate run --staged --changed --tier commit`; a finding in a file the commit does not touch never blocks it (`commit-gate-blocking`). A gate run that cannot start refuses too (`commit-gates-unrunnable`). The row says how many gates judged how many files |
| `commit-claim-unreceipted` | the message says "N/N pass", "all tests pass" or "green" | no `Check-Receipt: <id>` trailer naming THIS staged set's id — or one whose receipt covers no check (an empty commit tier) or a check not passing |

THE MESSAGE IS THE ROUTE'S. The route reads exactly the bytes `git commit` will commit and hands git those bytes
(`-F <private file>`): `-m` values are joined as git joins them, `-F` is read relative to the repository root, `-F -`
reads standard input once, and `--trailer` lines are folded in. A message the route cannot judge first is refused
(`commit-message-unreadable`, exit 2): `-C`/`-c`/`--reuse-message`/`--reedit-message`/`--fixup`/`--squash`/`-t`/
`--template`/`-e`, `-m` combined with `-F`, an unreadable file, and no message at all — except `--amend --no-edit`,
which commits HEAD's own message (that is what is judged).

RED/GREEN RECORDS. `cotterpin redgreen --test <path> [--test <path> ...] [-- <command>]` proves the staged regression
tests fail WITHOUT the fix and pass WITH it: the green tree is the index as staged, the red tree the same index with
every staged non-test change put back to HEAD; each runs in a throwaway detached worktree (the command is the caller's,
or the one the installed pack's door gives — Java: `cotterpin pack java maven -- mvn -B test -Dtest=...`). The record
(`<git common dir>/cotterpin/redgreen/<index tree>-<digest>.json`) holds the index tree, each test's staged blob, the
paths taken away, the command and both exits; it covers a test only for exactly that index tree and blob.

`cotterpin commit --preflight` runs only these checks and writes `<git common dir>/cotterpin/commit/preflight.json`,
keyed by the index tree. `cotterpin commit --rehearse` runs the whole commit tier (the route's checks, worktree
isolation, the consumer's commit-tier checks) and commits nothing; it prints the `Check-Receipt:` id the real commit
will compute for the same staged set.

## Pack doors

A pack declares commit doors (`COMMIT_DOORS` in its `hooks.py`): its own check of the files a commit touches. The
commit route runs every relevant door after the commit-tier checks, within `commitDoorBudgetSeconds` of
`.cotterpin/policy.yaml` (default 20 s). A step the door's own measured history says will not fit, or one that runs
out of time, is DEFERRED with every step after it — its row says `deferred (over budget)` and names the steps, never
`pass`. The deferred verify runs `cotterpin door run --tier deferred` in its sandbox after the deferred-tier checks
(every door relevant to the pushed range, no budget); its failure is a red verdict. The push gate waits for that
verdict wherever a door is relevant to the repository, even with no `tier: deferred` check.

* Terraform (`door-terraform`): `fmt -check`, `init -backend=false`, `validate` and, with `*.tftest.hcl` files,
  `terraform test` on the changed modules (`terraform-check-failed`, `terraform-unavailable`). Step times are kept in
  `<git common dir>/cotterpin/doors/terraform-timings.json` (a deferred run records into the origin's).
* Java (`door-java-context-circular`, CONTEXT-CIRCULAR-1's dynamic half): always deferred (a Spring context costs
  20–60 s). In the verify, every module holding a `@SpringBootApplication` runs its own `@SpringBootTest` classes
  through the Maven door with `-Dspring.main.allow-circular-references=false` (a system property outranks every
  configuration file a test profile loads): `context-circular-failed`, or `context-circular-no-context-test` for an
  application module with no context-load test.

## The push gate

`protectedBranches:` in `.cotterpin/policy.yaml` names branches reached only through a pull request; a push to one is
refused (`push-protected-branch`), whether or not the repository declares deferred checks.

## Holds

`cotterpin hold add <path>` holds a path in THIS worktree (`$(git rev-parse --git-dir)/cotterpin/holds.json`, never
tracked); `cotterpin hold check --dirty` exits 1 naming every held path with uncommitted changes; `cotterpin hold remove
<path>` refuses while a sibling worktree has the path dirty. The Java pack's door refuses to package, install or deploy
while a held path is dirty (`build-held-path-dirty`). A deploy script outside Cotterpin adds one line before it builds:

```sh
cotterpin hold check --dirty || exit 1
```

## Hand-back apply scripts

A `*-apply.sh` written under the declared patches folder (`patches:` in `.cotterpin/policy.yaml`, default `patches/`)
must check whether the patch is already in, run the check the patch fixes and require it to FAIL first, apply with
`git apply`, restore on failure (`trap ... ERR`), rehearse the commit (`cotterpin commit --rehearse`) and accept
`--reapply`. The hook rule `handback-script-contract` refuses a script that lacks a step; `cotterpin verify-handback
<script>` checks the contract and then RUNS the script twice in a throwaway worktree (the first run must change the
tree, the second must change nothing).

## Deploy verification

`cotterpin verify-deploy --cluster C --service S --task-definition <family:rev>` succeeds only when the service's
PRIMARY deployment runs exactly that revision and its rollout is COMPLETED (`verify-primary-not-new-revision`).

## The audit library

`cotterpin audit query` (the same tool as `cotterpin tool audit-query`) is the one reader of the delivery-audit ledgers (counts and populations, always with the
population's size and filter). `idPrefixes` in a scope declaration routes row ids; `cotterpin tool audit-rekey --from
<prefix> --into <SCOPE>` moves orphaned rows. A FULL re-census of a scope whose ledger HEAD already holds is refused
(`audit-full-refused`) unless a person approved a request bound to `audit-full-reset:<SCOPE>`. `cotterpin tool
audit-invalidate` invalidates only verdicts the run's dispatched wave re-audits (`audit-invalidation-unreachable`).
`testIntegrity` is one of `DISCRIMINATES`, `DOES-NOT-DISCRIMINATE`, `NOT-PROVEN`, `NO-TEST`, with a reason.

## The gate runtime's contracts

* `gate-input-oversized`: in a narrowed run (the commit route), an input over the size limit that a gate's scope reads
  is a blocking finding, never a silent skip.
* `gate-population-zero`: a gate module may declare `POPULATION`; a full run over a repository its pack serves in which
  that population is empty is a blocking finding unless the module declares `VACUOUS_ALLOWED` with a reason. The
  standalone scanner prints `EVALUATED: <n> <subject>` before `TOTAL: <n>`.
* `gate-fixture-outside-population`: a pack gate's red fixture file must be a path the gate's scope selects.
* A fixture folder may declare the pack settings it runs under in `settings.json`.
* The same contract for a consumer's own `.cotterpin/checks.yaml` checks: a check declaring `population: <subject>`
  must print `EVALUATED: <n> <subject>` from its own process while it runs; no line fails it
  (`check-population-missing`), and `n == 0` fails it (`check-population-zero`) unless the check declares
  `vacuousAllowed: <reason>`.

## The Java pack

* `java-unscoped-test` (destructive: a person's signed approval of the exact command): a Maven run of the test phase
  with no `-Dtest`/`-Dit.test` selector — or a SELECTED run that already passed over exactly the same inputs
  (TEST-DELTA-SCOPE-1). The door (`cotterpin pack java maven -- mvn ...`) refuses the same commands: a full suite
  unless `COTTERPIN_FULL_SUITE_APPROVAL` names a request a person approved, bound to `java-full-suite:<reactor root>`;
  a green rerun unless `COTTERPIN_RERUN_APPROVAL` names one bound to `java-rerun:<reactor root>`. The door records
  each green scoped run in `<git common dir>/cotterpin/java/green-runs.json` (the canonical selection — goals in order,
  options sorted, output-only flags dropped — and the content id of the whole working tree); any content change
  re-admits the run, a touched mtime does not.
* The door's staleness is keyed on CONTENT and on UPSTREAM sources: in a tree its own builds compiled (no restored
  snapshot), every module source whose content differs from what the last green full-reactor build compiled is
  stamped before Maven runs, and so is every source of every module downstream of a changed main source (javac
  inlines an upstream constant; Maven's stale check sees only a module's own sources). An mtime-preserving copy can
  no longer leave a stale class looking current.
* `java-pl-without-am` (sensitive write): `-pl` without `-am`.
* New gates (advisory until calibrated on a corpus): OWNER-AUTHZ-1, CACHE-EVICT-TEST-VACUOUS-1, CONTEXT-CIRCULAR-1
  (static half; the dynamic half is the deferred door above), INFRA-FALLBACK-1, FIXTURE-VOCAB-1,
  SAFETY-CATCH-FAIL-CLOSED-1, CLIENT-AUTHZ-SOURCE-1 and HEALTH-WINDOW-1 — see GATES.md.

## The Terraform pack

* `terraform-operator-only` (destructive): `apply`, `destroy`, `refresh`, `import`, `taint`, `untaint`,
  `force-unlock`, `state`, `login`, `logout`, `workspace new|select|delete`, `init` with a backend, `plan` of a module
  with a remote backend, and Terraform Cloud API or `TF_TOKEN_*` use. Allowed: `fmt`, `validate`, `test`,
  `init -backend=false`.
* `cotterpin pack terraform check` — the same door by hand; in `cotterpin commit` it runs as `door-terraform` (above).
* Gates: KMS-IMMUTABLE-POLICY-READS-1 and TF-ACCOUNT-BOUNDARY-1 (the account boundary is the repository's own
  `accountBoundary` setting under `packs: terraform:` in `.cotterpin/gates.yaml`; the pack names no account).
