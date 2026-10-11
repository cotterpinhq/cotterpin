# How a run commits, warms its checkout and picks its workers

This page covers what happens at three points of a task run that you might otherwise only notice when something goes
wrong: how the run commits its own change, what happens when that commit is refused, how the checkout is warmed before
the run starts, and which worker instructions the run's steps follow.

## The run commits through `cotterpin commit`

A task shipped with Cotterpin (for example the Java de-stub task) commits the files it changed with the same command
you use by hand, `cotterpin commit`, run inside the run itself:

1. your repository's commit-tier checks (`.cotterpin/checks.yaml`, `tier: commit`) run on exactly the staged files;
2. sibling worktrees are checked for colliding uncommitted copies;
3. `git commit` runs, with your own git hooks as usual;
4. the deferred checks start in the background and the push gate waits for their verdict.

You do not need a commit script in your repository. A task definition says how it commits with exactly one of:

| In the task's `driver` | Meaning |
|---|---|
| `"commitRoute": "product"` | commit with `cotterpin commit` (every task Cotterpin ships) |
| `"commitManager": "tools/commit.py"` | run your own commit script from this checkout, as `python3 tools/commit.py commit -F <message file>` |

Naming both, neither, or a script that is not in the checkout stops the run before anything is staged
(`cotterpin explain commit-manager-missing`).

The run's checks run inside the run's own machine reservation, so on a machine where you have not allowed live load
sampling (runs take turns) the run never waits behind itself. A commit script that calls `cotterpin commit` gets the
same treatment through the `COTTERPIN_PARENT_RUN_ID` variable the run sets for it.

## When the commit is refused

`cotterpin commit` exits with one of these statuses:

| Exit | Meaning | What the run does |
|---|---|---|
| 0 | committed | finishes the step |
| 75 | refused for a reason that clears on its own: a check could not get a machine reservation in time, or the staged files changed while the checks ran | keeps the change and tries the same commit again |
| anything else | the checks (or git) refused this change | stops with `COMMIT_REFUSED` |

A `COMMIT_REFUSED` run:

- keeps the first refusal line your checks printed and the end of their output — `cotterpin legacy ... status` shows
  them, so you never have to reproduce the failure to read it;
- frees what it was holding on this machine at the same moment it stops, so other runs can start;
- leaves its changed files in the checkout, listed under `uncommittedPaths`;
- remembers the refusal. The same change on the same commit is not tried again, by this run or a new one: the next
  attempt stops straight away with the first refusal's reason. Changing the files, or building on a newer commit,
  makes it a new attempt.

What to do: read the reason, fix it in the files or in your checks, then commit the run's files yourself:

```
git add <the uncommittedPaths>
cotterpin commit -m "<message>"
```

A commit script of your own can mark a refusal as "try again" by exiting with status 75; every other non-zero status
is treated as a judged refusal.

## Warming the checkout before a run

Just before a new run starts, Cotterpin tells each installed language pack that the run's checkout is ready. The Java
pack uses this to restore the compiled output it saved for that exact commit (the same restore that
`cotterpin pack java maven-cache restore` performs), so the run's first build compiles only what the run changes.

- Nothing is restored unless the saved output matches the commit, the JDK, Maven and the build files exactly.
- The output goes into each module's `target/`. If git does not ignore `target/`, nothing is restored and the run is
  told why (`outputs-not-ignored`): add `target/` to `.gitignore`.
- If warming left the checkout changed as git sees it, the run does not start (`cotterpin explain
  worktree-prepare-dirty`).
- `COTTERPIN_JAVA_BUILD_CACHE=off` turns the restore off.

What each pack did is recorded with the run under `worktreePrepared`.

## Which instructions each step follows

A shipped task names, for each of its steps, the worker instructions that step follows (for the Java de-stub task: a
writer, a reviewer and a relay that runs one fixed command). Cotterpin hands those instructions to the provider with
each dispatch, so the named workers are what actually run — nothing is installed into your repository or your user
settings. The instruction files are checked when the run starts and again on every step: a release whose instruction
files are missing or damaged stops the run (`cotterpin explain persona-missing`).

## The route's own checks, `--preflight` and `--rehearse` (wave nine)

Before the consumer's commit-tier checks, `cotterpin commit` judges the staged snapshot with its own relevance-gated
checks (each prints a row with its milliseconds; an excluded check prints `skipped (not relevant)`), waits — only with
box consent — while another build of the repository runs, and after the commit tier requires a green claim in the
message to cite this staged set's `Check-Receipt:` id. `--preflight` runs only the route's checks and records them in
`<git common dir>/cotterpin/commit/preflight.json` keyed by the index tree; `--rehearse` runs the whole commit tier and
commits nothing. The reference: docs/product/hooks/commit-and-packs.md.
