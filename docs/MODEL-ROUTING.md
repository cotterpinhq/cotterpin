# Model routing: `cotterpin route`

Not every step of a route needs the strongest model. Cotterpin chooses the model and effort for each step itself:
**task → class → required capability → model**, instead of *everything → the biggest model*.

A route stage never names a model. It says what kind of work it is — its **task class** — and, where a wrong answer
costs more, its **risk**. Cotterpin's routing policy turns that into a model and effort for the provider you use, under
the caps and budget you set, and can always say why.

```sh
cotterpin route table                               # the default class x risk table, and this repository's policy
cotterpin route list                                # every shipped workflow, and the class of each of its stages
cotterpin route explain cotterpin-delivery-audit auditor-s1   # one stage: its class, the inputs, the choice, and why
cotterpin route plan cotterpin-delivery-audit       # every stage routed, with its width and routed units per pass
cotterpin route issue delivery_audit --run-id <runId> --base-head <baseHead>  # the decision a direct dispatch passes
```

Each takes `--repository PATH` and `--json`. `explain` and `plan` also take `--provider claude|codex|grok` and
`--override <task>/<role>=<tier>/<effort>` for this run.

## Task classes

| class | the stage… |
|---|---|
| `relay` | runs one deterministic Cotterpin command and copies its output; the tool does the work |
| `classify-select` | sorts, triages or picks from a known set of answers |
| `mechanical-edit` | applies a stated, mechanical change |
| `search-scan` | reads widely to find and list things |
| `implement` | writes or changes code or documents |
| `review-verify` | checks work against the evidence and gives a verdict |
| `adversarial-refute` | argues against a verdict to try to break it |
| `judge-synthesise` | weighs competing evidence and decides, or synthesises one answer |

Risk is `low`, `normal` (the default), `elevated` or `high`.

## The default table

| class | low | normal | elevated | high |
|---|---|---|---|---|
| `relay` | fast/low | fast/low | fast/low | fast/low |
| `classify-select` | fast/low | fast/low | balanced/low | balanced/medium |
| `mechanical-edit` | fast/low | fast/low | balanced/low | balanced/medium |
| `search-scan` | fast/low | balanced/low | balanced/medium | balanced/high |
| `implement` | balanced/low | balanced/medium | balanced/high | strongest/high |
| `review-verify` | balanced/low | balanced/medium | balanced/high | strongest/high |
| `adversarial-refute` | balanced/medium | balanced/medium | balanced/high | strongest/high |
| `judge-synthesise` | balanced/medium | balanced/high | strongest/high | strongest/high |

Mechanical and classification work runs on the fast, cheap tier at low effort; implementation runs balanced; review
and adversarial work on high-risk stages runs on the strongest tier at high effort.

| tier | Claude | Codex | Grok |
|---|---|---|---|
| `fast` | `haiku` | the provider's default model | the provider's default model |
| `balanced` | `sonnet` | the provider's default model | the provider's default model |
| `strongest` | `opus` | the provider's default model | the provider's default model |

Codex and Grok name their own models; map them per tier in `routing.providers` (below). Until you do, the effort
carries the tier for them. Every provider gets the same class, risk and effort for each stage: the Claude command, the
Codex runbook and the Grok playbook all show each role's task class and effort.

## Selection does not need generation

A `relay` stage runs one deterministic Cotterpin tool: the tool makes the decision and the model only runs the command
and copies the answer, so it always runs on the cheapest tier. A `classify-select` stage names its deterministic
implementation (`"deterministic": "<command>"`) where Cotterpin ships one; where none ships, `cotterpin route explain`
says so — for example the release triager, which classifies harm sentences with a model at the cheapest tier its risk
allows.

## Your policy: the `routing` block of `.cotterpin/policy.yaml`

Everything is optional. Without the block, every stage runs at the default table on your configured provider.

```yaml
routing:
  provider: claude                 # the provider routed stages run on (default: providers.roles.writer, else claude)
  providers:                       # each provider's model per tier (Claude's are known; map Codex's and Grok's)
    codex: {fast: <model>, balanced: <model>, strongest: <model>}
  cap: {maxTier: balanced, maxEffort: high}     # going above needs your consent, per stage
  classes:                         # replace the table for a class: for every risk ...
    implement: {tier: strongest, effort: high}
    review-verify:                 # ... or per risk
      high: {tier: strongest, effort: high}
  stages:                          # one stage of one route; a reason is required
    delivery_audit/auditor-s2: {tier: strongest, effort: high, reason: "S2 here is payment code"}
    delivery_audit/refuter: {provider: codex, reason: "an independent reviewer from another provider"}
  budget:
    maxConcurrentUnits: 60         # parallel width x units per call must fit this
    maxRunUnits: 2000              # what one run may reserve, pass by pass
```

Precedence, each layer replacing the one before: the default table (or a stage's own pin in its route, which must give
its reason) → `routing.classes` → `routing.stages` → this run's overrides.

### This run only

```sh
COTTERPIN_ROUTE_OVERRIDES='delivery_audit/auditor-s2=strongest/high,census-writer=fast' cotterpin audit --scope PAYMENTS
COTTERPIN_ROUTE_PROVIDER=codex cotterpin route plan cotterpin-delivery-audit
```

An override names `<task>/<role>` (one route) or `<role>` (any route with that stage) and `<tier>[/<effort>]`.

## Consent

Two routing choices change where your code goes or what it costs, so Cotterpin says **what** it will do and **why**,
and you approve or decline (see [CONSENT-AND-BOX.md](CONSENT-AND-BOX.md)):

| id | asked when | if you decline |
|---|---|---|
| `route.provider-switch` | an override sends a stage to a provider other than the one you configured | the stage runs on your configured provider |
| `route.above-cap` | the table or an override puts a stage above your `routing.cap` | the stage runs at your cap |

**Every yes is for one stage of one run, never a standing grant.** Each stage asks under its own id —
`route.above-cap.<task>.<role>` or `route.provider-switch.<task>.<role>`, the task's `_` written `-` (for example
`route.above-cap.delivery-audit.auditor-s1`) — and the answer is never stored: `cotterpin consent grant
route.above-cap` is refused, and a stored answer is never read. `cotterpin route explain`, `plan` and `issue` ask on a
terminal, for that command only. A run in progress never stops to ask: it honours only what its own command line
approves (`--consent route.above-cap.delivery-audit.auditor-s1` for that one stage, or `--consent route.above-cap`
for every stage of that one run), and anything unanswered is declined — the configured default, never an error. A
route the kernel runs on
Claude's workflow runtime can only run Claude's models, so there a provider override is reported in the stage's
reasons and the stage stays on Claude; the switch applies where the stage is played by that provider (its Codex
runbook or Grok playbook). A provider you pick for one
run (`COTTERPIN_ROUTE_PROVIDER`) is your configuration for that run, not a switch.

**The approval is yours, not the agent's.** An agent writes the commands that start and drive a run, so the
`spend-approval` hook rule ([HOOKS.md](HOOKS.md)) puts to you any agent command that names a `route` consent
(`--consent route...` or `COTTERPIN_CONSENT=route...`) or sets `COTTERPIN_ROUTE_OVERRIDES` /
`COTTERPIN_ROUTE_PROVIDER`; with no one at the keyboard to answer it is refused. The approval a run used is visible
on its command line and recorded as `aboveCap` in the run's state.

## One budget view with the Box Budget

A routed call costs **units = tier units × effort factor**: `fast` 1, `balanced` 3, `strongest` 15, times `low` 1,
`medium` 2, `high` 3. Units are a planning currency for comparing choices, not money: `providers.budget` (tokens and
dollars, [PROVIDERS-AND-COST.md](PROVIDERS-AND-COST.md)) remains the hard stop.

- **Width.** A fan-out's width is the Box Budget's agent width ([CONSENT-AND-BOX.md](CONSENT-AND-BOX.md)), narrowed so
  that `width × units` fits `routing.budget.maxConcurrentUnits` — never below 1. A stronger tier therefore runs
  fewer at once; a cheaper one runs wider. Every agent fan-out prices its single width at its route's most expensive
  fanned-out stage: the kernel route tools, the Java pack's generate launcher, de-stub shards and migrate judgement
  shards, and campaign waves (at the most expensive of the campaign's routes). With no
  `maxConcurrentUnits` set, the width is the Box Budget's and no route is even loaded. Inside a run, those tools
  price the width at the policy committed at the run's `baseHead`, and the workflow clamps every fan-out to the
  width the run's routing decision priced that stage at (`routedWidth`), so the run's reservation is never smaller
  than what it really runs at once.
- **Per-run cap.** Each pass of a run reserves, for every stage, its units at its planned width. Before a pass starts,
  Cotterpin checks the run's reservations so far plus this pass against `routing.budget.maxRunUnits`. A pass that
  would cross it is **not started** (`routing-budget-exceeded`): the message gives what was reserved, the cap, and
  the three ways out (raise the cap, route stages cheaper, narrow the width). With Watch (no trial or plan) the pass
  runs and the refusal is reported instead (see [LICENSING-AND-BILLING.md](LICENSING-AND-BILLING.md)). The run's
  reservations are kept in the kernel's own state for the run, so no file an agent could delete resets them.

## How a run uses it

A run is held to the routing policy **committed at its base commit** (`baseHead`): editing `.cotterpin/policy.yaml`
in the run's checkout during the run changes nothing — not the models, not the per-capability fix-writer tier, and
not any fan-out's width (the route tools read the committed policy inside a run, and every workflow clamps its
fan-outs to the decision's widths). When the kernel dispatches a pass of a route, it routes every
stage of that route and hands the workflow a **routing decision** as its `routing` argument, bound to the pass: its
`runId` and `baseHead`, the digest of the policy that decided it, your cap, each stage's model, effort, tier, units
and width (and `aboveCap` where you approved it), and a sha256 digest of the whole. The kernel records the decision
in the run's state and:

- each workflow's generated block **refuses to run without it** (`routing-decision-unbound`), recomputes the digest,
  and refuses a decision for another run, an altered one, a stage this workflow does not have or with another class or
  risk than its route declares, a tier, effort, provider or model outside the vocabulary, and a stage above the cap
  without its approval. Then `routed(role)` returns the decided options; there are no defaults to fall back to, and
  `routedWidth(width, role...)` bounds each fan-out by the stage widths the decision priced;
- the digest is a plain sha256 with no key: it catches a decision altered by accident or by a careless edit, but
  anyone can recompute it. **What makes a decision authentic is the kernel's receipt**: the kernel refuses the
  receipt of any pass whose workflow received other arguments than the ones it wrote, so an agent that rewrites the
  decision (and recomputes its digest) gets nothing back. A workflow you dispatch yourself, outside a kernel run, has
  no receipt, so nothing there binds the decision to your policy: a re-digested decision with the cap removed, or
  with `aboveCap` set, passes the block. Hold a run to your cap by running it through the kernel;
- a broker worker (a Codex or Grok supervisor's worker, or a native workflow's) runs at the tier this pass was routed
  to, mapped through the provider's tier mapping as any tier is (or a model you mapped under `routing.providers`),
  after re-verifying the recorded decision — the same decision the workflow was handed. A classed route whose run
  has no recorded decision is refused (`routing-decision-unbound`), never run at the route's frozen default, which
  could be above your cap. A routed tier can be one the route's default never used (for example `haiku/medium`
  under a `fast`/`medium` cap), so a provider with a `modelMapping` in `.agents/control-plane.json` needs a key for
  it: `worker-tier-unmapped` names the exact key to add (`providers.<provider>.modelMapping."<model>/<effort>"`).

To dispatch a workflow yourself, outside a kernel run, pass the decision `cotterpin route issue` prints for the same
run identity:

```sh
cotterpin route issue cotterpin-delivery-audit --run-id my-run-1 --base-head "$(git rev-parse HEAD)"
```

The generated block is rebuilt from the routes' classes by `tools/routing/build_workflow_routing.py`, and a test fails
when it is stale. A route whose stages still name models (a repository's own legacy route) runs exactly as before;
`cotterpin tool route-check` reports it.

## For route authors

Declare each stage in the route's `contract.tiers`:

```json
{"role": "auditor-s1", "class": "review-verify", "risk": "high", "why": "a wrong verdict on S1 is caught by nothing"}
```

Optional: `"deterministic": "<the Cotterpin command that decides>"` for a selection stage, and — only when a stage
truly needs a fixed tier — `"pin": {"tier": "strongest", "effort": "high", "reason": "…"}`. The workflow takes the
stage's worker options from `routed('<role>')` and nothing else.

## Refusals

| code | means | next |
|---|---|---|
| `routing-policy-invalid` | the routing block or a run override is malformed | `cotterpin route table` |
| `routing-decision-unbound` | a workflow or broker worker got no routing decision, one for another run, or one that does not match its digest | `cotterpin route issue <workflow> --run-id <runId> --base-head <baseHead>` |
| `routing-stage-unknown` | no shipped workflow or stage has that name | `cotterpin route list` |
| `routing-stage-unclassed` | a route stage names a model, or no class | `cotterpin route list` |
| `routing-budget-exceeded` | the next pass would cross `routing.budget.maxRunUnits` | `cotterpin route plan <workflow>` |
