# Onboarding commands: `setup`, `init`, `doctor`, `uninstall`, `--uninstall`, `cache`

Reference for the developer-mode commands (ADR-005 F10, X1, X2, X3, X18, X19). For a walk-through, see
[QUICKSTART.md](QUICKSTART.md). The code is in `cotterpin/onboarding/` and the tests are in `tests/onboarding/`.

## Asking first

Some actions probe your machine or toolchain, call a provider, or delete files outside the repository. Before each
one, Cotterpin shows what it will do, where it reads from, why it needs it, and what happens if you say no. The
answer is yes only when you type `y` at an interactive prompt or pass an explicit flag for that run:

| Flag | Allows |
|---|---|
| `--consent` | every probe the command asks about, for this run only |
| `--consent toolchain.git,machine.disk` | only the named probes |
| `--consent toolchain` | a family: `toolchain.git`, `toolchain.java.jdk`, … |
| `--yes` (`cache gc`, `cache clear`, `uninstall`, `--uninstall`) | the deletion the command lists |

When you decline, don't answer, or run without a terminal and without the flag, nothing is probed or deleted. The
command still works, using its unscanned default.

An answer at a probe's prompt lasts only for the command that asked. To allow a probe for good, ahead of time, grant
it: `cotterpin consent grant toolchain.git` (any id `cotterpin consent list` shows: `toolchain.git`,
`toolchain.python`, `toolchain.node`, `toolchain.agent-cli`, `toolchain.<pack>.<id>`, `provider.sign-in`,
`machine.disk`, `repository.stack-scan`). Every later run, a non-interactive one included, runs that probe without
asking; `cotterpin consent revoke <id>` stops it. The grant is kept per user and per machine, outside any repository
(`cotterpin.kernel.consent`, [CONSENT-AND-BOX.md](CONSENT-AND-BOX.md)); under `--ci` only the command line counts.

## `cotterpin setup`

One walk-through of everything Cotterpin can set up in a repository. You can pause it, carry on later, and change your
mind afterwards.

| Command | What it does |
|---|---|
| `cotterpin setup` | offers each step not done yet: what it is, why, and whether it is recommended. Answer `y` to install, `s` to skip for now, `q` to stop. |
| `cotterpin setup --quick` | installs every recommended step not installed yet. It lists them and the consent each needs first; that command is your yes to exactly those. |
| `cotterpin setup --status` (`--json`) | each step: installed, skipped, declined, failed or not done yet, with the command that changes it |
| `cotterpin setup --add <step>` | installs one step now: one you skipped, or one that is not recommended |
| `cotterpin setup --skip <step>` | stops offering a step |
| `cotterpin setup --remove <step>` | takes a step out again, or tells you how where only you can |

The steps, in order:

1. **`machine`**: measures cores, memory, free disk and a one-second calibration (consents `box.cores`,
   `box.memory`, `box.disk`, `box.calibration` and `host.live-load`). It then prints how many agents, builds and light
   jobs Cotterpin will run at once on this machine.
2. **`repository`**: `cotterpin init`.
3. **`hooks`**: `cotterpin hooks install`.
4. **`adapters`**: `cotterpin adapters install` for each agent tool found on this machine (Claude Code, Codex,
   Grok).
5. **`knowledge`**: a knowledge bundle (consent `knowledge.bundle`; nothing is sent anywhere). Your agent tool then
   fills it with `/cotterpin:run-okf-produce`. If your repository already keeps a bundle (`.okf/`), it asks instead to
   read and modernise that one (consent `knowledge.modernise`, below in `cotterpin speed`), and never offers to create
   another.
6. **`memory`**: the personal memory store (consent `memory.user`).
7. **`check`**: `cotterpin doctor`.

Each step is the command named, with the same question it always asks; the walk-through adds no permission of its own.
Without a terminal, nothing is asked: it lists what is left and how to do it. Your answers are kept on this machine,
for this repository only, and are never committed. Whether a step is installed is always read from the feature
itself, so a step you add or remove by hand shows correctly.

Three things need an administrator, so `setup` shows their commands and never runs them: `cotterpin approvals setup`,
`cotterpin harden hooks install`, and, for one unattended session, `cotterpin unattended on --for 8h`.

## `cotterpin speed`

What would make this repository's work faster on this machine. Each suggestion says what it changes, why it is faster,
and the consent it needs. You accept or decline each one, or accept them all.

| Command | What it does |
|---|---|
| `cotterpin speed` | lists the suggestions that apply, then asks for each: `y` apply, `n` no (not offered again), `a` all the rest, `q` stop |
| `cotterpin speed --all` | applies every suggestion listed |
| `cotterpin speed --accept <id>` / `--decline <id>` | one suggestion; a declined one is not offered again |
| `cotterpin speed --report` | before → after for each accepted suggestion |

The suggestions: `parallel-width` (consent `box.cores`: checks, tests and agents run in parallel instead of one or two
at a time), `live-load` (consent `host.live-load`: a busy machine is said out loud, and speed is measured only on a
quiet one), `gate-results` and `shared-results` (consents `cache.gate-results` and `cache.shared`: results reused
across repositories and worktrees), `knowledge-modernise` (consent `knowledge.modernise`, for a repository that already
keeps a `.okf/` bundle: Cotterpin reads it and adds `.cotterpin/okf.yaml`, so the commit checks judge only the
concepts a change touches; an older OKF version is reported with the route your agent tool migrates it with), and
`stale-verifies` (stops background verifies nobody will read).

A suggestion that grants a consent is applied only when you run the command yourself at a terminal. An agent tool's
call has no terminal, so for those it only prints the command, whatever options it passes.

**Before and after.** Every commit keeps its stage timings and the load it ran under, on this machine only. The report
compares the median total of the quiet commits before a suggestion was accepted with the median of the quiet commits
after it. A quiet commit is one made while the 1-minute load was below half the logical cores. Commits on a busy
machine, and commits whose load was not read (no `host.live-load` consent), never count. Until three quiet commits sit
on each side, the report says "not measured yet" rather than guess.

## `cotterpin upgrades`

What this repository can upgrade, and the route your agent tool runs for each. Each installed language pack reads its
own build files: Java's release and Jackson 2 (`pom.xml`, Gradle builds), Angular's major and RxJS (`package.json`),
.NET's target framework and Newtonsoft.Json (`.csproj`), Python's minimum version and Pydantic 1 (`pyproject.toml`,
requirements files), and the hashicorp/aws provider (`.tf`). A knowledge bundle on an older OKF version is listed too.

| Command | What it does |
|---|---|
| `cotterpin upgrades` | lists each upgrade (current → target) with the command that starts its route in your agent tool, e.g. `/cotterpin:run-java-upgrade` |
| `cotterpin upgrades --json` | the same as JSON, with each route's command |

A route raises one step per run (the next LTS, the next major), and every unit it changes is reviewed by a second
agent, verified and revertible. Run `cotterpin upgrades` again for the next step.

Finding the upgrades reads files only: no tool is started and nothing is changed. Tools a route needs that are not on
this machine's PATH (a JDK, Maven, Node.js, the .NET SDK, uv, Terraform) are listed with the command that installs them
on this platform. At a terminal, Cotterpin then offers to install them all: it shows the exact commands, and installs
on your yes. If any of them needs administrator rights, your sudo password is asked once and covers all of them for
that run. Commands that need no administrator rights (Homebrew, winget, SDKMAN!, nvm) run without sudo. From an agent
tool, nothing is installed; run `cotterpin upgrades` yourself.

## `cotterpin init`

Sets the current repository up for developer mode.

```
cotterpin init [--repository PATH] [--pack ID]... [--dry-run] [--consent [IDS]]
```

- **Probe:** `repository.stack-scan` lists the file names (not the contents) at the repository root and matches them
  against each installed pack's markers. `--pack` skips the scan. If you decline, no pack is selected.
- **Writes** (repository only, never overwriting): `.cotterpin/policy.yaml`, `.cotterpin.lock.json` (a developer lock:
  Cotterpin version, each pack's digest, the policy digest), and a marked block in `.gitignore`.
- **Records** what it created in Git's own directory (`git rev-parse --git-path cotterpin/install-record.json`). That
  location also works in a linked worktree.
- **Notes the repository** in Cotterpin's list on this machine (`<config dir>/repositories.json`), so `cotterpin
  --uninstall` can find it later without searching your disk. `cotterpin adapters install` and `cotterpin hooks
  install` note it too.
- Running it a second time changes nothing.
- **Trial** (`licence.service`): unless this machine already holds a licence, it offers the 14-day trial — every gate
  on, no card — saying exactly what is sent (licence id, plan, this machine's fingerprint, the Cotterpin version) and
  why. Declined, non-interactive or unreachable: Cotterpin runs in Watch, and `init` still succeeds. Not with
  `--dry-run`. See [Licensing and billing](LICENSING-AND-BILLING.md).

| Exit | Meaning |
|---|---|
| 0 | written, already set up, or `--dry-run` |
| 2 | refused: not a git repository (run `git init`), or no installed pack has that name (the message lists the installed ones) |

## `cotterpin doctor`

Checks whether this machine is ready for a first run.

```
cotterpin doctor [--repository PATH] [--pack ID]... [--json] [--install] [--consent [IDS]]
```

It asks once, in a few lines, before it checks anything (`doctor.check`): which tools it will run `--version` for,
that it asks your agent CLIs whether you are signed in, and that it reads the disk's free space. Yes allows every
check below for this run. No (or no terminal) runs none: each line shows SKIP. Nothing is asked when each check is
already allowed (`--consent`, or `cotterpin consent grant <id>`).

| Check id | What it runs | Passes when |
|---|---|---|
| `toolchain.git` | `git --version` | git 2.30 or newer |
| `toolchain.python` | `python3 --version` | Cotterpin runs on 3.11+, and any `python3` on PATH is 3.11+ (otherwise it prints an install hint that leaves the system Python alone) |
| `toolchain.node` | `node --version` | Node.js 18 or newer |
| `toolchain.agent-cli` | `<cli> --version` for each supported agent CLI on PATH | at least one is installed, in its accepted version range |
| `toolchain.<pack>.<id>` | the pack's own probe, e.g. `java -version`, `mvn -v` | at or above the pack's minimum. A repository wrapper (`./mvnw`) passes without being run, so nothing is downloaded |
| `provider.sign-in` | each agent CLI's own sign-in status command | at least one provider is signed in |
| `machine.disk` | the file-system's free-space statistics | 5 GiB or more free |

Pack checks come from `--pack`, or the committed policy's `packs`, or the stack scan.

Every FIX line has a `fix:` line with the exact command. A SKIP line (a declined probe) has a `to check it:` line.

With `--install`, doctor then offers to install what the FIX lines name, after one more question (`doctor.install`,
asked each time, never stored). On macOS it runs `brew install` for the tools a pack marks with a Homebrew formula
(Terraform, TFLint, uv, Python 3.13), as you, never with sudo, and checks again. Anything needing an administrator (a
JDK, the .NET SDK, git) and every install on Linux or WSL (apt needs sudo) is printed for you to run. An AI agent never
installs: it gets the commands.
Exit status: 0 when nothing needs fixing (skipped checks don't count), 1 when any line says FIX, 2 when the command is
refused.

## `cotterpin packs install`

Adds language pack wheels you have as files (for example ones you built) to the Cotterpin that is running.

```
cotterpin packs install WHEEL... [--yes]
```

Each wheel must be a `cotterpin_pack_<id>-*.whl` whose pinned Cotterpin version is the one running; anything else is
refused (exit 2) before anything is installed. It installs into this Cotterpin's own environment without resolving
anything (`pip install --no-deps`, or `uv pip install --no-deps` when that environment has no pip), so a pack's exact
kernel pin never sends a resolver to the package index. It asks first (`packs.install`, asked each time, never
stored); `--yes` agrees in advance, and with no terminal and no `--yes` nothing is installed (exit 1). An AI agent
never installs: it is told the command for you to run.

## `cotterpin uninstall`

```
cotterpin uninstall [--repository PATH] [--yes] [--dry-run]
```

It lists the changes, then asks. Without a terminal and without `--yes`, it changes nothing and prints the command
to run. It removes:

- the files `init` created, if they are still untracked and unchanged;
- Cotterpin's `.gitignore` block, and the file itself if `init` created it and nothing else is in it;
- `.cotterpin/local/`, and `.cotterpin/` if that leaves it empty;
- every hook marked `# cotterpin-managed-hook` in Git's hooks directory (including a `core.hooksPath` such as
  `.husky`). If the hook had replaced one of yours, kept as `<hook>.cotterpin-chained`, your hook is put back
  byte for byte, with its permissions;
- its record in Git's own directory.

It keeps any file you committed or edited, and prints the `git rm` or `rm` command that removes it. Cotterpin's cache
is per machine, not per repository: remove it with `cotterpin cache clear`. On a repository Cotterpin set up and
nobody touched, `git status --porcelain` prints nothing afterwards. A test proves this.

## `cotterpin --uninstall`: remove Cotterpin from this machine

```
cotterpin --uninstall [--dry-run] [--yes] [--scan FOLDER]... [--export-audit FILE] [--keep-seat]
cotterpin uninstall --machine [the same options]
```

The two spellings are the same command. It first lists, grouped and in plain words, everything it will remove and
why, and everything it will keep with the command that removes it by hand. Then it asks once. `--dry-run` only lists.
Without a terminal and without `--yes`, it changes nothing and prints the command to run (`uninstall-not-interactive`).

What it removes, in this order:

| Group | What | Where Cotterpin knows it from |
|---|---|---|
| Export (only if you ask) | a `.tar.gz` of every audit-log and trajectory file, with a manifest naming where each came from. Answer `e` at the question (it goes into your home folder), or pass `--export-audit FILE` | the audit folders below |
| This machine's seat | gives the seat back through the licence service's machines route (the one `cotterpin machines remove` uses), so you can use it on another machine. It sends your licence, this machine's fingerprint and the Cotterpin version, and nothing else. Your yes at the question covers this. `--yes` on its own does not: add `--consent licence.service`. If the service cannot be reached, it is skipped with a note (`uninstall-seat-offline`), and the rest still happens | `licence.json` |
| Every repository Cotterpin set up | for each one, the repository uninstall above (the files `init` wrote, the `.gitignore` block, every agent adapter, Cotterpin's git hooks with `core.hooksPath` put back), then Cotterpin's folder inside Git's own directory: the private cache, approval requests, the audit log, session and run records | Cotterpin's list, `<config dir>/repositories.json`, which `init`, `adapters install` and `hooks install` write |
| Administrator parts (hardened mode) | the root-owned settings folder (`/private/etc/cotterpin` or `/etc/cotterpin`: the security policy, the approval signer and its keys, the supervisor's settings), the supervisor's launch daemon (stopped first), and its folders under `/Library/Application Support/Cotterpin` and `/private/var`. It says they need administrator rights, then runs ONE `sudo -k` with the same password / Touch ID prompt approvals use. Cotterpin adds no sudoers, PAM or systemd entries. The runner user accounts are kept: deleting an account is your administrator's decision | fixed paths, checked one by one |
| Caches | `~/.cache/cotterpin`, with the release runtimes in it, goes whole. A folder you named in `$COTTERPIN_CACHE_DIR`, or any cache folder that holds a repository, loses only what Cotterpin's cache can be shown to have written: the namespaces the store marked when it made them (a `.cotterpin-namespace.json` note naming the namespace) with their entries, release bundles whose every digest recomputes from their own bytes and whose release digest is their folder's name, the runtimes such a bundle carries (or, landed without its bundle, whose own bytes recompute their folder's name), the staging folders a killed landing leaves when their content is the start of that proven content, and Cotterpin's signed revocation list. A layout alone proves nothing: another tool's `cas/<2 hex>/<sha256>` store or a folder of downloads named by digest is kept. Everything else in it is kept and listed — an empty folder of yours beside Cotterpin's entries too. A folder goes only if removing Cotterpin's entries empties it AND Cotterpin made it: the store notes, in each namespace's note, which folders of the namespace's path it created, so a folder of yours it merely wrote into (an empty `kernel/` that was already there) is kept and listed, and the release cache's own `bundles/`, `releases/` and `revocations/` go. The folder `$COTTERPIN_CACHE_DIR` names goes only if the store created it (it then writes a `.cotterpin-cache-root.json` note in it); a folder you made and named there is kept and listed, however empty. That note also names the folders ABOVE the cache folder that Cotterpin made to hold it (`~/.cache` on a machine that had none, the `a/b` of a new `$COTTERPIN_CACHE_DIR=~/a/b/c`; the cache store and the release cache both write it): each goes after the cache folder, listed, only while nothing else is in it. A cache folder that is a link (a cache kept on another disk) is yours: the link stays, listed, and the folder it points to is looked through like a folder you named | the fixed path, the store's notes, and each release's own bytes |
| Configuration | only the files Cotterpin can show it wrote there: `licence.json`, `consent.json`, the clock watermark, the list of repositories and its other JSON files only when they carry the kind their writer puts in them; in `audit`, `approvals`, `sessions` and `memory` only the files at their writer's place in their writer's form (audit-log decisions, pending-action records and the empty lock a killed approval leaves, session write records, memory facts, the memory index and journal). A temporary file a stopped writer left (`.licence-…`, `.consent.…`, `approvals/.pending-…`, `memory/.catalog.json.…`, `memory/facts/.u-….json.…` and the like) is Cotterpin's only when it is empty or holds exactly the bytes its writer writes; each one removed is named in the list, and a file of yours under such a name is kept and listed. `admin.json` and `release.json` are always kept and listed: you write them by hand (see ADMIN.md and RELEASE.md), Cotterpin only reads them. Anything else in the folder — a folder of yours called `memory`, an empty folder of yours inside it, a `release.json` of another tool — is kept and listed, whatever the folder is called. Cotterpin notes in `created-folders.json` every folder it makes to hold its configuration: the folder itself, the folders above it (`~/.config` on a machine that had none) and its folders inside it. The folder goes when that leaves it empty, and only if it is `$XDG_CONFIG_HOME/cotterpin` or `~/.config/cotterpin`, or Cotterpin noted that it made it; a folder you made and named in `$COTTERPIN_CONFIG_DIR` is kept and listed, and so is a folder of yours inside it that Cotterpin only wrote into (an `approvals/` you made). The noted folders above it go too, while empty. A configuration folder that is a link (a dotfiles layout such as stow or chezmoi) loses the files Cotterpin wrote where it points, exactly as above; the link and the folder it points to are yours, and are kept and listed with the command that removes each. If a repository could not be finished, or is not there (moved, or on a disk that is not mounted: `uninstall-repository-missing`), the list of repositories is kept, naming only those, so running `cotterpin --uninstall` again finds them; `--forget PATH` drops a repository that is gone for good. A list that cannot be read is kept exactly as it is, and the run fails with `uninstall-registry-unreadable` | `$COTTERPIN_CONFIG_DIR`, `$XDG_CONFIG_HOME/cotterpin` or `~/.config/cotterpin` |
| Cotterpin itself, last | it works out how it was installed (pipx, `uv tool`, Homebrew, pip or `pip --user`, `uv pip`, the release installer's folder) and runs the matching uninstall. A source checkout, or an installer whose tool is not on `PATH`, is printed instead, never run | the install's own folders |

Before Cotterpin itself goes, a final check runs the same enumeration again: anything Cotterpin wrote that is still
there, except what you chose to keep, is reported as `uninstall-leftover`. The closing summary lists what was
removed, what was kept, and anything that failed with its refusal code and fix.

**Repositories set up before the list existed.** Cotterpin keeps the list only from version 0.3.0rc1. It never
searches your disk without asking, so the listing says what it cannot know. `--scan FOLDER` looks under that folder
(at most six levels down, skipping hidden, dependency and build folders) for repositories with Cotterpin's marks. It
reads folder names and each repository's `.git` folder, never file contents. It asks first (`uninstall.scan`; in a
script, `--consent uninstall.scan`). You can also run `cotterpin uninstall --repository <path>` in each repository.

**Agents.** The `approval-integrity` hook rule refuses `cotterpin --uninstall` and `cotterpin uninstall` from an
agent tool, in any spelling, while the hook enforces (a current licence; in Watch it reports) ([HOOKS.md](HOOKS.md)).
The command also refuses on its own, before changing anything, when an agent tool's environment markers are set,
when an agent tool is among the processes that started it (by program name, or by the script a shell or `node`
runs), the same two signs approvals read (`uninstall-agent-refused`), and when it has no terminal of its own
(`uninstall-needs-terminal`): an agent tool's shell has none, so a command it double-forks to shed its ancestry is
still refused. `--yes` skips only the question; it still needs your terminal. `--dry-run` stays allowed. These are
early refusals, NOT a security boundary: an agent runs as your own user, so one that opens a pseudo-terminal of its
own can still run the command — as it could delete these files by hand. The only proof of a person is the operating
system's authentication, and Cotterpin does not ask for your password to take itself away (removing it must work
without administrator rights).

| Exit | Meaning |
|---|---|
| 0 | removed (or nothing to remove), or `--dry-run` |
| 1 | declined, not asked (no terminal, no `--yes`), the export failed, or something failed — including a repository that is not there or a list of repositories that cannot be read; the summary names each failure's code and fix |
| 2 | refused: an agent started it, it has no terminal of its own, or the options do not fit together |

Refusal codes: `uninstall-not-interactive`, `uninstall-agent-refused`, `uninstall-needs-terminal`,
`uninstall-export-failed`, `uninstall-registry-unreadable`, `uninstall-repository-failed`,
`uninstall-repository-missing`, `uninstall-path-failed`, `uninstall-seat-offline`,
`uninstall-seat-not-released`, `uninstall-admin-failed`, `uninstall-admin-unavailable`, `uninstall-package-failed`,
`uninstall-leftover` (see [REFUSALS.md](REFUSALS.md)). The tests are in `tests/onboarding/test_machine_uninstall.py`.
They use two real repositories set up by the real commands, the real licence service handler over loopback HTTP, a
real `pip uninstall` in a real virtual environment, and the administrator parts in a scratch root. The suite does
not run as root, so `sudo` itself is not run there; the command it would run is pinned.

## `cotterpin cache du | gc | clear`

Two stores. The per-machine store at `$COTTERPIN_CACHE_DIR` or `~/.cache/cotterpin` (written only with your
`cache.shared` consent or a directory you named), and the repository's private store at
`<git-common-dir>/cotterpin/cache`, which every component uses otherwise (gate results, facts, fingerprints, compiled
output, verify verdicts) and which the worktrees of that repository share. Every entry can be rebuilt, so deleting one
costs only speed.

```
cotterpin cache du [--json] [--max-size SIZE] [--repository PATH]
cotterpin cache gc [--max-size SIZE] [--yes] [--json] [--repository PATH]
cotterpin cache clear [--yes] [--json] [--repository PATH]
```

- `du` shows bytes and entries per namespace, the total and the cap, for both stores. It changes nothing.
- `gc` deletes the least recently used entries, across all namespaces, until each store fits its cap. The per-machine
  cap is `--max-size` (for example `2G`, `500M`), else `$COTTERPIN_CACHE_MAX_BYTES`, else 10 GiB; the private store's
  is `$COTTERPIN_REPO_CACHE_MAX_BYTES` (bytes), else 2 GiB. After every `cotterpin commit`, the detached housekeeping
  keeps the private store within its cap too.
- `clear` deletes every entry of both stores.
- `--repository` names the repository whose private store is included (default: the current folder; none outside a
  repository).
- Approved release runtimes (`bundles/`, `releases/`, `revocations/`) are never deleted. `du` reports them separately.

`gc` of the per-machine store (when it is over its cap) and `clear` delete files outside the repository, so they ask
first. Without a terminal, use `--yes`. `gc` of the private store deletes only inside the repository's own git
directory and does not ask. Exit status: 0 done (or nothing to do), 1 declined, 2 a size that cannot be read (the
message shows one that works).

## Install without the enterprise extra

`pip install cotterpin` installs only PyYAML. `botocore`, `cryptography` and `fido2` are the `enterprise` extra
(`pip install 'cotterpin[enterprise]'`), needed only for AWS-backed authority, release signing and hardware-key
enrolment. `tests/conformance/test_developer_install.py` runs every command on this page in a process where importing
those libraries fails.
