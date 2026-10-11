# Memory: `cotterpin memory`

Coding agents forget everything between sessions, and the usual fix — summarise the conversation, store the summary,
inject it forever — stops scaling the day the store grows. Cotterpin gives memory its own architecture, the same for
Claude Code, Codex and Grok:

- **Durable memory** — facts with a scope, provenance, an owner and a lifecycle. The conversation is not memory;
  memory is the residue worth keeping.
- **Retrieval, hybrid** — at session start the agent gets a compact, budgeted index of names; mid-task it searches
  and reads facts on demand. The full corpus is never injected.
- **Consolidation, off the hot path** — a deterministic pipeline that turns raw notes into facts, removes duplicates,
  supersedes contradicted facts and expires stale ones, run in the background after a turn or on demand.

Memory never leaves your machine through Cotterpin ([PRIVACY.md](PRIVACY.md#what-stays-on-the-machine)).

## Scopes

A preference of yours must never silently become your team's policy, and a decision in one checkout must not quietly
become a rule everywhere. Each fact belongs to exactly one scope:

| scope | whose | where it lives | lifecycle |
|---|---|---|---|
| `user` | yours, across every repository | `memory/` in your user configuration directory (`$COTTERPIN_CONFIG_DIR`, else `$XDG_CONFIG_HOME/cotterpin`, else `~/.config/cotterpin`), mode 0700 | kept until you expire it; written only after you allow `memory.user` |
| `repository` | the team's | `.cotterpin/memory/facts/` in the repository — **committed and reviewed like code** | changes only by an explicit command, left in the working tree for your commit |
| `task` | this checkout's current work | `<git dir>/cotterpin/memory/task` (per worktree, never tracked) | expires after 14 days by default; disappears with the worktree |

The repository's own OKF bundle (`.okf/`, or the folder named by `okfBundle` in `.cotterpin/memory.json`) is read
**live** as repository knowledge: each concept appears in the index and in search under an `okf:<path>` id. It is
never copied.

**A user fact never silently becomes a repository fact, and a person approves every promotion.** The only way up is
`cotterpin memory promote <id>`. It never takes a flag, a stored consent or an environment variable as approval —
anything an agent's own tool call could set. Instead:

1. `cotterpin memory promote <id> [--to user|repository]` records a **pending approval request** bound to exactly that
   promotion (`memory-promote:<id>:<scope>`), prints what will be written, where and why, and exits 1 having changed
   nothing. Asking again reuses the same request.
2. The developer runs `cotterpin approve <pa-id>`. An agent runs as the developer's own OS user, so a terminal (a
   pseudo-terminal it opens itself is enough), a code printed on it, an environment variable or a file are all within
   its reach — none of them proves a person. An approval is a **signature** by a key the developer's user cannot read:
   `cotterpin approvals setup` (once per machine; it says what and why, and asks) has `sudo` create a root-owned folder
   (`/private/etc/cotterpin/approvals` on macOS, `/etc/cotterpin/approvals` on Linux) holding an ECDSA P-256 signing
   key readable only by root, its public key and a root-owned copy of the signer. `approve` runs that signer through
   `sudo -k`, so the operating system asks for the account password (or Touch ID) **every time**; the signer shows the
   request, asks for a yes and signs it with who sudo authenticated, when, the scope and the expiry. Where sudo would
   not ask (`NOPASSWD`), approving is refused. Obvious agent processes (their environment markers, no terminal, an
   agent tool among ALL the process's ancestors) are refused earlier, but those checks are not the boundary.
   `cotterpin decline <pa-id>` refuses a request; `cotterpin approvals list` shows what is waiting.
3. `cotterpin memory promote <id> --to <scope> --approval <pa-id>` then verifies the signature against the public key
   in the root-owned folder, writes the new fact with `promotedFrom`, `approval` and `approvedBy` provenance and marks
   the original superseded. A record an agent writes or edits — `status: approved` with a made-up approval, or one
   signed with a key the agent generated — does not verify and is refused. The approval covers that one promotion
   once: another fact, another scope or a second use is refused (`memory-promote-unapproved`).

`memory add` records **new** knowledge in any scope (a repository fact is left in the working tree, so committing it
is the review; a personal fact needs `memory.user`). It refuses to copy an existing narrower fact into a wider store —
the same text, case and spacing aside, as a task fact added to the personal or repository store, or a personal fact
added to the repository store, in any state (`memory-copy-refused`): that is a promotion, and it goes through
`promote` and a person's approval. A paraphrase is new knowledge as far as `add` can tell; the commit review is where a
reworded copy is caught.

These are Cotterpin's ONE approval mechanism (`cotterpin.kernel.approvals`, [APPROVALS.md](APPROVALS.md)): the same
records, the same root-owned signer and the same refusals as every other approval — a destructive hook action, a
guard change, a person's false-positive mark in `cotterpin report` ([SECURITY-MODEL.md](SECURITY-MODEL.md)).
A repository fact is left in the working tree, so committing it is a second review. Promoting a personal fact needs
`memory.user`, like `show`: without it nothing about the fact is printed, planned or copied. Nothing else —
consolidation, import, the agent — moves a fact between scopes, and the `memory-direct-write` hook rule (destructive
tier) refuses an agent that writes a memory store by hand with any shell command or edit tool (Claude's `Edit`,
`Write`, `MultiEdit`, `NotebookEdit`; Codex's `apply_patch`; Grok's `search_replace`, `write`, `delete`). Writing an
approvals store or the trust folder, and running `cotterpin approve` itself (directly or wrapped in `script`, `env -i`,
`python -c`, `sh -c`), are refused by `approval-integrity`, the rule that guards every approval
([HOOKS.md](HOOKS.md)).

## A fact

One JSON file per fact, `<store>/facts/<id>.json`:

```json
{"kind": "cotterpin-memory-fact", "schemaVersion": 1, "id": "r-3fa9c1d2e4b5", "scope": "repository",
 "name": "Architecture diagrams use Mermaid", "description": "Mermaid, not PlantUML, for every architecture diagram.",
 "body": "...", "tags": ["docs"], "paths": ["docs/architecture"], "owner": "repository",
 "provenance": {"by": "agent:codex", "tool": "cotterpin memory add", "source": "typed on the command line",
                "sourceDigest": null, "recordedAt": "2026-10-04T09:12:00Z", "promotedFrom": null},
 "lifecycle": {"state": "active", "expiresAt": null, "supersededBy": null, "supersedes": ["r-0b1c..."],
               "history": [{"at": "2026-10-04T09:12:00Z", "state": "active", "reason": "recorded", "by": "agent:codex"}]}}
```

- **id** — derived from the scope, the name and the normalised text, so the same fact recorded twice is one fact.
- **provenance** — who or what wrote it (`developer`, `agent:<tool>`, `import:<tool>`, `consolidate`, `promote`), with
  which command, from which source (an imported file's path and SHA-256), and when.
- **lifecycle** — `active`, `superseded` or `expired`. A fact's text is never edited: a correction is a new fact that
  supersedes the old one, and the old one keeps its file and its history. A store file whose id no longer matches its
  text is refused (`memory-store-unreadable`).

Every stored field — name, description, text, owner, tags, paths, the provenance's who, tool and source, and every
history row's reason and author — and every journal and note line is passed through the redaction filter
([PRIVACY.md](PRIVACY.md)) before it is written, so a secret typed into any option never reaches a store, `memory
show` or an agent's context. Text is redacted again when it is sent to an assisting provider or injected.

### Rule and trap memories: `enforcedBy`, and `cotterpin memory audit`

A memory that says "never do X" is worth only what enforces it. `--kind` records what a memory is: `fact` (the
default), `rule`, `trap`, `resume`, `hub` or `obsolete`. A `rule` or `trap` must name the mechanisms that enforce it,
as typed ids:

```sh
cotterpin memory add --scope repository --kind rule --name "Never write the memory store by hand" --text "..." \
    --enforced-by hook:memory-direct-write --enforced-by refusal:hook-memory-direct-write
```

| id | exists when | wired when |
|---|---|---|
| `hook:<rule-id>` | a kernel or pack hook rule has that id | (a) each event it judges is bound in the adapters' hook bindings for one of its tools (every logical tool — Bash, Read, Edit, Write, Agent, Workflow, Task, TaskStop, TaskCreate, TaskUpdate, SendMessage — and the tool-less Stop, SubagentStop, SessionStart, UserPromptSubmit); (b) a Stop or SubagentStop rule runs where an agent's protocol can block a stop (else `unwired-advisory`); (c) it enforces here (`advise` or `off` in `.cotterpin/hooks.json` is unwired); (d) with installation checked (`memory audit` and the session start), a `cotterpin hook <event>` entry whose matcher covers EVERY tool name it judges is in at least one agent's effective settings (`~/.claude/settings.json`, the project's `.claude/settings*.json` or its enabled plugin, `~/.codex/hooks.json`, `.codex/hooks.json`, `~/.grok/hooks`, `.grok/hooks`); every other agent is reported `not-installed` |
| `gate:<GATE-ID>` | a row of the kernel's or an installed pack's gate table (read from the table source, no gate imported) | the row names a tier (commit or deferred) AND its enforcement, after this repository's `.cotterpin/gates.yaml` promotion or demotion, is `blocking` (an advisory gate reports and fails nothing) |
| `check:<selector>` | an entry of this repository's `.cotterpin/checks.yaml` | the entry names a route |
| `conformance:<tests/...py>::<name>[::<name>]` | the test is found by a static index (the file is parsed, never imported or collected) | the same |
| `refusal:<code>` | the code is in the refusal catalogue | a hook rule that EMITS the code resolves and is wired (a catalogue entry refuses nothing by itself) |
| `pending:<batch>` | — a promise, never passing: before release candidate 1 only, for a batch both the store's baseline and the release allow, while the store's enforcement debt is within its shrink-only baseline (below), and for at most 30 days after the promise was made (`pendingSince`); from RC1 on, never valid | — |

Without a licence Cotterpin runs in Watch: nothing refuses, so every mechanism, whatever its type, is labelled
`watch-only` — and a memory whose mechanisms refuse nothing is not enforced: Watch FAILS the audit, `memory add` and the
commit tier.

`add` refuses a rule or trap with no mechanism, or with one that does not exist or is not wired, and also a rule-like
id written in its text (`TEST-DELTA-SCOPE-1`) or a typed id (`hook:<id>`, `refusal:<code>`, ...) that does not resolve
and is not named in `--enforced-by` (`memory-unenforced`); a non-rule with `--enforced-by` is refused as well. `cotterpin
memory audit [--scope S ...] [--skip-installation] [--json]` re-measures every active rule, trap and obsolete memory each
time it runs — a hook later switched off, a check removed, a test renamed, an adapter uninstalled — and exits 1 when any
fails (0 when all are `ok`, or `pending` before release candidate 1). It reads the rule table, the bindings, the gate tables, the
refusal catalogue, `checks.yaml`, the agents' settings and the test files statically: no test collection, no network.

### Wave nine: every memory mechanically enforced

Memory is prose, and prose is advisory at best (operator ruling 2026-10-05: "All memories must be mechanically enforced
and codified"). So every rule or trap names a mechanism that BLOCKS, there is no exemption, and the enforcement is
checked where it can break:

* **What a memory is.** `fact`, `resume` and `hub` state what IS: a durable one (user or repository) whose text
  instructs — never/always/must used as an imperative, at the start of a sentence or addressed to someone ("you
  must always"; "the queue must always drain" describes a thing and is a fact) — is refused (`memory-rule-in-fact`)
  when it is recorded AND whenever it is read, so a record written or restored by hand is refused too; split the rule
  out with `--kind rule --enforced-by ...`. `obsolete` names what superseded it and when it retires: `--superseded-by
  memory:<name>|<fact id>|<mechanism id> --retire-at now|backend-switch-off`, and the successor must RESOLVE — an
  active memory, or a mechanism that exists and blocks (`memory-obsolete-invalid`). A retired memory is never served in
  the session index: its text is history.
* **No exemption.** There is no advise strength and no not-enforceable half: a rule whose judgement half no mechanism
  decides is codified as the strongest deterministic predicate that catches it, rewritten as a descriptive fact, or
  deleted. A record carrying `strength`, `strengthApproval` or `notEnforceable` is refused as unreadable.
* **The pending ratchet.** A store's enforcement DEBT — pending entries, `unclassified` imports and `externalClaims`
  (rule ids of another repository's own scripts, which Cotterpin cannot resolve) — may only fall. `cotterpin memory
  baseline --shrink [--scope user|repository]` records it in `<store>/pending-baseline.json` and refuses any increase
  (`memory-pending-grew`); while the debt is above the baseline every pending entry fails (`memory-pending-invalid`);
  the baseline's allowed batches can only narrow (a staged widening fails the commit tier). From release candidate 1
  on, every pending entry fails, and an unclassified rule always fails (it names nothing that blocks). The repository
  store's debt is an open item that refuses a release candidate's tag (`release-rc-open-items`). The file sits in the
  store: `memory-direct-write` refuses writing it by hand, and in a repository it is reviewed.
* **At session start** the audit runs across the user, repository and task stores, with each agent's installed
  settings, and adds one context line per failing memory. It is cached in `<git dir>/cotterpin/memory/audit-cache.json`
  under a stat signature of everything it reads (budget: hit 5 ms, miss 150 ms; a store of plain facts never loads the
  audit). A failing audit leaves `audit-failing.json` beside it, and `cotterpin memory add --kind rule|trap` refuses
  (`memory-audit-failing`) until the failing memories are fixed and the audit passes again.
* **In the commit tier** the check `cotterpin.memory.commit_check` (in `.cotterpin/checks.yaml`; the onboarding
  template `cotterpin.onboarding.checks_template` puts it in a new catalog) reads every staged memory record as the
  store reads it and audits the staged rules, traps and obsolete records, refuses a staged baseline that grows or
  widens its batches, and refuses a staged change that DELETES OR RENAMES a hook rule, kernel or pack gate, check,
  refusal code or memory-named test (named in `enforcedBy`, `intendedBy` or as a typed id in the text) that an active
  memory relies on, or a staged `.cotterpin/hooks.json` / `.cotterpin/gates.yaml` that takes such a rule out of
  `enforce` or such a gate out of `blocking` (`memory-mechanism-removed`) — the ids are read from the HEAD and the
  staged text of the changed files only, so an id moved between files is not removed. A commit touching none of it
  prints `skipped (not relevant)` (budget: 100 ms relevant, one git process otherwise).
* **The memory-write route.** `memory-direct-write` also refuses Edit/Write/MultiEdit/NotebookEdit and shell writes into
  the agent tools' OWN memory folders — `~/.claude/projects/<project>/memory/` (a project folder that is a symlink to
  another project's is resolved), `~/.codex/memories/`, `~/.grok/memory-v2/` — so memory goes through `cotterpin memory
  add --kind ... --enforced-by ...`, where it is audited. A shell write includes the pathspecs of `git checkout`, `git
  restore`, `git rm` and `git mv`. A pure path test (budget 0.1 ms; nothing imported).
* **Classified import.** `cotterpin memory import claude --map <file>` imports each memory file with its kind and
  enforcement from a classification map (JSON: `{"kind": "cotterpin-memory-import-map", "schemaVersion": 1, "entries":
  {"<file>.md": {"memoryKind", "scope": "user|repository|skip|delete", "enforcedBy", "supersededBy", "retireAt",
  "intendedBy", "externalClaims", "name", "description", "body", "note"}}, "splits": [...], "rewrite": [{"pattern",
  "replacement"}]}`): rules and traps about a repository's code or process go to that repository's reviewed store, the
  developer's own preferences to the personal store; an embedded rule is split into its own memory; a memory that
  cannot be codified is rewritten as a fact (`body`) or deleted (`"scope": "delete"` with a `note` saying why); a rule
  or trap with no entry is imported `unclassified`, which fails the audit. A repository store records which memory file
  a fact came from, never the developer's home path.

## Retrieval

### Automatic: the session-start index

At every session start the `SessionStart` hook gives the agent an index like this, and nothing more:

```
Cotterpin memory: 214 fact(s) known here; the most relevant are listed below by name only. Read one in full with
`cotterpin memory show <id>`; look for anything else with `cotterpin memory search <words>`.
- t-cfe166724d0e [task] Payments retry backoff — Retry uses exponential backoff.
- r-c69673abb8f3 [repo] Architecture diagrams use Mermaid — Mermaid, not PlantUML, for every architecture diagram.
- okf:services/payments.md [okf] Payments service — Takes card payments and retries them.
(195 more not listed: cotterpin memory search <words>)
```

- **Bounded** by a token budget: 1,000 tokens by default (estimated as one token per four characters), set with
  `budgetTokens` in `.cotterpin/memory.json` (100–20,000) or `COTTERPIN_MEMORY_BUDGET` for one shell.
- **Ranked deterministically** by relevance to where you are working — no model, no embeddings: the words of the
  branch name (weight 3), of the paths the last 30 commits changed (2) and of the repository folder (1), matched
  against each fact's name, description, tags and paths; 4 more for each of a fact's `paths` that was recently
  changed (at most 3); 2 more for task facts and 1 for repository facts; ties by the most recently recorded, then the
  id. Only active, unexpired facts are listed.
- **Personal facts** are listed only while you allow `memory.user`; otherwise the index says how many were left out.
- **Nothing at all** is injected in a repository with no memory, and `"inject": false` in `.cotterpin/memory.json`
  switches injection off.

`cotterpin memory index [--budget N] [--json]` prints exactly what a session start would inject and its size.

### Automatic: at every prompt, matched to the instruction

The session-start index fires once and lists names only; operators give new instructions mid-session, and a fact
recorded in a concept's BODY never reaches a name-only index. So the `UserPromptSubmit` hook also searches, for THIS
prompt (`cotterpin/memory/prompt.py`), the OKF concepts (full text), the repository's own skills
(`.claude/skills/*/SKILL.md`, `.cotterpin/skills/*/SKILL.md`) and workflows (`.claude/workflows/**` `.js`/`.json`, a
JSON config described by its `description`, `whenToUse`, `summary`, `why` or `justification`), and live task and
repository facts — personal ones only while you allow `memory.user`, exactly as above — and injects at most five
matches, or **nothing**:

```
Cotterpin memory, matched to this prompt (ranked by its rarer words; nothing is shown when nothing matches well). …
The first entry is REQUIRED reading before you write (…); the rest are optional pointers.
- REQUIRED before you write: `.okf/governance/delivery-verification.md` [okf] — Freshness fingerprints: …
- okf:governance/quality-gates.md [okf] — The commit and deploy enforcement layers … (optional: cotterpin memory show okf:governance/quality-gates.md)
- skill backend-flyway-migrations [skill] — Use when writing or shipping a Flyway migration. (optional: cotterpin skill read backend-flyway-migrations)
- `.claude/workflows/delivery-audit-drive.js` [workflow] — Drive the delivery audit shard by shard. Delta-aware.
```

- **Ranked by rarity, silent by default.** Inverse document frequency over the corpus (a word in most documents counts
  for nothing, so there is no stop-word list to maintain); a word in a document's path scores 3×, in its opening
  (title, description) 2×, elsewhere 1×; a document qualifies only when a distinctive word (in under ~15% of the
  corpus) lands in its path or opening, and a generated `capabilities/` concept never qualifies on its own. Below a
  score of 8 nothing is injected ("what time is the standup tomorrow" injects nothing); hits under 45% of the best are
  dropped; every description is clipped to 150 characters and the whole block to 1,600.
- **One required read, not five.** `okf-read-before-write` and `skill-read-before-write` count every `.okf/…md` and
  `skills/<name>/SKILL.md` path injected after the prompt. Only the top hit is written as such a path; the others are
  `okf:<id>` / `skill <name>` pointers those rules do not count, and a path inside a description is rewritten the same
  way. Reading the top hit whole is enough to write.
- **Not the product catalogue.** `cotterpin ops search` (kernel and pack skills, routes, gates, refusals, documents)
  is not searched at a prompt: building it costs about 300 ms, more than a whole hook call; every agent tool already
  carries its summary and the `search` tool.
- **Cost.** The searched folders are listed by `stat` (no file is read) and the prompt is answered from a cached,
  sharded inverted index in `<git dir>/cotterpin/memory/prompt-index/` while that listing, `.cotterpin/memory.json`
  and your consent are unchanged; a prompt reads only the shards its words fall in. A repository with none of these
  folders pays a few `stat` calls and loads no retrieval code. Measured on a copy of a real 1,695-file corpus (1,060
  concepts, 613 workflow files): a warm prompt 6–12 ms in process (+11 ms CPU on a ~58 ms hook call); the rebuild
  after one edited file about 0.35 s (unchanged files are not re-read); the first build about 2.5 s. `"inject":
  false` switches this off too. A problem here never blocks a prompt: it injects nothing.

### Explicit: search and show, mid-task

```sh
cotterpin memory search <words...> [--limit N] [--all-states]   # rank facts and OKF concepts by these words
cotterpin memory show <id>                                       # one fact in full, with provenance and history
cotterpin memory list [--scope S] [--state active|superseded|expired|all]
```

Search scores each query word by where it appears (three times in the name, twice in the description or tags, once
in the text) and by how rare it is across the store. It is deterministic. The `memory` skill shipped in every adapter
tells the agent when to search and how to note what it learns.

## Recording

```sh
cotterpin memory note "<one or two sentences>" [--tag T] [--path P] [--by agent:<tool>]   # raw, for consolidation
cotterpin memory add --scope task|user|repository --name "<few words>" --text "<statement>" \
    [--description D] [--tag T] [--path P] [--owner O] [--supersedes <id>] [--expires-in DAYS] [--by WHO] \
    [--kind fact|rule|trap|resume|hub|obsolete] [--enforced-by TYPE:ID ...]
cotterpin memory promote <id> [--to user|repository] [--dry-run] [--approval <pa-id>]
cotterpin memory expire <id> --reason "<why>"
cotterpin memory audit [--scope S ...]
```

`note` is cheap: one locked append to this checkout's inbox. The note becomes a task fact at the next consolidation.

## Consolidation

```sh
cotterpin memory consolidate [--scope task|user|repository ...] [--assist claude|codex|grok] [--json]
```

Runs on demand, and **in the background after a turn**: the `Stop` hook checks (one file check) whether notes are
waiting and, if so, starts `cotterpin memory consolidate` in its own process session and returns at once. Steps, per
scope:

1. **Extract** — each waiting note becomes a task fact (its first sentence names it).
2. **Normalise** — Unicode NFC, Unix newlines, no trailing spaces, single blank lines; one-line names and descriptions.
3. **Expire** — a fact past its `expiresAt` becomes `expired`.
4. **De-duplicate** — of two active facts in one scope with the same normalised text, or whose content words overlap
   by 85% or more, the later is superseded by the earlier.
5. **Supersede** — a newer fact supersedes an older one in the same scope when both have the same name words, or when
   the newer one's statement says it replaces something the older one states (`X instead of Y`, `rather than Y`,
   `no longer using Y`, `stopped using Y`, `Y is deprecated`). "Architecture diagrams use Mermaid instead of PlantUML"
   supersedes "Architecture diagrams use PlantUML". An imperative such as "replace the file" never retires a fact.

Nothing is deleted and nothing crosses a scope. By default consolidation covers `task`, and `user` when you allowed
it; `repository` only when you name it, because its facts are tracked files (the changes are left for your review).
Every step is journalled in the scope's `journal.jsonl` (task and personal) or `<git common dir>/cotterpin/memory/
repository-journal.jsonl` — never tracked, never sent.

**Provider-assisted review (optional).** `--assist <provider>` asks Claude, Codex or Grok, through its own command-line
tool, to judge the pairs the deterministic steps leave alone (40–85% word overlap): `duplicate`, `a-supersedes-b`,
`b-supersedes-a` or `distinct`. It first states what would be sent (the names, descriptions and text of N pairs, after
redaction), to which provider and why, and sends nothing if you decline (`memory.assist.<provider>`, never
remembered); the deterministic result stands either way. If the provider is missing or fails, the deterministic
report is still printed, with the failure beside it (`memory-assist-failed` on standard error and in the JSON), and
the command exits 1.

## Importing existing memory

```sh
cotterpin memory import claude|codex|grok|okf [--from PATH] [--scope user|repository] [--all-projects] [--map FILE]
                                              [--dry-run]
```

| tool | read from (default) | one fact per |
|---|---|---|
| `claude` | `~/.claude/projects/<repository path with every non-alphanumeric character as ->/memory` — Claude Code's per-project memory folder | memory file (frontmatter `name`/`description`; a `MEMORY.md` line fills a missing description) |
| `codex` | `~/.codex/memories/MEMORY.md` | `# Task Group:` section whose `applies_to: cwd=` is this repository (`--all-projects` for all) |
| `grok` | `~/.grok/memory-v2/workspaces/<repository folder>-*` and `~/.grok/memory-v2/global` | topic and pending observation listed in its `MEMORY.md` |
| `okf` | `--from <bundle>` (required; the repository's own bundle is already read live) | concept (`title`, `description`, `type`, `tags`, `resource`) |

Imports are **read-only**: nothing in the source is created, changed or deleted, and each fact's provenance names the
source file and its SHA-256. Re-importing imports nothing new. An agent tool's memory is yours, so `claude`, `codex`
and `grok` import into the personal store only — unless a classification map (`--map`, above) assigns a file to the
repository; an OKF bundle may go to `--scope repository` (left in the working tree for review). Without a map, a file
whose text instructs is imported as an `unclassified` rule (debt), never as a fact that instructs. Reading another tool's files is asked first (`memory.import.<tool>`), as is the personal store
(`memory.user`); declining imports nothing and exits 1.

## Settings: `.cotterpin/memory.json`

```json
{"kind": "cotterpin-memory-settings", "schemaVersion": 1, "inject": true, "budgetTokens": 1000, "okfBundle": ".okf"}
```

Every key is optional. A malformed file keeps every default and the index says why. `okfBundle: null` stops reading
the bundle.

## Measured

On a copy of a real, large Claude Code memory folder (207 files, 514 KB — about 128,000 tokens), never the original:

| what the agent receives at session start | size |
|---|---|
| today: Claude Code loads the folder's `MEMORY.md` index into every session | 14,312 characters, about **3,578 tokens**, growing with every memory |
| the whole folder, if it were injected | about 128,000 tokens |
| Cotterpin, default budget | **928 tokens**: the 19 most relevant of 206 facts, the rest one search away |
| Cotterpin, `--budget 500` / `2000` | 472 tokens (9 facts) / 1,928 tokens (41 facts) |
| plus that repository's OKF bundle (1,035 concepts, about 2,090,000 tokens of text) | **899 tokens**: 11 of 1,241 entries |

The index stays inside its budget however large the store grows (pinned by `tests/memory/test_memory_retrieval.py`).
Import of the 206 files took about 0.5 s; consolidating them, about 0.25 s.

**Hook cost.** Measured in fresh interpreters that have already loaded the hook router, so only memory's own work is
timed:

| median of 15–21 runs, macOS laptop | session start | end of turn |
|---|---|---|
| a repository with no memory | +0.95 ms (load average ~10); +2.6 ms (load ~15) | +0.05–0.10 ms |
| 206 personal facts + 1,035 OKF concepts, index cached | +12.8 ms (load ~10); +30 ms (load ~15) | +0.08–0.21 ms |

For scale, the whole `cotterpin hook SessionStart` process takes about 60 ms on the same machine. Most of the large
case is listing the 1,035 concept files to notice an edit; a store of a few hundred facts costs a few milliseconds.

A repository without memory pays a few file checks and loads no retrieval code (pinned by
`tests/memory/test_memory_retrieval.py`). With memory, an unchanged store costs a stat-and-read: the index text is
served from `<git dir>/cotterpin/memory/session-snapshot.json` while every store's listing (each file's name, size and
modification time), the settings file, the budget, the branch and HEAD are unchanged and no listed fact has expired,
with no retrieval code loaded and byte for byte the text the full path built (a personal store holding facts always
takes the full path, because listing it is your consent decision). Otherwise the full path answers from
`session-index.json` under the same conditions plus your consent, or rebuilds it from per-store catalogues that are
themselves cached by file listing. Git runs only for a HEAD not seen before. Budget (`tests/perf/
test_memory_budget.py`): a session with 230 facts costs at most +10% CPU over one without memory; measured 1.025x.

## Refusals

| code | when |
|---|---|
| `memory-arguments-invalid` | a scope, name, text or option the command does not accept |
| `memory-not-a-repository` | task or repository memory used outside a git checkout |
| `memory-fact-unknown` | no fact with that id in the scope its id names |
| `memory-store-unreadable` | a store file is not a fact, or its id no longer matches its text |
| `memory-promote-refused` | promoting a fact that is not active, or not to a wider scope |
| `memory-promote-unapproved` | `--approval` names a request a person has not approved for exactly this promotion, or one already used |
| `memory-copy-refused` | `add` would copy an existing narrower fact's text into a wider store (use `promote`) |
| `memory-unenforced` | a rule or trap names no mechanism, or one that does not exist or is not wired |
| `memory-rule-in-fact` | a durable fact, resume or hub instructs (split the rule out, with what enforces it) |
| `memory-pending-grew` | `baseline --shrink`, or a staged baseline, would raise the store's enforcement debt |
| `memory-pending-invalid` | a pending entry at or after release candidate 1, or naming a batch the baseline does not allow, or the debt is above the baseline |
| `memory-audit-failing` | a new rule or trap while the last audit failed |
| `memory-mechanism-removed` | a staged change deletes or renames a mechanism an active memory names |
| `memory-obsolete-invalid` | an obsolete memory without what superseded it and when it retires, or whose successor does not resolve |
| `memory-map-invalid` | an import's classification map is unreadable or malformed |
| `memory-import-source-missing` | no store of that tool where the command looked |
| `memory-assist-failed` | the assisting provider could not be run or gave no usable answer |
| `hook-memory-direct-write` | an agent wrote a memory store, or an agent tool's own memory folder, by hand |

Approving itself refuses with the approval codes every approval shares (`approval-*`, [APPROVALS.md](APPROVALS.md)).

Each is explained by `cotterpin explain <code>` ([REFUSALS.md](REFUSALS.md)). Declining a consent request is never a
refusal: the command does nothing and exits 1. A promotion waiting for a person's approval also exits 1.
