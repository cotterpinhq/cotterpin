# Run progress: `cotterpin status`

Every run records its progress as it goes: when each stage and each shard starts and finishes, how long it took, and
the tokens and cost it used. `cotterpin status` shows it.

```sh
cotterpin status                   # the most recent run in this repository
cotterpin status --run <run-id>    # a specific run
cotterpin status --watch           # refresh every 2 s until the run ends (--interval to change; Ctrl-C to stop watching)
cotterpin status --json            # the machine-readable summary
cotterpin status --repository path/to/repo
```

Example:

```
run destub-1004-a1 — running, 4m12s elapsed, about 6m05s to go
  ✓ plan           finished  0m35s  12,340 tokens  $0.18
  ▶ write          running   3m37s  shards 6/10 done, 3 running
  · review         waiting
spend: 120,400 / 2,000,000 tokens · $1.84 / $25.00
```

## What landed, and whether it is working

A run's `status` and `drive` answers end with `landed: <sha>` when the branch moved forward from where the run started,
or `NOTHING LANDED` — measured from git, never from the run's own report. A run meant to change the repository that
dispatched nothing, or wrote nothing, is reported **degraded** (`run-write-mode-zero-dispatch`), not completed.

Heartbeats carry the CPU used by everything below the run (`cpu: 41.2s across 7 process(es)`): CPU that keeps climbing
means the work is running, CPU that stands still means it is waiting.

## Time to go

The estimate comes from this repository's own history, never from a guess:

- a stage that is running with shards: the shards still to finish × the average time of the shards already finished
  (in this run, or in earlier runs if none has finished yet), divided by how many are running at once;
- a stage that is running without shards: the median time this stage took in the earlier runs, minus its time so far;
- a stage still waiting: the median time it took in the earlier runs.

If a stage that is still to run has never run in this repository, the time to go is shown as "not known yet" rather
than invented. It is known from the second run onwards.

## Where progress is kept

One append-only file per run inside the repository's git directory (`git rev-parse --git-path cotterpin/runs`), so it
is never a tracked file and never leaves the machine. Every line passes the redaction filter before it is written
(see [PRIVACY.md](PRIVACY.md)).

## When it refuses

| Message | Next step |
|---|---|
| `not a git repository` | run it from inside the repository the run was started in, or pass `--repository` |
| `no run has recorded progress in this repository yet` | start a run; run `cotterpin status` again once it has started |
| `no progress has been recorded for run <id>` | run `cotterpin status` with no run id to see the latest run |

Exit codes: `0` shown; `2` nothing to show (the message says why and what to run).
