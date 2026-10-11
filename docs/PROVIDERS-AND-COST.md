# Providers, models and cost: `cotterpin providers`

Cotterpin runs three kinds of job with a model: the **writer** (changes code), the **reviewer** (checks it) and the
**planner** (splits work). You choose which provider and model does each job, how each provider is paid for, and how
much one run may spend, in the `providers` block of `.cotterpin/policy.yaml`. The whole block is optional.

```yaml
providers:
  accounts:                        # how each provider is paid (default: subscription)
    claude: {auth: subscription}   # your signed-in CLI's subscription pays
    codex:  {auth: api-key, apiKeyEnv: OPENAI_API_KEY}   # the variable's NAME; never the key itself
  roles:
    writer:   {provider: claude, model: claude-sonnet-4-5}
    reviewer: {provider: codex,  model: gpt-5}
    planner:  {provider: claude}   # no model: the provider's own default
  budget:                          # per run; the run stops when either is reached
    maxTokens: 2000000
    maxCostUsd: 25
  prices:                          # USD per million tokens, for models paid by API key
    gpt-5: {inputUsdPerMillion: 1.25, outputUsdPerMillion: 10}
  rateLimit: {maxRetries: 6, baseSeconds: 1, maxSeconds: 60}
```

| Key | Meaning |
|---|---|
| `accounts.<provider>.auth` | `subscription` (default) or `api-key` |
| `accounts.<provider>.apiKeyEnv` | with `api-key`: the environment variable that holds the key. Defaults: `ANTHROPIC_API_KEY` (claude), `OPENAI_API_KEY` (codex), `XAI_API_KEY` (grok) |
| `roles.<writer\|reviewer\|planner>` | `provider` (required) and `model` (optional) |
| `budget.maxTokens` / `budget.maxCostUsd` | the per-run hard stop (both optional) |
| `prices.<model>` | `inputUsdPerMillion` and `outputUsdPerMillion`. Cotterpin never guesses a price: a cost budget over a model paid by API key needs its price here |
| `rateLimit` | retries after a provider says "too many requests": `maxRetries`, and the backoff range `baseSeconds`..`maxSeconds` |

Supported providers: `claude`, `codex`, `grok`.

Inside a route, each stage's model and effort come from its task class, not from these three jobs: see
[MODEL-ROUTING.md](MODEL-ROUTING.md) (`cotterpin route explain <workflow> <stage>`). The routing policy's configured
provider defaults to `roles.writer` here.

## Check it

```sh
cotterpin providers            # each job's provider and model, the budget, and whether each provider is ready
cotterpin providers --json     # the same, machine-readable
cotterpin providers --repository path/to/repo
```

Exit codes: `0` ready; `1` a provider paid by API key has no key in its environment variable (the output gives the
exact `export` line); `2` the policy was refused (the output names the key, what is wrong, and the fix).

A provider on a subscription is reported as "check with `cotterpin connect`": `cotterpin connect` asks each provider's
CLI whether it is signed in.

## How the budget works

- **Before each call**, the call's worst case (its input plus the most output it may produce) is checked against what
  the run has spent. A call that could cross either limit is **not made**, and the run stops.
- **After each call**, its actual tokens and cost are added to the run's spend and shown live by `cotterpin status`.
  If the actual use reached a limit, the run stops before its next call.
- A stopped run says what was spent against which limit, and the fix: raise `providers.budget` and start the run again.
- Calls paid by a subscription count tokens but cost `$0.00` in the budget (the subscription pays).

## Rate limits

When a provider refuses a call for rate or capacity reasons, Cotterpin waits and retries: attempt *n* waits a random
time between 0 and `min(maxSeconds, baseSeconds × 2ⁿ)` (so parallel shards do not retry in lock-step), never less than
the provider's own "retry after" hint, and never more than `maxSeconds`. After `maxRetries` refusals the stage stops
and says to wait a few minutes or raise `maxRetries`.

## Before anything is sent

The first call to each provider asks for your approval to send code to it (see [PRIVACY.md](PRIVACY.md)). If you
decline, nothing is sent and the run stops.
