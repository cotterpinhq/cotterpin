# Licensing and billing

This page describes how a developer gets and keeps a Cotterpin licence, what Cotterpin sends to do it, and how the
licence service takes payment through **Paddle Billing**. Paddle is the merchant of record: it takes the payment,
collects and files sales tax and VAT worldwide, and handles disputes. Card details never touch Cotterpin.

## What the website promises, and where each promise is kept

| Promise | Kept by |
|---|---|
| 14-day trial, every gate on, **no card** | `POST /v1/trials`, started by `cotterpin init` after consent: one trial per machine fingerprint, rate-limited per source address |
| After the trial: **Watch** (free, unlimited machines; reports, never blocks or fixes) | The trial token expires; every enforcing path asks `cotterpin.kernel.enforcement` at the moment it would refuse, which reads this machine's licence (`cotterpin.release.licence_mode` → `enforcement_mode.select_mode`) and, for a lapsed or absent licence, reports instead of refusing — see *Enforce or Watch* below |
| **Pro**: $100 a year, 3 machines per person (work, home, spare) | `cotterpin subscribe` → `POST /v1/checkout` → a Paddle transaction for the Pro price, quantity 1 |
| Move a licence to a new machine yourself, any time | `cotterpin machines [list\|add\|move <from> <to>\|remove <id>]` → `GET/POST /v1/machines`, each change audited |
| **Team**: $30 a seat a month, billed annually, 5-seat minimum | `cotterpin subscribe team --seats N` → a Paddle transaction for the Team price, quantity N (N ≥ 5); 3 machines per seat |
| **Team SSO**: Okta, Entra ID, Google, GitHub | One identity provider per Team (`cotterpin team sso set`); developers take a seat with `cotterpin login` — see *Team single sign-on* below |
| Cancel, change payment method, invoices | `cotterpin billing` → `POST /v1/billing-portal` → Paddle's customer portal |
| Updates are signed release downloads | `cotterpin update --fetch` → `POST /v1/downloads` (`channel: latest`) → the release is verified (signature, digests, revocation, tier) before it lands |
| To Cotterpin, for licensing: **only** licence id, plan, machine fingerprint, version | See *What is sent* below |

## What is sent, and when

Every licensing command first says what it will send and why, and asks (consent id `licence.service`, operator rule
2026-10-04: "We MUST ALWAYS say WHAT we are going to do and WHY we need to do it. The developer can approve/decline.
If decline, then we run in serial or always take the unscanned, default option"). For licensing the unscanned
default is **Watch**: declining is never an error and never blocks work.

- **Sent**: the licence (the service's own signed token, which carries the licence id and plan), the machine
  fingerprint, and the Cotterpin version. Nothing about code, files, repositories or accounts.
- **Machine fingerprint**: `mfp_` + HMAC-SHA256 of the machine's stable hardware id (`IOPlatformUUID` on macOS,
  `/etc/machine-id` on Linux) under a fixed product salt, computed on the developer's machine. The hardware id itself
  is never stored or sent.
- **Email claims** (`cotterpin subscribe --claim <email>`) also send the typed email address, under their own consent
  (`licence.claim`). The service stores only a SHA-256 of any email address.
- **Card details** are entered only on Paddle's checkout in the developer's browser.

## The developer's commands

| Command | What it does |
|---|---|
| `cotterpin init` | Offers the trial (with consent). Declined, non-interactive or failed: Watch |
| `cotterpin subscribe [pro\|team --seats N]` | Asks the licence service for a Paddle checkout, opens it in the browser, and polls until the paid licence arrives (Ctrl-C stops waiting; `cotterpin machines` picks it up later) |
| `cotterpin subscribe --claim <email>` | Claims a licence bought on the website (Paddle.js checkout), or uses a licence you already pay for on a new machine: the service emails that address, if it bought Cotterpin, a one-time code and a link. Press **Confirm this machine** on the page the link opens (it names the machine; opening it changes nothing) and the waiting terminal binds the licence by itself; or type the code. Either one binds it, once |
| `cotterpin billing` | Opens the Paddle customer portal |
| `cotterpin machines` | Lists the licence's machines; `add [<id>]`, `move <from> <to>` (`this` = this machine) and `remove <id>` change them |
| `cotterpin subscribe --list` | The plans and what each covers; sends nothing. `subscribe watch` and `subscribe enterprise` say what each needs, also sending nothing |
| `cotterpin update --fetch` | Fetches the newest signed release this licence covers and verifies it before it lands in the local cache; a repository moves to it only with `cotterpin upgrade` (`cotterpin update` without `--fetch` moves the repository's lock, as before) |

**Moving to a new machine.** On the new machine, `cotterpin machines` prints its id. If the licence still has a free
slot, run `cotterpin subscribe --claim <the email you paid with>` there. If every slot is in use, first run
`cotterpin machines move <old id> <new id>` on a licensed machine (the old machine stops enforcing at once), then
claim on the new one.

The licence token lives in `licence.json` in the user configuration directory (mode 0600). Tokens are short-lived
(at most 35 days) and renewed online, so a machine that was moved away stops enforcing within that window even
offline, and immediately for anything that talks to the service.

## Team single sign-on

A Team licence registers exactly **one** identity provider, and each developer then takes a seat by signing in with
it. Supported: any OpenID Connect issuer — **Okta**, **Microsoft Entra ID** (its tenant issuer,
`https://login.microsoftonline.com/<tenant id>/v2.0`; never `common`), **Google Workspace**
(`https://accounts.google.com`) — and **GitHub** (an OAuth app or a GitHub App, restricted to one organization).

### For Team admins

Admins are the machines the purchaser bound with the licence itself (the Paddle customer's own machines, at most 3,
together one seat), and the members they name.

| Command | What it does |
|---|---|
| `cotterpin team sso set --team <name> --provider oidc --issuer <url> --client-id <id> --domain <email domain> [--domain ...]` | Registers an OpenID Connect provider; members must sign in with an email in one of the domains |
| `cotterpin team sso set --team <name> --provider github --client-id <id> --org <organization>` | Registers GitHub; members must be ACTIVE members of the organization |
| `cotterpin team sso [show]` | The provider, the Team's sign-in name and the admins (the client secret is never shown) |
| `cotterpin team sso test [--sign-in]` | Checks the secret is readable and, for OpenID Connect, the issuer's discovery document and RS256 keys; `--sign-in` signs the admin in once, end to end, without taking a seat |
| `cotterpin team members` | Every member: email, provider, machines, admin, revoked |
| `cotterpin team members revoke <email>` / `restore <email>` | Revoke releases every machine of that member AT ONCE and stops them signing in again until restored |
| `cotterpin team members admin <email>` / `unadmin <email>` | Name or remove an admin |
| `cotterpin team seats` | Seats, seats in use, seats free, machines per seat |

The client secret is read from `$COTTERPIN_SSO_CLIENT_SECRET` (or `--client-secret-env NAME`), else asked for without
echo, and is sent once (consent `licence.sso.secret`) to the licence service, which stores it **only** in AWS Secrets
Manager as `cotterpin/sso/<licence id>` and keeps its ARN. At the provider, register the application with the
redirect URI `https://licence.cotterpin.io/v1/sso/callback`, the authorization-code grant with PKCE, and (OpenID
Connect) refresh tokens (`offline_access`; Google: offline access). GitHub needs the scopes `read:user user:email
read:org`.

### For developers

`cotterpin login --team <name>` (consent `licence.service` for the machine fingerprint, and `licence.sso`, which says
it will open the browser and store the sign-in):

1. the CLI asks the licence service for a sign-in (`POST /v1/sso/device`) and shows a short code (`BCDF-GHJK`) and
   `https://licence.cotterpin.io/v1/sso/start`, which it also opens;
2. the browser goes from that page to the provider with PKCE (S256), a `state` and a `nonce`; after sign-in the
   provider returns to `/v1/sso/callback`, where the service exchanges the code with the verifier and the Team's
   client secret, verifies the ID token's RS256 signature against the provider's JWKS and its issuer, audience
   (`aud`/`azp`), expiry and nonce (GitHub: the user, its verified primary email and ACTIVE organization membership),
   and checks the email domain or organization. A `state` is spent before the provider is called, so a replayed
   response is refused;
3. the service binds this machine to the member's seat — a new member takes a free seat; a member's 4th machine is
   refused — and the CLI collects the Team licence once (`POST /v1/sso/token`).

An SSO machine's licence lasts at most **7 days** and renews only through the provider: `cotterpin login` (with a
stored sign-in, it renews without a browser; `--fresh` signs in again) or `cotterpin machines renew` send the stored
provider credential to `POST /v1/sso/renew`, and the service asks the provider again (an OpenID Connect refresh grant
whose new ID token must name the same subject and an allowed domain; GitHub: the same user, still an active member).
A person removed or disabled at the provider therefore stops renewing, and stops enforcing within 7 days; an admin's
`revoke` stops them at once. `cotterpin logout` releases this machine's seat and deletes the licence and the sign-in
here. Machines on a sign-in are not added or moved with `cotterpin machines`; you sign in on them.

### What the service keeps

For seat assignment the service stores **only** the identity's subject (the provider's stable user id), its email
address, and its Team membership (machines, admin flag, revoked flag, when it signed in). Provider tokens are not kept:
the sign-in record that hands the CLI its credential expires in 10 minutes and the credential is removed the moment the
CLI collects it. The credential lives on the developer's machine in `sso.json` (user configuration directory, mode
0600) and is useless without the Team's client secret, which only the service holds.

### Routes (configuration schema 3, `sso`)

| Route | Auth | Purpose |
|---|---|---|
| `POST /v1/team/sso` | Team admin's licence token | `show`, `set` (provider + client secret), `test` |
| `POST /v1/team/members` | Team admin's licence token | `list`, `revoke`, `restore`, `admin`, `unadmin` |
| `POST /v1/team/seats` | Team admin's licence token | Seats in use |
| `POST /v1/sso/device` | public, rate-limited per source | Starts a sign-in: device code, user code (admins: `mode: test`) |
| `GET /v1/sso/start` | browser; the user code | Redirects to the provider (PKCE, state, nonce) |
| `GET /v1/sso/callback` | browser; the `state` | Verifies the sign-in and binds the seat; answers an HTML page |
| `POST /v1/sso/token` | the device code | The CLI collects its licence and credential once |
| `POST /v1/sso/renew` | licence token + provider credential | Renews after the provider vouches again |
| `POST /v1/sso/logout` | licence token | Releases this machine |

```json
"sso": {
  "publicBaseUrl": "https://licence.cotterpin.io",
  "secretNamePrefix": "cotterpin/sso/",
  "deviceRequestsPerHour": 60
}
```

The Lambda additionally needs `secretsmanager:CreateSecret`, `secretsmanager:PutSecretValue` and
`secretsmanager:GetSecretValue` on `arn:aws:secretsmanager:<region>:<account>:secret:cotterpin/sso/*`, outbound HTTPS
to each Team's issuer (its `jwks_uri` and `token_endpoint`), `github.com` and `api.github.com`, and API Gateway must
pass query strings to the two browser routes (`deployment_artifact_contract()["sso"]`).

## Enforce or Watch, on this machine

Execution reads the licence for ONE thing: whether to refuse (ADR-003 §4). Every enforcing path asks at the moment it
would refuse, never earlier — so a run that finds nothing reads no licence and computes no fingerprint:

| Path | Enforcing (a current Trial, Pro or Team licence issued to this machine) | Watch (none, lapsed, another machine's) |
|---|---|---|
| `cotterpin gate run` (and the commit-tier gate check) | a blocking finding exits 1 | exits 0; the report says "passed in Watch" and lists what would have failed |
| `cotterpin commit` fast tier | a failing commit-tier check or a colliding worktree refuses | the commit lands; the report carries `watch` (what would have been refused, and why it was not) |
| `cotterpin push-gate` | a ref without a green deferred verdict refuses the push | the push goes; each ref is reported "Watch, would have REFUSED …" |
| `cotterpin hook <event>` | a rule's deny refuses the agent's action | the action runs; the agent is told what would have been refused |
| work routes (`delivery_audit`, `delivery_audit_fix`, …) | a pass with blockers is sent back; findings go to a fix route | the run ends `WATCH_REPORTED` carrying what would have been sent back; `cotterpin fix --scope` reports the run instead of starting it |

Each Watch event is kept as one line in `cotterpin/watch-report.jsonl` under the repository's Git directory (inside
the repository, never sent), and at the end of every agent turn the `Stop` hook tells the session everything Watch let
through since the last summary. A question a person at the keyboard can answer (`git reset --hard` in Claude Code)
stays a question in both modes: asking is not blocking.

The licence is read from `licence.json`, verified against the licence key this build pins (a published build pins the
KMS licence key; a development build whose pin names no key reads `$COTTERPIN_LICENCE_TRUST_PIN` instead), and
matched to this machine's fingerprint — computed only when your stored answer to `licence.service` is yes (it is
recalled, never asked: hooks and commits run where no one may be at a terminal). `--no-consent` therefore runs that
command in Watch, and so does CI unless it names the consent (`COTTERPIN_CONSENT=licence.service`). A clock wound
back cannot extend a licence (the highest time seen is kept in `clock-watermark.json` beside the licence).

This build pins ONE licence key (`cotterpin/release/manifests/licence-trust-pin-v1.json`): the KMS key
`alias/cotterpin/licence`, `arn:aws:kms:eu-west-1:019745375054:key/860eaa77-2b84-47ab-93e1-00b1a059a35f`, in the
Cotterpin AWS account, trust domain `cotterpin`, purpose `licence`, valid `1791072000`–`1854230400` — the key the live
service at `https://licence.cotterpin.io` signs with. A licence signed by any other key, including the keys once held
in the earlier AWS account (`326404743717`), does not verify, and that machine runs in Watch. Because this build pins a key,
`$COTTERPIN_LICENCE_TRUST_PIN` is ignored.

## The licence service (self-serve routes)

Configuration schema 2 adds a `commerce` section; schema 1 has none and every route below refuses
`commerce-unconfigured`. Every failure denies.

| Route | Auth | Purpose |
|---|---|---|
| `POST /v1/trials` | public, rate-limited per source | A 14-day trial bound to one machine fingerprint; one per fingerprint. A machine whose trial ended gets its own expired token back (it runs Watch, and can still subscribe) |
| `GET /v1/machines` | licence token in `X-Cotterpin-Licence` (base64url) | The licence's machines |
| `POST /v1/machines` | licence token | `renew`, `add`, `move`, `remove`; at most the plan's limit (trial 1, Pro 3, Team 3 × seats); each change written with an `AUDIT#` record in the same DynamoDB transaction |
| `POST /v1/checkout` | licence or trial token | Creates a Paddle transaction for the plan's price and seat quantity, `custom_data = {licenceId, machineFingerprint}`, and returns its `checkout.url` |
| `POST /v1/billing-portal` | licence token | Creates a Paddle customer-portal session and returns its overview URL |
| `POST /v1/paddle/webhook` | `Paddle-Signature` | Verifies and applies Paddle notifications (below) |
| `POST /v1/claims` | public, rate-limited per source and per email | Emails a one-time code (8 digits, 15 minutes, 5 attempts) when the address belongs to a paying Paddle customer; the same answer either way |
| `POST /v1/claims/verify` | one-time code | Binds the purchased licence to this machine and returns its token |
| `POST /v1/downloads` | licence token | Schema 1: one release by digest. Schema 2 (`channel: latest`): the newest public release the licence's tier may fetch |
| `POST /v1/admin/licences`, `/v1/admin/trials`, `/v1/admin/licences/revoke`, `/v1/admin/licences/move`, `/v1/admin/licences/extend` | `AWS_IAM`, issuer principals, MFA | The operator's `cotterpin admin` — see the admin CLI. A licence the operator revokes stays revoked whatever Paddle sends later; a trial the operator extends reaches each machine on its next `cotterpin machines renew` |
| `POST /v1/admin-web/*` (and the `OPTIONS` preflight) | Entra ID access token of the ONE operator (API Gateway JWT authorizer, verified again by the Lambda) | The operator's browser page at https://cotterpin.io/admin/ — the same actions plus the clients and the audit log; see the admin CLI |

Licences are KMS-signed exactly as before. A self-serve token is licence claims **schema 3**: it adds `plan`
(`trial`, `pro`, `team`) and `machineFingerprint`. Enforcement honours a schema-3 token only on the machine it names.

### Paddle: the only outbound calls

1. `POST /transactions` — `{"items":[{"price_id": <plan price>, "quantity": <seats>}], "custom_data":
   {"licenceId": ..., "machineFingerprint": ...}, "collection_mode": "automatic"}` (+ `customer_id` once known). The
   response's `checkout.url` must be on the configured default payment link's host and carry `_ptxn=<that
   transaction id>`.
2. `POST /customers/{customer_id}/portal-sessions` — `{"subscription_ids": [...]}`; the overview URL must be on
   `customer-portal.paddle.com` (live) or `sandbox-customer-portal.paddle.com` (sandbox).

Both send `Authorization: Bearer <API key>` and `Paddle-Version: 1`, use verified TLS, follow no redirects and use
no environment proxy. A live key (`pdl_live_apikey_…`) is refused in a sandbox configuration and vice versa.

### Paddle webhooks

`Paddle-Signature: ts=<unix seconds>;h1=<hex>`. The service computes HMAC-SHA256 with the notification destination's
secret key over `"<ts>:<raw body>"` — the exact bytes received, never re-serialised JSON — and compares it in
constant time against every `h1` (two are sent while a secret rotates). The timestamp must be within 300 seconds.
Only then is the body parsed. A notification whose `event_id` was already applied is acknowledged and changes
nothing (`paddle-event-replayed`), so Paddle's redeliveries and captured replays are both harmless.

| Notification | Effect |
|---|---|
| `subscription.created` / `activated` / `updated` / `resumed` (status `active` or `trialing`) | Licence `ACTIVE`; plan from the price, seats from the quantity (Team); paid through the current billing period's end |
| `subscription.past_due` (status `past_due`) | Stays `ACTIVE` until the paid period ends plus 3 days' grace, not beyond |
| `subscription.canceled` / `paused` | Licence `REVOKED` (Watch; no new releases); a machine may still be removed |
| `transaction.completed` | Renewal: paid through the transaction's billing period end |
| `customer.created` / `updated` | Records the SHA-256 of the customer's email, so their purchases can be claimed |

The licence is the one named in `custom_data.licenceId` (purchases started by `cotterpin subscribe`; Paddle copies a
transaction's custom data to the subscription it creates). A purchase with no licence id — the website's Paddle.js
overlay checkout — creates a new, unbound licence recorded against the Paddle customer, claimed later by email.
Notifications older than the state already applied are ignored (Paddle does not order delivery).

### Secrets and configuration

The Paddle API key and the notification secret key live **only** in AWS Secrets Manager, read by the licence Lambda
at cold start (`commerce.paddleApiKeySecretArn`, `commerce.paddleNotificationSecretArn`; two separate secrets).

```json
"commerce": {
  "paddleEnvironment": "live",
  "paddleApiKeySecretArn": "arn:aws:secretsmanager:<region>:<account>:secret:cotterpin/paddle-api-key-…",
  "paddleNotificationSecretArn": "arn:aws:secretsmanager:<region>:<account>:secret:cotterpin/paddle-notification-…",
  "prices": {"pro": "pri_…", "team": "pri_…"},
  "checkoutUrl": "https://cotterpin.io/checkout",
  "claimEmailFrom": "licences@cotterpin.io",
  "trialRequestsPerHour": 20
}
```

`checkoutUrl` is the account's **default payment link** (Paddle → Checkout settings); it must be a page on the
website that loads Paddle.js, which opens the checkout for the `_ptxn` in its address. `claimEmailFrom` is an Amazon
SES verified sender; `null` disables email claims, and `/v1/claims` then refuses `claim-email-unavailable`, naming
the gap.

The website uses Paddle.js overlay checkout with a **client-side token** (safe to publish) and the same price ids.

### Deployment

`cotterpin broker build --artifact licence-service` builds the Lambda artifact from a committed tree; its closure
includes `licence_service.py`, `licence_commerce.py`, `licence_paddle.py`, `licence_admin.py` (the operator routes of
`cotterpin admin`, docs/product/ADMIN.md), `licence_admin_web.py` (the operator's browser page) and `licence_sso.py`
(with the ID-token verifier it shares with enterprise sign-in, `cotterpin/auth/oidc_jwt.py` and `oidc_discovery.py`).
Configuration schema 3 (`sso`) is the one current schema: Team single sign-on needs it, and the admin routes need no
configuration of their own (they are served to the `issuerPrincipalArns` already configured); the browser page needs
the optional `adminWeb` section (docs/product/ADMIN.md). `deployment_artifact_contract()` lists every route and method, the IAM
actions (DynamoDB `GetItem`, `PutItem`, `UpdateItem`, `TransactWriteItems`, and `Scan` for the admin routes' reads; KMS
`Sign`; Secrets Manager `GetSecretValue`; SES `SendEmail` when claims are on), the secrets, the outbound hosts, the
handled Paddle notifications, and the webhook path. The DynamoDB table needs TTL on the attribute `ttl`.

## Tests

- `tests/release/test_licence_paddle.py` — real HMAC verification over documented-shape notification samples
  (`tests/support/fixtures/paddle/`); the two outbound calls over real HTTP to a loopback server answering with
  Paddle's recorded response shapes; and an opt-in acceptance test against the **Paddle sandbox**, run only when
  `COTTERPIN_PADDLE_SANDBOX_API_KEY`, `COTTERPIN_PADDLE_SANDBOX_PRICE_ID` and `COTTERPIN_PADDLE_SANDBOX_CHECKOUT_HOST`
  are set.
- `tests/release/test_licence_commerce.py` — every route through the real Lambda handler.
- `tests/release/test_licence_client_e2e.py` — the CLI client against the real handler behind a localhost HTTP
  server, with Paddle's webhooks delivered as real signed HTTP requests.
- `tests/kernel/test_enforcement_modes.py` — every enforcing path in both modes, with real licences signed by the
  test licence signer and bound to the test machine's real fingerprint.
- `tests/release/test_licence_sso.py` — Team single sign-on end to end: the CLI, the real handler behind the localhost
  gateway, a real browser client, and a real HTTPS identity provider (`tests/support/sso_testkit.py`) that issues real
  RS256 ID tokens with a real RSA key and serves a real JWKS (OpenID Connect) or answers as GitHub; covering a wrong
  issuer, a wrong audience, an expired token, a bad signature, another sign-in's nonce, a replayed and a forged
  `state`, a wrong domain or organization, an unverified email, seat exhaustion, machines per seat, renewal through
  the provider, removal at the provider, admin revocation, and logout.

Doubles exist only at the named external boundaries — DynamoDB, KMS, SES, AWS Secrets Manager, Paddle's network and
the identity providers' network (`tests/support/licence_testkit.py`, `tests/support/sso_testkit.py`).

## Refusals

Every refusal code is in [the refusal catalogue](REFUSALS.md) (`cotterpin explain <code>`): `machine-limit`,
`machine-bound`, `machine-released`, `machine-unknown`, `licence-token`, `licence-conflict`, `licence-pending`,
`licence-lapsed`, `trial-used`, `trial-rate-limited`, `checkout-seats`, `commerce-unconfigured`,
`subscription-exists`, `billing-no-customer`, `claim-code-invalid`, `claim-rate-limited`, `claim-email-failed`,
`claim-email-unavailable`, `paddle-*`, `machine-fingerprint`, `seat-limit`, and the single sign-on codes `sso-*`.
