# Agent tool adapters: Claude Code, Codex and Grok

Cotterpin works inside the coding agent you already use. One command puts its capability index (a compact summary
and the `cotterpin` MCP server the agent searches and loads from), agents, route commands and guard hooks into a
repository for **Claude Code**, **Codex** or **Grok**, and one command takes exactly that back out.

```sh
cotterpin adapters list                      # the three adapters this release ships, each with its digest
cotterpin adapters install <claude|codex|grok> [--repository <path>] [--dry-run] [--yes]
cotterpin adapters status [--json]           # what is installed here, and whether any of its files changed
cotterpin adapters uninstall <claude|codex|grok>
cotterpin adapters verify                    # this Cotterpin's adapters are exactly the ones its release pinned
```

Exit status: 0 done (or already installed, or a dry run, or nothing to remove), 1 declined, 2 refused. Every refusal
ends with `Next:` and the exact command to run; `cotterpin explain adapter-<code>` says more
([REFUSALS.md](REFUSALS.md)).

## What each adapter writes

Everything is **project scope**: only files inside the repository are read or written, so the whole team gets the
same adapter by committing it. Nothing in your home folder changes.

| Adapter | Files it owns | Shared file it extends |
|---|---|---|
| `claude` | `.cotterpin/adapters/claude-plugin/` — a Claude Code plugin (`.claude-plugin/plugin.json`) that is also its own one-plugin marketplace (`.claude-plugin/marketplace.json`), with `.mcp.json`, `skills/cotterpin/`, `agents/`, `commands/` and `hooks/hooks.json` | `.claude/settings.json`: `extraKnownMarketplaces.cotterpin` (a `directory` source at `./.cotterpin/adapters/claude-plugin`) and `enabledPlugins["cotterpin@cotterpin"]` |
| `codex` | `.codex/agents/<name>.toml`, `.codex/hooks.json`, `.codex/runbooks/<runbook>.md` | `AGENTS.md`: one marked block; `.codex/config.toml`: one marked block, `[mcp_servers.cotterpin]` |
| `grok` | `.grok/plugins/cotterpin/` (a Grok plugin: `.grok-plugin/plugin.json`, `skills/cotterpin/`, `agents/`, `commands/`, `hooks/hooks.json`), `.grok/hooks/cotterpin.json`, `.grok/playbooks/<runbook>.md` | `.grok/config.toml`: one marked block, `[plugins] enabled = ["cotterpin"]` and `[mcp_servers.cotterpin]` |

Each install also writes its record, `.cotterpin/adapters/<adapter>.install.json`: the release, the adapter's digest,
the sha256 of every file it wrote, the blocks and settings it added, and the folders it created.

What each part is for:

* **the capability index** — progressive disclosure ([PROGRESSIVE-DISCLOSURE.md](PROGRESSIVE-DISCLOSURE.md)). No
  adapter copies the skills or lists the catalogue. Each registers the read-only MCP server `cotterpin mcp serve
  --agent <tool>` and puts only a compact summary (packs, skill families and workflow ids by name) and "search before
  loading" guidance in front of the model: as the one `cotterpin` skill for Claude Code and Grok, as the `AGENTS.md`
  block for Codex. The agent `search`es, then `load`s the skill ([SKILLS-AND-AGENTS.md](SKILLS-AND-AGENTS.md)),
  workflow, gate, refusal or document it needs; a known id loads directly. Codex reads a project's
  `.codex/config.toml` only once you trust the project;
* **agents** — the product and pack agents. Claude Code gets them as shipped; Codex gets each as an agent role file
  (`name`, `description`, `developer_instructions`); Grok gets them without the Claude model name (its models are
  its own; each route says the effort a role needs);
* **route commands** — `/cotterpin:route` picks the route for a request; `/cotterpin:run-<task>` runs one route.
  They are for the person to type (`disable-model-invocation`); the model reaches the same route through
  `load workflow:<task>`. Claude Code's command carries the route's runbook, its roles, the agent for each role and
  the model and effort.
  Codex and Grok cannot run a route's workflow script, so for them the runbook is the procedure:
  `.codex/runbooks/<runbook>.md` and `.grok/playbooks/<runbook>.md`, each with the route's roles and agents;
* **hooks** — every agent event calls the one entrypoint, `cotterpin hook <event> --agent <tool>`
  ([HOOKS.md](HOOKS.md)): `SessionStart`, `UserPromptSubmit`, `PreToolUse` (the `Bash`, `Read`, `Edit` and `Write`
  tools and the dispatch tools `Agent`, `Workflow`, `Task`, `TaskStop`, `TaskCreate`, `TaskUpdate`, `SendMessage`),
  `PostToolUse` (`Bash`, `Read`, `Edit`, `Write`, `Agent`, `Workflow`, `TaskCreate`, `TaskUpdate`), `Stop` and
  `SubagentStop` (both able to BLOCK the end of a turn in all three tools). The bindings are one product file,
  `cotterpin/adapters/hook-bindings.json`, naming the entrypoint's own events and logical tools; each adapter's matcher
  is built from the names the entrypoint itself reads as each tool (`cotterpin.hooks.protocol.AGENT_TOOL_NAMES`), so
  no call a rule judges can bypass it:

  | Logical tool | Claude Code | Codex | Grok |
  |---|---|---|---|
  | `Bash` | `Bash` | `Bash`, `container.exec`, `exec_command`, `local_shell`, `shell`, `unified_exec` | `run_terminal_command` |
  | `Read` | `Read` | `Read` | `read_file` |
  | `Edit` | `Edit`, `MultiEdit`, `NotebookEdit` | `apply_patch` (every path in the patch is checked), `Edit`, `MultiEdit`, `NotebookEdit` | `search_replace`, `delete`, `delete_file` |
  | `Write` | `Write` | `Write` | `write` |
  | `Agent` | `Agent` | `spawn_agent` | `spawn_subagent` |
  | `Workflow` | `Workflow` | — | `workflow` |
  | `Task`, `TaskStop`, `TaskCreate`, `TaskUpdate`, `SendMessage` | the same names | — | — |

  A tool an agent does not have contributes no name (never an empty matcher, which would match every call).

  `tests/adapters/test_render.py` holds every rule's events and tools to these matchers for all three tools.
  `cotterpin uninstall` removes every installed adapter through this family's own uninstall.

  Grok runs a project's hooks from `.grok/hooks/`; the plugin carries the same file, and Grok runs identical
  handlers once.

## Asking first

Before writing anything, `install` lists every file and setting, then says **what** it will write, **where**,
**why**, and **what happens if you say no** — through Cotterpin's one consent mechanism
([CONSENT-AND-BOX.md](CONSENT-AND-BOX.md)). Saying no, or running without a terminal and without `--yes`
(`COTTERPIN_NON_INTERACTIVE`, CI), writes nothing: the agent tool keeps working without Cotterpin's skills, commands
and guard hooks. `--dry-run` prints the same list and statement and writes nothing. The answer is for that one
install only; it is never remembered.

Install also refuses, before writing anything, when:

* a file it would own already exists and Cotterpin did not write it (`adapter-file-exists`) — it never overwrites
  one, and it never adopts a Cotterpin block that no install record names;
* `.claude/settings.json` is not valid JSON, or `.codex/config.toml` / `.grok/config.toml` is not valid TOML
  (`adapter-settings-unreadable`);
* `.claude/settings.json` already sets one of the two settings, or `.grok/config.toml` already has its own `plugins`
  setting (`adapter-settings-conflict`) — add `"cotterpin"` to its `enabled` list yourself — or `.codex/config.toml` /
  `.grok/config.toml` already declares an MCP server named `cotterpin` (`adapter-settings-conflict`). The TOML is
  parsed, so every valid spelling counts: a `[mcp_servers.cotterpin]` or quoted `[mcp_servers."cotterpin"]` header,
  `cotterpin = { ... }` inside `[mcp_servers]`, or a dotted key;
* the configuration would not parse with Cotterpin's block added (`adapter-settings-unreadable`) — for example an
  inline-table `mcp_servers = { ... }`, which no table header may extend. A valid configuration is never turned into
  one the agent tool cannot read;
* a path leads out of the repository through a link (`adapter-path-outside`);
* another copy of the adapter is installed, or one of its files changed (`adapter-installed`): uninstall first;
* the adapter it would write is not exactly the one this release pinned (`adapter-pin-mismatch`), or a language pack
  the adapter includes is not installed at the pinned version (`adapter-pack-missing`).

## Approvals and questions in every adapter

All three adapters carry the same hooks and the same skill, `approvals-and-questions`, so the three agent tools behave
the same way ([APPROVALS.md](APPROVALS.md)):

* **Approval is the harness's.** A destructive action (and, in Codex and Grok, which cannot be asked from a hook, a
  sensitive write) is refused by the hook with a pending approval; the agent tells the developer the id, the
  developer runs `cotterpin approve <id>` in their own terminal, and the agent runs the same action again. In Claude
  Code a sensitive write is confirmed in Claude Code's own permission prompt. The model never decides whether to ask.
* **Asking the developer is the model's.** When the agent is missing something only the developer knows, it asks
  through the agent tool's normal question path — a plain question in its reply, or the tool's ask-the-user feature
  — and waits. An answer is information, never permission: it grants nothing that needs `cotterpin approve`.

## Taking it out

`uninstall` reads the record and removes exactly what it lists:

* a file still byte-identical to what was written is deleted; one changed since is **kept** and named;
* its block is cut out of `AGENTS.md` / `.codex/config.toml` / `.grok/config.toml`, leaving your text byte for byte as it was (the file is
  deleted only if Cotterpin created it and nothing else is in it); an edited block is kept and named;
* `.claude/settings.json` is put back byte for byte when nobody changed it since; otherwise only Cotterpin's two
  settings are removed and everything else is kept;
* folders it created are removed when empty, and so is the record.

On a repository nobody touched in between, install followed by uninstall leaves every file as it was.

## After the install: commit it, then start the agent tool

`install` ends with two next steps:

1. **Review, then commit it** — the exact `git add <paths> && cotterpin commit -m "..."` that stages the install and
   nothing else: each folder the install created is named once, and a file in a folder that was already there
   (`AGENTS.md`, `.claude/settings.json` beside your own settings) by itself. Cotterpin's own commit-tier checks
   recognise the adapter's files by the install record and this release's pins
   (`cotterpin.adapters.install.unedited_files`): a file whose staged bytes have the sha256 its record lists AND the
   one `pins.json` pins is Cotterpin's generated text, so, for example, a shipped runbook's example ARN needs no
   `Infra-Delta:` trailer. An edited file — even with its record edited to match — is judged like any other file.
2. **Start (or restart) the agent tool in this repository** — each tool loads the adapter only when a session starts,
   and only once you trust it (below). For Claude Code: approve the `cotterpin` plugin it offers; if it does not,
   run `/plugin marketplace add ./.cotterpin/adapters/claude-plugin`, then `/plugin install cotterpin@cotterpin`, then
   `/reload-plugins`.

`cotterpin adapters status` repeats the second step for each installed adapter: Cotterpin cannot see inside a running
session, so it never claims the adapter loaded (`--json`: `sessionLoaded` is `null`, `sessionNextStep` the step). In
Claude Code, `/plugin` lists `cotterpin` as enabled and `/mcp` lists its server once a session loaded it.

## The first time each tool opens the repository

Each tool asks you, once, to trust what the repository asks it to run:

* **Claude Code** offers to install the repository's `cotterpin` plugin from the marketplace the project settings
  declare, and asks you to trust it;
* **Codex** asks you to trust the repository's hooks (`.codex/hooks.json`) before it runs them;
* **Grok** runs a project's hooks, plugin, skills and instructions only in a folder you trust (`/hooks-trust`, or
  start it with `--trust`).

## Pinning: how the lock covers the adapters

An adapter is a pure function of shipped files, so it is pinned by digest, never copied into the lock:

1. `cotterpin/adapters/pins.json` records, for each adapter, the digest of its files (sha256 over the sorted
   `{path, sha256}` pairs — the same form the lock uses for a pack's content digest), each file's sha256, the release
   and the pack versions it includes. It is generated together with the adapters.
2. `pins.json`, the rendering code and every source file — skills, agents, routes, runbooks,
   `hook-bindings.json` — are runtime files of the release, so the repository's `.cotterpin.lock.json` pins each of
   them by sha256 and Git blob id (`runtimePackage.files`, and each pack row's `files`;
   [LOCK-AND-PACKS.md](LOCK-AND-PACKS.md)). The lock therefore pins every adapter transitively: lock → `pins.json` →
   adapter digest → each file.
3. `cotterpin adapters install` renders the adapter from the runtime the lock admitted and refuses unless the result
   equals the pinned digest; the install record keeps that digest, and `cotterpin adapters status` reports when the
   installed copy differs from what the current release pins (after an upgrade: uninstall, then install).

## For Cotterpin's own developers

The adapters are generated by ONE generator, from one provider-neutral source:

```sh
python3 tools/adapters/build_adapters.py          # writes adapters/{claude-plugin,codex,grok}/ and cotterpin/adapters/pins.json
python3 tools/adapters/build_adapters.py --check  # lists every stale, missing or extra file
```

The rendering lives in the shipped `cotterpin.adapters.render` so an installed Cotterpin renders exactly what was
committed. `tests/conformance/test_adapter_freshness.py` fails when a committed adapter differs from what the
generator produces now; change a skill, agent, route, runbook or binding, then rebuild. The sources are validated as
they are read: malformed frontmatter, a name used twice, a skill named like a route command, a route naming a runbook
or agent that does not ship, or a binding that does not call `cotterpin hook` is refused with the file named.

How each adapter is checked with the real tool (`tests/adapters/test_agent_tools.py`, no sign-in, no prompt sent):

| Tool | Command | What it proves |
|---|---|---|
| Claude Code | `claude plugin validate --strict` | the plugin and marketplace manifests |
| Claude Code | `claude --plugin-dir <plugin> plugin details cotterpin` | the gateway skill, every command, agent, the six hook events and the MCP server load |
| Claude Code | `claude --plugin-dir <plugin> mcp list` | Claude Code starts `cotterpin mcp serve --agent claude` and connects |
| Codex | `codex debug prompt-input` | the `AGENTS.md` block reaches the model, and nothing of Cotterpin's beyond it (under 4 KiB) |
| Codex | `codex mcp list --json` (trusted project) | the server is read from `.codex/config.toml` |
| Grok | `grok plugin validate` | the plugin manifest |
| Grok | `grok inspect --json` (`GROK_FOLDER_TRUST=0`) | the plugin is found and enabled with its one skill, and every hook in `.grok/hooks` is a project hook Grok runs |
| Grok | `grok mcp doctor cotterpin --json` | Grok starts the server, completes the MCP handshake and discovers the three tools |

Codex has no offline command that loads `.codex/hooks.json` or `.codex/agents/`, and Grok reports a plugin's agents
only as a folder count; those files are pinned by format tests (`tests/adapters/test_render.py`) and by the
real-provider acceptance tier.
