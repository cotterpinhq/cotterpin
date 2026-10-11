# Consent and the Box Budget

Cotterpin runs work in parallel when your machine can take it, and one job at a time when it cannot. To know which,
it has to look at your machine — and it never does that without asking you first.

> "We MUST ALWAYS say WHAT we are going to do and WHY we need to do it. The developer can approve/decline. If decline,
> then we run in serial or always take the unscanned, default option." — operator ruling, 2026-10-04 (ADR-005 X21)

## What Cotterpin may measure

Each measurement is asked about separately. Every question says what is read, where from, why, and what happens if
you say no. The results stay on your machine.

| id | what | read from | why | if you decline |
|---|---|---|---|---|
| `box.cores` | processor cores, split into performance and efficiency cores | `os.cpu_count`; on macOS `sysctl hw.perflevelN.physicalcpu` / `hw.perflevelN.name` (or `hw.physicalcpu`) | how many builds, tests and scanners run at once | every job runs one at a time |
| `box.memory` | total physical memory | `sysconf(SC_PHYS_PAGES)` × `sysconf(SC_PAGE_SIZE)` | how many memory-hungry jobs fit without swapping | memory-hungry jobs run one at a time |
| `box.disk` | free space on the cache disk, and whether it is solid-state | `statvfs`; on macOS `diskutil info` for the disk type | how many isolated checkouts fit | checkouts are not sized to the disk |
| `box.calibration` | a short timed run (about one second) | a child process of the Python interpreter running Cotterpin | prices each kind of job, so a slower machine gets smaller batches | no timing; sizes use cores and memory alone |
| `host.live-load` | how busy the machine is right now: CPU load, free memory, checkouts in progress, whether other Cotterpin runs are alive | `host_statistics`, `sysctl` and `vm_stat` on macOS, `/proc/meminfo` on Linux, `os.getloadavg`, `pgrep` | before each new job and between batches, so a busy machine shrinks the work instead of freezing your IDE | the live load is never read; runs take turns (serial) |
| `report.transcripts` | the token counts and model names your agent tools wrote in their own session logs, for the sessions this repository recorded — never the conversation text | Claude Code's transcripts (`~/.claude/projects` or `$CLAUDE_CONFIG_DIR`), Codex's session files (`~/.codex/sessions` or `$CODEX_HOME`), Grok's (`~/.grok` or `$GROK_HOME`) | `cotterpin report` shows tokens and cost per landed change ([Observability](OBSERVABILITY.md)) | the report leaves tokens and cost out; everything else is shown |

Saying no is always safe: everything still works, just more slowly.

## Commands

```sh
cotterpin consent                 # list every measurement, its state, what it reads and why (same as `consent list`)
cotterpin consent list --json     # the same, machine-readable
cotterpin consent grant <id>      # allow one, e.g. cotterpin consent grant box.cores — any id the list shows,
                                  # asked about before or not (the doctor's probes, licence.service, ...)
cotterpin consent revoke <id>     # stop it; Cotterpin will not ask again until a release changes that measurement
cotterpin box [--json] [--repository PATH]
                                  # on a terminal, asks about anything you have not answered yet; then shows what was
                                  # measured and how many jobs of each kind run at once
cotterpin resources               # one live load reading; asks first (or refuses with the command to allow it)
```

Any command also takes these, for that command only (they are never written to your stored choices, and the processes
the command starts inherit them):

```sh
cotterpin <command> --consent box.cores,box.memory   # allow these measurements for this command
cotterpin <command> --consent toolchain              # a single word allows every id under it (toolchain.git, ...)
cotterpin <command> --consent                        # approve every request THIS command makes
cotterpin <command> --no-consent                     # decline everything for this command, even what you allowed
```

A bare `--consent` is explicit approval for one command: each request is still described (what, where from, why, and
what happens if you decline) before it runs, and nothing is remembered.

`COTTERPIN_CONSENT=box.cores,host.live-load` (or `none`) does the same for a whole shell or CI job.

### Measurements and one-off approvals

The measurements above are remembered once you answer (per version), and so is `memory.user`, the personal memory
store ([MEMORY.md](MEMORY.md)): keeping facts in your user configuration directory and listing them in each agent
session's starting index. Declined, nothing is written outside the repository and personal facts are neither kept nor
listed. Other requests approve one action — installing git hooks, sending code to a provider, removing an exact list
of leftovers, running a doctor probe, reading another agent tool's memory (`memory.import.<tool>`), sending similar
facts to a provider for review (`memory.assist.<provider>`). They use the same statement and the same flags, but an
answer covers that one request only and is never stored as a standing grant. The doctor's probes (`toolchain.*`,
`provider.sign-in`, `machine.disk`, `repository.stack-scan`) are the one exception you choose yourself: their
prompt's answer is still for that run only, but `cotterpin consent grant <id>` stores a standing yes for one ahead of
time (and `revoke` a standing no), which every later doctor and init honours, non-interactive ones included.

`cotterpin consent list`, `grant` and `revoke` read the whole catalogue (`cotterpin.kernel.consent.CATALOGUE`: the
kernel's measurements above, `licence.service`, `licence.sso`, `cache.shared`, `cache.gate-results` and the doctor's
probes), so every id that can be stored is listed with what it reads, why and what happens if you decline, whether or
not this command has used it yet.

Promoting a memory fact to a wider scope is NOT a consent: no flag, `--consent` or `COTTERPIN_CONSENT` approves it,
because an agent's own tool call can set all three. It raises a pending approval request that a person resolves with
`cotterpin approve <id>`: the operating system authenticates them afresh (`sudo -k`: password or Touch ID) and a
root-owned key signs the approval, which promote verifies ([MEMORY.md](MEMORY.md#scopes)). Setting that key up once
(`cotterpin approvals setup`) is itself a consent request (`approvals.setup`, asked each time, never stored): declined,
nothing is installed and nothing can be approved.

Consent is Cotterpin asking YOU before it reads or does something on your machine. Approving an AGENT's risky action
(a `git reset --hard`, a `--no-verify`) is a different mechanism with the same principle — say what and why, a person
decides — built for actions an agent asks for: pending approvals, `cotterpin approve <id>` at your own terminal,
where the operating system authenticates you afresh (`sudo -k`) and a root-held key signs the approval
([APPROVALS.md](APPROVALS.md)). Setting that key up (`cotterpin approvals setup`) is itself a consent request
(`approvals.setup`, asked each time, never stored): declined, nothing is installed and destructive actions stay
refused.

### Model routing choices

Two choices of [model routing](MODEL-ROUTING.md) are asked the same way: `route.provider-switch` (an override would
send a route stage to a provider other than the one you configured; declined, it stays on yours) and
`route.above-cap` (a stage would run above your `routing.cap`; declined, it runs at your cap). Unlike a measurement,
each is asked **per stage and per run** and never remembered: the id names the stage
(`route.above-cap.delivery-audit.auditor-s1`), `cotterpin consent grant` refuses it, and a run honours only what its
own command line approves (`--consent route.above-cap.delivery-audit.auditor-s1`, or `--consent route.above-cap` for
every stage of that one run). A run in progress never stops to ask: unanswered means declined.

### When Cotterpin asks, and when it does not

- On a terminal, the first command that needs a measurement asks once and remembers your answer.
- In a non-interactive shell (a pipe, CI, or `COTTERPIN_NON_INTERACTIVE=1`) nothing is asked: an unanswered
  measurement counts as **declined**, unless you passed `--consent` or set `COTTERPIN_CONSENT`.
- A new release that changes what a measurement reads asks again for that measurement only.

### Where your choices are kept

Per user and machine, outside every repository: `$COTTERPIN_CONFIG_DIR/consent.json`, else
`$XDG_CONFIG_HOME/cotterpin/consent.json`, else `~/.config/cotterpin/consent.json` (readable only by you). Delete the
file to be asked everything again.

## How many jobs run at once

Work comes in four kinds, each sized by what limits it:

| kind | examples | limited by |
|---|---|---|
| `agent` | model calls (shard writers, reviewers) | memory per agent process and provider rate; never more than 8 at once |
| `build` | compiles and test runs | cores (efficiency cores count half) and memory (2 GiB each) |
| `container` | containers | memory (4 GiB each) |
| `light` | git, scanners, fact extraction | cores |

Cotterpin plans against 80% of memory, keeps every width at 1 or more, and never runs more jobs than there are items.

**When you decline (or never answer) the machine questions**, nothing is measured and every kind runs one at a time —
except `agent`, which runs **two** at once (operator ruling 5, 2026-10-04). Model calls are bounded by the provider and
by each agent's memory, not by this machine's cores, so two at once is safe on any machine that runs an agent tool at
all; still no probe runs. `build`, `container` and `light` stay at 1.

Campaigns batch by default: `cotterpin campaign run --verify-command "<command> {modules}"` executes each wave and
builds and checks it **once per verification batch** (units whose checks overlap share one build), while every unit is
still judged only on its own result. `--per-change` checks each unit on its own instead — the same verdicts, more
builds. `--dry-run` simulates.
With `--agent claude|codex|grok` (or `--agent-command "<program> {prompt_file}"`), Cotterpin runs the fan-out itself:
every unit of a wave is dispatched at once — never more than the `agent` width, so two when you declined — to that
provider's CLI in print mode, each in its own run worktree (under `.cotterpin/runs/`, hidden from `git status`, or
`--tree-root`). Every provider call goes through the provider door (consent `provider.send.<provider>`, asked once
before anything starts; the run's token budget; rate-limit backoff). What each agent changed becomes a commit on its
own branch (`cotterpin/campaign-<run>/unit-<id>`); a unit that changed nothing, changed a path its manifest does not
declare, or whose wave wrote into your own checkout, fails on its own row. Units that pass their batch's check land on
the campaign trunk (`cotterpin/campaign-<run>/trunk`), which the next wave starts from; your branch is never touched.
A width is only how much work is *offered* at once; each job is still admitted individually, so an overloaded machine
is never pushed past its limit.

Between batches, with `host.live-load` allowed, widths adapt: they **halve** when free memory runs low, the measured
load reaches 70% of the cores, or four or more checkouts are in progress, and they **grow by one** when the machine has
headroom, never above the measured maximum. Other Cotterpin runs that are still alive take a slot each; runs that
started in the last three minutes stop the widths from growing (their load is not visible yet) but never shrink them on
their own.

With nothing allowed, every kind of job runs one at a time, and a second Cotterpin run waits for the first.

Agent widths and model tiers share one budget view: with `routing.budget.maxConcurrentUnits` set in
`.cotterpin/policy.yaml`, every agent fan-out — the kernel route tools, the Java pack's generate, de-stub and migrate
launchers, and campaign waves — is narrowed so that width times the routed cost of one call fits it, so a stronger
model runs fewer at once ([MODEL-ROUTING.md](MODEL-ROUTING.md)).

### Declaring widths yourself: `.cotterpin/box.yaml`

If you would rather not have the machine measured, or want to hold capacity back for your own tools, declare it in the
repository:

```yaml
schemaVersion: 1        # optional
widths:                 # used exactly as given, with or without consent
  build: 2
  light: 6
reserve:                # kept back from what was measured
  cores: 2
  memoryMiB: 4096
```

A declared width is your statement, not a measurement: it is used as given (never more than the number of items) and
is not adapted. A kind you do not declare is sized from the measurements you allowed, or runs one at a time.

## Troubleshooting

| you see | it means | do this |
|---|---|---|
| `Nothing was measured: you have not allowed Cotterpin to measure this machine` | every measurement is declined or unanswered | run `cotterpin box` in a terminal and answer, or `cotterpin consent grant box.cores` |
| `another Cotterpin run is active, and without your consent to live load sampling runs take turns (serial)` | a second run is waiting for the first | wait, or `cotterpin consent grant host.live-load` |
| `"code": "consent-declined"` from `cotterpin resources` | live load sampling is not allowed | `cotterpin consent grant host.live-load`, or `cotterpin resources --consent host.live-load` |
| `.cotterpin/box.yaml: widths names 'gpu', which is not a work class` | a typo in your declaration | use one of `agent`, `build`, `container`, `light` |
| `your consent choices at … are not readable JSON` | the choices file is damaged | delete it (the message prints the exact `rm` command); you will be asked again |

## For component authors

Every probe of the machine or toolchain, every write outside the repository, every hook installation and every call
to a provider goes through `cotterpin.kernel.consent`:

```python
from cotterpin.kernel import consent

if consent.request("toolchain.runtime", what="the installed runtime version",
                   source="`<runtime> --version`", why="to pick a compatible build image",
                   on_decline="the default image is used"):
    ...  # measure
else:
    ...  # the working, slower default
```

`request(id, what, source, why, on_decline) -> bool` asks (on a terminal) and remembers; `granted(id) -> bool` never
asks and is what code deep inside a run uses. Register a measurement with `consent.register(Measurement(...))` in a function named in
`consent.CATALOGUE` so it appears in `cotterpin consent` (and can be granted ahead of time); bump its `version` when what it reads changes. A fan-out chooses its width with
`cotterpin.kernel.box.plan(kind, wanted)`; a pack can price one of its kinds with `box.register_calibration(kind, fn)`,
which runs only under `box.calibration` consent.
