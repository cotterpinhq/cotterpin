# Cotterpin — install, packaging, naming and gate integrity

Design note, 2026-09-18. Companion to `COMMERCIAL.md` (private `strategy` repository) (why) and
../architecture/architecture.md (what exists). It covers four decisions: the
product name, how the product is packaged and installed, how the gates are protected from
tampering, and what AWS is for.

(Filed at the repository root rather than `docs/` because a repository guard currently refuses
writes into that subdirectory from this checkout. Move it when convenient.)

---

## 1. The name: Cotterpin

**Decided 2026-09-18.** A cotter pin is the small part whose entire job is to stop something
falling apart while it is moving — which is the product.

| Surface | Status (checked 2026-09-18) |
|---|---|
| `cotterpin` on PyPI | **Free** |
| `cotterpin.io` | **Free** |
| `cotterpin.dev` | Free (no registration, no delegation) |
| `cotterpin.com` | Taken since 1999 — not required; `.io` is the primary |
| Trademark classes 9 and 42 | **Not yet searched — do this before filing** |

### 1.1 Why not "Harness" or "Universal Harness"

| Name | Status | Evidence |
|---|---|---|
| **HARNESS® as a product name** | **Taken, in our exact field** | Harness Inc holds US Reg. 5409033 (serial 87454296, filed May 2017) in classes 9 and 42, for software that orchestrates, configures, provisions, secures, monitors and automates deployment ([Justia](https://trademarks.justia.com/874/54/harness-87454296.html), [Harness trademark guidelines](https://www.harness.io/legal/trademark)) |
| `harness` on PyPI | Taken, dormant | v0.1.0, last released 2020-03-28 |
| `harness` on npm | Taken, dormant | v0.0.6, last published 2012-11-26 |
| **`universal-harness` on PyPI** | **Taken, active, adjacent** | v1.2.0 released 2026-05-13: *"Universal Harness (UH) — thin namespace facade over aiking-core governance for cross-substrate agents"* |

A registered mark in our own classes, held by a well-funded company that publishes trademark
guidelines and therefore polices it, is not a name to build on: a CLI binary is use in
commerce, and we would be exposed rather than merely unable to register. Putting the mark in
the *domain* instead (e.g. a Deadeye product served from a `universalharness` domain) keeps
exactly the same exposure and splits the brand, so it was rejected too.

**The internal name may stay.** `task_harness` as the Python import, and "harness" as a common
noun in architecture prose, carry little risk. The risk attaches to the product name, the
command, the domain and the registry entries.

### 1.2 Registrations to make

Do the free ones this week — first-come, zero cost, irreversible if someone else takes them.

| Surface | Action | Cost |
|---|---|---|
| PyPI `cotterpin` | Register, publish a 0.0.1 placeholder | Free |
| npm `cotterpin` | Same (check first) | Free |
| crates.io `cotterpin` | Same | Free |
| `cotterpin.io` + `cotterpin.dev` | Register both | ~£60/yr |
| GitHub org `cotterpin` | Claim | Free |
| Homebrew | Own tap `cotterpin/tap/cotterpin` | Free |
| winget | Publish manifest to winget-pkgs | Free |
| **Trademark, classes 9 + 42** | Search first, then UK, then US, then EUIPO | ~£170 UK first class; US ~$250–350/class; plus attorney fees |
| Defensive | Claim `cotterpin` on registries we do not use yet | Free |

### 1.3 Naming shape

- **Distribution name** (`pip install cotterpin`, `brew install cotterpin`): `cotterpin`
- **Command**: `cotterpin`. No short alias initially — `cp` collides with a core Unix command,
  which is exactly the sort of thing to avoid
- **Python import**: `task_harness` stays internal for now; rename later if it is ever public
- **Config directory in a customer repo**: `.cotterpin/`
- **Lock file**: `.cotterpin.lock.json`

---

## 2. Install: two modes, honestly labelled

Today's flow — staged admin installers, framework permission repair, root supervisor,
dedicated runner accounts, provider enrollment, native canary, release lock adoption — is a
security design for a shared host. It is not an onboarding, and at $10/seat it cannot be one
(COMMERCIAL.md §7.1, §12).

| | Developer mode (default) | Hardened mode (enterprise) |
|---|---|---|
| Install | User-space, no admin | Root supervisor, dedicated runner UIDs, confined workers |
| Protects against | A *mistaken or fabricating agent* | A *hostile local process or user* |
| Gate enforcement | Signed packs, outside the agent's writable tree, tamper-**evident** | Root-owned policy, tamper-**resistant**, enforced isolation |
| Entry point | `cotterpin install` | `cotterpin harden`, or pushed by MDM |
| Claim we may make | "The agent cannot mark work done without evidence" | "…and a local process cannot forge that evidence" |

`../architecture/security-audit.md` already draws this line — *"unrestricted local execution is not a
hostile multi-user security boundary"*. Making it two named modes turns a caveat into a
feature and an upsell.

*Built (hardened entry point):* `cotterpin harden hooks` registers the hook in the agent tools' administrator-managed
settings and runs it from the root-owned runtime ([SECURITY-MODEL.md](SECURITY-MODEL.md#hardened-mode)):

```sh
cotterpin harden hooks render --into <payload-dir>   # the files as a pkgbuild --root / MDM payload; no root needed
sudo cotterpin harden hooks install                  # writes them root-owned; reads the runtime from supervisor-install.json
cotterpin harden hooks status [--json]               # registered | missing | differs | unsafe, per file; exit 0 = protected
```

It covers Claude Code (a managed-settings drop-in with `allowManagedHooksOnly`) and Codex (`/etc/codex/requirements.toml`
with `allow_managed_hooks_only`). Grok has no administrator-managed hook registration, so it is reported as not covered.
Passkey and hardware-key enrolment for hardened approvals: `cotterpin auth hardware-key enrol` (the person), then
`sudo cotterpin auth hardware-key install-credential` (the administrator) — [APPROVALS.md](APPROVALS.md).

### 2.1 The three commands

```sh
cotterpin install         # 1. user-space runtime, signature-verified, ~60s
cotterpin connect         # 2. detect provider CLIs, verify auth; we store no provider secret
cotterpin init [repo]     # 3. write policy, pin the stack pack, dry-run the gates
```

**`install`** — fetches and verifies a signed, self-contained artifact into
`~/.local/share/cotterpin/` (or `%LOCALAPPDATA%\Cotterpin`), puts a launcher on PATH, writes
nothing outside the user's home, and raises no administrator prompt. It prints what it will do
before doing it, and supports `--offline <bundle>` for air-gapped machines.

**`connect`** — discovers installed provider CLIs and checks each is authenticated *by asking
the CLI*. It stores no provider secret and distinguishes "available" from "configured". A
failure is a diagnosis ("Codex found, not logged in — run X"), never a stack trace.
*Built 0.2.0:* `cotterpin/providers/provider_connect.py`. It uses the kernel preflight's own probe table
(`provider_probe.py`), so the two cannot disagree about whether a provider is ready. `--json` prints the
machine-readable report.

**`init`** — writes a reviewable `.cotterpin/policy.yaml` into the repository, selects the
stack pack (Java / Terraform / .NET / Angular), pins its digest into `.cotterpin.lock.json`,
then runs the gates in report-only mode and prints what *would* have blocked. First contact
with the enforcement layer must inform, never refuse.
*Built (ADR-005 F10/X1):* `cotterpin/onboarding/`. `init` writes the policy, a developer lock and a `.gitignore`
block, and asks before it scans. `doctor`, `uninstall` and `cache du|gc|clear` are built too. Every probe is
consent-gated, and the developer path needs no `enterprise` extra. The report-only gate dry-run is not built yet. See
[QUICKSTART.md](QUICKSTART.md) and [ONBOARDING-COMMANDS.md](ONBOARDING-COMMANDS.md).

Then `cotterpin run <task>`.

### 2.2 Acceptance criteria

1. A machine with only Python and one provider CLI reaches a passing `init` dry-run in under
   ten minutes with zero administrator prompts, on macOS, Windows and Linux.
2. No step asks for `sudo` in developer mode.
3. Every failure names the next action; none leaves a partial install a re-run cannot repair.
4. `cotterpin uninstall` removes what it created and states what it kept (repository policy
   files stay — they are the customer's).
5. The flow needs no network beyond the artifact fetch and the provider's own login.
6. `cotterpin --uninstall` (also `cotterpin uninstall --machine`) removes Cotterpin from the whole machine, from its
   own records: every repository it set up (`init`, `adapters install` and `hooks install` note each one in
   `<config dir>/repositories.json`), the caches, the configuration folder, this machine's licence seat (given back
   through the licence service), a hardened install's root-owned parts (one `sudo -k`), and last the package itself.
   It detects how the package was installed: `pipx uninstall cotterpin`, `uv tool uninstall cotterpin`, `brew
   uninstall cotterpin`, `python -m pip uninstall cotterpin` (also `--user`), `uv pip uninstall`, or the release
   installer's `~/.local/share/cotterpin` folder and its launcher. A source checkout is never deleted, and the command
   to unlink it is printed. It lists everything first and asks once, and a final check proves nothing it wrote is
   left. See [ONBOARDING-COMMANDS.md](ONBOARDING-COMMANDS.md).

### 2.3 Packaging per platform

**Launch scope (operator ruling, 2026-10-02):**

| Platform | Mode at launch | Runtime wheel lock |
|---|---|---|
| macOS arm64 | hardened and developer | `mac-runtime-wheel-lock-v1.json` (covered today) |
| Linux x86_64 and aarch64, including Windows via WSL2 | developer only | a Linux lock, added with the developer-mode install (REL-5): manylinux wheels for the three compiled dependencies (cffi, cryptography, PyYAML) |
| Intel macOS, native Windows | not at launch | — (Windows execution is refused at the entry point until its adapters exist) |

Why: Linux covers dev containers, cloud workstations and CI runners, and through WSL2 most Windows developers, for
one extra wheel set; Apple has sold only Apple Silicon since 2023; a native Windows execution and isolation adapter
does not exist yet. Hardened mode stays macOS-only because the supervisor is built on launchd and dedicated UIDs.

The table below is the target per OS once each is in scope.

| OS | Artifact | Channel | Signing |
|---|---|---|---|
| macOS | the compiled wheels (REL-7) in a `.pkg`, plus a Homebrew tap | `brew install cotterpin/tap/cotterpin` | Developer ID + notarisation |
| Windows | MSIX or signed MSI | `winget install cotterpin` | EV code-signing certificate |
| Linux | `.deb`/`.rpm` + static tarball | apt/yum repo, or a signature-checked install script | GPG-signed repo |
| Any (developers) | wheel | `pipx install cotterpin` | PyPI + Sigstore attestations |

Ship compiled code rather than plain Python: it removes "we shipped our source to every customer"
(COMMERCIAL.md §8). Keep the build reproducible so the SBOM means something. **Built (REL-7, 2026-10-05):**
`tools/release/build_compiled.py` compiles every kernel and pack module with the pinned Cython into a native
extension inside a platform wheel — not a Nuitka single binary, because a wheel keeps what the product already
relies on: `pip`/`pipx` install, packs found through their entry points and admitted against the lock, and the
signed release manifest naming each file. Reproducible, in the SBOM, signed and installed by
`tools/release/install_release.py`; the measured speed against the pure wheels is in [RELEASE.md](RELEASE.md).

---

## 3. Protecting the gates

### 3.1 Threat model first

| # | Threat | Who | Real? | What actually stops it |
|---|---|---|---|---|
| T1 | **The agent edits or deletes the gates constraining it** | The coding agent, mid-task | **Yes — the daily one.** The backend's RULE 4 exists because it happened | Gates live outside the agent's writable tree; digests pinned and re-verified before each run |
| T2 | **Receipts forged** to claim work was verified | A confused or over-eager agent | Yes | Hash-chained receipts, signed by a key the agent's identity cannot read |
| T3 | **A developer disables a gate** to land a commit | The customer's own engineer | Yes, and sometimes legitimately | Tamper-*evidence*: the override is recorded and centrally visible. Not prevention |
| T4 | **Gate packs copied** to an unlicensed machine | A customer | Moderate | Licence-bound packs; mostly a commercial control |
| T5 | **A hostile local process** steals credentials or forges evidence | Malware, another user | Only on shared hosts | Hardened mode: root supervisor, confined runner UIDs — already designed |

**The honest boundary: on a machine its owner controls, nothing is tamper-proof.** The design
goal is *tamper-evident and centrally detectable*, with tamper-resistance as the enterprise
upgrade. Any stronger claim is falsifiable, and Cotterpin's whole value is that it does not
make falsifiable claims.

### 3.2 The layered design

1. **Signed gate packs.** Content-addressed, signed by our release key, public key embedded in
   the binary, verified offline. A pack failing signature or digest refuses to load — an
   unverified gate is worse than an absent one.
2. **Digest pinned in the repository.** `.cotterpin.lock.json` records the pack digest, is
   committed, and is reviewed like any other change, so swapping a pack is a visible diff.
3. **Gates outside the agent's writable set.** Packs live in the install directory; the
   kernel re-verifies digests before each run, so editing a pack on disk fails closed.
4. **Hash-chained receipts.** Each receipt carries the previous receipt's hash, so deleting or
   rewriting history breaks the chain — cheap, local, detectable.
5. **Overrides are first-class, not loopholes.** Recorded with who, when, which gate and why.
   Systems that forbid overrides get bypassed wholesale; systems that make them expensive and
   visible survive contact.
6. **Hardened mode** adds root-owned policy and confined execution identities — the only
   configuration in which "a local process cannot forge this" is true.

### 3.3 What AWS is for

AWS holds **what must be centrally true**, and nothing that breaks "no code leaves the
machine".

| Component | Service | Why |
|---|---|---|
| Release + gate-pack distribution | S3 + CloudFront | Signed, versioned, cacheable, air-gap exportable |
| Signing keys | **KMS asymmetric** | The private key never exists on a laptop; signing is an API call from CI |
| Licence issuance and seat state | API Gateway + Lambda + DynamoDB | Small, cheap, the natural home for Paddle Billing webhooks (LICENSING-AND-BILLING.md) |
| Revocation and entitlements | Same | Short-lived signed tokens, verified offline on the client |
| **Receipt anchoring (optional, off by default)** | Lambda + DynamoDB | Client posts *only* `{chain head hash, run id, gate ids, verdict counts, timestamp}` — no code, prompts, diffs, or clear-text repository names |
| Enterprise attestation view | Same data | See `DASHBOARD-AND-UI.md` (private `strategy` repository) |

**Never in AWS:** source, diffs, prompts, model responses, file paths, clear repository names,
credentials. Publish the egress schema and enforce it with a test — that test *is* the claim.

**Cost:** at a few thousand seats, low tens of dollars a month. The real constraint is not
cost but availability: **if our AWS is down, the customer's gates must keep working.** Hence
offline verification everywhere, with anchoring queued and retried.

### 3.4 The strongest control is not local at all

For enterprises, the highest-value design is **re-verification in their CI**: the same signed
pack runs again on a machine the developer does not control, and the laptop's receipt chain is
compared against it. Local tampering then surfaces at the one point the organisation already
trusts. Cheap for us — the same packs in a container image — and it makes the claim credible
without trusting the endpoint. It should be the Enterprise tier's headline feature.

---

## 4. Phasing

| Phase | Work | Done when |
|---|---|---|
| **0. Name** | Trademark search, registrations, rename repo and package | Registries held, mark filed, `cotterpin` published as a placeholder |
| **1. Developer install** | `install` / `connect` / `init`, user-space, three OSes | §2.2 criteria pass on all three |
| **2. Packaging** | compiled build (built: REL-7), signing, notarisation, tap/winget/apt | A stranger installs from a public channel |
| **3. Gate integrity** | KMS pack signing, digest pinning, chained receipts | A tampered pack refuses; a broken chain is caught by a test |
| **4. Licensing** | Paddle Billing (merchant of record) + licence service + offline tokens | A paid seat activates and runs offline for 30 days |
| **5. Enterprise** | `harden` mode, CI re-verification, attestation dashboard, SBOM | One design partner runs it in CI |

---

## 5. Decisions still open

1. **Trademark search on COTTERPIN** in classes 9 and 42, before filing or public launch.
2. **Receipt anchoring default.** Recommend off by default, on for Enterprise, schema always
   published.
3. **Ship developer mode before hardened mode is finished?** Recommend yes, with the two-mode
   labelling above.
4. **Who holds the KMS signing key and who may approve a release?** Needs an owner before the
   first public artifact.
5. **Whether to run `detent` (Apache 2.0) as the commodity-check gate provider** for
   Python/JS/Go/Rust rather than building those stacks ourselves (COMMERCIAL.md §4.3).
