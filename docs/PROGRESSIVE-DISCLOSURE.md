# Progressive disclosure: search, then load

Cotterpin offers an agent a lot: product and pack skills, workflows (routes), agent roles, code gates, hundreds of
refusal explanations and the product documents. Putting all of it in front of the model in every session costs
context the task needs, and most of it is never used. So an agent sees a **compact capability summary** and three
operations, and pulls in the one item it needs, when it needs it.

| Operation | What it returns |
|---|---|
| `list_capabilities` | the installed packs, the workflow ids, the skill families by name, and how many of each kind exist — no descriptions |
| `search <words> [kind]` | ids with one-line descriptions only, best first (kinds: `skill`, `workflow`, `agent`, `gate`, `refusal`, `doc`) |
| `load <id>` | the full text of one id, plus every id its text references, each as a one-line row |

The same three are a command and an MCP server:

```sh
cotterpin ops list-capabilities [--json]
cotterpin ops search <words...> [--kind skill|workflow|agent|gate|refusal|doc] [--limit N] [--json]
cotterpin ops load <id> [--agent claude|codex|grok] [--json]
cotterpin mcp serve [--agent claude|codex|grok]       # stdio JSON-RPC: list_capabilities, search, load
```

Exit status: 0 answered, 1 a search found nothing, 2 refused. A refusal prints its code with the cause, the fix and
the next command (`cotterpin explain <code>`; the `ops-*` codes are in [REFUSALS.md](REFUSALS.md)). `--json`, or the
global `--ci`, prints the machine-readable answer.

## Ids

| Id | What it is | Loads |
|---|---|---|
| `skill:<name>` | a product or pack skill | its `SKILL.md`, byte for byte |
| `workflow:<task>` | a route | the roles (the agent for each, for the asking agent tool), model and effort, the contract's ownership, routing, verification and result envelope, then the runbook |
| `agent:<name>` | an agent role | its instructions |
| `gate:<ID>` | a code gate | what it catches, why, the remedy, scope, tier, default enforcement and rationale |
| `refusal:<code>` | a refusal code | what happened, what to do, and the command |
| `doc:<name>` | a product document (`docs/product/<NAME>.md`, lower-cased, shipped in `cotterpin/ops/product-docs.json`) or a pack document (`doc:<pack>/<name>`) | the document |

**A known id needs no search.** `load` takes the full id, or a bare name when only one item has it
(`commit-route`, `MOCK-SUT-1`), or a route's command form (`run-java-bug-fix`, `java-bug-fix`). A name two kinds
share (the skill `delivery-audit` and the workflow `delivery_audit`) is refused with both full ids
(`ops-id-ambiguous`).

**Nothing is copied twice.** A load does not paste in the items its text mentions. It lists them as
`id — description` rows — a workflow's role agents, the skills, workflows, agents and gates its text names in
backticks, the codes behind `cotterpin explain <code>`, gate ids, and linked product documents — and the agent loads
one only when it needs it.

The catalogue holds only what this repository may use: `cotterpin ops` and `cotterpin mcp serve` admit the packs the
repository's lock approves, exactly as `cotterpin tool` does. Product documents ship inside the package as
`cotterpin/ops/product-docs.json` (generated from `docs/product/*.md` by `tools/adapters/build_adapters.py`, declared
in the release descriptor and the wheel), so a released Cotterpin serves every `doc:` id a source checkout does; a
runtime missing that file is refused (`ops-catalogue-invalid`), never served a shorter catalogue. Pack documents ship
with their pack. `tests/ops/test_ops_release.py` proves it from exactly the released file set.

## Search ranking

Deterministic, with no model and no network: the same catalogue and the same words always give the same order. Each
query word is stemmed (`committing` → `commit`, `stubs` → `stub`) and scored per item:

| Where the word is found | Points |
|---|---|
| the whole query is the item's id or name (or a route's command form) | 100 |
| in the name | 8 |
| in the one-line description | 4 |
| in the path (its pack, its folder) | 2 |
| anywhere in the full text | 1 |
| two adjacent query words adjacent in the name or description | 3 per pair |
| coverage: the share of query words found | up to 6 |
| the kind's prior, on a match: skill or workflow 3, gate 2, agent or doc 1, refusal 0 | |

Ties go to the kind order above, then the id. Refusal codes rank last on a tie because there are hundreds of them.

## What each agent tool sees

Every adapter ([AGENT-ADAPTERS.md](AGENT-ADAPTERS.md)) registers the MCP server for its own tool and injects only
the summary and the guidance:

| Tool | Server registration | Summary and guidance |
|---|---|---|
| Claude Code | the plugin's `.mcp.json` (`cotterpin mcp serve --agent claude`) | the one `cotterpin` skill: its description is the summary |
| Codex | `.codex/config.toml`, a marked block (`[mcp_servers.cotterpin]`, `--agent codex`); Codex reads it once you trust the project | the `AGENTS.md` block |
| Grok | `.grok/config.toml`'s marked block (`[mcp_servers.cotterpin]`, `--agent grok`) | the one `cotterpin` skill in the plugin |

Route commands (`/cotterpin:run-<task>`, `/cotterpin:route`) stay for the person to type, marked
`disable-model-invocation`; the model reaches a route with `load workflow:<task>`. Agent roles stay as each tool's
own agent definitions, because a route dispatches them by name.

The server is read-only and closed-world (each tool is annotated so); it answers `initialize`, `ping`, `tools/list`
and `tools/call` over MCP's stdio transport, one JSON-RPC message per line. A request it cannot answer — an empty
query, an unknown id — is a tool result with `isError: true` carrying the refusal's code, cause, fix and next
command, so the agent reads it and carries on; a malformed message is a JSON-RPC error and the session continues.

## Measured (2026-10-04, this release)

**Context every session carries before any skill or agent fires**, before (every skill and route listed) and after:

| Tool | How measured | Before | After |
|---|---|---|---|
| Codex | `codex debug prompt-input`, bytes over the same Codex with no adapter | 30,565 bytes (~7,640 tokens) | 2,551 bytes (~640 tokens) |
| Claude Code | `claude plugin details cotterpin`, its own "Always-on" estimate | ~4,825 tokens | ~3,326 tokens |
| Claude Code | `tools/adapters/measure_context.py` | 19,092 bytes (~4,773 tokens) | 13,328 bytes (~3,332 tokens) |
| Codex | `tools/adapters/measure_context.py` | 27,713 bytes (~6,928 tokens) | 4,292 bytes (~1,073 tokens) |
| Grok | `tools/adapters/measure_context.py` | 19,092 bytes (~4,773 tokens) | 13,328 bytes (~3,332 tokens) |

`measure_context.py` counts what each tool loads up front: skill and model-invocable command `name: description`
lines, agent role `name: description` lines (Claude Code, Grok), the `AGENTS.md` block, and — after — the MCP
server's tool definitions and instructions (1,957 bytes). It agrees with Claude Code's own estimate to within 2%.
The catalogue itself (skills, commands, the `AGENTS.md` listing) fell from 8,465 to 744 bytes for Claude Code and
Grok and from 27,713 to 2,335 bytes for Codex; what remains for Claude Code and Grok is the 39 agent roles
(10,627 bytes), which a route needs as real agent definitions. Tokens are approximate (bytes / 4).

**Latency** (median of 160 searches and 120 loads over a real stdio session; CLI medians of 5 cold processes):

| | Median | p95 |
|---|---|---|
| MCP server start to `initialize` answered (builds the catalogue once) | 227 ms | |
| `search` over MCP | 0.37 ms | 0.55 ms |
| `load` over MCP | 0.12 ms | 0.36 ms |
| `cotterpin ops search` (cold process, catalogue built each time) | 192 ms | |
| `cotterpin ops load` (cold process) | 208 ms | |

None of this is on the hook path: `cotterpin hook` neither imports nor builds the catalogue, so its budget is
unchanged.

## How it is tested

With the real tools, never a stand-in ([TEST-TIERS.md](TEST-TIERS.md)):

* `tests/ops/test_ops_catalog.py` — the catalogue over the real shipped skills, agents, routes, gates, refusals and
  documents: population, one-line descriptions, ranking, determinism, every refusal, references resolved by id;
* `tests/ops/test_mcp_server.py` — a real `python -m cotterpin mcp serve` process driven over real stdio JSON-RPC:
  handshake, notifications, `tools/list`, search then load, tool errors and protocol errors;
* `tests/ops/test_ops_cli.py` — the CLI in-process and as a real process;
* `tests/adapters/test_agent_tools.py` — each adapter as the real tool reads it: Claude Code connects to the server
  (`claude mcp list`), Codex shows only the summary (`codex debug prompt-input`, bounded under 2 KiB plus 640 bytes
  per installed pack, since every skill and workflow name stays in it) and lists the server (`codex mcp list`), Grok's
  own doctor starts the server, completes the handshake and finds the three tools (`grok mcp doctor`).
