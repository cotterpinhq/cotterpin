# Stopping, resuming, cleaning up, and dry runs

ADR-005 X11 (interruption and resume) and X17 (escape hatches). This page covers four commands — `cotterpin status`,
`cotterpin resume`, `cotterpin clean` and the `--dry-run` flag — and what happens to a run when your machine sleeps,
the network drops or you press Ctrl-C.

## What happens when a run is interrupted

Cotterpin saves a run's progress after every stage. The progress file is in your repository's shared git directory
(found with `git rev-parse --git-common-dir`, under `cotterpin/runs/<run>.json`). Every linked worktree of the
repository sees the same runs, and nothing is written to your working tree.

| What happened | What Cotterpin does | What you do |
|---|---|---|
| **Ctrl-C**, the terminal closed, or a request to stop | Saves which stage was running and stops (exit status 130). It removes and releases nothing: worktrees, claims on shared capacity and partial output stay where they are, because resuming needs them. | `cotterpin resume <run>` |
| **The machine slept** (lid closed) | Notices that the wall clock moved further than the machine's awake clock and carries on. The sleep does not count against any timeout. `cotterpin status <run>` shows each sleep. | Nothing |
| **The network dropped** | Retries the stage, waiting a little longer each time (up to 30 s between tries). If the network is still down after 5 minutes of awake time, the run pauses (exit status 75) instead of failing. | Once you are back online: `cotterpin resume <run>` |
| **A stage failed** | Keeps every finished stage and records the error. | Fix the cause, then `cotterpin resume <run>` |
| **The machine shut down mid-run** | Nothing could be saved at that moment, but every stage that finished before the shutdown was saved. `cotterpin status` reports the run as "stopped unexpectedly". | `cotterpin resume <run>` |

When you resume, the stage that was running when the run stopped is re-run from its beginning. Stages that finished
are never run again.

## `cotterpin status [run]`

With no run name, this lists every run that has saved progress in this repository, with its stage count and state.
With a run name, it shows:

- which stages are done and which are still to do;
- how many times the machine slept during the run, and for how long in total;
- how many network errors were retried;
- **every check that was skipped, and the reason for skipping it** — a check is never skipped silently;
- what is being kept so the run can resume;
- the command to run next.

`--json` prints the same information for scripts. Options: `--repository <path>` (the default is the current
directory).

## Runs that outlive their terminal, stay awake, and stand down when superseded

* `drive --detach` starts the driver detached from the process tree that launched it, so stopping an agent's
  background task (which kills that whole tree) no longer kills the run; its output goes to a log beside the run.
* Every run holds a sleep assertion for as long as its driver lives (`caffeinate` on macOS, `systemd-inhibit` on
  Linux). An unattended run that cannot hold one is refused (`run-sleep-assertion-missing`).
* A run whose repository lock changed, or whose declared inputs a commit since its start touched, is cancelled and
  cleaned up as `superseded` (`run-superseded`), with the command that starts it again on today's state.
* `cotterpin lease run <resource>... -- <command>` holds a reservation for exactly the command's duration, in its own
  process; a reservation taken from the command line must name a live owner that is not its own shell
  (`lease-owner-pid-required`).
* `cotterpin harvest --inventory` says what parked work (stashes, worktrees, patch files) is really worth: already
  upstream, applies, conflicts, or no longer applies — by patch identity — and how many lines are left.

## `cotterpin resume <run>`

Continues a stopped, paused or failed run from its last completed stage. The run re-runs the command that started
it, so you do not need to remember the original arguments. `cotterpin resume <run> --dry-run` shows which stages are
already done and which would run, and changes nothing.

`resume` refuses, says why, and tells you what to run instead, when:

| Situation | Next command |
|---|---|
| No run has that name here | `cotterpin status` lists the runs you can resume |
| The run already finished | Start a new run with a different name |
| The run is still running in another process | `cotterpin status <run>`, or stop it with Ctrl-C first |

## `cotterpin clean`

Removes what finished or abandoned runs left behind. It always shows the list first and asks before removing
anything.

It may remove only these:

- a worktree whose directory is already gone (only git's record of it remains; `git worktree prune`);
- a worktree created by a Cotterpin run that **finished**, where nothing in the worktree is uncommitted. A campaign's
  unit checkouts count as the campaign's: they sit inside the folder its run keeps (`.cotterpin/runs/<run>/units/`);
- that folder itself, with the run's logs, once every worktree inside it is removed and nothing inside it is kept;
- a worktree whose branch has **landed** on your default branch, where nothing in the worktree is uncommitted, and a
  local branch merged into the default branch that no kept worktree has checked out;
- a worktree whose work the branch you are on **carries**: its branch has commits of its own, not on the default
  branch, and every one of them is on the branch you are on (work stacked branch on branch). Any uncommitted change it
  still holds, untracked files included, is first saved as a patch in `.git/cotterpin/reverts/` (`git apply <patch>` on that
  branch brings it back); if the change cannot be saved, the worktree stays. Its branch is kept;
- a claim on shared capacity whose time ran out **and** whose process has ended;
- the saved progress of a finished run.

It never removes:

- your main checkout, or the checkout you are working in;
- a locked worktree;
- a worktree that Cotterpin did not create, unless its branch has landed or is carried as above;
- a worktree with uncommitted changes (it prints the `git -C <path> status` command so you can look), except a carried
  one, whose changes are saved first;
- anything a resumable run still needs. The worktree is listed as kept, with `cotterpin resume <run>` as the next
  command.

To give up a stopped run for good, use `cotterpin clean --abandon <run>`. The run's worktree and saved progress are
then added to the list, and `clean` still asks before removing them. This includes a stopped route run (such as a
blocked gate port), which keeps its state under `.git/cotterpin/harness/`. When several runs hold one worktree, the
kept line names every one, and its next command gives up all of them at once.

| Option | Effect |
|---|---|
| `--dry-run` | List only. Removes nothing and asks nothing. |
| `--yes` | Approve removing exactly the listed items without being asked. |
| `--abandon <run>` | Give up a stopped run (repeatable). |
| `--json` | Machine-readable output. |

**Consent.** Without `--yes`, `clean` asks for approval through Cotterpin's consent prompt when one is installed, or
otherwise on your terminal. Approval covers exactly the list shown; a different list asks again. Answering no,
giving no answer, or running in a non-interactive shell (CI, a pipe) without `--yes` removes nothing, and `clean`
then prints `cotterpin clean --yes` as the next command. Each item is checked again just before it is removed:
git refuses to remove a worktree that gained a change after the list was made, and a claim whose process came back
is kept.

## `--dry-run`

`--dry-run` shows what a command would do and does none of it:

- the **stages**, in order, marking the ones already done;
- the **units** each stage would work on (for example the classes or test suites it shards into);
- the **files** it would change, when the task declares them;
- an **estimate** of model tokens, and the cost when you set `COTTERPIN_PRICE_PER_MILLION_TOKENS` to your price per
  million tokens. A stage that does not declare its token use is named as unknown; it is not guessed.

A dry run writes no file, starts no process other than read-only `git`, dispatches no agent and contacts no
provider. A test enforces this by failing on any write, any other process and any network connection.

| Command | What the dry run shows |
|---|---|
| `cotterpin run ... --dry-run` | The supervised run's steps; nothing is sent to the supervisor or the provider |
| `cotterpin check --dry-run` | The checks declared in `.cotterpin/checks.yaml`; none are run |
| `cotterpin resume <run> --dry-run` | Done and remaining stages, and the command that would continue the run |
| `cotterpin clean --dry-run` | What would be removed and what would be kept |
| `cotterpin pack <id> <command> ... --dry-run` | The pack's own plan for that command. A command that cannot describe its steps in advance refuses; it is not run to find out. |
| harness `start` / `drive --dry-run` | The task manifest's stages (those the run has already proven are marked done), its declared `touches`, and its `estimate.tokensPerUnit` |

A task manifest makes its estimate exact by declaring `"estimate": {"tokensPerUnit": {"<stage>": <tokens>}}` and
`"touches": ["<path glob>", ...]`.

A long-running command built on Cotterpin's stage runner (`cotterpin.kernel.run_journal.StagedRun`) gets
`plan()` for free. A pack exposes the plan to `cotterpin pack ... --dry-run` by adding the command to a
`DRY_RUN: dict[str, Callable[[list[str]], RunPlan]]` table in its `cli.py`, next to its `CLI` table.

## Skipped checks and `git commit --no-verify`

Whenever Cotterpin skips a check (for example, a slow test suite deferred from commit time to the pre-push verify),
it records the check and the reason in the run's progress, and `cotterpin status <run>` lists both. A skip without a
reason is refused.

`git commit --no-verify` bypasses every commit-time check, and Cotterpin cannot prevent that. The deferred verify is
what catches it. Before a push, the pre-push hook installed by `cotterpin init` or `cotterpin hooks install` (both
ask first) reads the verdict of the deferred
verify, which ran every deferred check over everything you are about to push (`origin/<default>..HEAD`). A commit
made with `--no-verify` is included in that range like any other, so its checks still run. The push is refused,
naming the command and the log, until the verify is green. `git push --no-verify` skips that hook too; the CI
re-verification (ADR-005 X14) is the line that holds in that case.
