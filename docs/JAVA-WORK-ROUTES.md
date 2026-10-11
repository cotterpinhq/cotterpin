# Java work routes: bug fix, gate drain, refactor integration

Three routes of the Java pack that change or check existing code. Each plans its work deterministically from your
repository and the Facts store, writes in parallel into a separate run checkout, has every change reviewed by a
second agent, and lets ONE deterministic tool decide the outcome from real builds — never an agent's word. None of them
asks you to keep scripts or documents of your own. Why each exists, and what it replaced, is in
[WORKFLOWS.md](WORKFLOWS.md).

| Route | Start it with | It hands you |
|---|---|---|
| Fix confirmed bugs | `cotterpin pack java bugfix-start --bugs bugs.json` | one commit: each fix plus a regression test proven to fail without it and pass with it |
| Drain a gate | `cotterpin pack java gate-drain-start --gate <ID>` | one commit: the gate's findings fixed in up to 8 files (`--files` up to 32) |
| Check a refactor | `cotterpin pack java refactor-start --module <dir> --test <Class>` | a GO, or exactly which compile error or test failure stops it; nothing is changed |

Every route also has `-plan` (what it would do; changes nothing), `-drive` (run it; long — run it in the background)
and `-status`. Each prints the exact next command.

## Before you start

- Cotterpin must be installed in the repository and its files committed (`.cotterpin/`); a start refuses before it
  creates anything otherwise, and says so.
- The run checkout goes to your temporary folder only if you agree when asked (consents `bugfix.run-tree`,
  `gate-drain.run-tree`, `refactor.run-tree`); otherwise it is created inside your repository at
  `.cotterpin/runs/<run id>`, hidden from `git status` through `.git/info/exclude`. Run scratch lives under
  `.cotterpin/scratch/<run id>/`, hidden the same way. Nothing else is written outside your repository.
- Writers and reviewers run one at a time unless you consented to measuring this machine or declared a width in
  `.cotterpin/box.yaml` (see [CONSENT-AND-BOX.md](CONSENT-AND-BOX.md)).
- Builds run through the pack's Maven door (`cotterpin pack java maven`) with the build cache disabled. These routes
  need a Maven build: modules come from the `pom.xml` files in the Facts store, so a file outside any Maven module
  (a Gradle-only repository, for example) is refused at plan time with the reason.

## Fix confirmed bugs (`JAVA-BUG-FIX`)

Describe each bug in a JSON file (at most 16):

```json
[{"id": "order-total-rounding", "summary": "Order totals round half-down",
  "diagnosis": "core/src/main/java/shop/order/OrderTotals.java:8 rounds with RoundingMode.DOWN",
  "productionFile": "core/src/main/java/shop/order/OrderTotals.java",
  "testClass": "shop.order.OrderTotalsRoundingTest", "proposedFix": "round HALF_UP", "risk": "BILLING"}]
```

`proposedFix` and `risk` (`ROUTINE`, `SECURITY`, `BILLING`, `UNCERTAIN`; higher risks get a stronger model) are
optional. Each bug changes exactly one production file; its regression test class is created, or extended when it
already exists (existing tests are kept). What happens:

1. a writer re-reads the code and confirms the diagnosis — or refuses it, with the reason, and changes nothing;
2. it writes the smallest fix and the regression test, and `cotterpin pack java bugfix-check` checks them (a real
   change, a test with an assertion, no mocks, no existing test removed);
3. a different agent reviews each fix against the unfixed code;
4. `cotterpin pack java bugfix-lane` runs the regression tests WITHOUT the fixes — every one must fail — then WITH them
   — every one must pass — and only then hands the kernel the files to commit, with the trailer
   `BUGFIX-RECEIPT: <id>`. Any failure puts every file back.

Refused bugs are listed in the result's `refused` with the writer's reason; the others still land.

## Drain a gate (`JAVA-GATE-DRAIN`)

```text
cotterpin gate run CMP-NULL-1                        # what it reports today
cotterpin pack java gate-drain-plan --gate CMP-NULL-1
cotterpin pack java gate-drain-start --gate CMP-NULL-1 --files 8
```

One writer per flagged file fixes every finding of that gate at the source. `cotterpin pack java gate-drain-check`
re-runs the gates on the written file: the gate must report zero, no other gate may report more than before, and no
`cotterpin:allow` marker may be added — draining never suppresses. A writer that finds a finding is not a real defect
refuses the whole file with its evidence; allowing it (`// cotterpin:allow <ID> <reason>`) stays your decision. The
lane re-measures on the real tree, compiles the affected modules, and hands the kernel the files with the trailer
`GATE-DRAIN-RECEIPT: <id>`. Run it again until `cotterpin gate run <ID>` reports zero, then promote the gate in
`.cotterpin/gates.yaml` ([GATES.md](GATES.md)).

The plan measures your checkout, so a planned file you have changed — or a changed `.cotterpin/gates.yaml` — is
refused until you commit or stash it. Gates that read the whole tree cannot be drained file by file and are refused.

## Check a refactor (`JAVA-REFACTOR-INTEGRATION`)

```text
cotterpin pack java refactor-plan  --module core --test OrderServiceTest --test OrderControllerTest
cotterpin pack java refactor-start --since origin/main --test OrderServiceTest
```

The scope is every module you name (or that changed since `--since`) plus every module that depends on them; each
named test must be exactly one test class with test methods in that scope (a simple name is enough when it is
unique). One tool checks the run checkout, test-compiles the whole scope with `-am`, runs exactly those tests, and
requires a fresh Surefire report with tests > 0 and no failure for every one — a build that ran nothing is not a GO.
It validates what you committed (`--base`, default HEAD) and never changes anything.

## When something is refused

Every refusal says what happened, why, and the command that fixes it, on standard error, with exit code 2. A route
that ran and did not land reports `status` and `blockers` in its result; `-status` shows them for a run in progress.
