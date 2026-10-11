# Observability: `cotterpin report` and the trajectory

An agent's behaviour comes from the whole system — the model, its instructions, the tools, and the rules Cotterpin
applies — not from the model alone. Change a rule or a route and the outcome changes even with the same model. So
Cotterpin keeps an ordered record of every decision it makes on an agent's behalf (the *trajectory*), and
`cotterpin report` measures the system from it.

Everything is local. The record lives inside your repository's git folder, the report reads it on your machine, and
**nothing is uploaded or sent anywhere**. See [Privacy](PRIVACY.md).

```sh
cotterpin report                          # the metrics, as tables
cotterpin report --json                   # the same, machine-readable
cotterpin report --since 7d               # 30m, 24h, 7d, 2w, or a date: --since 2026-10-01
cotterpin report --agent codex            # only this agent tool's sessions (claude, codex or grok)
cotterpin report --repository ../service  # another repository (default: here)
cotterpin report trajectory <session|run> # one session or run, step by step, in order
cotterpin report mark-fp <id> --reason "<why>"   # a person's verdict that a refusal was wrong (approved: below)
```

## What is recorded

One line per decision, in `<git common dir>/cotterpin/trajectory.jsonl` (one file for the repository and all of its
linked worktrees; never a tracked file; readable only by you). Past 32 MiB it is moved to `trajectory.1.jsonl` and a
new one starts, so it never grows without bound.

| What | Recorded by | What the line keeps |
|---|---|---|
| Every agent tool call Cotterpin's hook judges (Claude Code, Codex and Grok alike) | `cotterpin hook` | the event and tool, the command or file paths (redacted, clipped to 300 characters), what the agent met (allowed, refused, asked, advised, or let through by Watch), every rule that objected, and — after a shell command — its exit code and the commit it landed |
| Every `cotterpin commit` | the commit route | committed or refused, why, the commit, the time it took, each commit-tier check's outcome and whether its earlier result was reused |
| Every push the push gate judges | the push gate | each ref, its tip, the deferred verdict it found, allowed or refused |
| Every code-gate run | `cotterpin gate run` and the gate runtime | blocking findings per gate, cache hits and misses, enforce or Watch |
| Every consent question a person answered | the consent mechanism | which question, and the answer |
| Every approved `mark-fp` | `cotterpin report mark-fp --approval <pa-id>` | the refusal it names, the reason, and the approval that makes it a person's verdict |

The report also reads what Cotterpin already keeps elsewhere: the deferred verify's verdicts, the run journals and run
progress (`cotterpin status`), the events Watch let through, and the policy layer's action audit log
(`<git common dir>/cotterpin/audit/actions.jsonl`, in the same schema — below).

What is **never** recorded: your prompts, the agent's replies, any tool output (only the exit code and a commit id),
and any secret — every text passes WHOLE through the same redaction filter as every log line, and only then is it
clipped (a secret cut in two first would be too short for its pattern, and the half before the cut would be kept).
Only the first 64 KiB of a text is redacted, and the word that limit cuts through is dropped whole, with everything
after it: no piece of a secret at that edge can be carried into the kept text when its whitespace is collapsed.
A line that is not well formed (no string `id`, no numeric time) is skipped when it is read. Every line also names the working tree it came from (`checkout`). The report redacts every line again as it reads it.

`COTTERPIN_TRAJECTORY=off` stops all recording in that environment. Recording never changes what Cotterpin decides:
if the line cannot be written (a read-only git folder, a full disk) the hook, the commit or the push goes on exactly
as before.

Cost on the agent's hook path, measured on the release machine: one record takes about 0.3 ms once loaded; a whole
hook call (a fresh process per tool call) measured a median of 58.6 ms with recording switched off and 64.1 ms with it
on — most of the difference is loading the redaction filter.

## The metrics

**Refusals per rule and tier.** Every rule that refused (*enforced*), was let through because this machine is in Watch
(*watch*), asked a person (*asked*), only advised (*advised*), or — for the deferred verify — failed. Tiers:
`hook` (an agent action — its audit-log line is the same decision and is not counted again), `commit` (a
commit-tier check or worktree isolation), `push` (the push gate), `gate` (a blocking code-gate finding), `deferred` (a red deferred verify) and
`route` (a work route Watch let through).

**Guard false-positive rate.** Of the agent actions that were refused (enforced or watched), the share that is either

- *marked*: a person approved a mark of that refusal (`cotterpin report mark-fp <id>`, then `cotterpin approve`;
  the ids are listed under "Recent refusals"; a mark without a verified approval is never counted — see below), or
- *rerouted*: within 30 minutes the same session attempted the same intent again, it was allowed, and the tool did
  not then report a failure. The intent is what the action is for, not how it was written: the first command that
  does something, as the program and its first word that reads as a verb or a name (`git commit`, `make test`; a
  path or a file name is not part of it), with `cotterpin commit` counted as the same intent as `git commit`; for a
  file tool, the tool family and the file.

A reroute is a signal, not a verdict — rewriting a refused action into the safe form is also the guard doing its job —
so the report shows both counts, and per rule. A person's mark is the verdict.

**Operator interruptions.** Questions a person had to answer: agent-action rules that asked, the action log's
approvals, and consent questions — and the rate per hour of observed agent time (the sum of every session's first to
last record). Under a minute of observed time gives no rate.

**Time to commit and to push.** The commit route's wall time per landed commit; per session, the time from its first
record to its first landed commit; per pushed tip, the time from its commit until the push gate allowed it. Each as
median, 90th percentile and longest.

**Commit tier versus deferred.** Commits the fast tier refused; deferred verifies that came back green and red; and
the red ones whose commit had *passed* the fast tier — what slipped past it, with the verify's log.

**Cache.** Code-gate results served from the cache, and commit-tier checks whose earlier result for the same files was
reused.

**Task success.** Runs that landed a commit (a commit the route made for that run), finished without one (an audit,
say), stopped (failed or interrupted) or are still running; agent sessions that landed a commit — one the agent's own
`git commit` / `cotterpin commit` printed, or a commit record that names the session — and those that did not. A
commit is never credited to a session because it happened while the session ran: every record names the working tree
it came from (`checkout`), and a short id a tool printed is matched to the full id recorded in that same working
tree.

**Tokens and cost per landed change.** For runs, the tokens and cost the run recorded as it spent them. For agent
sessions, only with your consent (`report.transcripts`, below): the token counts each agent tool wrote in its own
session log. Cost uses `providers.prices` in `.cotterpin/policy.yaml` ([Providers and cost](PROVIDERS-AND-COST.md)):
a subscription is shown as paid by subscription, and a model with no price shows no cost — prices are never guessed.
Cache-read input tokens are priced at the model's input price, so an API-key cost is an upper bound.

**Licence.** Whether this machine enforces or watches, and why.

## Agent session logs: asked first

The agent tools — not Cotterpin — know how many tokens a session used. Reading that is reading files in your home
folder, so Cotterpin asks first, says what it reads and why, and remembers your answer
([Consent and the Box Budget](CONSENT-AND-BOX.md)):

| id | what | read from | if you decline |
|---|---|---|---|
| `report.transcripts` | the token counts and model names in the agent tools' own session logs, for the sessions this repository recorded — never the conversation text | Claude Code's transcripts (`~/.claude/projects`, or `$CLAUDE_CONFIG_DIR/projects`), Codex's session files (`~/.codex/sessions` or `$CODEX_HOME/sessions`), Grok's (`~/.grok` or `$GROK_HOME`) — only files inside those folders: a transcript path the hook recorded is used only when it (links resolved) lies inside its tool's folder, else the log is looked up there by session id | the report leaves tokens and cost out and says how to include them |

Claude Code repeats a message's usage on every content block; each message is counted once. Codex keeps a running
total; the last one is used. A Grok log is read when it carries the usual `usage` objects (`prompt_tokens`,
`completion_tokens`); otherwise the report says that tool's log does not show token usage.

```sh
cotterpin report --consent report.transcripts     # this time only
cotterpin consent grant report.transcripts        # from now on
```

## `cotterpin report trajectory <session|run>`

The ordered timeline of one agent session (its id, or the first characters of it) or one Cotterpin run: what was
attempted, which rule fired, what was asked and answered, what each commit, gate, deferred verify and push decided,
and what landed. A session's timeline holds what is LINKED to it, never what merely happened at the same time: its
own lines; the commits it landed (the commit its tool printed, or a commit record that names the session) and the
pushes and deferred verifies of those commits; and a gate run or consent question only when it came from one of the
session's own working trees while it ran. Several sessions often run side by side in different worktrees of one
repository and share one record, so another worktree's commits never appear in, or count for, this session. A run's
timeline includes its progress (stages, spend) and the commits made for it.

```text
Session demo-session (claude) — 6 step(s), landed: 6bf5a53
  2026-10-04 10:04:45  2a9a406055fd  agent (claude) PreToolUse Bash git commit --no-verify -m wip  ->  deny [git-hook-bypass, commit-route-only]
  2026-10-04 10:04:45  760409fb8c92  agent (claude) PreToolUse Bash cd .git  ->  ask [cd-into-git-dir]
  2026-10-04 10:04:45  1a39c5f48079  agent (claude) PreToolUse Bash cotterpin commit -m wip  ->  allow
  2026-10-04 10:04:45  fe80c13c7fd2  agent (claude) PostToolUse Bash cotterpin commit -m wip  ->  landed 6bf5a53
```

## The action audit log

The policy layer keeps a log of every action it judged and every approval command, at
`<git common dir>/cotterpin/audit/actions.jsonl` (outside a checkout, `<config dir>/audit/actions.jsonl`), in the
SAME schema as the trajectory — ONE schema for both, built by `cotterpin.kernel.trajectory.action_record`: `kind:
cotterpin-trajectory`, `schemaVersion`, `type: action`, `id`, `at`, `session`, `run`, `agent`, `checkout`, `tool`,
`tier`, `rules`, `outcome` (the audit's word: `run`, `approval-pending`, `approved-run`, `approved`, `declined` ...),
`decision` (what the agent met, in the trajectory's words), `digest` (of the exact action — never its text), `summary`
(the programs it runs, never their arguments) and `approval`. It is a separate file because it is a security record:
it is written whatever `COTTERPIN_TRAJECTORY` says, and it is what a one-use approval's spent state and a session's
enforcing history are read from ([Approvals](APPROVALS.md)).

The report reads it beside the trajectory. A hook decision's audit line is the same decision the hook's own trajectory
line records, so it is not counted twice; an approval command's line (a person approving or declining) counts as an
interruption and appears in the session's timeline. Every text field is redacted by the ONE output filter before it is
clipped, and again when it is read: any process can append to a file, so nothing in it reaches the report unredacted.

## Records only Cotterpin writes, verdicts only a person gives

The trajectory, its older generation, the Watch ledger and the audit log are guarded by the `approval-integrity` hook
rule (destructive tier, [Hooks](HOOKS.md)) — the same rule that guards the approvals store and the licence files:
writing, moving, linking or removing one by hand (the agent's file tools, a shell redirect, `tee`, `cp`, `mv`, `ln`,
`rm` of a record or of its folder, a glob such as `.git/cotterpin/*.jsonl`, `find -delete`, or inline code that
renames or rewrites one) waits for a person's approval. Reading them is fine.

A false-positive mark is a person's verdict, so it is made ONLY through Cotterpin's one approval mechanism
([Approvals](APPROVALS.md), [Security model](SECURITY-MODEL.md)):

```sh
cotterpin report mark-fp <id> --reason "a docs-only change"     # raises request pa-1234abcd; records nothing yet
cotterpin approve pa-1234abcd                                    # the developer, in their own terminal (sudo -k)
cotterpin report mark-fp <id> --approval pa-1234abcd --reason "a docs-only change"
```

The request is bound to exactly that refusal (`report-mark-fp:<id>`); approving it asks the operating system to
authenticate the developer and is signed by a key only root can read. The mark records the approval, and the report
re-verifies the signature and the binding every time it counts the mark. An agent can raise the request — it can never
approve it — so a mark an agent makes, through any wrapper, a forged terminal, or a line appended by hand that claims a
person, is listed apart ("marked by an agent, not a person — not counted") and never moves the rate. There is no need
to wait for your agents to be idle.

## Refusals

| code | when |
|---|---|
| `report-since-invalid` | `--since` was neither a time back from now nor a date |
| `report-target-unknown` | no recorded session or run has that name (or `trajectory`/`mark-fp` was given none) |
| `report-record-unknown` | `mark-fp` named an id that is not a recorded refusal |
| `report-record-unwritable` | the verdict could not be kept (recording switched off, or the git folder is read-only) |
| `report-mark-unapproved` | `--approval` names a request a person has not approved for exactly that refusal |

`cotterpin explain <code>` says the same, with the next command.
