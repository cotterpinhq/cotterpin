# Test tiers: fast, deferred, and provider acceptance

Cotterpin tests its build tools for real. The Maven door, the Java build cache, the de-stub verify lane and the
Gradle adapter run a real JDK, real Maven and a real Gradle wrapper against small real projects. Every shipped
workflow also runs under real node. Real tools take seconds per test, so these tests run in their own tier, and the
commit gate stays fast.

| Tier | What it runs | Who runs it | How |
|---|---|---|---|
| **Fast (commit)** | the tests the STAGED change reaches, except the real-tool ones and the speed budgets, within a time budget; the rest is deferred, never dropped | `cotterpin commit`, before every commit (`.cotterpin/checks.yaml` → `tools/checks/run.py commit-delta`) | `python3 tools/ci/run_suite.py --tier commit --staged --budget 5` |
| **Deferred (full)** | every test the verified range reaches, the real-tool ones and the speed budgets (`tests/perf/`, in their own serial phase after the parallel workers) included; the whole suite as the backstop | the deferred verify (`cotterpin verify-deferred`, launched after each commit at the lowest CPU priority), which the pre-push gate and `tools/release/cut_release.py` require green for the exact tree; CI — each with `COTTERPIN_REAL_TOOLS=require` | `COTTERPIN_REAL_TOOLS=require python3 tools/ci/run_suite.py --tier full --delta <base>` |
| **Provider acceptance** | Claude Code, Codex and Grok, each in one real headless session: install, a refused destructive command, an approval round-trip and a gated commit, with a KMS-signed receipt | the operator, on purpose only, at the release cut | `python3 tools/acceptance/providers/run.py --run --kms-key <arn>` (see below) |

This is the F9 split (ADR-005): a check that runs a build or a test suite belongs in the deferred tier.

**Baseline, then only deltas.** A test file runs when the change reaches it and it has not already passed on exactly
these inputs. Each passing run leaves a receipt per test file: the file, every file it executes, the dependency locks
and the interpreter. A later run whose test file matches its receipt reuses it instead of running it, unless a data
file the test names changed since. The commit tier and the deferred verify both read and write the receipts, so the
verify after a commit does not run again what the commit just ran on the same tree. A real-tool test's receipt also
names the tools it runs (the JDK, Maven, Gradle, node, .NET or Terraform found on the PATH, and `JAVA_HOME` and the
like), so it runs again after a tool upgrade. A speed budget's receipt names every product file and the machine: it is
timed again only when the product, the budgets, the locks or the machine change.

**When the deferred verify runs.** By default, when you push: a commit starts no verify, so nothing competes with
your work. Push with `cotterpin push` (git push's own arguments pass through): it verifies everything the push will
send, several branches at once, waits for the result, and only then connects and pushes. A plain `git push` starts the
same verify but waits only 45 seconds for it, because a remote closes an idle connection; past that it is refused, the
verify goes on, and `cotterpin push` (or pushing again once it is green) finishes the job. Set `verifyOn: commit` in `.cotterpin/policy.yaml` to also verify after every commit, in the
background at the lowest CPU priority, for an earlier warning.

**What the deferred verify judges.** Only what changed since the nearest ancestor already verified green, not the
whole branch since the default branch. The push gate joins those verdicts into a chain: green only when every link is
green, running while any link runs, red when any link is red. The whole suite runs
only to measure the impact map for the first time, or when the build or a dependency lock changes. Every passing run
folds what it measured into the map, so a new test is selected precisely from its first run on.
`cotterpin verify-deferred --base X` still judges exactly the range you name.

**Your work first, and a busy machine said out loud.** While `cotterpin commit` runs, the repository's background
verifies and the test workers they started are paused, and they continue when the commit ends. A verify that a newer
commit has superseded stops itself within 15 seconds. Each commit prints how long each of its stages took, and names
any stage that went over its budget. `cotterpin commit --metrics` shows the median and slowest of each stage over your
last 20 commits, from a file kept on your machine and never sent. When the machine is busy, the commit says so.
`cotterpin busy` lists what is running: Cotterpin's own verifies, each marked needed or stale (superseded, or already
covered by a green verdict), and other heavy programs, which Cotterpin never touches. It names the recommended step
every time:

| Command | What it does |
|---|---|
| `cotterpin busy stop --stale` | stops the verifies whose verdict nobody will read |
| `cotterpin busy pause` | pauses all of Cotterpin's background work until you resume it; a commit leaves it paused |
| `cotterpin busy stop --all` | stops all of Cotterpin's background work in one command; a push launches the verify it needs again |
| `cotterpin busy resume` | continues what you paused |

**Speed budgets (`pytest.mark.perf`, `tests/perf/`).** The deferred tier also times the real CLI in a temporary
repository: the p95 of a `cotterpin hook` call, the import cost of the hook path, a cold `cotterpin --version`, the
commit tier for a docs-only and a one-module change, and the warm gate cost per changed file. Each is held to the
speed-integrated baseline plus at most 10 % (`tests/perf/budgets.json`: the baseline commit, the limit, and one
recorded measurement with its machine profile). Because absolute times move with the machine's load, the test exports
the baseline commit from history (`git archive`) and measures it sample by sample in turn with the checkout (one sample
of each, the order alternating, each tree's bytecode compiled once into its own prefix as an install does), on the same machine at the same moment; each number of the checkout must stay within the baseline's number times the limit. The same module pins that the hook path
imports no licence service, single sign-on, admin, Paddle or gate module, and that `cotterpin commit` imports no single
sign-on or admin code. `python tests/perf/test_speed_budgets.py measure <checkout> <out.json>` records a baseline of
any checkout without asserting.

**The perf phase: the speed budgets run alone.** Interleaving cancels load that lands on both trees alike, but not
load that changes how the machine runs them: inside the 18-worker full suite (measured 2026-10-04) one hook call took
about four times its quiet time (184 ms against 47 ms) and the hook-path ratios read 1.12–1.13 against their 1.10
limit, while the same trees measured on a quiet machine read 1.08–1.09. So in the full tier `run_suite.py` never runs
a file under `tests/perf/` beside other tests. It runs every other selected file across the parallel workers first;
when all of them have exited, it runs the perf files in their OWN SERIAL PHASE: one pytest process, nothing else of the
suite running. The deferred verify, CI and the release cut all run `run_suite.py --tier full`, so all of them get it;
the commit tier deselects the perf tests by marker and has no perf phase.

Before the phase measures, it reads the machine's load: the Box Budget's live sample (`os.getloadavg` against the
logical cores), only with your `host.live-load` consent (`cotterpin consent grant host.live-load`, or
`COTTERPIN_CONSENT=host.live-load` for one shell or CI job). The parallel phase that just ended keeps the 1-minute load
average up for a while, so the phase waits for it to fall below half the cores (`--perf-max-load-per-core 0.5`),
sampling every 5 s for at most 180 s (`--perf-wait 180`). The log says what it found:

| Log line | Meaning | Verdict |
|---|---|---|
| `CI: PERF PHASE — machine quiet: load 3.10 on 18 cores (below 9) after waiting 45 s` | the load fell; the perf tests ran alone | each perf test's own result |
| `FAILED tests/perf/test_policy_budget.py - perf not measured: machine busy (load 12.40 on 18 cores; it must fall below 9, and did not within 180 s)` | the machine stayed busy (other work on it); nothing was timed | **failed** — every perf file, in the log, the summary and the JUnit report |
| `FAILED tests/perf/... - perf not measured: machine busy: the machine's load is not read without your consent, so it is not known to be quiet ...` | no `host.live-load` consent (or no load average on this platform): the machine is not known to be quiet | **failed** — every perf file; grant the consent |

A busy machine is a failure, never a skip: a skipped check looks exactly like a passing one, and a speed budget nobody
measured has not passed. A machine whose load cannot be read counts as busy (since 2026-10-10; before, it was measured
anyway). Commit again when the machine is quieter: the verify's perf phase is the only place the speed budgets run, and
the `perf-run-by-hand` guard refuses an agent's own run of them. `tests/tools/ci/test_run_suite_perf_phase.py` pins, with real pytest
workers and the real load average, that perf tests never overlap another test and run in one worker after the others,
and that a busy machine fails each perf file with that reason and never runs it.

**Parallel.** `run_suite.py --workers auto` (the default) splits the selected test files across pytest workers —
longest first, each to the least-loaded worker, by the per-file durations the last green run of that tier recorded in
`~/.cache/cotterpin-ci/durations.json` (beside the impact map) — and runs as many pytest processes at once as the Box
Budget plans (`box.plan("light", n)`). That is one process, exactly as before, until you consent to measuring your
machine (`cotterpin consent`) or declare a width in `.cotterpin/box.yaml`; `--workers N` names it. Every selected test
runs exactly once at any width, any failure in any worker fails the run, a full backstop merges the workers' partial
impact maps, and the merged JUnit report holds every worker (`tests/tools/ci/test_run_suite_delta_and_shards.py` pins
the same verdict serial and sharded, against real git and real pytest).

## Which tests are real-tool tests

A test module that runs a real JDK, Maven, Gradle or node says so on one line:

```python
import pytest

pytestmark = pytest.mark.real_tool
```

`tests/conformance/test_real_tool_tiering.py` enforces this. A test that uses the real-tool fixtures
(`tests/support/real_tools.py`), that looks up `node`, `mvn`, `gradle` or `java` on the real `PATH`, or that runs a
workflow through a route-simulation kit's real-node entry point (`RouteSimulation` in `tests/support/route_testkit.py`;
`run_workflow`, `launch` or `node` in `tests/packs/java/work_route_testkit.py`), must carry the marker. The same test also runs a real pytest collection to prove the commit tier really leaves the marked tests
out, and it checks that every workflow the product ships is run under real node by a marked test.

| Real-tool tests | What they prove | Wall time (this machine, warm caches) |
|---|---|---|
| `tests/packs/java/test_maven_real.py` | the door with real Maven: green and failing compiles, an empty jar refused (exit 87), the agent digest of a real log, and selected tests judged from real Surefire XML by the strict parser (pass, fail, skipped, a selector that ran nothing refused with exit 88, a stale report never borrowed) | 11 tests, 25 s |
| `tests/packs/java/test_java_build_cache_real{,_restore,_staleness,_incremental}.py` (one module per concern, so the parallel runner gives each its own worker) | a real full compile admitted as a snapshot, then restored into a new worktree by clone (APFS clonefile on macOS) so that real Maven compiles nothing; after a copy that keeps the old timestamp, exactly the changed source is recompiled; the control without freshening keeps the stale class; every admission and restore refusal | 24 tests, 101 s |
| `tests/packs/java/test_destub_lane_real.py` | the de-stub verify lane end to end: real patch apply, the bounded Maven lane run detached, the receipt judging real Surefire XML, the reactor phase derived, closure from the real lease store | 2 tests, 10 s |
| `tests/packs/java/test_buildtool_gradle_real.py` | the Gradle adapter through a wrapper generated with `gradle wrapper`: compile, selected tests passing, failing, skipped, and a filter that matches nothing | 8 tests, 19 s |
| `tests/packs/java/test_java_{test_destub,generate,migrate}_route.py` | every shipped workflow executed under real node | 74 tests, 13 s |
| `tests/packs/java/test_java_{bug_fix,gate_drain,refactor_integration}_route.py`, `test_java_work_route_transport.py` | the Java work routes under real node, every terminal through the kernel's own result check | under node |
| `tests/kernel/test_route_*.py` | the kernel's six governance and audit routes under real node, against real git and the real `cotterpin tool` commands | under node |
| `tests/packs/java/test_java_worktree_prepared.py` | a snapshot really admitted by real Maven restored into a new run checkout by the kernel's `worktree-prepared` event; the run's first real build compiles nothing | real Maven |

**When a tool is missing.** A real-tool test whose tool is not on `PATH` is skipped, and the skip says what to
install. Set `COTTERPIN_REAL_TOOLS=require` (on CI and the release machine) to make a missing tool a failure
instead, so a missing tool cannot pass as a skip.

**Network.** Maven downloads any plugin or library missing from `~/.m2/repository`. The fixture pins versions a
machine that has built a Maven project usually already has. The first Gradle run on a machine downloads the pinned
Gradle distribution (once to generate the wrapper, cached in `~/.cache/cotterpin-tests/gradle`, and once by
`./gradlew` into `~/.gradle/wrapper/dists`) and JUnit into `~/.gradle/caches`. Later runs reuse all of them.

**Where test doubles remain, and why.** Some tests still use a recording `mvn` or `gradle`
(`tests/support/fake_maven.py`, `tests/packs/java/buildtool_testkit.py`). They test only what the door itself does
with its arguments, and what a real tool cannot report back or cannot be made to produce on this machine:

- option parsing and refusals before anything is queued;
- lease bookkeeping and receipt bracketing;
- the environment handed to the child process;
- a cache key built over a JDK whose `javac` bytes a test changes;
- a build-cache-extension restore line, and a failed classpath capture;
- a Gradle run that exits 0 without writing a report.

Each of these files says so in its docstring.

## Provider acceptance (spends your subscription)

The command the operator runs at the RC1 cut, from their OWN terminal (not inside an agent tool: an approval started
under one is refused by design), with the release installed (`cotterpin` on `PATH`), a current licence, approvals set
up once (`cotterpin approvals setup`) and an AWS session that may sign with the key:

```sh
python3 tools/acceptance/providers/run.py                 # the plan and its token cost; starts nothing
python3 tools/acceptance/providers/run.py --dry-run --json
python3 tools/acceptance/providers/run.py --run --consent acceptance.providers,provider.send \
    --kms-key arn:aws:kms:eu-west-1:019745375054:key/8b1e62a0-0e20-4a30-aa24-e67a5222ff25 --out ./acceptance-receipts
python3 tools/acceptance/providers/run.py --verify ./acceptance-receipts/*.json \
    --kms-key arn:aws:kms:eu-west-1:019745375054:key/8b1e62a0-0e20-4a30-aa24-e67a5222ff25
COTTERPIN_CONSENT=acceptance.providers,provider.send COTTERPIN_ACCEPTANCE_KMS_KEY=<arn> \
    python3 -m pytest tools/acceptance/providers -m provider_acceptance -s
```

`--provider claude` (repeatable) runs only the ones named. `--kms-key` is any ECC_NIST_P256 SIGN_VERIFY key your AWS
session may sign with (above: the Cotterpin release key, `alias/cotterpin/release`, whose signing needs MFA — see
[RELEASE.md](RELEASE.md); the receipt's signature input is bound to its own kind, so it
can never verify as a release or revocation signature). `--aws-profile` picks the profile.

For each provider CLI on `PATH`, in a fresh throwaway repository, ONE headless session in two turns. Every step is
judged from Cotterpin's own records, never from the model's reply:

1. **Install.** `cotterpin init`, a one-check commit-tier catalog pinned by `cotterpin update`, and `cotterpin adapters
   install <provider> --yes`, committed. Before any spend the provider must load what was installed: Grok's
   `grok --trust inspect --json` lists Cotterpin's project hooks, `claude plugin validate` accepts the installed
   plugin, and for Codex the installed `.codex/hooks.json` is there (`cotterpin adapters status` must say intact).
   Each session loads only that install: Claude Code with `--plugin-dir <the installed plugin> --setting-sources
   local` (none of your own hooks), Codex with `--ignore-user-config --ignore-rules --dangerously-bypass-hook-trust`
   and this one project trusted, Grok with `--trust` (Grok keeps that trust of the throwaway folder in
   `~/.grok/trusted_folders.toml`; it also runs the user-level Claude Code hooks it imports, which can change the
   outcome — the receipt then says which step failed).
2. **A refused destructive command.** Turn 1 asks the model to run `git branch -D acceptance-scratch`. The hook must
   refuse it: the branch is still there, and exactly one pending approval names this provider and exactly that
   command (tier destructive), with `approval-pending` in the audit log.
3. **An approval round-trip.** The runner shows the request and runs `cotterpin approve <id>` in your terminal: you
   type your password or use Touch ID (`sudo -k`, the root-owned signer). It approves only a request whose action is
   exactly that command. Turn 2 resumes the same session and the model runs the command again: the branch is gone,
   the request is `used`, and the audit log has `approved-run`. Declining stops the provider (exit 3).
4. **A gated commit.** In turn 2 the model writes `ACCEPTANCE.txt` holding a nonce, stages it and runs `cotterpin
   commit`. HEAD must be one commit on top of the install, holding exactly the nonce, and Cotterpin's trajectory must
   record that commit through the commit route with its commit-tier check EXECUTED and PASS, enforcing (not Watch).
5. **A signed receipt.** One JSON per provider under `--out`: the argv, prompt and output digests per turn, the
   session, the digest of the provider's native session record (Claude Code's transcript under `~/.claude/projects`,
   Codex's rollout under `~/.codex/sessions`, `grok usage <session>`), the usage, the kernel budget's spend and every
   observation above. It is signed with the KMS key (ECDSA P-256; the digest is signed, the key stays in KMS), read
   back, its signature verified against the public key KMS returned (kept in the receipt, so `--verify` works
   offline) and judged. A failing receipt is signed too.

Turns go through the kernel's provider door (`ProviderCallGate`): consent, secret redaction, the token budget the
fixture's `.cotterpin/policy.yaml` declares (twice the estimate), rate-limit backoff, and the charge.

**Preconditions, checked before anything is spent** (exit 2): `cotterpin` on `PATH`; this machine enforcing (the
real hook must refuse `git branch -D` in a throwaway probe repository — in Watch nothing is refused, so the tier
could not pass); approvals set up; the KMS key usable; the provider CLI on `PATH`.

**Cost.** Up to 310,000 tokens for Claude Code (model `haiku`), 260,000 for Codex and 260,000 for Grok: 830,000 for
all three. These are ceilings: each tool re-reads its own system prompt and tool definitions on every model request
(five tool calls in all), mostly from its prompt cache. On a subscription the calls cost $0.00 but count against the
plan's usage. With an API key, Claude Code on Haiku 4.5 ($1 per million input tokens, $0.10 cached, $5 output) costs
at most $0.35 if nothing were cached and typically a few cents; Codex and Grok cost what their default model costs
for that many tokens. The three KMS signatures cost a fraction of a cent. Wall time is a few minutes per provider plus
your approval. Set `COTTERPIN_ACCEPTANCE_<PROVIDER>_MODEL` to choose another model.

**Consent.** Each provider asks twice through the kernel's one consent mechanism. The first question is the tier's
own (`acceptance.providers.<provider>`, which states the token cost and what is installed and signed). The second
comes from the kernel door (`provider.send.<provider>`). If either is declined, or the shell is not interactive and
has no `--consent`, the provider is not started (exit 3). `--consent acceptance.providers,provider.send` approves both
for one command and is not remembered.

**Never by default.** The live tests live in `tools/acceptance/providers/`, outside `tests/`. They carry the
`provider_acceptance` marker, which the default pytest run deselects (`addopts` in `pyproject.toml`), and
`run_suite.py` never selects it. The runner is tested without any provider call: the plan and the refusals that need
no install in `tests/tools/acceptance/test_provider_acceptance_runner.py` (fast tier), and the whole tier — real git,
the real `cotterpin` install, hooks, approvals, commit route and check, a real P-256 signature — in
`tests/tools/acceptance/test_provider_acceptance_tier.py` (deferred tier). Three boundaries are stood in for, by name:
the provider CLI (`tests/support/provider_cli_double.py`, which runs the installed hooks where and when the provider
would), the person's `sudo` authentication (`tests/support/trusted_cotterpin.py`) and AWS KMS.

| Exit | Meaning |
|---|---|
| 0 | every selected provider passed |
| 1 | a provider ran and failed the check, or the install failed (the receipt says which step) |
| 2 | a precondition is missing (above); nothing was spent |
| 3 | consent or the approval was not given, so nothing (more) was started |
