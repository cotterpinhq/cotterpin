# Agent coordination rules

How Cotterpin's hook keeps an agent honest when it **dispatches other agents**, **writes their briefs**, **ends a
turn**, and **starts a session**. Every rule below runs inside the one hook entrypoint (`cotterpin hook <event>`,
[HOOKS.md](../HOOKS.md)); each refusal has a code (`hook-<rule id>`) that `cotterpin explain <code>` explains, and a
person can change any rule for a repository with `cotterpin hook set <rule> advise|off --reason "<why>"` — a
protective rule only with their signed approval ([APPROVALS.md](../APPROVALS.md)).

What a finding does is decided by its **risk tier** ([SECURITY-MODEL.md](../SECURITY-MODEL.md)), never by the rule:
a *sensitive write* is confirmed by the developer (refused outright when nobody can answer, for example in CI or an
unattended repository); a *destructive* action waits for `cotterpin approve <id>`. Every dispatch and brief rule below
**refuses** — its tier is destructive, so the call is denied and a pending approval is recorded even with a person at
the keyboard, never the agent tool's click-through prompt; only a person's signed approval of that exact call lets it
run. At the end of a turn a finding **blocks the stop**: the agent is told why and continues.

## Text rules: one retry, with evidence

Rules marked **text** judge the words of the agent's final message, not a measured fact. They block the stop once. The
agent may stop again, and that stop is accepted only if the final message now cites evidence the session transcript
confirms — a command it ran this turn, in backticks, or `path:line` of a file it Read this turn. The acceptance is
recorded and shown at the next session start. A stop without evidence is blocked again, every time: a text rule is
never let through unevidenced (ruling 1). Each text rule first looks for the measurement its claim needs, so a turn
that measured before it claimed is never blocked.

## Dispatch and briefs (before an Agent, Task, Workflow, TaskStop or SendMessage call)

| rule | refuses | instead |
|---|---|---|
| `dispatch-while-staged` | a sub-agent or workflow that can write (any agent holding a shell or an edit tool, and every workflow) while files are staged for a commit — a path named in the brief isolates nothing | land or unstage the commit first; or give one Agent `isolation: "worktree"` |
| `route-outside-harness` | ANY Workflow (a shipped route's by name, a renamed copy, a custom script), or a sub-agent dispatch past this machine's agent width + 1 in one turn (the 3rd when the scan was declined), started outside a VERIFIED Cotterpin run (its marker names a live run record whose worktree holds the agent's folder). With `host.live-load` consent, also any sub-agent dispatch, or a Bash line that builds or runs a test suite, while the live load is at or over 80% of the cores or available memory is under 20% (everything already running counts, whichever turn started it) | `cotterpin audit --scope <id>` / `cotterpin fix --scope <id>`, `cotterpin campaign run`; for a heavy command, wait or `cotterpin lease run host:tests -- <command>` |
| `run-marker-forged` | a Bash line or a written program sets or passes `COTTERPIN_CHILD` / `COTTERPIN_PARENT_RUN_ID` / `COTTERPIN_CAMPAIGN_UNIT` (a plain read — `$COTTERPIN_CHILD`, `printenv` — is not) | start the work as a run; the run sets the marker |
| `workflow-requires-scriptPath` | a Workflow started by `name` alone (that runs the last COMMITTED copy of the script) | pass `scriptPath` |
| `workflow-first` | a writing custom agent with a hand-written brief; nothing the agent can write (a file, a line in its brief) is an exception | run the product route; record a missing route with `cotterpin decisions append`; only a person's approval of that exact dispatch (`cotterpin approve <id>`) lets it run |
| `brief-claim` | "there is no caller of X" (X a name, `file.py`, a dotted module or a path) with no enumeration beside it; "the operator approved X" without ITS OWN quotation (on the claim's line or the next line — a quotation elsewhere in the brief backs nothing) | `ENUMERATED: <command>` or the backticked listing; `UNVERIFIED:`; `OPERATOR SAID: "<their words>"` beside the claim |
| `brief-budget` | a builder or integrator brief with no `SPEED BUDGET:` block carrying a measured limit | add the budget with units |
| `reviewer-brief-verdict` | a reviewer's brief naming a prior verdict or the conclusion to reach | give the change, the claim and how to measure it |
| `brief-unpinned-head` | `git diff HEAD~1..`, "compare against HEAD" in agent-facing text | `{baseHead}` or a full commit id |
| `brief-citation-truth` | a cited repository `path:line` whose file is missing or shorter than the line | cite a line that exists |
| `taskstop-live-run` (destructive) | stopping a task whose process tree owns a working Cotterpin run (its command found in the run's ancestry with the shell's `'"'"'` quote escapes undone) | let the run finish, or cancel the run itself |
| `unattended-prompt` (destructive) | in an unattended session: an edit outside the session's checkout or run worktree, or a Workflow dispatch (each would wait on a prompt) | work inside the checkout; `cotterpin decisions append` for the rest |
| `self-report-without-witness` | after a sub-agent reported success without the `WITNESS: <path>` file its brief declared: the next write that depends on it | produce the witness, or `cotterpin blocker add self-report-without-witness "<why>"` |

`cotterpin brief check <file> [--kind builder|reviewer]` runs **the same function** the hook runs on a brief, so a brief
can be tested before it is sent; it exits 1 with each finding when the hook would refuse it.

`cotterpin probe --case NAME=COMMAND --control NAME=COMMAND` prints a verdict only after every declared negative
control FAILED; a probe without a control, or whose control passed, is refused (`probe-no-negative-control`).

### Ruling 3: fan-outs outside Cotterpin are refused

Cotterpin runs agent fan-outs itself: `cotterpin campaign run --agent claude|codex|grok` (or `--agent-command`)
dispatches each unit of a wave to an agent in its own run worktree, at the Box Budget's agent width
(`cotterpin.kernel.campaign.RUNS_AGENT_FANOUTS` is True). So `route-outside-harness` and `idle-capacity` **refuse**
(ruling 3 as amended 2026-10-05: no advice state). Inside a Cotterpin run (`COTTERPIN_CHILD`, which every campaign
agent is started with) neither applies, and `idle-capacity` never refuses a stop the operator asked for
(a clause of their latest prompt that BEGINS with a stop request — "stop here", "please pause" — never "do not stop" or "non-stop"; a sub-agent's brief never counts; no repository option widens it), as `idle-stop`. Neither rule is ever released by the loop guard: the block stands until the runs are driven.

## The task mirror

Every `TaskCreate`/`TaskUpdate` is appended to `<git common dir>/cotterpin/tasks.jsonl` (`task-mirror`); when a session
starts — including after `/clear` — the tasks still open are given back, within the memory index budget
(`task-reinject`).

## End of a turn (Stop and SubagentStop)

| rule | kind | blocks the stop when |
|---|---|---|
| `unverified-completion-claim` | text; measured after a commit | the reply says applied/verified/landed/unblocked/fixed and nothing after the turn's last change measured it (a preflight, `git rev-parse`/`log`, a test run, `cotterpin status`/`check`, a pack's door). After a commit this turn, or for "landed", only a green deferred verdict of HEAD's tree counts: running, red or absent blocks, and a retry never releases it (say "committed, verifying" instead). A repository that never ran a deferred verify keeps the measurement rule |
| `absence-claim-unenumerated` | text | the reply says something does not exist with no listing of its scope this turn (`ls`, `find`, `git ls-files`, `grep -r`, Glob/Grep) |
| `unlanded-work` | measured | the turn wrote files and leaves tracked changes, new files it wrote, patch files it wrote that still apply, or worktrees it wrote with uncommitted or branchless work — unless `cotterpin blocker add unlanded-work "<why>"` ran after the last change. With `toolRules.reapLanded`, also the parked work `worktree-add-budget` names (landed worktrees, merged branches, stashes, stray worktree-root entries), whatever the turn wrote |
| `diagnosed-not-fixed` | text; measured for a red verdict | a defect cited at `file:line`, or called pre-existing / out of scope, with no commit this turn and no decision request (`cotterpin decisions append`, a `DECISION:` line). Also: the turn ran a verify, push or commit and HEAD's deferred verdict is red, with no fix committed and no decision recorded — never released by a retry |
| `script-body-in-reply` | text | a shell block of 8+ lines, a shebang or `set -e` handed to the operator (write it to a file; reply `bash <path>`) |
| `operator-command-first` | text | the command the operator must run is not the first block, or the reply only points back to it |
| `idle-capacity` | measured (ruling 3) | queued runs wait for a driver and fewer agents work than `box.plan("agent")` allows; unless the operator's latest prompt affirmatively asked to stop (a clause beginning with a stop request; never released by the loop guard) |
| `idle-stop` | measured | the reply waits on an operator decision while queued runs or this session's open tasks can still go; unless the operator's latest prompt affirmatively asked to stop (a clause beginning with a stop request; never released by the loop guard) |
| `settled-ruling-reask` | text | a question matches a signed ruling in `.cotterpin/rulings.json` (its id, or 2 of its keywords) |
| `post-rc-classification` | text | open ADR-001/ADR-005 items are called post-RC, later or nice to have; an Edit or Write under `docs/adr` saying so is refused before it lands by its twin `adr-post-rc-edit` (same predicate) |
| `shard-by-letter` | text | "shard C" while the repository declares shard names (`.cotterpin/audit/scopes/`) |
| `gate-armed-overclaim` | text | "X is armed/blocking/enforcing" while X's own record says advisory, advise/off, unbound, armed=false or population 0 |
| `unmeasured-debt-claim` | text | counts of unique/unmerged/not-upstream work without this session's `cotterpin harvest --inventory` |
| `perf-numbers-on-landing` | text | the turn landed a `cotterpin/` change — pushed the branch, or opened or completed its pull request — and the reply has no before → after speed numbers. A commit on a branch whose coding is unfinished asks for none: measure once, at the end, on a quiet box |
| `commit-handback` | measured | the reply hands over a commit command while files are staged and the newest preflight (`<git common dir>/cotterpin/commit/preflight.json`) shows 0 blockers, or names a `-F` file that does not exist |
| `relaxed-permission-unannounced` | measured + text | a deny/ask rule in force at session start was removed, the turn wrote a path it covered, and the reply does not say it is "safe to restore" |
| `credential-request` | text | the reply asks the operator for a cloud or Terraform credential or token |
| `fanout-permission-ask` | text | the reply asks leave to fan out or work in parallel ("shall I fan out ... or one at a time?", "if you want"), or scopes fanning out to "the rest of this session" — fan-out is the default in every session |

## Session

* `unattended-preflight` — your prompt asking for an unattended or autonomous session declares the repository
  unattended for 12 hours (`cotterpin unattended status` shows it): from then on every question a guard would ask is
  refused with its reason instead, so the session never waits for a person. No approval is needed: the declaration
  only ever refuses more. `cotterpin unattended off` ends it.
* `auto-reconcile-dead-runs` — at session start, runs whose owner process is gone, that hold no reservation and whose
  worktree no longer exists are retired by the kernel, and the session is told which. A worktree holding work is never
  removed.

## The small verbs

| command | does |
|---|---|
| `cotterpin decisions append <item>` / `list` | appends to `<git common dir>/cotterpin/pending-decisions.md`, for the operator to answer in one pass |
| `cotterpin blocker add <guard> <reason>` / `list` | records why work cannot land or be proven now (`<git common dir>/cotterpin/blockers.jsonl`), with what it covers as measured then |
| `cotterpin rulings add <id> --question … --answer … [--keywords …]` / `list` / `show` | records a settled ruling with a person's signed approval (`--request` raises it; `--approval <id>` records it); an unsigned or edited ruling is ignored |
| `cotterpin brief check <file>` | the dispatch hook's brief rules, on a file |
| `cotterpin probe --case … --control …` | a verdict only once every negative control failed |

## Speed

Every rule costs at most 1 ms on a call it does not match; a dispatch call's PreToolUse stays within 150 ms at the
95th percentile (the brief rules a few ms, `dispatch-while-staged` one `git diff --cached`, `brief-citation-truth` at
most 64 file reads); all turn-end rules together stay within 150 ms per turn on a 5 MB transcript (one shared,
backwards parse); UserPromptSubmit and SessionStart add under 10 ms unless the prompt asks for an unattended session.
The budgets are tests in `tests/perf/test_coordination_budget.py`.
