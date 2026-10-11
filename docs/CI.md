# Running Cotterpin in CI

CI mode runs Cotterpin with nobody watching. It never waits for an answer, it always prints JSON, and it never
measures the machine or acts outside the repository unless the job names that permission explicitly.

## The flags

| Flag | What it does |
|---|---|
| `--ci` | CI mode: no prompts, JSON output, and every consent question is answered **no** unless `--consent` names it — a choice stored on the CI machine does not count. Accepted anywhere on the command line. `COTTERPIN_CI=1` does the same. |
| `--consent <id>[,<id>...]` | Allow exactly these items (for example measuring CPU cores so work can run in parallel). Accepted anywhere on the command line. `COTTERPIN_CONSENT` does the same. A bare `--consent` approves every request of that one command. |

Answering **no** is always safe: Cotterpin takes the slower default (one item at a time, nothing measured). When it
skips something it prints, on standard error, what it skipped, why it wanted it, what it did instead, and the exact
flag that allows it next time.

Both settings are passed to every process the run starts, so a pack tool sees the same answer.

## The cache

Cotterpin keeps a shared store of work it can reuse (`~/.cache/cotterpin`, or `COTTERPIN_CACHE_DIR`). Every entry is
keyed by the exact bytes it was made from **and by the Cotterpin version**, so a restored cache can never give a
stale answer, and an upgrade starts afresh. `cotterpin ci cache-key` prints the key and path a CI cache should use:

| Field | Value |
|---|---|
| `key` | `cotterpin-<version>-<first 16 hex of the lock digest>` (`nolock` before the first lock) |
| `restoreKeys` | `cotterpin-<version>-` — any entry from the same version is safe to reuse |
| `path` | the store directory |

`--format github` prints `key=`, `restore-keys=` and `path=` lines for `$GITHUB_OUTPUT`; `--format azure` prints
`##vso[task.setvariable]` commands. Put the runner's operating system in front of the key yourself, as below.

## GitHub Actions

```yaml
jobs:
  cotterpin:
    runs-on: ubuntu-latest
    env:
      COTTERPIN_CACHE_DIR: ${{ github.workspace }}/.cotterpin-cache
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: python3 -m pip install "$COTTERPIN_WHEEL"   # your organisation's approved Cotterpin release
      - id: cotterpin-cache
        run: cotterpin ci cache-key --format github >> "$GITHUB_OUTPUT"
      - uses: actions/cache@v4
        with:
          path: ${{ steps.cotterpin-cache.outputs.path }}
          key: ${{ runner.os }}-${{ steps.cotterpin-cache.outputs.key }}
          restore-keys: ${{ runner.os }}-${{ steps.cotterpin-cache.outputs.restore-keys }}
      - run: cotterpin --ci check
```

## Azure Pipelines

```yaml
variables:
  COTTERPIN_CACHE_DIR: $(Pipeline.Workspace)/.cotterpin-cache

steps:
  - checkout: self
    fetchDepth: 0
  - task: UsePythonVersion@0
    inputs:
      versionSpec: "3.11"
  - script: python3 -m pip install "$(COTTERPIN_WHEEL)"   # your organisation's approved Cotterpin release
  - script: cotterpin ci cache-key --format azure
    displayName: Cotterpin cache key
  - task: Cache@2
    inputs:
      key: '"cotterpin" | "$(Agent.OS)" | "$(COTTERPIN_CACHE_KEY)"'
      restoreKeys: '"cotterpin" | "$(Agent.OS)" | "$(COTTERPIN_CACHE_RESTORE)"'
      path: $(COTTERPIN_CACHE_DIR)
  - script: cotterpin --ci check
    displayName: Cotterpin checks
```

## What the CI job runs

`cotterpin --ci check` runs every check your repository declares in `.cotterpin/checks.yaml` — including the slow
ones a developer's commit skips — so CI is where the full set runs. Its exit code is 0 when every check passed, 1 when
any did not, and 2 when the checks could not start; the JSON names each check and, for a refusal, the code, cause,
fix and command (see [the refusal catalogue](REFUSALS.md)).

To let the job measure the runner so work can run in parallel, name each permission:

```sh
cotterpin --ci --consent box.cores,box.memory check
```

## Exit codes and refusals

Every refusal in CI mode is one JSON object on standard output with `ok: false`, the `error` code, the `message`,
and an `explain` object holding `cause`, `fix`, `command` and `more` (`cotterpin explain <code>`).
