# The repository lock and language packs

Release 0.3.0-rc1. Covers ADR-001 CUST-6 (the lock pins digests instead of carrying the product's source) and
PACK-1 (each language pack is its own distribution, found through an entry point and admitted by the lock).

## What the lock is

`.cotterpin.lock.json` sits at the root of your repository and is committed with it. It records exactly which
Cotterpin release, and which language packs, this repository approved. It holds **no product source**. For every
product file it holds four facts:

| field | meaning |
|---|---|
| `path` | where the file lives in the release |
| `mode` | `100644` or `100755` |
| `blob` | the file's Git blob id, proven against the publisher's own Git tree |
| `sha256` | the sha256 of the file's bytes |

and, for the kernel and for each pack, the sha256 of the one wheel that carries those files:

```json
"runtimePackage": {"artefact": {"distribution": "cotterpin", "version": "0.3.0rc1",
                                "file": "cotterpin-0.3.0rc1-py3-none-any.whl", "sha256": "sha256:…"},
                   "files": [{"path": "cotterpin/cli.py", "mode": "100644", "blob": "…", "sha256": "sha256:…"}, …]},
"packs": [{"id": "java", "version": "0.3.0rc1", "kernelApi": {"minimum": 1, "maximum": 1},
           "descriptorPath": "cotterpin_pack_java/pack-release-descriptor.json",
           "files": [ … ], "digest": "sha256:…",
           "artefact": {"distribution": "cotterpin-pack-java", "version": "0.3.0rc1",
                        "file": "cotterpin_pack_java-0.3.0rc1-py3-none-any.whl", "sha256": "sha256:…"}}]
```

So the lock grows with the number of files, never with their size, and a change to it reads like any other small
diff in review. A test pins this: a release whose runtime file grows by four megabytes changes the lock by less than a
kilobyte, and a lock over 4 MiB is refused.

The lock's `schemaVersion` is **4**. Versions 1–3 carried a copy of every product file; Cotterpin no longer reads them.

### Agent tool adapters

The Claude Code, Codex and Grok adapters are not copied into the lock either. Each is generated from runtime files
the lock already pins, and its digest is recorded in `cotterpin/adapters/pins.json` — itself a pinned runtime file.
`cotterpin adapters install` refuses unless the adapter it renders has exactly that digest, and records the digest in
`.cotterpin/adapters/<adapter>.install.json`. See [AGENT-ADAPTERS.md](AGENT-ADAPTERS.md#pinning-how-the-lock-covers-the-adapters).

## Where the bytes come from

The wheels are built by Cotterpin itself, deterministically: the same files always give byte-identical wheels on any
machine (stored members, fixed timestamps, sorted order). That is what makes a lock proposed on one machine valid on
another. Every file read from a wheel — or from the release cache, or from a Git checkout of the release — is checked
against its `sha256` **and** its Git `blob` id before it is used.

| command | what it does |
|---|---|
| `cotterpin library build-artefacts --lock .cotterpin.lock.json --source-repo <Cotterpin checkout> --output-directory <new dir> [--cache-root ~/.cache/cotterpin]` | rebuilds every wheel the lock pins from the release commit and refuses unless each one's sha256 is the pinned one; optionally stores them in the release cache |
| `cotterpin library store-artefact --wheel <file>` | puts one wheel into the release cache at `~/.cache/cotterpin/artefacts/<sha256>.whl` |
| `cotterpin library materialise --lock .cotterpin.lock.json [--wheel <file> …] [--cache-root ~/.cache/cotterpin] --into <new dir>` | writes every approved file into a new directory, read from the pinned wheels and verified file by file |
| `cotterpin library inspect --lock .cotterpin.lock.json` | prints the release, the pinned paths, the packs and the wheel pins |
| `cotterpin verify --release` | checks the lock, the materialised runtime (each file by sha256) and every approved pack installed on this machine |

## Language packs

A language pack is its own distribution, `cotterpin-pack-<id>`, versioned on its own. Its package
`cotterpin_pack_<id>/` ships:

* `pack.json` — exactly `{"id", "version", "kernelApi": {"minimum", "maximum"}}`. `kernelApi` is the range of
  Cotterpin pack API versions the pack works with; this Cotterpin provides API **1**.
* `pack-release-descriptor.json` — `{"kind": "cotterpin-pack-release-descriptor", "schemaVersion": 1, "pack", "packagePaths"}`:
  every file the pack ships, itself and `pack.json` included, and nothing outside its own package.

The kernel's release descriptor names each pack descriptor in `packDescriptorPaths` and never lists a pack file
itself. The kernel wheel contains no pack.

### How Cotterpin finds a pack, and when it uses one

A pack distribution declares an entry point in the `cotterpin.packs` group (`java = cotterpin_pack_java`). Cotterpin
finds packs through that entry point, and also finds a pack sitting beside `cotterpin/` in its own runtime directory
(a source checkout, or a release materialised without installer metadata). **Finding a pack never approves it.**

* In a repository with a lock, Cotterpin uses exactly the packs the lock approves. Before a pack tool runs
  (`cotterpin pack <id> …`) and before a repository run starts, each approved pack must be installed, serve this
  Cotterpin's pack API, and hold exactly the approved bytes: every pinned file present with its sha256 and blob id, no
  unpinned file inside the package (`__pycache__` is ignored), and its content digest equal to the lock's. An
  installed pack the lock does not approve is never used.
* Outside a repository with a lock (for example `cotterpin --version`), only packs inside Cotterpin's own runtime
  directory are used — they are part of the runtime Cotterpin itself is running from. A pack installed anywhere else
  is not used until a lock approves it.

What you see when something is wrong, and what to run:

| message begins | run |
|---|---|
| `this repository's lock approves the <id> pack <version>, which is not installed` | `pip install cotterpin-pack-<id>==<version>` |
| `the installed <id> pack is <x>, but this repository's lock approves <y>` | `pip install cotterpin-pack-<id>==<y>` |
| `the installed <id> pack differs from the one this repository's lock approves (changed …; missing …; not approved …)` | `pip install --force-reinstall cotterpin-pack-<id>==<version>` |
| `the <id> pack <version> needs Cotterpin pack API <a>–<b>` | `pip install --upgrade cotterpin cotterpin-pack-<id>` |
| `the <id> pack is installed twice (<path> and <path>)` | `pip uninstall cotterpin-pack-<id>`, then install it once |
| `the approved wheel for … is not on this machine` | pass it with `--wheel <file>`, or `cotterpin library store-artefact --wheel <file>` |
| `the wheel <file> you passed is not the one this repository's lock approves` | use the approved wheel, or `cotterpin library build-artefacts …` from the release |
| `file bytes differ from the approved lock: <path>` | the copy you have was changed; fetch or rebuild the approved wheel |
| `this repository's lock (schema 1/2/3) was written by an earlier Cotterpin` | regenerate the lock once (below) |

### Regenerating a lock written by an earlier Cotterpin

```sh
cotterpin library propose --source-repo <Cotterpin checkout> --release <release> --source-commit <commit> \
    --release-descriptor cotterpin/release/manifests/release-descriptor-v1.json --manifest-paths <paths.json> \
    --compatibility <compatibility.json> --overlay <overlay.json> --lock .cotterpin.lock.json --output proposal.json
cotterpin library apply --proposal proposal.json --lock .cotterpin.lock.json
```

The old lock is replaced, never read: nothing in it is used.

## Repository packs (your team's own rules)

A repository pack is a folder in your own repository, `.cotterpin/packs/<id>/`, for rules that belong to your team
rather than to a language: house gates, agent guards and their refusal explanations. You write it and review it in
your own pull requests; it is shared through your git like any other file. Cotterpin never uploads, stores or
downloads it.

* `pack.json` — exactly `{"id", "version", "kernelApi": {"minimum", "maximum"}}`, like a language pack's. The id is
  lower-case letters and digits, starting with a letter, and may not be an installed pack's id or `kernel`, `new`,
  `list` or `verify`.
* It may provide only `gates/` (or `gates.py`), `hooks.py` and `refusals.py`. A hook rule's id starts with
  `<id>-`.
* `cotterpin init` and `cotterpin update` pin every file of every repository pack in `.cotterpin.lock.json`
  (`repositoryPacks`). Commit the lock with the pack.
* Before any command serves a repository pack, every file is checked against its pin, and the pack's code runs from
  exactly the bytes that were checked. A pack that differs is not served, and says what differs and how to re-pin.
* The first time a command serves a pack in your checkout (and again when its pinned files change), Cotterpin says
  so once, on standard error: which pack, that each file was checked against the lock, and that nothing was
  downloaded.

| command | what it does |
|---|---|
| `cotterpin pack list [--repository <path>] [--json]` | the installed language packs, and each repository pack with its state against the lock: `pinned`, `edited`, `not pinned` or `missing` |
| `cotterpin pack verify [--repository <path>] [--json]` | the check every command runs before serving a repository pack: exit 0 when every pack matches, 1 naming what differs (`cotterpin explain <code>`), 2 when it cannot check |
| `cotterpin pack new <id> [--repository <path>]` | starts an empty pack (`pack.json`, `gates/`, `hooks.py`, `refusals.py`, each a working empty stub); pin it with `cotterpin update` once you have reviewed it. Needs a current licence (Trial, Pro or Team): without one it is refused, and every pack you already have keeps working |

Coming in a future release: team signatures on packs, and organisation-wide packs from your own package registry.

## Developer mode from a source checkout

Install the distributions editable, from the repository root:

```sh
pip install -e . -e packaging/cotterpin-pack-java -e packaging/cotterpin-pack-angular -e packaging/cotterpin-pack-terraform \
    -e packaging/cotterpin-pack-python
```

Each pack's source stays at `cotterpin_pack_<id>/` (its repository path is its installed path); the recipe in
`packaging/cotterpin-pack-<id>/pyproject.toml` only builds it. Running straight from a checkout without installing
also works: the packs sit beside `cotterpin/` in the same directory. The packs shipped today are `java`
([JAVA-WORK-ROUTES.md](JAVA-WORK-ROUTES.md)), `angular` ([PACK-ANGULAR.md](PACK-ANGULAR.md)), `terraform`
([PACK-TERRAFORM.md](PACK-TERRAFORM.md)) and `python` (uv-first work routes, Python defect gates, toolchain guards —
[PACK-PYTHON.md](PACK-PYTHON.md)).

## Releasing a pack

1. Change the pack; keep `pack-release-descriptor.json` listing every file of the pack (a conformance test fails
   otherwise) and bump `version` in both `pack.json` and `packaging/cotterpin-pack-<id>/pyproject.toml` (a test keeps
   them equal).
2. A repository adopts it by proposing and applying a new lock; the lock records the pack's files and its wheel sha256.
3. Publish the wheels `cotterpin library build-artefacts` produces: those are the bytes the lock approves.
