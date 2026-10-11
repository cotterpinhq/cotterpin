# Releases: cutting, signing and checking a Cotterpin release

This page is for two readers: the **operator** who cuts a release, and the **developer** who wants to check that
what they downloaded is what was released.

## Names

| | final release | release candidate |
|---|---|---|
| release name (locks, manifest) | `0.3.0` | `0.3.0-rc1` |
| Python version (pyproject.toml, `cotterpin/version.py`) | `0.3.0` | `0.3.0rc1` |
| git tag | `cotterpin-v0.3.0` | `cotterpin-v0.3.0-rc1` (a pre-release) |

A candidate orders before its final release. Tags are lightweight: the packager requires the tag to resolve to the
release commit itself.

## Check a release you downloaded

Every release publishes: the wheels — for the kernel and for each language pack, a pure wheel
(`cotterpin-0.3.0rc1-py3-none-any.whl`) and a compiled one (`cotterpin-0.3.0rc1-cp313-cp313-macosx_11_0_arm64.whl`,
see *Compiled distribution* below) — `sbom.cdx.json`, `release-manifest.json` (each published file by sha256) and
`release-manifest.sig.json` (the release key's signature over the manifest).

Install them, checked first (the signature, then every wheel's bytes; nothing is installed when any check fails):

```sh
python3 tools/release/install_release.py --release-dir <the downloaded files> [--python <interpreter>] \
    [--flavour auto|compiled|pure] [--mode auto|developer|hardened]
```

`auto` installs the compiled wheels when they were built for that interpreter (its CPython version and platform), else
the pure ones. Or check them yourself:

```sh
cotterpin verify --release --manifest release-manifest.json --signature release-manifest.sig.json \
    --artefact cotterpin-0.3.0rc1-py3-none-any.whl --artefact sbom.cdx.json
```

- Exit 0: the signature verifies and every file matches. Exit 1: a check failed — do not install those files.
  Exit 2: the check could not run; the message says why and what to run next.
- **Which trust set checks the signature.** `--mode hardened` uses the administrator's root-owned trust set
  (`/private/etc/cotterpin/release-trust.json`, which the administrator installs while setting up hardened mode:
  `cotterpin harden`, [SECURITY-MODEL.md](SECURITY-MODEL.md#hardened-mode)). `--mode developer` uses the trust set pinned inside this build, so no
  root access is needed. The default, `auto`, uses the root-owned set whenever it is installed. If that set is
  present but damaged, the check refuses rather than falling back to the pinned one.
- Nothing is sent anywhere: the check is offline.

## Cut a release (operator)

One-time setup: the release configuration, outside the repository, at `~/.config/cotterpin/release.json`
(or pass `--config`):

```json
{"kind": "cotterpin-release-config", "schemaVersion": 1,
 "kmsKeyArn": "arn:aws:kms:<region>:<account>:key/<key id>", "trustDomain": "<trust domain>"}
```

`awsProfile` is optional. The release is signed **only** with this key. With no configuration, or no `kmsKeyArn`,
nothing is signed and the release stops before it starts, naming the file to create.

Pin the key into the build (once per key, merged like any change), so developer installs can check signatures:

```sh
python3 -m cotterpin.release.release_authoring pin-trust --config ~/.config/cotterpin/release.json
```

This reads the key's PUBLIC key from KMS with your own AWS session and writes
`cotterpin/release/manifests/release-trust-pin-v1.json`.

**The keys this build pins** (2026-10-05), all in the Cotterpin AWS account `019745375054`, `eu-west-1`, trust domain
`cotterpin`, valid `1791072000`–`1854230400` (2026-10-04 to 2028-10-04), exactly as the live licence service's trust
block names them:

| Pin | KMS alias | Key ARN | Purposes |
|---|---|---|---|
| `release-trust-pin-v1.json` | `alias/cotterpin/release` (signing needs MFA) | `arn:aws:kms:eu-west-1:019745375054:key/8b1e62a0-0e20-4a30-aa24-e67a5222ff25` | `release`, `revocation` |
| `licence-trust-pin-v1.json` | `alias/cotterpin/licence` | `arn:aws:kms:eu-west-1:019745375054:key/860eaa77-2b84-47ab-93e1-00b1a059a35f` | `licence` |

The keys held in the earlier AWS account (`326404743717`) are no longer trusted by any build: a release or licence they sign
is refused (`tests/release/test_shipped_trust_pins.py`). The release configuration therefore names
`arn:aws:kms:eu-west-1:019745375054:key/8b1e62a0-0e20-4a30-aa24-e67a5222ff25` as `kmsKeyArn`.

Then cut. It is a dry run until `--approve`:

```sh
python3 tools/release/cut_release.py cut --version 0.3.0 --rc 1            # read the plan
python3 tools/release/cut_release.py cut --version 0.3.0 --rc 1 --approve  # act
```

It checks that `main` is clean and equal to `origin/main` and carries the Python version; runs the tests (the delta
since `--since <ref>`, or the full suite); tags and pushes `cotterpin-v0.3.0-rc1`; builds the pure and the compiled
wheels of the kernel and every pack reproducibly from the tagged commit (the compiled ones twice, refused unless
byte-identical) and the SBOM; writes and signs the manifest; and prints the install line above. Run it with an
interpreter that holds the pinned Cython (`pip install --require-hashes` from `tools/release/compiled-build-lock.json`,
or `pip install -e .[compiled-build]`); without it the compiled build refuses and the release stops there.

**Any test failure stops the release.** Nothing is re-run alone and nothing is waved through as a flake: a test that
fails only under load has a cause, and it is fixed there.

A release needs **no consumer**. Each step checks whether it already happened, so a stopped release is re-run, not
restarted.

## Adopt a release into a consumer (operator, later)

```sh
python3 tools/release/cut_release.py adopt --release 0.3.0-rc1 \
    --previous-release-ref refs/tags/cotterpin-v<the release the consumer's committed lock adopted> \
    --reason-file <your approval text> --consumer <checkout> --repository-id <id> --setup <setup directory>
```

It packages the release for that consumer, cross-checks the guard review against plain `git diff`, and prints the
one `sudo` line to run. When the previous release shipped no guard reviewer, the review was judged only by the new
release's reviewer; the command says so and needs `--accept-bootstrap-review` to continue.

A consumer that adopted a release tagged before the `cotterpin-v` prefix: add `cotterpin-v<that release>` on the
same commit first (`git tag cotterpin-v<release> <old tag>`).

## Reproducible wheels

```sh
python3 tools/release/build_wheel.py --commit <full sha> --output <dir> --all     # the kernel and every pack
```

The same commit builds the same bytes on any machine: the files are exactly those each pyproject.toml declares (the
kernel's, and `packaging/cotterpin-pack-<id>/pyproject.toml` for a pack), every entry carries SOURCE_DATE_EPOCH (the
commit time unless you set it), entries are sorted, modes are fixed, and the metadata names no build tool, host or path.

## Compiled distribution

```sh
python3 tools/release/build_compiled.py --commit <full sha> --output <dir> --all --check-reproducible
```

Every kernel and pack MODULE is translated to C by the pinned Cython (`tools/release/compiled-build-lock.json`: the
version, both wheels' sha256, the translator directives and the compiler flags) and compiled into a native extension
that replaces its `.py` in a platform wheel (`cp313-cp313-macosx_11_0_arm64` on the launch Mac). Everything else is
the pure wheel's file set, unchanged. These `.py` stay source, decided from the tree and the lock on every build
(`build_compiled.compiled_modules`, pinned by `tests/tools/release/test_compiled_entry_modules.py`):

- `__init__.py` and `__main__.py`, so packages stay packages and `python -m cotterpin` runs;
- package data run by path (`scripts/*.py`);
- ENTRY modules — a module with a `__main__` block that the tree runs or documents as `python -m <module>`, every gate
  (each is documented as runnable on its own), and a module whose own file product code hands to an interpreter
  (`approval_signer`, the Maven `java_launcher`, the Python check route). Neither `runpy` nor `python <file>` can run
  an extension;
- a module product code reads as TEXT, each named with its reason in the lock's `keepSource` (today only
  `cotterpin/version.py`, which the adapter generator reads);
- the HOOK PATH: the 39 modules one `cotterpin hook` call imports (the lock's `hookPath`, held equal to what a real
  hook call imports by `tests/tools/release/test_compiled_entry_modules.py`). Speed: importing a native extension
  costs ~0.6 ms more than cached bytecode, and every agent tool call is a fresh hook process.

One semantic difference is deliberate: a compiled module binds its builtins (`print`, `open`, ...) when it is
imported, so patching `builtins.print` AFTER the import is not seen by compiled code — capture output by redirecting
stdout instead. (Turning that binding off, Cython's `cache_builtins=False`, made every compiled
`cotterpin hook PreToolUse` call segfault, measured 2026-10-05, so it stays on.)

String constants are kept uncompressed in each extension (the lock's `-DCYTHON_COMPRESS_STRINGS=0`; Cython compresses
them by default), so `release_authoring installed --marker <text>` finds a release marker in the compiled kernel core
exactly as it does in `core.py`. A marker in a COMMENT is not in the binary: pick one from the code.

Measured 2026-10-05: kernel 207 of 288 modules compiled (81% of its lines), Java pack 106 of 175 (71%: its 64
standalone gates stay source). Wheels: kernel 19.6 MB compiled against 2.2 MB pure, Java pack 7.5 MB against 1.0 MB.

**Speed** (`tools/release/measure_compiled.py`: the two flavours installed in two environments, measured sample by
sample in turn, the lower of two passes; Apple silicon, Python 3.13.14; 1-minute load 8.7 at the start, other work
pushed it to 17 during the run, which falls on both flavours alike):

| | pure | compiled | ratio |
|---|---|---|---|
| `cotterpin --version`, cold | 28.2 ms | 27.7 ms | 0.98 |
| `cotterpin hook PreToolUse`, p95 | 167.9 ms | 152.9 ms | 0.91 |
| `cotterpin hook PreToolUse`, p50 | 65.3 ms | 64.2 ms | 0.98 |
| hook CPU (median) | 59.6 ms | 59.4 ms | 1.00 |
| hook import cost | 80.0 ms | 75.9 ms | 0.95 |
| commit-tier gate run, one-module change | 577.0 ms | 610.6 ms | 1.06 |

Every number is within the +10% limit. Before the hook path was kept source, the same measurement read hook p95
1.34x, hook CPU 1.25x and hook import 1.45x the pure wheel (cold start 1.02x): over the limit, which is why it is.
Compiled code is not faster here: the
product's time is in subprocesses, git and file I/O, not in Python bytecode; the compiled distribution is for not
shipping source, at no measured cost.

**Reproducible.** Each module is translated and compiled from a relative path in a scratch directory, with fixed flags,
no debug information and local symbols stripped, so no build path, host or time reaches a binary. The same commit, the
same lock and the same compiler build the same bytes; `--check-reproducible` builds twice in two directories and
refuses unless every wheel's sha256 matches. The wheel's `cotterpin-compiled-build.json` records the translator, the
compiler's version line, the flags and which modules stayed source.

**In the SBOM, signed, installed.** The SBOM lists the pinned Cython wheels (scope `excluded`: nothing imports them at
run time) and every published wheel by sha256; the signed manifest names each wheel; `install_release.py` verifies
and installs it.

**Behaves identically.** The suite runs against the INSTALLED compiled build and, as the control, against the
installed pure build, from the same checkout, and the two verdicts are compared test by test. Measured 2026-10-05
(commit tier, 7,211 tests each): **0 tests differ** — 7,171 pass, 11 skip and 29 fail in BOTH. 26 of them fail only
because an installed runtime is not the checkout the tests were written against (they expect the checkout's paths, its
`pyproject.toml` and git history, or find the Java pack twice: once installed, once in the checkout); the source run of
the same tree passes them. The other 3 failed in the source run too (the docs bundle was stale; regenerated). Writing
code the translator handles: Cython 3.2 has no `match` statement, and refuses a starred item after
another item in a list display (`[a, *b]`; write `[a] + list(b)`); the build names each module it cannot translate.

**Limits.** An APPROVED-RELEASE lock pins each pack file's source bytes and Git blob, so it admits the pure pack
wheel only; a developer lock (`cotterpin init`) pins the installed bytes and admits either. Tools that package
SOURCE (the licence Lambda artifact) build from a source checkout's commit, as they always did.

## Platforms

The runtime's third-party wheels are pinned per operating system:

| platform | lock | Python |
|---|---|---|
| macOS, Apple silicon | `mac-runtime-wheel-lock-v1.json` | 3.13 |
| Linux x86_64 and aarch64 (glibc 2.17+) | `linux-runtime-wheel-lock-v1.json` | 3.11 – 3.14 |

`cotterpin.release.runtime_locks.select()` picks the lock for the machine and refuses when a platform or Python
version has no pinned wheel, naming what is supported. Native Windows is not supported; use WSL.

## Release governance (wave nine)

* **Release candidates wait for every open item.** `python3 -m cotterpin.release.release_authoring tag --version
  X.Y.Z-rcN --commit <sha>` refuses (`release-rc-open-items`) while an item row of ADR-001 or ADR-005 says `Open:`,
  `**open**`, `... open |` or `still open`, and while any gate or hook-rule module is still pending an adversary receipt.
* **Adversary receipts.** Every pack gate module and hook-rule module carries a SOUND receipt from an independent Refute
  run, re-arbitrated by the controller (`cotterpin/tooling/refute_rearbitrate.py` `receipt`), bound to the module's
  sha256 — or it is listed as pending in `cotterpin/release/manifests/gate-adversary-receipts-v1.json`. The release runs
  `tests/packs/java/test_gate_adversary_receipts.py`; the pending list may only shrink from one release to the next
  (`release_gate_policy.adversary_ratchet`). Bootstrapped in wave nine with all 78 modules pending: the backfill is
  RC1 work, and the candidate tag waits for the list to be empty.
* **Release tags are made only by `release_authoring tag`.** The repository's commit wrapper's `commit --tag cotterpin-v...`
  is refused (`release-tag-not-via-authoring`), and the wrapper refuses to run from inside another checkout than its
  own (`commit-manager-wrong-root`).
* **Bootstrap adoption** passes a lock refusal's own reason back from the operator child when it is one of the lock
  library's fixed sentences (`adoption-lock-error-reason`); a message built at run time never crosses the boundary.
* **Signing keys.** The release and licence key ARNs are NOT yet in `release-trust-pin-v1.json`: the live keys are in
  the first customer's account, and the pin waits for keys in Cotterpin's own account.
