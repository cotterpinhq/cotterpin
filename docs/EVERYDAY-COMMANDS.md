# Everyday commands: `audit`, `fix`, `update`, `why`, `report`, `machines`, `subscribe`

These are the commands the Cotterpin website describes. Each one is built on something Cotterpin already does.
`machines`, `subscribe` (and `billing`) and `update --fetch` reach the Cotterpin licence service, and each says what
it will send and why, and asks, before it does; declined, it does what it can on this machine alone and sends
nothing.

`cotterpin --help` lists every command with a line saying what it does. It starts with the eight a new developer
needs first: `init`, `doctor`, `hooks`, `adapters`, `commit`, `verify-deferred`, `uninstall` and `cache`
([ONBOARDING-COMMANDS.md](ONBOARDING-COMMANDS.md)). The few that only Cotterpin's own hooks run are named last, under
"Internal".

Every command takes `--json`. In CI mode (`--ci` or `COTTERPIN_CI=1`) the output is always JSON. A refusal prints its
code, what happened, what to do and the exact next command, which is also what `cotterpin explain <code>` prints (see
[REFUSALS.md](REFUSALS.md)). Exit codes are `0` for done or nothing to do, `1` when the command found something or was
not approved, and `2` when it refused.

## `cotterpin audit`: a findings report that changes nothing

```sh
cotterpin audit                    # this repository
cotterpin audit --dry-run          # list the steps; run none
cotterpin audit --json
```

The audit runs these steps in order:

1. **Cotterpin's own files.** It checks that every versioned `.cotterpin/` file is in the format this Cotterpin reads.
   A file that is behind is fixable (`cotterpin fix`). A file written by a newer Cotterpin, or one with no readable
   `schemaVersion`, is left for you.
2. **The local-state ignore rule.** It checks that `.gitignore` holds the block `cotterpin init` writes, so that
   Cotterpin's per-developer files can never be committed. If the block is missing, `cotterpin fix` can add it.
3. **The code gates.** It runs every installed language pack's gates (the same run as `cotterpin gate run`) over your
   working tree. Each finding names its gate, the file and line, and the gate's remedy; `cotterpin why <gate>` says
   why the gate exists. If the gates cannot start (for example an unusable `.cotterpin/gates.yaml`), the audit skips
   the step and records why.
4. **Your declared checks.** It runs every check in `.cotterpin/checks.yaml` through the same route as
   `cotterpin check`. A check that does not pass is a finding for you or your agent to fix. If the repository declares
   no checks, or they cannot start, the audit skips the step and records why.

Nothing in your working tree, index or branch changes. The report is kept next to Git's own files for this checkout
(`git rev-parse --git-path cotterpin/audit`), and the audit's progress is kept with every other run's. An interrupted
audit continues with `cotterpin resume <run>`. Every finding is advisory: an audit reports and never blocks.

## `cotterpin fix`: the fixes Cotterpin can apply, after you approve them

```sh
cotterpin fix --dry-run            # list them; change nothing
cotterpin fix                      # list them, say what will change and why, then ask
cotterpin fix --yes                # approve exactly the listed fixes (same as --consent fix.apply)
```

`fix` checks your files again itself. It never relies on an old report. It applies only the fixes that need no
judgement:

- it converts a `.cotterpin/` file that is behind to the current format. This uses the same steps as
  `cotterpin upgrade`, and either every file converts or none does;
- it adds Cotterpin's block back to `.gitignore` and records it, so `cotterpin uninstall` still removes it;
- it applies a code gate's remedy only when that gate declares the one rewrite that removes its finding. No gate the
  Java pack ships today has such a remedy (each needs a judgement about the code), so their findings are listed for
  you with the gate's remedy.

Before it changes anything, `fix` says what it will change and why, then asks. If you say no, or if there is nobody to
ask (no terminal, or CI) and you did not pass `--yes` or `--consent`, nothing changes. If a fix fails partway through,
every file it touched is put back (`fix-failed`). Findings that need a person, such as a failing check from the last
audit or a gate finding, are listed with their remedy. Apart from a gate's declared mechanical rewrite, `fix` never
edits your code.

## `cotterpin audit --scope` and `cotterpin fix --scope`: start an audit or fix RUN

```sh
cotterpin audit --scope PAYMENTS --dry-run    # what the run would be; nothing is created or started
cotterpin audit --scope PAYMENTS              # start the kernel's delivery_audit route for the scope
cotterpin fix --scope PAYMENTS                # start delivery_audit_fix, after you approve (or with --yes)
cotterpin fix --scope PAYMENTS --decision PAYMENTS-refund-window="30 days after capture" --yes
```

The report above reads and never changes anything. When you want the kernel to WORK on a scope you declared in
`.cotterpin/audit/scopes/<SCOPE>.json` ([WORKFLOWS.md](WORKFLOWS.md)), name it with `--scope`: `audit` starts the
`delivery_audit` route (census, audit, refute, sample and record every capability of the scope, committed pass by
pass) and `fix` starts `delivery_audit_fix` (deliver what the audit recorded as not delivered, each change reviewed by
a second agent and checked by your declared checks). A fix run changes your code, so it asks first (`fix.route`).
Optional: `--only <capability>` (repeatable), `--base <commit>` (default `HEAD`), `--tree-root <folder>`.

The scope is checked by the route's own tool before anything is created (`audit-scope-missing`,
`audit-scope-invalid`), and the commit the run starts from must hold your approved lock (`route-not-installed`). The
run gets its own checkout on `cotterpin/<run id>` — inside the repository at `.cotterpin/runs/<run id>`, hidden from
`git status`, unless you allowed checkouts outside it — and the kernel's `start` runs there. The long `drive` is
printed as the next command: run it in the background, and follow the run with `cotterpin why <run id>` or
`cotterpin status`.

## `cotterpin update` and `cotterpin update --rollback`

```sh
cotterpin update --dry-run         # what would change
cotterpin update                   # do it
cotterpin update --rollback        # undo the last update (add --dry-run to see what it would restore)
```

What an update moves depends on your repository's lock:

- **Set up with `cotterpin init` (developer mode).** The lock pins a Cotterpin version and each selected pack. To get
  a newer Cotterpin, upgrade it with your installer (for example `pipx upgrade cotterpin`). Then `cotterpin update`
  pins this repository to the installed version, exactly as `cotterpin init` would write the lock today.
- **An approved release.** The update goes through `cotterpin upgrade`, so the release must be approved on this machine
  and its commit must be exact. Name a local Cotterpin checkout that holds it:
  `cotterpin update --source-repo <cotterpin-checkout> --release <release> --source-commit <commit>`. Without one,
  the update refuses with `update-source-required`.

`cotterpin update --fetch` is the other half: it downloads the newest signed release your licence covers and verifies
it (signature, every digest, revocation, tier) into the local release cache. It asks first — it sends your licence and
this machine's fingerprint to the licence service (`licence.service`) — and declined, nothing is fetched and the
installed release keeps running. It never changes a repository; it runs on its own (`update-fetch-alone`).

In both cases your `.cotterpin/` files are converted before the lock moves, and your settings, checks and saved results
are kept. An update never runs while a Cotterpin run is in progress in the repository (`update-run-in-progress`).

**Rollback.** Every update records the previous lock and the original bytes of every file it converted. The record is
kept next to Git's own files for this checkout, never in the working tree. `--rollback` puts them back, with these
safeguards:

| Refusal | When | What to do |
|---|---|---|
| `update-no-previous` | no update of this checkout was recorded | nothing to undo |
| `update-rollback-lock-changed` | the lock changed after the update | restore it or update again first |
| `update-rollback-schema` | a converted file was edited after the update and is in a format the previous version cannot read | undo your edits to it (`git diff -- <file>`) or return it to that format, then roll back |
| `update-rollback-unverified` | the previous approved release no longer checks out on this machine | the rollback is undone; check it with `cotterpin verify --release` |

Rolling back a developer lock pins the previous version. To run that version, install it with your installer. The
command prints the exact line.

## `cotterpin why <name>`

```sh
cotterpin why update-rollback-schema   # a refusal code
cotterpin why TOMAP-1                  # a code gate: the incident it was born from, what it catches, its remedy
cotterpin why <check>                  # a check from the last audit, passing or not
cotterpin why local-state-not-ignored  # an audit finding's rule (or the file it is in)
cotterpin why "declared checks"        # a step a run skipped, with the reason it recorded
cotterpin why <run-id>                 # a run: its state, how far it got, the next command
```

`why` looks first in the refusal catalogue, then in the gate registry, then in this checkout's last audit report, then
in the run journal. It
reports every match. A name it finds nowhere is refused (`why-unknown`) with the closest names it does know.

## `cotterpin report`

```sh
cotterpin report [--since 7d] [--agent claude|codex|grok] [--json]   # refusals, false positives, interruptions,
                                                                     # time to commit and push, cache, task success,
                                                                     # tokens and cost per landed change
cotterpin report trajectory <session|run>                            # one session or run, step by step
cotterpin report mark-fp <id> --reason "<why>"                       # record that a refusal was wrong
```

Read from the records Cotterpin keeps on this machine; nothing is uploaded. Token counts from the agent tools' own
session logs are read only with your consent (`report.transcripts`). Every metric and how it is computed:
[Observability](OBSERVABILITY.md).

## `cotterpin machines`

```sh
cotterpin machines                 # the machines your licence covers (asks first)
cotterpin machines move <from> this   # move your licence to this machine
cotterpin machines add [<id>] | remove <id> | renew
```

`machines` asks the licence service for the machines your licence covers — after saying what it sends (your licence,
this machine's fingerprint and the Cotterpin version) and asking (`licence.service`). Pro covers three machines per
person, Team three per seat, and you add, move or remove one yourself, any time
([LICENSING-AND-BILLING.md](LICENSING-AND-BILLING.md)).

Declined, it lists **this** machine only: its box profile — only what you allowed Cotterpin to measure (see
[CONSENT-AND-BOX.md](CONSENT-AND-BOX.md)), and for each measurement whether you allowed it — and its standing:
enforcing (Trial, Pro or Team) or Watch, and why. It asks nothing else and measures nothing you have not allowed; to be
asked about measurements, run `cotterpin box`. No fingerprint is computed and nothing leaves this machine.

## `cotterpin subscribe`

```sh
cotterpin subscribe --list             # the plans, what each covers and costs (sends nothing)
cotterpin subscribe                    # Pro: $100 a year, 3 machines
cotterpin subscribe team --seats 5     # Team: $30 a seat a month, billed annually, 5 seats at least
cotterpin subscribe --claim <email>    # a plan bought on the website, bound to this machine
```

Each plan is a licence tier (Watch: `community`, Pro: `individual`, Team: `team`, Enterprise: `enterprise`). Every new
machine starts with a 14-day trial (every gate on, no card); without a current licence Cotterpin runs as Watch.
`subscribe pro|team` asks first (`licence.service`), then opens Paddle's checkout in your browser — Paddle is the
merchant of record, and card details are entered only there — and waits for the payment to arrive (Ctrl-C stops
waiting; `cotterpin machines` picks the licence up later). `subscribe watch` needs no subscription, and Enterprise is
agreed with your organisation (`subscribe enterprise` says how); neither sends anything. See
[LICENSING-AND-BILLING.md](LICENSING-AND-BILLING.md).
