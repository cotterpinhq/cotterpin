# Agent hooks: `cotterpin hook <event>`

Coding agents (Claude Code, Codex, Grok) can run a command before and after every tool call, when a prompt is
submitted, when a session starts and when a turn ends. Cotterpin gives all three ONE such command:

```sh
cotterpin hook PreToolUse   [--agent claude|codex|grok]   # before a tool call: may refuse it
cotterpin hook PostToolUse  [--agent ...]                 # after a tool call: may advise
cotterpin hook UserPromptSubmit | Stop | SubagentStop | SessionStart [--agent ...]
```

The agent tool writes its hook payload on standard input; Cotterpin runs every rule that judges that event and tool,
and answers in that tool's own protocol. `--agent` defaults to Claude Code; a Grok payload (camelCase) is recognised
without it. The interactive adapters (a Claude Code plugin, a Codex adapter, a Grok adapter) are generated from this
entrypoint and only wire each event to it.

Not to be confused with `cotterpin hooks` (plural), which chains Cotterpin's steps in front of your **git** hooks —
see [HOOKS-AND-HOSTS.md](HOOKS-AND-HOSTS.md).

## What the agent sees

Every tool call is classified into one **risk tier** — read, low-risk write, sensitive write, destructive / high
impact — and the tier alone decides what happens: a read runs; a low-risk write runs and is audited; a sensitive write
is confirmed by the developer once (Claude Code's permission prompt, or a pending approval where nobody can be asked);
a destructive action waits for a person's explicit approval (`cotterpin approve <id>`). Every decision is written to
the audit log. The whole policy layer, the approval commands and the audit log are in [APPROVALS.md](APPROVALS.md).

Refusals happen while this machine holds a current Trial, Pro or Team licence. In **Watch** (no licence, or a lapsed
one) the same words reach the agent as a report headed "Watch: Cotterpin would have refused this", the action runs, and
at the end of each turn the `Stop` hook lists everything Watch let through
([Licensing and billing: Enforce or Watch](LICENSING-AND-BILLING.md#enforce-or-watch-on-this-machine)). One exception: an agent session the hook ENFORCED for earlier stays approve-only for destructive actions if the licence disappears mid-session (removing it is exactly what an agent would do to need no approval). A question a
person at the keyboard can answer stays a question in both modes.

A refused call explains itself in plain words, names the rule and its tier, and — for an action that needs approval —
the request to approve:

```
`git reset --hard` throws away every uncommitted change in this checkout. This cannot be undone.
Next: save the work first (`git stash push -m <name>` or commit it to a branch), then name only the files you mean;
or ask the developer to approve this exact command
(Cotterpin rule `destructive-git`, tier destructive / high impact. Why it exists: cotterpin explain
hook-destructive-git. A person can change it for this repository: cotterpin hook set destructive-git advise --reason
"<why>".)

Approval request pa-1f2e3d4c was recorded (tier destructive; expires ...). Ask the developer to run
`cotterpin approve pa-1f2e3d4c` in their own terminal (or `cotterpin decline pa-1f2e3d4c`), then run exactly the same
action again ...
```

Everything the hook answers — refusals, advice, Watch reports, approval requests — passes through Cotterpin's one
redaction filter first, so no licence token, sign-in token, API key or other credential reaches the agent
([PRIVACY.md](PRIVACY.md)).

| Agent tool | Refuse | Ask a person (sensitive write) | Advice | Turn end |
|---|---|---|---|---|
| Claude Code | `permissionDecision: deny`, exit 0 | `permissionDecision: ask` | `additionalContext` | `{"decision":"block"}` |
| Codex | same as Claude Code | cannot ask: a pending approval instead | `additionalContext` | same |
| Grok | `{"decision":"deny"}`, exit 2 | cannot ask: a pending approval instead | `additionalContext` | `{"decision":"block"}`, exit 2 |

When nobody can answer a question (`COTTERPIN_NON_INTERACTIVE` or `COTTERPIN_CI` is set), a sensitive write is
refused with a pending approval instead of asked. A turn-end refusal is never repeated while the agent tool says it is
already continuing because of one, so no rule can trap a session in a loop.

**Memory.** `SessionStart` also gives the agent the bounded memory index (names and one-line descriptions only, the
most relevant first, within a token budget), and `Stop` starts a background consolidation when notes are waiting. A
repository with no memory gets nothing extra. Both are the same for all three agent tools; see [MEMORY.md](MEMORY.md).

**Failing closed.** If the payload cannot be read (not JSON, a different event than the one called, a patch with no
readable path, arguments the tool cut short), or a rule crashes, a tool call is **refused** with the reason — a guard
that fails open is no guard. On every other event the problem is printed on standard error (exit 1) and the session
continues. The same holds when Cotterpin cannot run at all — `cotterpin` missing from the `PATH`, a broken install, the
hardened launcher's release root gone: every adapter's `PreToolUse` command (and the hardened managed settings') turns
any exit other than allow (0) or refuse (2) into a refusal, with `cotterpin doctor` as the next step, because the agent
tools treat any other exit as a non-blocking error and would run the action unchecked.

**The trajectory.** Every hook call — for all three agent tools alike — also keeps one line in the repository's git
directory: the event and tool, the command or file paths (redacted and clipped), what the agent met, every rule that
objected, and after a shell command its exit code and any commit it landed. Never a prompt, a reply or tool output.
`cotterpin report` measures the rules from it (refusals per rule, false positives, questions per hour) and
`cotterpin report trajectory <session>` replays a session in order; see [Observability](OBSERVABILITY.md). Keeping the
line never changes the hook's answer, and `COTTERPIN_TRAJECTORY=off` stops it.

## At every prompt (`UserPromptSubmit`): the knowledge that matches it

`UserPromptSubmit` carries, as context and never as a rule, the repository's knowledge that matches the prompt — OKF
concepts, its own skills and workflows, memory facts — at most five entries, or nothing when nothing matches well
(`cotterpin/memory/prompt.py`; ranking, privacy and cost in [MEMORY.md](MEMORY.md), "At every prompt"). Only the top
entry is written as a path `okf-read-before-write` / `skill-read-before-write` count, so a prompt asks for at most one
read before the next write; the others are optional `okf:<id>` / `skill <name>` pointers.

## Wave nine: the hook platform

**Dispatch tools.** `Agent`, `Workflow`, `Task`, `TaskStop`, `TaskCreate`, `TaskUpdate` and `SendMessage` reach the
hook as their own logical tools; a rule sees the words a dispatch carries (`Event.prompt_text`: a sub-agent's brief, a
workflow's script and arguments, a message), the whole tool input, and the session's transcript path.

**Blocking turn ends (ruling 1).** `Stop` and `SubagentStop` can BLOCK in Claude Code, Codex and Grok. The router — never
a rule — counts strikes per session and rule (`<git common dir>/cotterpin/session/<id>/turn-strikes.json`):

* a rule that judges the agent's WORDS (`text_heuristic`) blocks the stop once; the agent may stop again exactly once,
  and that stop is accepted only when its final message cites evidence this turn's transcript confirms — a command it
  ran, in backticks, or `path:line` of a file it Read. A retry without evidence is blocked once more; the stop after
  that is let through and recorded;
* a rule that MEASURES something (git, a file) blocks until the condition clears, at most three times in a row, then
  the stop is let through and recorded.

Every let-through and every accepted retry is shown at the next session start. The transcript is parsed ONCE per turn
end, from its end (`cotterpin/hooks/transcript.py`: at most 20 ms on 5 MB), and a whole turn end costs at most 150 ms
(`tests/perf/test_turn_end_budget.py`). `UserPromptSubmit` and `SessionStart` stay context-only.

**Router safety.** A call whose working folder is inside a `.git` folder is refused (`hook-cwd-inside-git-dir`; run it
from the checkout); a call whose working folder does not exist is refused (`hook-cwd-missing`). Every refused shell line
says that NOTHING in it ran, naming the files it would have written — so the agent never builds on a file it believes it
wrote. If the rule table does not import (a rule module half-way through an edit), the call is judged by the last
verified, read-only release copy of the hooks (`hook-rule-table-fallback`), and refused only when there is none.

**Unattended.** `cotterpin unattended on [--for 12h]` — or your own prompt asking for an unattended session ("I'm going
to sleep, keep working") — declares the repository unattended until it expires (12 hours by default, at most 7 days):
every question the hook would ask is refused instead, with its reason, so an unattended session never stalls on a
question nobody will answer. It needs no approval because it only ever refuses more; `off` ends it early.

**Rules are discovered.** Every module of `cotterpin/hooks/rules` that defines `RULES` joins the table, ordered by its
`ORDER` then its name; refusal catalogue areas likewise live in `cotterpin/kernel/refusal_families/<area>.py`. Globs in
rule options are segment-aware: `*` stays within one folder, `**` crosses folders.

## The rules

The tier is the rule's; the outcome is the tier's ([APPROVALS.md](APPROVALS.md)). Mode is the default repository mode
(`advise`: reported, never counted towards the tier).

| Rule | Tier | Mode | Events / tools | What it finds, and why |
|---|---|---|---|---|
| `destructive-git` | destructive | enforce | before Bash | `git reset --hard`, `push --force` (`--force-with-lease[=<ref>]` too), `clean -f`, `checkout -- <folder>` / `restore <folder>` (a glob or `<folder>/` without `--` too), `checkout -f` / `switch --discard-changes`, `stash drop|clear`, `branch -D`: work thrown away with no copy. With `toolRules.noStash` the next step is a WIP commit, never a stash |
| `destructive-delete` | destructive | enforce | before Bash | `rm -r` of anything except scratch folders outside every checkout |
| `git-hook-bypass` | destructive | enforce | before Bash | `--no-verify`, `commit -n`, `-c core.hooksPath=`, `git config core.hooksPath`: switching the repository's checks off (high impact) |
| `cd-into-git-dir` | sensitive write | enforce | before Bash | a `cd` that LEAVES the shell inside `.git`: no longer in a checkout, for every later command (a subshell, a child shell, or moving back out runs) |
| `kill-by-pattern` | destructive | enforce | before Bash | `pkill`, `killall`, `kill $(pgrep ...)`: they also stop the developer's own processes |
| `agent-settings-self-edit` | destructive | enforce | before Bash, Edit, Write | writes to the agent tool's own settings, plugins or hook scripts (`.claude/settings*.json`, `~/.claude/plugins`, `.codex/config.toml`, `.grok/...`, the administrator's managed settings) by the shell (after `cd`, through globs, moves and links of the folder) or by the agent's Write/Edit tools: an agent widening its own permissions or switching its guards off (`disableAllHooks`) (high impact). A shell write into a skill folder (`.claude/skills`, `.codex/skills`, the repository's or the home folder's) is a sensitive write: it rewrites what every later session is told to do |
| `commit-route-only` | sensitive write | enforce | before Bash | a raw `git commit` (also inside `sh -c`, a here-document a shell runs, or an inline program that runs it): use `cotterpin commit`. On by default because Cotterpin's own runs commit through the same route; the message names the opt-out, `cotterpin hook set commit-route-only off --reason "<why>"` |
| `fabricated-commit-id` | sensitive write (read for a git command that only reads) | enforce | before Bash | a git command using a full 40- or 64-character commit id this repository does not have (a typed or remembered id); messages, search patterns and `fetch`/`pull`/`ls-remote`/`clone` are not judged |
| `batch-commit` | sensitive write | enforce (since wave nine) | before Bash | committing part of the finished work minutes after the last commit; a held file that is staged (the refusal names the pattern; `*.bak-*` is held built in); see [tool rules](hooks/tool-rules.md) |
| `live-run-protection` | destructive (sensitive write for a commit) | enforce | before Bash | a commit, or removing a run's worktree, while a Cotterpin run is still working (see below) |
| `worktree-escape` | sensitive write | enforce | before Bash, Edit, Write | an agent in its own worktree writing into another checkout of the same repository |
| `unregistered-checkout-write` | sensitive write | enforce | before Bash, Edit, Write | a write into a copy of this repository that git does not list as a worktree (a pruned, moved or copied worktree, or a full copy): no check, commit or cleanup here ever sees it |
| `locked-worktree` | destructive | enforce | before Bash | `git worktree unlock`, or removing a locked worktree: the lock marks a producer still running |
| `shell-edit-source` | sensitive write | enforce | before Bash | `sed -i`, `perl -i`, `head/tail/awk/sed/... >`, `cp`/`mv` onto a file **git tracks** |
| `self-truncation` | destructive | enforce | before Bash | `cmd file > file`: the shell empties the file before the command reads it (`echo`/`printf` only print their words) |
| `spend-approval` | sensitive write | enforce | before Bash | an agent command that approves or changes a run's model spend: `--consent route...`, `COTTERPIN_CONSENT=route...`, or setting `COTTERPIN_ROUTE_OVERRIDES` / `COTTERPIN_ROUTE_PROVIDER`. A stage above `routing.cap`, or on another provider, is the developer's decision ([MODEL-ROUTING.md](MODEL-ROUTING.md)): they confirm the one command, or sign a pending approval with `cotterpin approve` |
| `unsafe-patch` | destructive | enforce | before Bash | `git diff --no-index <target> <candidate>` captured as a patch (redirected to a `.patch`/`.diff`, piped into `git apply`/`patch`/`tee`), and `git apply`/`patch` of a patch whose `---`/`+++` sides name different files with no declared rename: git applies it as a rename, deleting the file it was meant to edit (`git apply --check` still reports success). `--check`/`--stat` and a merely read `--no-index` diff are allowed; the refusal prints the safe `diff -u -L a/<target> -L b/<target>` generator |
| `raw-build-tool` | sensitive write | enforce | before Bash | a build tool a language pack routes through its own door, run directly (the message prints the door command with the same arguments) |
| `live-output-filter` | sensitive write | enforce | before Bash | a live build/test/commit piped into `tail`/`head`/`grep`/`sed`/`awk`/`wc`, errors sent to `/dev/null`, or a pack-declared quiet flag; with `toolRules.liveOutputFilter: any` (default `builds`) ANY live producer piped into one of those filters (`git log \| head`), except programs that only read or search files (`cat`, `grep`, `rg`, `ls`, `find`, `jq`...); a `\|` inside quotes is data |
| `huge-file-read` | read | enforce | before Bash, Read | reading a file larger than `maxBytes` (512 KiB) whole: it runs, and the agent is told how to read only the part it needs |
| `credential-exposure` | destructive | enforce | before Bash, Read, Grep, Glob | putting a credential into the agent's context BY ANY ROUTE — judged by effect, not by program: any program naming Cotterpin's `licence.json`/`sso.json` (variables, `~`, globs anywhere in the path and `cd` resolved; `python3 -c "open(...)"`, `cp` then `cat`, `git diff --no-index`, `tar`, `$(cat ...)`), `.env` and cloud credential files (also `.credentials.json`, `gh/hosts.yml`), a recursive read over the configuration folder, a name built at run time inside a protected folder (`$(echo licence).json`, `$f.json`, `cd <config> && cat $(ls)`, `ls \| xargs cat` there), brace expansion, `file://` URLs, the Read/Grep/Glob tools on them, an interpreter program's text (a name joined from pieces, `os.getenv('X_TOKEN')`, `process.env.X_TOKEN`, `$ENV{...}`, `ENVIRON[...]` printed; a file the line writes then runs), a variable copied from a secret (`x=$TOKEN; echo $x`) or a here-string of one, a credential file redirected into `cotterpin`, programs whose job is printing a credential (`gh auth token`, `aws configure get\|export-credentials`, `aws sts ...`, `security find-*-password -w`, `git credential fill`, `gcloud auth print-*-token`, `az account get-access-token`, `kubectl config view --raw`, `op read`, `docker-credential-* get`...), and environment dumps (`env`, `printenv`, `set`, `typeset`, `declare`, `ps eww`, `echo $TOKEN`, `${!name}`, `launchctl getenv`, `osascript`'s `do shell script`, `print(os.environ)`) (see [PRIVACY.md](PRIVACY.md)) |
| `os-prompt` | destructive | enforce | before Bash | a command that would make the operating system ask the developer for a password, keychain access or permission (NO-OS-PROMPT-1): a Chromium-family browser started without every no-prompt switch (`--use-mock-keychain --password-store=basic --no-first-run --no-default-browser-check`) and a throwaway `--user-data-dir`, a non-Chromium desktop browser, `open -a <browser>` / `open -b <browser id>` / `open https://...` (the developer's own browser and profile), an installed-browser channel (`--channel=chrome`/`msedge`, `--browser=chrome`), and the `security` commands that ask for the keychain password or show an access dialog (`unlock-keychain`, `add-*-password`, `delete-*-password`, `set-*-partition-list`, `find-*-password -w`/`-g`...); also inside `sh -c`. A word that only mentions a browser (`grep chrome log`) is never a launch. Language packs refuse their own runners' installed-browser options (the Angular pack: `angular-karma-browser`). `tests/conformance/test_no_os_prompt.py` holds the product and its tests to the same rule |
| `approval-integrity` | destructive | enforce | before Bash, Edit, Write | an agent writing, deleting, moving or changing the permissions of the approvals store, the audit log, the session's record of the files it wrote, the approval trust folder, the git pointers that decide where those are (`<git dir>/commondir`, a worktree's `.git` file), an installed Cotterpin (decided by where it is), the hook interpreter's `site-packages` (`.pth`, `sitecustomize`) and `bin`, the release cache, the `cotterpin` launcher in a `bin`/`PATH` folder, the shell start-up files, the configuration folder's `licence.json`/`consent.json`/`clock-watermark.json`, `.cotterpin/hooks.json`, or the records `cotterpin report` measures by (the trajectory, the Watch ledger) — also after `cd`, through a normalised path, a folder, glob, variable, link, tree copy, archive or `find` that reaches them, and in any interpreter's program text (`node -e`, `perl -e`, `ruby -e`, `awk`; names joined from pieces or built from `$COTTERPIN_CONFIG_DIR`/`process.env`); installing, upgrading or removing Cotterpin, or anything into the hook's interpreter, with `pip`/`pipx`/`uv`/`brew`/`conda`; running `cotterpin approve` or the approval signer itself (any wrapper, `python -m cotterpin[.cli]`, `runpy`, a pty helper, `xargs`, `eval`, a git alias); a Cotterpin command whose program, verb, rule or mode is only known at run time (`c=cotterpin; $c ...`, `$(echo off)`) and any command whose program name is; a shell or interpreter fed a program from a pipe or here-string the line does not spell out (`\| base64 -d \| python3`, `curl ... \| sh`); turning a sensitive or destructive rule down with `cotterpin hook set ... off\|advise` (read with the CLI's own parser in any word order, failing closed); the commands that grant standing authority or lower enforcement (`consent grant`, `consent revoke licence...\|all`, `logout`, `machines remove\|move`, `adapters uninstall`, `uninstall`, `--uninstall` — removing Cotterpin from the whole machine, whatever global options come before it —, `upgrade --apply`, `library apply`); writing a program whose text names one of these places or prints a secret; or passing a typed `--gate-change-reason`. At the sensitive tier: running a file this agent session wrote (by any runner: `-X`, `timeout`, `-m`, `import`, `uv run`, `cat f \| sh`, a git alias — DESTRUCTIVE when its text was flagged), and an inline or here-document program that can run other programs (`subprocess`, `os`, `pty`, `child_process`, `system`, `exec`) ([APPROVALS.md](APPROVALS.md), [SECURITY-MODEL.md](SECURITY-MODEL.md)) |
| `memory-direct-write` | destructive | enforce | before Bash, Edit, Write | writing a memory store (`.cotterpin/memory/`, the task store in the git directory, the personal store) by hand: no provenance, and a copied personal fact is a silent promotion; use `cotterpin memory` ([MEMORY.md](MEMORY.md)) |
| `zero-tests-ran` | read (destructive before a commit resting on it) | enforce (since wave nine) | after Bash; before a commit | a test command whose output says no test ran: the result proves nothing, and the session's next commit waits for a run that collects tests |
| `test-run-unscoped` | destructive | enforce | before Bash | a test run that is not the delta: `pytest` with no test file or with a folder, `python -m unittest` with no module or `discover`, or the repository's `toolRules.testDoor` without its own options. The full suite is the deferred verify's baseline ([hooks/tool-rules.md](hooks/tool-rules.md#test-scope)) |
| `perf-run-by-hand` | destructive | enforce | before Bash | a test run that selects speed budgets (a path in a `perf` folder, `-m perf`, or the suite runner pointed at one): only the deferred verify's perf phase runs them, alone and on a quiet machine, and a run by hand adds load to whatever is measuring. Read their numbers from the verify's log ([hooks/tool-rules.md](hooks/tool-rules.md#test-scope)) |
| `java-test-selector-plus` | sensitive write | enforce | before Bash | (Java pack) `-Dtest=A+B`: `+` between classes matches no class |
| `dotnet-ef-remote-database`, `dotnet-ef-drop`, `dotnet-ef-remove-applied`, `dotnet-nuget-publish` | destructive | enforce | before Bash | (.NET pack) EF Core changing a non-local or production database, dropping a database or reverting an applied migration; pushing or deleting a NuGet package ([PACK-DOTNET.md](PACK-DOTNET.md#hook-guards)) |
| `dotnet-nuget-locals-clear`, `dotnet-new-force`, `dotnet-warnings-silenced`, `dotnet-quiet-verbosity`, `dotnet-global-tool-install`, `dotnet-os-prompt` | sensitive write | enforce | before Bash | (.NET pack) clearing the machine-wide NuGet caches, generating over files, switching warning rules off on the command line, quiet builds, machine-wide tool installs, a dotnet command that would open an OS keychain or certificate dialog (`dev-certs`, a web run over HTTPS, `--interactive`) |

Wave nine's further shell, git and file-write rules — stash drops checked by reverse-apply, unsaved reverts, archive
restores, patch headers, worktree budgets and write claims, a run's child leaving its checkout, policy surfaces, frozen
paths, archives, protected branches, approval tokens, backups in a checkout, heredocs where banned, settings that widen
or do not parse, and reading what you were pointed at before writing — are listed with their tiers in
[tool rules](hooks/tool-rules.md).

How each command is read: words, quotes, pipes and redirections are parsed, never matched as substrings; a
here-document's body is data only when the line keeps it as data — a plain reader (`cat`, `grep`), a message (`cotterpin commit -F -`), or a file the line writes and hands to nothing but a plain reader. Otherwise it fails closed and the body is read as the commands it may become: a shell or interpreter runs it (`bash <<EOF`, `python3 - <<EOF`); the file it is written to is a git hook, a shell start-up file or a build file (`Makefile`, `package.json`: its quoted strings too); or another command on the line names that file (`bash r.sh`, `"$PWD/r.sh"`, `$(pwd)/r.sh`, `bash < r.sh`, `chmod +x r.sh`, `cp r.sh s.sh`); or it is piped into anything but a plain reader (`| xargs bash -c`); `eval`'s words, the command `xargs` runs, `echo ... | sh` and the shell commands an inline Python
program runs (`subprocess.run([...])`, `os.system(...)`) are read as the commands they are; a command in a subshell
does not move the caller's shell. The rules that were hard refusals before 2026-10-04 and now classify the
actual effect are listed in [APPROVALS.md](APPROVALS.md#what-changed-in-the-rules-2026-10-04).

"Source" means whatever the repository tracks — Cotterpin asks git, so no rule carries a list of languages. Build
tools, their doors, their quiet flags and their "no test ran" lines come from the installed language packs
(`cotterpin_pack_<id>/hooks.py`), never from the kernel.

Every refusal code is in the [refusal catalogue](REFUSALS.md) (`cotterpin explain hook-<rule>`).

### Live runs and the "just finished" race

`live-run-protection` reads evidence from the repository's shared git folder: a run journal whose status is `running`
and whose process is alive; a task run record that is `active` and was written in the last 10 minutes; or a run's
progress stream written in the last 10 minutes (`freshSeconds`). A run whose journal already records a final status
is **settled** if its last progress write is no later than 5 seconds (`settleToleranceSeconds`) after that record:
the final progress line routinely lands milliseconds after the "completed" record, and without the tolerance a
finished run read as live for ten minutes and refused every commit. A resume writes long after the result, so a
resumed run still reads live. A run lands its own work from inside its own worktree; that commit is allowed.

## Your repository's own steps (extensions)

A repository adds its own behaviour through `.cotterpin/extensions.json` ([CONTRACT-AND-EXTENSIONS.md](CONTRACT-AND-EXTENSIONS.md)).
Its `hooks` entries attach ONLY to git's step hooks (`pre-commit`, `commit-msg`, `pre-push`, ...; never a server-side
hook and never an agent event): Cotterpin's step for that git hook (`cotterpin hooks install`) runs each declared step,
in order, at the bytes the approved lock pins, and the first that fails stops git with its exit code. An edited or
unpinned step file stops git with the reason. An extension may not reuse the name of a rule above. The agent rules on
this page are the product's and the installed packs'; a repository changes them only with `cotterpin hook set`.

## Changing a rule for one repository

```sh
cotterpin hook rules [--json]                                     # every rule, its mode here, and why
cotterpin hook set batch-commit enforce --reason "we always batch" # enforce | advise | off
```

Decisions live in `.cotterpin/hooks.json` (commit it, so every developer and agent gets the same rules):

```json
{"kind": "cotterpin-hook-rules", "schemaVersion": 1,
 "rules": {"batch-commit": {"mode": "enforce", "reason": "we always batch", "changedAt": "2026-10-04T10:00:00+00:00",
                            "options": {"hold": ["docs/drafts/*"], "windowSeconds": 3600}},
           "huge-file-read": {"options": {"maxBytes": 2097152}}}}
```

Nothing is weakened silently:

* changing a rule from its default needs a reason; a hand edit without one is **not applied** (the rule keeps its
  default);
* turning a SENSITIVE or DESTRUCTIVE rule down (`off` or `advise`) also needs a person's signed approval: `cotterpin
  hook set <rule> off --reason "..."` asks the operating system to authenticate you (password or Touch ID, as
  `cotterpin approve` does) and records the signed approval, bound to this repository, rule and mode, in the entry
  (or pass `--approval <id>` for a request already approved with `--bind hook-set:<repository>:<rule>:<mode>`). The
  hook verifies it against the machine's root-owned approval key on every call; a downgrade without one — a hand
  edit, a copy from another machine, an archive, a merge — is **not applied** and is reported. Strengthening a rule,
  and changing a read or low-risk rule, need no approval;
* an unknown rule, an unknown mode, or a file that cannot be read is reported and every rule keeps its default;
* at the start of every session the agent is told which rules this repository changed, with the reasons, and any
  settings problem.

Options: `batch-commit` — `hold` (path patterns never expected in a commit), `windowSeconds`; `huge-file-read` —
`maxBytes`; `live-run-protection` — `freshSeconds`, `settleToleranceSeconds`.

## Where the rules came from: the first customer's hooks, classified

The first customer ran about 191 hook files through a global dispatcher (one script per hook, a manifest saying which
event runs which script, and a bridge per agent tool). Cotterpin replaces the dispatcher and bridges with this one
entrypoint, ports the guards **any** repository needs as rules, moves language-specific ones into the Java pack, and
leaves the customer's own conventions with the customer. Every file, classified:

* **product** — ported here as the named rule, or already owned by another Cotterpin family (named);
* **pack** — belongs to a language pack (Java);
* **consumer-extension** — this customer's repository conventions; they stay in the customer's repository (as its own
  `.cotterpin/checks.yaml` checks, or its own steps on git's step hooks declared in `.cotterpin/extensions.json` —
  see "Your repository's own steps" above);
* **retired** — the job no longer exists once Cotterpin is the entrypoint.

### Dispatch, bridges and hook plumbing

| Hook file | Class | Why |
|---|---|---|
| `claude_hook_dispatch.py` (and its global copy) | retired | Replaced by `cotterpin hook <event>`: one entrypoint, the rule table instead of a manifest of scripts |
| `codex_hook_bridge.py` | product → `cotterpin.hooks.protocol` | Codex payloads (`apply_patch` path extraction, ask→deny) are read by the entrypoint itself |
| `grok_hook_bridge.py` | product → `cotterpin.hooks.protocol` | Grok's camelCase payloads, tool names and exit-2 protocol are read and answered by the entrypoint |
| `gemini_hook_bridge.py` | retired | Not an RC1 agent tool; a fourth protocol is added to `protocol.py` if one is wanted |
| `hook_runtime_parity.py`, `hook_runtime_state.py` | retired | Parity between per-tool hook lists cannot drift when every tool calls the same command |
| `hook_canary.py` | retired | Proof-of-life for a fragile per-repository path; the adapters' freshness tests own this now |
| `live_run_evidence.py`, `apply_live_run_evidence_to_agent_command_guard.py` | product → `live-run-protection` | Live-run evidence is read from Cotterpin's own run journals and progress streams |
| `install_hooks.py` | product → `cotterpin hooks install` | Installing git hooks (chained, never overwritten) is the integrations family |
| `checked_run.py` | retired | Its job (keep the real exit code of a backgrounded command) is the run journal's and the commit route's |
| `external_result_route_contract.py` | consumer-extension | The customer's control-plane contract table |

### The command guard (`agent_command_guard.py`), rule by rule

| Behaviour | Class | Cotterpin rule / owner |
|---|---|---|
| `reset --hard`, `push --force`, `clean -f`, folder-wide `checkout --` (ask) | product | `destructive-git` |
| `rm -r` (ask) | product | `destructive-delete` |
| `--no-verify`, `commit -n`, `core.hooksPath` | product | `git-hook-bypass` |
| `sed -i` / `perl -i` on source, `head/tail/awk/sed >` a file, `cp`/`mv` onto source | product | `shell-edit-source` (keyed on "tracked by git", not an extension list) |
| filtering or silencing live build/test/deploy output | product | `live-output-filter` (+ pack quiet flags) |
| raw `git commit` instead of the single commit owner (incl. inline programs) | product | `commit-route-only` |
| unbatched commit, held file staged | product | `batch-commit` |
| commit while a workflow run is live; worktree remove/unlock of a locked worktree | product | `live-run-protection`, `locked-worktree` |
| live-run settledness with the closing-write tolerance | product | `live-run-protection` (the 5-second tolerance) |
| an isolated agent writing into the primary checkout | product | `worktree-escape` (any other checkout, not just the primary) |
| `cd` into `.git` | product | `cd-into-git-dir` |
| `pkill` / `killall` / kill by lookup | product | `kill-by-pattern` |
| agent writing its own settings, plugins or hook scripts | product | `agent-settings-self-edit` |
| a test runner that collected zero tests (advice) | product | `zero-tests-ran` |
| raw `mvn` instead of the Maven door | pack | Java pack `BUILD_TOOLS` → `raw-build-tool` |
| `-Dtest=A+B` | pack | `java-test-selector-plus` |
| `mvn -pl` without `-am` from a stale local repository | pack | the Java pack's Maven door refuses it (`cotterpin pack java maven`) |
| `mvn clean` (ask: destroys test reports) | consumer-extension | The customer's evidence convention |
| heredoc ban | consumer-extension | An operator preference of this customer, not a hazard in itself; the product reads a here-document as data and judges it only when a shell or interpreter runs it |
| approval grant files, approval environment tokens | product (Cotterpin's own) / consumer-extension (the customer's) | Cotterpin's own approvals are structured pending actions (`cotterpin approve`, [APPROVALS.md](APPROVALS.md)); the customer's own approval files stay with the customer |
| fabricated 40-hex commit ids in git commands | product | `fabricated-commit-id` |
| `git stash drop` of the only copy; per-file revert of unbacked work | product (partly) | `destructive-git` covers `stash drop|clear`; the backing-copy analysis stays with the customer |
| raw docker kill of a test container | consumer-extension | Depends on the customer's container labels and reaper |
| idle fleet before a serial point; queue lanes | consumer-extension | Measures the customer's own backlog files and queue; Cotterpin's Box Budget plans widths instead |
| dispatch while staged / index-quiet window | consumer-extension | Tied to the customer's workflow tool runs; the product commit route judges the staged tree itself |
| harness child shell forms, cwd root drift, child leaving its checkout | consumer-extension | The customer's task-harness child conventions (environment marker, prompt doctrine) |
| patch-bypass of protected / hand-roll paths, autonomy and approval grant files | consumer-extension | The customer's own protected-file lists and approval flow |
| production deploy, local API regeneration, raw RDS restore, gate-skip flags | consumer-extension | The customer's deployment and database tooling |
| test-double writes, pattern-unexecuted advisory, action-premise reads | consumer-extension | The customer's test conventions and receipt files |
| destructive SQL, live migration tool (ask) | consumer-extension | The customer's database tooling |
| foreground commit refused (gate longer than the tool timeout) | retired | `cotterpin commit` runs the fast tier in seconds and defers the slow one |

### Everything else

| Hook file | Class | Why |
|---|---|---|
| `no_output_filter_guard.py` | product | `live-output-filter` |
| the patch-generation safety scanner (its command and patch-header predicates) | product | `unsafe-patch`; its third predicate, which reads the customer's own workflow briefs for a `git diff` capture that omits new files, stays with the customer |
| `dead_worktree_write_guard.py` | product | `worktree-escape` covers writes into another registered checkout; `unregistered-checkout-write` covers writes into a copy git does not list as a worktree |
| `build_cooldown_guard.py` | product → Box Budget | Machine saturation before a dispatch is planned by `cotterpin.kernel.box` and admission, under consent |
| `stranded_patch_guard.py` | consumer-extension | The customer's patch hand-off directories |
| `worktree_staleness.py`, `worktree_orphan_autoheal_writer.py` | product → worktree family | `cotterpin.library.worktree.isolation` (collision-only blocking) and `cotterpin clean` |
| `unfinished_worktree_stop_guard.py` | consumer-extension | Reads the operator's own roster of campaign worktrees |
| `commit_preflight.py`, `commit_hold_autoheal_writer.py`, `pre-commit.py`, `pre-push.py` | product → commit route | `cotterpin commit` (fast tier), deferred verify and `cotterpin push-gate`; the customer's checks move to its `.cotterpin/checks.yaml` |
| `protected_file_guard.py`, `budget_grant.py`, `approval_cta.py`, `approval_claim_guard.py` | consumer-extension | The customer's protected-file list, autonomy windows and approval wording |
| `skill_consult_reminder.py`, `skill_consulted_marker.py`, `rule_freshness_guard.py` | consumer-extension | The customer's skills and rule documents |
| `operator_queue_guard.py`, `active_task_abandon_guard.py`, `idle_capacity_stop_guard.py`, `output_claim_evidence_guard.py` | consumer-extension | The customer's operator queue, turn-end policy and claim auditing |
| `workflow_*` guards and checks (batch, dispatch, dispatch-stale, fanout, harness, lifecycle, prompt-free-brief, reap finalizer, route, routing, runbook parity, self-routing, skill parity, TDZ), `agent_fanout_route_guard.py`, `generic_workflow_check.py`, `harness_manifest_fields.py`, `catalog_drift_guard.py`, `catalog_invocation_check.py` | consumer-extension (routes) / product (contract) | They police the customer's own workflow catalogue. The product equivalents are the kernel's own refusals: product routes resolve from the pack (F1), the runtime validates manifests and contracts, and dispatch is by absolute runtime path, so a stale committed script cannot be run by name |
| `audit_workflow_guard.py`, `audit_workflow_sessionstart.py`, `ledger_writelock_guard.py`, `ledger_provenance_stop_guard.py`, `okf_capability_guard.py`, `okf_grep_reminder.py`, `okf_concept_autoheal_writer.py`, `gate_config_author_check.py` | consumer-extension | The customer's delivery-audit ledger, knowledge bundle and gate configuration conventions |
| `codex_isolation_guard.py`, `codex_handoff_sessionstart.py`, `claude_codex_audit_guard.py` | consumer-extension | The customer's two-agent hand-off board and branch conventions |
| `destub_receipt_guard.py`, `maven_compile_first_guard.py` | pack | Java de-stub receipts and Maven batching belong to the Java pack's de-stub route and Maven door |
| `migration_preedit_reminder.py`, `migration_postedit_check.py` | consumer-extension | The customer's database migration conventions |
| `actuator_exposure_check.py`, `cors_security_check.py`, `prod_config_checklist_check.py` | consumer-extension | Security regressions specific to the customer's services; they belong in its commit checks |
| `gate_permissiveness_scope_cases.json`, `stash_stranded_ratchet.json` | consumer-extension | Data for the customer's own guards |

The customer's `test_*.py` files (about 118) follow their subject's class: tests of a ported behaviour were re-written
against `cotterpin hook` as red/green fixtures (`tests/hooks/`, `tests/packs/java/test_java_hooks.py`); the rest stay
with the customer or retire with their subject. Tests of shared machinery — `test_runtime_hook_ports.py`,
`test_hook_state_isolation.py`, `test_broken_ref_hooks.py`, `test_orphan_scanner_hooks.py` — retire with the
dispatcher; tests of the customer's commit gate (`test_pre_commit_*`, `test_precommit_java_delta.py`,
`test_commit_manager_door.py`, `test_tooling_build_*`) stay with the customer.

The global helpers the customer ran beside its project hooks: the token-saving command rewrite and the reminders are
the developer's own user-level hooks, untouched by Cotterpin; the global output-filter guard is `live-output-filter`.
