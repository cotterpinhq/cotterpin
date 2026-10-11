# Privacy: what leaves your machine

This page states exactly what Cotterpin sends off your machine, to whom and when, and what it never sends.
`cotterpin privacy` prints the same statement (`--json` for the machine-readable form).

## What leaves the machine

| What | To | When |
|---|---|---|
| The source files a task selects, the task's prompt and its instructions | The provider you chose for that job (`claude`, `codex` or `grok`) under `providers.roles` in `.cotterpin/policy.yaml` | Only while a run you started is calling that provider, and only after you approved sending code to that provider on this machine |
| For licensing: your licence id, plan, this machine's fingerprint (a salted SHA-256 of its hardware id — never the id itself) and the Cotterpin version | The Cotterpin licence service | Only after you approve `licence.service`: starting the trial, `cotterpin subscribe`, `cotterpin machines`, `cotterpin billing`, `cotterpin update --fetch`. Declining means Watch, never an error |
| The email address you type for `cotterpin subscribe --claim <email>` | The Cotterpin licence service, which keeps only a SHA-256 of it | Only when you run that command and approve `licence.claim` |
| Team single sign-on: your Team's sign-in name, this machine's fingerprint and the Cotterpin version; then, in your browser, your sign-in at your Team's identity provider. The service keeps **only** your identity's subject (the provider's user id), your email address and your Team membership (machines, admin, revoked) | The Cotterpin licence service, and your Team's identity provider (Okta, Entra ID, Google, GitHub or another OpenID Connect provider) | Only when you run `cotterpin login` (or a Team admin runs `cotterpin team sso test --sign-in`) and approve `licence.sso`; renewing (`cotterpin login`, `cotterpin machines renew`) sends the stored sign-in credential to the licence service, which presents it to your provider and keeps nothing of it |
| A Team admin's identity-provider client secret | The Cotterpin licence service, which stores it only in AWS Secrets Manager | Only when an admin runs `cotterpin team sso set` and approves `licence.sso.secret` |
| A bug report: the Cotterpin, pack and Python versions, the operating system and processor family; for an internal error, its type, the command's name and up to five places in Cotterpin's own code (never its message); the period's refusals, each reduced to its time, tier, rule, code, outcome, agent tool and count; and the description you write, refused before sending if it holds a secret, a file path or code. With a licence, your licence id; without one, nothing about you. Never your code, diffs or file contents, file paths, commands, prompts or replies, repository, branch or remote names, commit messages, user or machine names, environment variables, secrets, error messages or the session record | The Cotterpin licence service, which keeps it until the fault is closed, then 12 months; the source IP address is counted only as a one-way hash that expires within two hours | Only when you have read the whole report and pressed **s** (`cotterpin report-bug`); never from an agent's run or a shell no one is at. If the service cannot be reached, you get an email link instead, which you send yourself. `cotterpin bug-report` then asks where your sent reports stand, sending only each one's receipt (a random number made for that report); `--offline` asks nothing |

Card and payment details never reach Cotterpin: you enter them on Paddle's checkout in your own browser (Paddle is the
merchant of record). See [Licensing and billing](LICENSING-AND-BILLING.md).

The Cotterpin operator's own `cotterpin admin` reads what Paddle already holds about a subscription (your Paddle
customer record, subscriptions and transactions) and what the licence service holds (your licence, its machine
fingerprints and its audit trail), to answer support and billing questions. It reads them in Paddle and the licence
service; it adds nothing to what leaves your machine, and the licence service still stores no email address
(the admin CLI).

Before the first call to a provider, Cotterpin asks you, once per machine:

> send the files this task selected, its prompt and instructions to *provider* — from the repository's committed
> source in the task's scope, after removing `.env` and credential files and redacting secrets — because *provider*
> is the provider your policy chose for this job and cannot do it without reading the code. If you decline, nothing is
> sent and the run stops; choose another provider under `providers.roles`, or run the step by hand.

Declining, not answering, or running in a non-interactive shell without having approved it beforehand all mean the
same thing: **nothing is sent**. You can change the answer at any time with `cotterpin consent`.

What the provider does with what it receives is governed by your account with that provider (your subscription or
API terms), not by Cotterpin. Cotterpin never sends anything to any other party.

## What never leaves the machine

- **`.env` files and credential files.** These are removed from the source a provider receives whatever the task's
  scope asks for: any file whose name starts with `.env` (`.env`, `.env.local`, `.envrc`, ...); private keys and
  certificate stores (`*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `*.ppk`, `id_rsa`, `id_ed25519`, ...);
  credential and secret files (`credentials`, `credentials.json`, `secrets.yaml`, `auth.json`, `.netrc`, `.npmrc`,
  `.pypirc`, `.pgpass`, `.git-credentials`, `.htpasswd`, `*.tfvars`, `terraform.tfstate`, ...); and everything under a
  `.ssh`, `.aws`, `.gnupg`, `.azure`, `.kube` or `.docker` directory. A scope that would contain nothing else is refused
  rather than sent.
- **API keys.** When a provider is paid by API key, Cotterpin reads the key from the environment variable you name
  (`apiKeyEnv`) at the moment of the call. It never writes the key to a file, a log or the progress stream, and
  `cotterpin providers` reports only whether the variable is set. A key pasted into `.cotterpin/policy.yaml` is refused,
  because that file is committed.
- **Secrets inside what is sent or logged.** Every prompt payload and every log line passes through one redaction
  filter first. It replaces, with `[REDACTED:<kind>]`:
  - provider and platform tokens: Anthropic (`sk-ant-...`), OpenAI (`sk-...`), xAI (`xai-...`), GitHub (`ghp_...`,
    `github_pat_...`), GitLab (`glpat-...`), Slack (`xox?-...`), Google API keys (`AIza...`);
  - AWS-style access key ids (`AKIA...`, `ASIA...`) and `aws_secret_access_key` / `aws_session_token` values;
  - private key blocks (`-----BEGIN ... PRIVATE KEY-----` to the end of the block);
  - JSON Web Tokens and `Bearer` tokens; passwords embedded in URLs (`https://user:password@host`);
  - `NAME=value` lines whose upper-case name contains SECRET, TOKEN, PASSWORD, PASSWD, PASSPHRASE, API_KEY,
    ACCESS_KEY, PRIVATE_KEY or CREDENTIAL, and quoted values after such a key in JSON, YAML or code;
  - the literal values written in the repository's own top-level `.env*` files, and the values of this process's
    environment variables whose names mark them sensitive;
  - Paddle API keys and notification secrets (`pdl_live_apikey_...`, `pdl_sdbx_...`, `pdl_ntfset_...`);
  - sign-in credentials in any shape: the values of `id_token`, `access_token`, `refresh_token`, `device_code`,
    `client_secret`, `session_token`, `token` and `licence_token` members in JSON (camelCase too), and the same
    names as form or URL parameters.

  To filter a log yourself before sharing it: `cotterpin privacy redact --repository . < run.log > run-redacted.log`.

## Credentials never enter an agent's context

An agent works through capabilities ("run the commit route", "show the licence status"); it never needs the secret
behind them. So everything Cotterpin itself RETURNS to an agent or prints — every hook answer (refusals, advice,
Watch reports, approval requests), every command's output and errors (`status`, `explain`, `privacy`, `approvals`,
refusals), the audit log, the Watch report and pending approvals — passes through the same filter, with three
additions for output:

- the literal values in Cotterpin's own credential files — this machine's licence token in `licence.json`, and every
  long string in `sso.json` (sign-in tokens and device codes) — wherever and however they appear;
- whole licence tokens (`{"kind": "...-licence-token", ...}`), and the licence token stored as escaped text;
- generic high-entropy secrets: a run of 32 or more letters, digits, `+`, `-`, `_` that mixes upper case, lower case
  and digits, switches between them often and has high entropy per character. Hex digests, UUIDs, identifiers and
  file paths are not touched.

The `cotterpin` process wraps its own standard output and error in this filter, and the hook entrypoint applies it to
its answer before it builds the agent tool's JSON. Each kind of secret is planted and proven absent from standard
output, standard error, the audit log, the Watch report and pending approvals by
`tests/kernel/test_credential_redaction.py`.

The redacting stream holds output until it is whole — a complete line (a compact JSON document is one line; an
indented one keeps each key with its value), a private-key block until its END line — and redacts it as one piece, so
a writer that splits a key from its value across writes (`json.dump` does) cannot slip a secret past it. A flush in the
middle of a line writes what is held EXCEPT a trailing piece that could still become a secret (an open quoted value
after a sensitive key, or a run of eight or more token characters): that waits for the rest of its line, so a token a
writer flushes in two halves is still redacted whole; a prompt ending in a space (`Approve? [y/N] `) still shows before
its question is read, and everything is written when the command ends. Output that a child process writes straight to
the inherited terminal does not pass through it.

This is ONE redactor: the same filter (`cotterpin.kernel.privacy.output_redactor_for`, with the checkout's `.env`
values) cleans what the hook answers, what every command prints, the trajectory, the action audit log, the Watch
ledger, pending approvals and the memory stores' fields; only a prompt sent to a provider uses the pattern set without
the high-entropy rule, which would mangle long identifiers in source.

What a SHELL command prints goes to the agent directly, so the hook rule `credential-exposure`
([HOOKS.md](HOOKS.md)) stops, before it runs, any agent action that would put a credential into the agent's context —
judged by EFFECT, not by a list of programs: any program that names `licence.json` or `sso.json` (in any place the
configuration folder can be; `$VAR`, `${VAR:-default}`, `~`, globs and `cd` along the line are resolved, and a path
behind a variable the hook cannot resolve fails closed), whether through `cat`, `python3 -c "open(...)"`, `cp` then
`cat`, `git diff --no-index`, `tar`, `$(cat ...)`, backticks, `xargs` or a loop reading `< file`; a `.env` or cloud
credential file; a recursive read (`grep -r`, `tar`, `rg`, `find -exec`) over the configuration folder or a folder that
contains it; the agent's own Read, Grep and Glob tools on those; and dumping the environment (`env`, `printenv`, `set`,
`export -p`, `declare -x`, `/proc/<pid>/environ`, `ps eww`, `print(os.environ)`) or printing a variable whose name
marks it secret (`echo $GITHUB_TOKEN`). Only programs that look at a NAME (`ls`, `stat`, `test`, `wc`, `echo` of the
path) or, for a generic credential file, USE it without printing it (`source .env`, `ssh -i key`) are left alone. It
is a sensitive write: the developer confirms it once, if it is really wanted. Using a credential without printing it
(`aws s3 ls`, `test -n "$TOKEN" && echo set`) runs.

## What stays on the machine

- **Run progress and spend** (`cotterpin status`): one append-only file per run inside the repository's own git
  directory (`git rev-parse --git-path cotterpin/runs`). It is never a tracked file and never leaves the machine.
- **The trajectory** (`cotterpin report`): one line per decision Cotterpin makes on an agent's behalf — hook decisions,
  commits, pushes, code-gate runs, consent questions you answered — in the repository's git directory
  (`<git common dir>/cotterpin/trajectory.jsonl`, readable only by you). It is never a tracked file and never leaves
  the machine. It keeps no prompt, no reply and no tool output (only an exit code and a commit id), and every line
  passes through the redaction filter first. `COTTERPIN_TRAJECTORY=off` stops it. See [Observability](OBSERVABILITY.md).
- **Agent tools' session logs** are only ever READ, and only with your consent (`report.transcripts`): `cotterpin
  report` takes the token counts and model names from them for tokens and cost per landed change. Their conversation
  text is never read into the report, and nothing from them is sent anywhere.
- **Your consent answers**: in your user configuration directory, outside every repository.
- **This machine's licence token**: `licence.json` in the same directory, readable only by you (mode 0600).
- **Your Team sign-in credential** (after `cotterpin login`): `sso.json` in the same directory, mode 0600 — an OpenID
  Connect refresh token or a GitHub user token, used only to renew your seat. `cotterpin logout` deletes it. The
  licence service never keeps it: the sign-in record that hands it to your terminal expires in 10 minutes and the
  credential is removed from it the moment your terminal collects it.
- **Bug reports** Cotterpin prepared, and those you kept or cancelled: `bugs/` in your user configuration directory
  (files mode 0600). A cancelled report is never sent.
- **The audit log of agent actions and pending approvals** ([APPROVALS.md](APPROVALS.md)): inside the repository's
  own git directory (`cotterpin/audit/actions.jsonl`, `cotterpin/approvals/`). The audit log holds each action's tier,
  outcome and a digest — never the command itself.
- **Memory** ([MEMORY.md](MEMORY.md)). Cotterpin never sends a memory fact anywhere: no store is uploaded, synced or
  reported, and consolidation is deterministic and local. Where each scope lives:
  - personal facts: `memory/` in your user configuration directory (mode 0700, files 0600), written only after you
    allow `memory.user`, never inside a repository;
  - task facts: inside this checkout's git directory (`<git dir>/cotterpin/memory/task`), never tracked, gone when the
    worktree is removed;
  - repository facts: `.cotterpin/memory/facts/` in the repository — they leave the machine only when *you* commit and
    push them, like any other file;
  - caches and journals (`<git common dir>/cotterpin/memory/`): never tracked, never sent.

  What does reach a provider is what your agent tool sends with the rest of its context: the session-start index
  (names and one-line descriptions, within a token budget; personal facts only with `memory.user`) and any fact the
  agent reads with `cotterpin memory show`. Every stored field of a fact (its text, name, description, owner, tags,
  paths, provenance and history) and every journal and note line passes the redaction filter above before it is
  written, and the text again when it is injected. Importing another tool's memory (`cotterpin memory import claude|codex|grok|okf`) only reads
  it, after asking. The one exception that sends memory is `cotterpin memory consolidate --assist <provider>`: it asks
  first, says exactly what will be sent (the names, descriptions and text of the similar pairs it wants judged, after
  redaction) and to which provider, and sends nothing if you decline.

## Telemetry

Telemetry is **off**. It can be turned on only by you, explicitly, through `cotterpin consent`; no repository setting
can turn it on for you. This release contains no telemetry sender at all: the switch exists so that anything which
ever reports usage is gated by your explicit approval first.

## Limits of this statement

- The provider CLIs you sign in with (`claude`, `codex`, `grok`) are separate programs with their own privacy terms.
- Pre-release gap (0.2.0): the `.env`/credential-file exclusion is applied wherever a task sends a *scoped* selection
  of the repository. The older whole-tree source path of the supervised Mac route still sends every tracked regular
  file; until it applies the same rule, do not commit `.env` or credential files to a repository you run on that route.
- The redaction filter is pattern-based. It removes the shapes listed above; a secret with no recognisable shape that
  is not in a `.env` file can still be sent if it is in a selected source file. Keep secrets out of source files.
  (The generic high-entropy rule applies to what Cotterpin prints, not to source sent to a provider, where it would
  mangle long identifiers and test data.)
