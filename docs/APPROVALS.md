# Risk tiers, approvals and questions

An agent deciding to do something does not mean it should happen. Every action a coding agent takes through
Cotterpin's hooks (`cotterpin hook PreToolUse`, [HOOKS.md](HOOKS.md)) passes through one policy layer between the
agent's intent and its execution:

```
agent's tool call -> classify (one risk tier) -> the tier's outcome -> run | ask the developer | wait for approval
                                             \-> audit log (every decision)
```

The same layer runs for Claude Code, Codex and Grok; only how a confirmation reaches the developer differs (below).

## The four tiers

Every action is classified into exactly one tier: the tier of what it does by itself (reading, or writing), raised by
the tier of every hook rule that found something in it. Each rule declares its tier and why (`cotterpin hook rules`
lists them). What happens is decided by the tier alone — never by a rule.

| Tier | Outcome | Examples |
|---|---|---|
| **read** | runs | `ls`, `git status`, `git show <id>`, reading a file — even a huge one (the agent is told how to read less) |
| **low-risk write** | runs, and is recorded in the audit log | editing a file in your own checkout, `npm install`, `echo x > notes.txt` |
| **sensitive write** | the developer confirms this one action | a raw `git commit` instead of `cotterpin commit`, writing into another checkout, rewriting a tracked file through the shell, a build piped into `tail`, printing a credential |
| **destructive / high impact** | refused until a person approves this exact action | `git reset --hard`, `git push --force`, `rm -r`, `--no-verify`, `pkill`, an agent editing its own settings, removing a running job's worktree |

**Confirming a sensitive write.** In Claude Code with a person at the keyboard, Claude Code's own permission prompt asks
the developer (once, for this action). Codex and Grok cannot be asked from a hook, and neither can a session with
nobody at the keyboard (`COTTERPIN_NON_INTERACTIVE`, CI): there the confirmation is a pending approval, exactly as for
a destructive action.

**Watch.** Without a current Trial, Pro or Team licence nothing is refused ([LICENSING-AND-BILLING.md](LICENSING-AND-BILLING.md)):
the action runs, the agent is told what would have been stopped, and no approval is recorded. Except mid-session: when the hook enforced earlier in the same agent session (its audit log says so) and then reads Watch — the licence or its consent went away — a destructive action still waits for approval. A new session on a lapsed machine is Watch as before.

A repository can still set a rule to `advise` or `off` (`cotterpin hook set <rule> advise|off --reason "<why>"`).
That removes the rule's tier from the decision, needs a reason, and every agent session is told at start. When an
AGENT runs it for a sensitive-write or destructive rule, it is itself a destructive action that waits for approval
(rule `approval-integrity`): with the rule off, what it guards would need no approval.

## Approvals: pending actions a person approves

Approval never depends on the model choosing to ask. When an action needs approval, the hook itself records a
**pending action** and refuses the call:

```
`git reset --hard` throws away every uncommitted change in this checkout. This cannot be undone.
Next: save the work first (...), or ask the developer to approve this exact command
(Cotterpin rule `destructive-git`, tier destructive / high impact. ...)

Approval request pa-1f2e3d4c was recorded (tier destructive; expires 2026-10-04T12:00:00Z). Ask the developer to run
`cotterpin approve pa-1f2e3d4c` in their own terminal (or `cotterpin decline pa-1f2e3d4c`), then run exactly the same
action again — the approval covers this exact action only. Never run `cotterpin approve` yourself: ...
```

A pending action records: its id, **what** will happen (for people), the **action** itself as the person is shown it
(the tool, the working folder and the whole command or edit, with any credential in it redacted), the **exact**
action's digest (which pins the hidden values), **why** it needs approval (the rules' words), the tier and rules,
**who asked** (agent tool and session), when, and when it expires (one hour). An approval is bound to the digest of
the shown action together with the exact digest: an approved action cannot be swapped for another, nor for the same
command with another credential in it. Asking again for the same action while it is pending gives the same id. At
the end of each turn the agent session is reminded of what still waits. A request that can no longer approve anything
(used, declined, expired) is removed a day later, when the next one is recorded; the audit log keeps the history.

The paused work resumes when it is approved: the agent runs the same action again and it runs.

```sh
cotterpin approvals setup                   # once per machine (asks first): the root-owned approval key and signer
cotterpin approvals list [--all] [--json]   # what waits for a person (and, with --all, recent decisions)
cotterpin approvals show <id> [--json]      # everything recorded about one request
cotterpin approve <id> [--once | --for 1h]  # approve it (default --once: one run, within 15 minutes)
cotterpin decline <id>                      # the action stays refused
```

All take `--repository <path>` (default: the current folder). Exit status: 0 done, 2 refused (with the code and the
fix, `cotterpin explain <code>`).

### Who can approve: something an agent cannot produce

An agent runs as YOUR operating-system user. Anything that user can read, write or type, the agent can too: files,
environment variables, a terminal (a pseudo-terminal it opens itself is a real terminal), a code printed on that
terminal. None of those proves a person. An approval therefore needs two things the agent does not have:

1. **A fresh authentication by the operating system.** `cotterpin approve` runs Cotterpin's approval signer through
   `sudo -k`. The `-k` makes sudo ignore any cached authentication and leave none behind, so every approval asks for
   your account password — or Touch ID, on a Mac where you enabled Touch ID for sudo (`pam_tid`) — and nothing an
   agent could reuse afterwards exists. The agent does not know your password and cannot touch the sensor. On Linux
   the same command asks for your password through PAM.
2. **A key only root can read.** `cotterpin approvals setup` (run once, by you; it says what and why first, and
   declining installs nothing — then no action can be approved and destructive actions stay refused) has sudo create
   `/private/etc/cotterpin/approvals` (macOS) or `/etc/cotterpin/approvals` (Linux), owned by root, holding an ECDSA
   P-256 signing key readable only by root (`signing.key`, mode 0600), its public key (`verify.pub`), and a root-owned
   copy of the signer program (`signer`), which sudo runs with the system Python in isolated mode (`-I -S`) — never
   your writable Cotterpin installation.

The signer shows you the request on the terminal — recomputing the digest from the action it shows, so what you read
is what is signed — asks you to confirm, and signs the pending action together with the approval: who sudo
authenticated (`SUDO_USER`/`SUDO_UID`, set by sudo itself), when, the scope and the expiry, from root's own clock.

To approve with NO user-space Cotterpin code between your password and the signature, run the root-owned signer
yourself: `sudo -k /private/etc/cotterpin/approvals/signer approve <id> --repository <checkout> [--for <seconds>]`
(`/etc/...` on Linux). It finds the repository's approvals store by reading the `.git` pointers, reads and writes the
request AS YOU (never as root), shows it, asks, and signs it — the same record `cotterpin approve` writes. Every
refusal names this command beside `cotterpin approve <id>`.

Turning a sensitive or destructive rule down (`cotterpin hook set <rule> off|advise --reason "..."`) is approved the
same way: the command raises a request bound to `hook-set:<repository>:<rule>:<mode>` and approves it through the
operating system's authentication, and the settings file keeps the signed approval; the hook lowers the rule only when
it verifies ([HOOKS.md](HOOKS.md#changing-a-rule-for-one-repository)).

The hook honours an approval only when that signature verifies against `verify.pub` in the root-owned folder; the
folder and every folder above it must be owned by root and not writable by anyone else
(`approval-trust-unsafe` otherwise). So a record an agent writes or edits in the approvals store — a forged
"approved", a longer expiry, another action — carries no valid signature: the hook ignores it, tells the agent, and
records `approval-forged` in the audit log. A key the agent generates itself is never trusted, because it is not in
the root-owned folder.

When this cannot be guaranteed, approving refuses rather than pretending: no trust folder
(`approval-presence-unconfigured`), sudo that would not ask for a password — `NOPASSWD`, found with a `sudo -n -k`
probe that never prompts (`approval-presence-unavailable`) — or an authentication that was not given
(`approval-presence-failed`). The earlier checks stay as friendly early refusals for the obvious cases: no terminal
(`approval-needs-terminal`), an agent tool's environment marker or an agent tool (`claude`, `codex`, `grok`) anywhere
among the command's ancestor processes (`approval-agent-refused`). They are not the boundary; the operating system's
authentication and root's key are.

Defence in depth: the hook rule `approval-integrity` (destructive tier) refuses an agent writing, deleting, moving,
linking or changing the permissions of the approvals store, the audit log, the trajectory and the Watch ledger, the
git pointers that decide where they are, the trust folder, an installed Cotterpin and the interpreter folders it runs
from, the `cotterpin` launcher and the shell start-up files (which decide what `cotterpin approve` runs in your
terminal), the configuration folder's licence, consent and clock-watermark files or `.cotterpin/hooks.json` (by any
tool, shell command or interpreter program, also through a folder, glob, variable, tree copy, archive or `find` that
reaches them), installing or removing Cotterpin with a package manager, running `cotterpin approve` or the signer
itself in any form (a variable, a substitution, `xargs`, `eval`, `python -m cotterpin.cli` — what stays unknown fails
closed), turning a sensitive or destructive rule down with `cotterpin hook set
<rule> off|advise` (in any word order) — with the rule off, what it guards would need no approval, so turning it off
needs one — and the Cotterpin commands that grant standing authority or lower enforcement: `consent grant`, `consent
revoke licence...`, `logout`, `machines remove|move`, `adapters uninstall`, `uninstall`, `--uninstall` (the whole
machine), `upgrade --apply` and
`library apply`. At the sensitive tier it asks before a script this agent session wrote is run, and before an inline
or here-document program that can run other programs.

### ONE approval mechanism

Everything in Cotterpin that grants authority goes through these same records, this same signer and these same
refusals (`approval-*`) — there is no second approval format anywhere:

| What needs a person | Bound to | Consumed by |
|---|---|---|
| a destructive (or unaskable sensitive) agent action | the exact action's digest | the hook, when the same action is run again |
| promoting a memory fact to a wider scope | `memory-promote:<fact>:<scope>` | `cotterpin memory promote <id> --approval <pa-id>` |
| a release that changes a guard | `gate-change:<commit>` | `prepare-release-install` / `guard-review --gate-change-approval <pa-id>` |
| a person's false-positive mark | `report-mark-fp:<refusal id>` | `cotterpin report mark-fp <id> --approval <pa-id>` (re-verified each time the report counts it) |
| routed spend above the cap, or on another provider, an agent's command asks for | the exact command (`spend-approval`, sensitive) | the hook |
| a standing consent grant, dropping the licence, removing the hooks | the exact command (`approval-integrity`) | the hook |

A command that consumes a bound approval checks the bind written on the record AND the bind inside the signed action,
the signature against the root-owned key, and — for a one-use approval — that the audit log has not already recorded
its use (`approved-run`), under a lock, before it marks it used. A routing consent is never stored (a standing grant
of above-cap spend is refused), so it needs no standing approval.

Limits, honestly: whoever can authenticate as an administrator on the machine can approve — that is the person the
operating system vouches for. A pending action is written by the hook when no person is there, so it is not signed;
it carries no authority until the signer, showing the person the action itself, signs it. A `--once` approval is
marked used in the store, which your user can write, AND its run is in the audit log: setting its status back does
not make it usable again. The setup step runs only a RELEASE-SIGNED signer: the digest comes from the signed release
the running Cotterpin was installed from (a development checkout refuses, `approval-signer-unsigned`), and the root
process reads the signer's bytes once, checks that digest, and runs a root-owned copy — never your writable file.
The signing screen shows every control character as a visible escape (`\x1b`), so an escape sequence in a command
cannot hide what you approve.

**Hardened mode** (the administrator's root-owned security policy is installed —
[SECURITY-MODEL.md](SECURITY-MODEL.md)): the same signed, OS-authenticated approval, and enforcement never depends on a
user file — a missing or edited licence never drops the machine to Watch, and `.cotterpin/hooks.json` never turns a
sensitive or destructive rule down.

**Bound to the organisation's authority.** An administrator can also require every approval to carry a fresh assertion
from the policy's hardware-key or OIDC authority, by naming the registered action `approval.grant`:

```json
"actionAuthorities": {"default": ["desk-key"], "approval.grant": ["desk-key"]}
```

Then:

```sh
cotterpin approve <id>                     # asks your enrolled key (Touch ID / security key) or a step-up login first
cotterpin approve <id> --authority corp-sso   # when the policy names more than one
cotterpin approvals presence <id> --out p.json   # for the direct root path:
sudo -k /private/etc/cotterpin/approvals/signer approve <id> --repository <checkout> --presence p.json
```

The assertion covers exactly this approval (its id, action digest, scope and duration, the operator and a fresh nonce).
The root-owned signer verifies it with the hardened install's own root-owned runtime before it shows the request, and
signs the verified summary into the approval; the hook honours an approval on such a machine only with that summary.
A hardware key's signature counter must rise, so an assertion cannot be used twice. The assertion must be from the
account sudo authenticated. Only `hardware-key` and `oidc` authorities can bind approvals: AWS IAM decides in its own
custody (a deployed broker) and proves nothing to the signer about the person at the keyboard.

Enrolling a key is two steps, because the registry of keys is root-owned:

```sh
cotterpin auth hardware-key enrol --out key.json                        # the person: touch the key / Touch ID
sudo cotterpin auth hardware-key install-credential --record key.json   # the administrator, after review
cotterpin auth hardware-key list
```

An agent can do neither: `cotterpin approvals presence` is refused by `approval-integrity`, and enrolment needs a
person at a terminal.

### An agent may raise a request, never approve one

```sh
cotterpin approvals request --what "<exactly what will happen>" --why "<why it is needed>" [--bind <what it covers>]
```

An agent that knows it will need approval raises the request first, so the developer can approve it while the agent
works. `--bind` names the exact thing a command that consumes the approval checks (for example
`gate-change:<commit>`).

### What replaced the typed approvals

Cotterpin's own release review used to take an approval as typed text: `--gate-change-reason "HUMAN-APPROVED-GATE-CHANGE:
<why>"` on `cotterpin prepare-release-install` and `release_authoring guard-review`. Any process can type text. Now:

```sh
cotterpin approvals request --bind gate-change:<release commit> --what "release touches guard files" --why "<why>"
cotterpin approve <id>                                   # the developer, in their own terminal
cotterpin prepare-release-install ... --gate-change-approval <id>
```

The recorded review text names who approved it, when, and the request. **Migration:** a bare `--gate-change-reason`
is no longer accepted as text. It raises the gate-change request with that text as its reason and approves it right
there through the same signer and `sudo -k` authentication — so `tools/release/cut_release.py adopt --reason-file`
keeps working for an operator at a terminal, and refuses for anyone the operating system does not authenticate (an
agent's call is refused before that by the `approval-integrity` hook rule). Approval files and approval environment
variables that a customer's own tooling uses are the customer's; Cotterpin's own approvals all go through
`cotterpin approve`.

## Questions: asking the developer

A model that is missing something only the developer knows — which environment "the payments service" means, which of
two branches to use — asks through its agent tool's normal question path: a plain question in its reply, or the tool's
ask-the-user feature. That is model-initiated clarification, a different primitive from approval:

* an answer is information, never permission — "yes, go ahead" in a chat does not approve a refused action; only
  `cotterpin approve <id>` at the developer's terminal does;
* in a long-running task the agent pauses with its state intact and says exactly what it needs to continue.

The shipped skill `approvals-and-questions` (in every adapter: Claude Code, Codex and Grok —
[AGENT-ADAPTERS.md](AGENT-ADAPTERS.md)) tells agents exactly this.

## The audit log

Every decision on a tool call is one line in `<git common dir>/cotterpin/audit/actions.jsonl` — the repository's
private git folder, never a tracked file and never sent anywhere (outside a git checkout:
`<config dir>/audit/actions.jsonl`). It is written in the trajectory's schema — ONE schema for the audit and for
`cotterpin report` ([OBSERVABILITY.md](OBSERVABILITY.md)):

```json
{"kind": "cotterpin-trajectory", "schemaVersion": 1, "type": "action", "id": "3f9a0c1d2e4b", "at": 1791100923.12,
 "agent": "claude", "session": "...", "run": "", "checkout": "/work/shop", "tool": "Bash", "tier": "destructive",
 "rules": ["destructive-git"], "outcome": "approval-pending", "decision": "deny", "digest": "sha256:...",
 "summary": "shell: git push", "approval": "pa-1f2e3d4c"}
```

It never holds the raw command — a command line may carry a secret — only the programs it runs (`summary`) and the
digest that identifies the exact action. Outcomes: `run`, `run+audit`, `advised`, `confirm-asked`,
`approval-pending`, `approved-run`, `approval-forged` (a record claimed an approval its signature does not carry),
`refused` (Cotterpin could not check the action), `watch-reported`, and for the approval commands `approved`,
`declined`, `requested`, `approval-refused`. Each line is ONE `O_APPEND` write (no fsync, no extra stat; measured well
under a millisecond). The line that takes the file past 2 MiB is written whole, then the file becomes
`actions.jsonl.1` (replacing the older one) and the next line starts a new file.

## What changed in the rules (2026-10-04)

Each hard refusal was re-examined against what the action actually does. The safe form now runs; the dangerous form
is still stopped (each pinned by a test in `tests/hooks/test_hook_policy.py` and `tests/hooks/test_hook_rules.py`):

| Was refused | Now | Still stopped |
|---|---|---|
| a here-document that only writes a note mentioning `git commit`, `git reset --hard`, `pkill` | runs: a here-document the line keeps as data is data | `bash <<EOF` / `python3 - <<EOF` whose body runs a commit; a body written to a git hook, a shell start-up file or a build file, or to a file another command on the line names (`bash r.sh`, `"$PWD/r.sh"`, `bash < r.sh`, `cp r.sh s.sh`), or piped into anything but a plain reader; an interpreter here-document that imports `os`/`subprocess`/`pty`/`child_process` (sensitive); `eval`, `xargs`, `echo ... \| sh` and a Python program's `subprocess`/`os.system` calls |
| backticks in prose (a quoted commit message, a note) | runs | `` kill `pgrep ...` ``, which the shell runs |
| a command that only mentions another (`echo 'never run pkill'`, `man pkill`, `pkill --help`) | runs | `pkill node` |
| `(cd .git && ls)`, `cd .git && ls && cd ..`, `sh -c 'cd .git && ...'` | runs: the shell is not left inside `.git` | `cd .git/refs && ls` |
| `printf 'see notes.md' > notes.md` | runs: `printf`/`echo` only print their words | `sort notes.md > notes.md` |
| `git show <typed id>`, `git diff HEAD..<typed id>` | runs (a read), with the advice | `git checkout`/`reset`/`cherry-pick`/`rebase` at a typed id |
| reading a huge file whole | runs (a read), with the advice | — |
| `git commit --no-verify`, an agent editing its own settings, `pkill` | explicit approval (a person decides, bound to the command) | — until approved |
| a compound git command whose every part targets the agent's own checkout | runs (it always did; now pinned) | a part that writes into another checkout |
