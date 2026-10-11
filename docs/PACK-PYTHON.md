# The Python pack (`cotterpin-pack-python`)

Release 0.3.0-rc1. The Python language pack is its own distribution (PACK-1): `cotterpin_pack_python/`, built by
`packaging/cotterpin-pack-python/pyproject.toml`, found through the `cotterpin.packs` entry point
(`python = cotterpin_pack_python`) and served only once the repository's lock approves it
([LOCK-AND-PACKS.md](LOCK-AND-PACKS.md)). It works uv-first: every route locks, installs, tests and builds through uv,
and every proof runs the project's own tools in the project's own locked environment — never in Cotterpin's.

```sh
pip install cotterpin cotterpin-pack-python             # or, from a checkout:
pip install -e . -e packaging/cotterpin-pack-python
cotterpin doctor                                        # asks before probing python3 and uv
```

## What it ships

| concern | file | what it does |
|---|---|---|
| work routes | `routes/*.json`, `manifests/PYTHON-*.json`, `workflows/python-task.js`, `runbooks/*.md` | the ten routes below, one shared workflow |
| deterministic tools | `tasks/` (`cotterpin pack python task-plan / task-apply / task-check / task-verify / task-revert`) | plan a unit, make the mechanical change, check residue, prove with the real toolchain, revert |
| the uv door | `cotterpin pack python uv -- <uv arguments>` | uv as the routes run it: no interpreter download, the index only with consent, caches outside the checkout |
| gates | `gates/` (19 gates, red and green fixtures each) | Python's classic defects; `cotterpin gate run` runs them |
| hook guards | `hooks.py` (5 rules) | the toolchain's destructive and misleading commands |
| skills and agents | `skills/python-*/SKILL.md` (10), `agents/python-task-*.md` (3) | when to use each route, its steps and traps; the route personas |
| refusals | `refusals.py` | every code the pack raises, in plain words (`cotterpin explain <code>`) |
| onboarding | `onboarding.py` | `cotterpin init` markers (`pyproject.toml`, `uv.lock`, `requirements.txt`, ...) and `cotterpin doctor` probes (python3 ≥ 3.10, uv ≥ 0.5) |
| campaign | `campaign.py` | each manifest's unit for `cotterpin campaign plan` (`<prefix>-root`, the repository's root project) |
| lifecycle hook | `hooks.py` `worktree-prepared` | a uv project's locked environment installed from uv's cache (`--frozen --offline`) before a run |

It ships no `bridge.py`, `supervisor.py` or `profiles.py` and no Facts store: those serve the Java pack's root-owned
build service and its Facts-planned units. Python routes run as the developer through uv, land through the kernel's
generic manifest-frontier profile, and plan from the repository itself (`task-plan`).

## The ten routes

Every route runs ONE unit per run: **Preflight** (the exact worktree, branch and head, and the kernel's child marker),
**Apply** (one relayed pack tool), **Judgement** (one writer shard per file, each reviewed by a different agent),
**Verify** (one deterministic lane, one targeted repair round), **Closure** (a pass that will not land is reverted).
Plan a unit with `cotterpin pack python task-plan --manifest <ID> --next`.

| route / manifest / skill | deterministic (apply) | judgement (writer shards) | proof (verify) | gates the proof runs | guards that matter | real end-to-end test |
|---|---|---|---|---|---|---|
| `python_version_upgrade` / `PYTHON-VERSION-UPGRADE` / `python-version-upgrade` | requires-python, `.python-version`, ruff/mypy targets, classifiers, `uv lock` for the new range, unittest alias renames | removed stdlib modules and attributes (distutils, imp, PEP 594, `ast.Num`) | interpreter installed (never downloaded), lock current, sync with the target, environment really runs it, tests | PY-REQUIRES-PYTHON-1 | python-system-pip | `VersionUpgrade` (3.13 → 3.14; and the failure path that reverts) |
| `python_uv_migration` / `PYTHON-UV-MIGRATION` / `python-uv-migration` | `[project]` (`uv init --bare`), `uv add -r` per file (`--group` for dev files), lock, pin, carried files deleted | lines uv cannot add (editable paths, indexes, VCS without a name), setup.py metadata | every original requirement declared with its specifier, no carried file left, lock, sync, tests | PY-REQUIRES-PYTHON-1 | python-requirements-overwrite | `UvMigration` |
| `python_add_mypy` / `PYTHON-ADD-MYPY` / `python-add-mypy` | mypy in the dev group, `[tool.mypy]`, `py.typed`, one mypy run | each file's mypy errors | no bare ignore, no `ignore_errors`, mypy exits 0, tests | PY-TYPE-IGNORE-BARE-1 | python-system-pip | `AddMypy` |
| `python_framework_upgrade` / `PYTHON-FRAMEWORK-UPGRADE` / `python-framework-upgrade` | `uv add '<framework>>=<version>'`, Django gettext/force_str/re_path renames, FastAPI `regex=` → `pattern=` | FastAPI `on_event` → lifespan, Django removals | locked version meets the target, no catalogued API left, lock, sync, tests | PY-FASTAPI-DUPLICATE-ROUTE-1 | python-blanket-upgrade | `FrameworkUpgrade` (FastAPI 0.110 → 0.115+) |
| `python_fastapi_endpoint` / `PYTHON-FASTAPI-ENDPOINT` / `python-fastapi-endpoint` | route proven free, httpx/pytest in the dev group, handler and test module laid out unfinished | the handler; the tests (success and a refusal) | registered exactly once on the running app, ≥ 2 new tests pass, every test asserts, whole suite | PY-FASTAPI-DUPLICATE-ROUTE-1, PY-TEST-NO-ASSERT-1 | python-system-pip | `FastapiEndpoint` |
| `python_pydantic_v2` / `PYTHON-PYDANTIC-V2` / `python-pydantic-v2` | `uv add 'pydantic>=2,<3'` (+ pydantic-settings when needed), class-method renames, Field keywords, mappable `class Config` → `ConfigDict` | validators, root validators, BaseSettings, unmapped config | Pydantic 2 locked, no v1 API in the project, lock, sync, tests | PY-PYDANTIC-V1-1 | python-blanket-upgrade | `PydanticV2` (1.10 → 2.x) |
| `python_vuln_fix` / `PYTHON-VULN-FIX` / `python-vuln-fix` | OSV query for the lock, lowest release clearing every advisory, one package at a time | code using a package that crossed a major version; no-fix advisories are operator decisions | the same source reports nothing fixable left, lock, sync, tests | — | python-blanket-upgrade | `VulnFix` (jinja2 3.1.3 → its lowest fully fixed release, live OSV) |
| `python_alembic_migration` / `PYTHON-ALEMBIC-MIGRATION` / `python-alembic-migration` | non-local URL refused, scratch SQLite at head, `alembic revision --autogenerate --rev-id <planned>` | review the operations (renames, defaults, data), remove the markers | one head, upgrade/downgrade/upgrade on a fresh scratch database, `alembic check`, tests | PY-ALEMBIC-HEADS-1 | python-alembic-remote-db | `AlembicMigration` |
| `python_raise_coverage` / `PYTHON-RAISE-COVERAGE` / `python-raise-coverage` | coverage in the dev group, branch coverage measured, uncovered lines and branches by function | the tests | no new exclusion, every test asserts, module ≥ threshold, whole suite | PY-TEST-NO-ASSERT-1 | — | `RaiseCoverage` (to 95 %) |
| `python_wheel_release` / `PYTHON-WHEEL-RELEASE` / `python-wheel-release` | version validated and written (pyproject, `__version__`), lock, changelog section opened | the changelog entry from the commits | `uv build` outside the checkout, METADATA and every RECORD hash, fresh install reports the version and imports, tests | — | python-publish | `WheelRelease` |

The real tests are `tests/packs/python/test_python_routes_real.py` (real uv, node, git, package index and OSV;
deferred tier). The workflow's control flow for all ten routes is `tests/packs/python/test_python_task_route.py`.

## Consent

| id | asked by | what is read or sent | on decline |
|---|---|---|---|
| `network.pypi` | every route step that runs uv | package metadata and wheels from your configured index, through uv | uv runs offline from its cache; a missing package is named |
| `network.osv` | `python_vuln_fix` | the name and version of every locked package, sent to api.osv.dev | the route refuses; pass `--advisories <OSV JSON file>` instead |
| `toolchain.python.interpreter`, `toolchain.python.uv` | `cotterpin doctor` | `python3 --version`, `uv --version` | the probe is skipped |

Allow one command with `cotterpin --consent network.pypi <command>`; an answer at a terminal is remembered.
No route ever downloads an interpreter (`UV_PYTHON_DOWNLOADS=never`): an upgrade to one this machine lacks is refused
with `uv python install <version>`, which stays the developer's step.

## No prompts

Nothing this pack starts raises an operating-system dialog: no Keychain ("wants to use your confidential
information"), password, Touch ID, admin or permission prompt. The pack starts no browser. Every child process (uv,
the project's pytest, mypy, coverage and Alembic through `uv run`, and git) gets one environment,
`cotterpin_pack_python.tasks.toolchain.NO_PROMPT`, with stdin closed:

| setting | effect |
|---|---|
| `UV_KEYRING_PROVIDER=disabled`, `PIP_KEYRING_PROVIDER=disabled`, `PIP_NO_INPUT=1` | uv and pip never ask a keyring (the macOS Keychain) for index credentials. The environment outranks a `uv.toml` or `pip.conf` that turns one on (measured: real `uv lock --show-settings` reads `Subprocess` without it, `Disabled` with it) |
| `PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring` | the project's own code and tests that use `keyring` get the null backend, not the Keychain |
| `GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE=never`, `credential.helper` cleared for the child (`GIT_CONFIG_COUNT`), `GIT_SSH_COMMAND=ssh -o BatchMode=yes` unless you set your own | git (also when uv fetches a git dependency) never consults `osxkeychain` or Git Credential Manager and never asks. A private git dependency fails with git's own message |

A private package index gets its token through `UV_INDEX_<NAME>_PASSWORD` (or the index URL), never a keyring.
The `python-no-prompt` hook guard refuses an agent command that would raise a dialog (below).
`tests/packs/python/test_python_no_prompt.py` enforces this. It statically scans every process launch in the pack and
its tests (each one must use the no-prompt environment and close stdin; no `keyring`/`webbrowser` import, no
`security` CLI, no browser binary), with red and green fixtures. `tests/packs/python/test_python_no_prompt_real.py`
(deferred tier) proves the uv and git overrides with the real tools, each against a plain-environment control.

## Gates

`cotterpin gate list` shows them; `cotterpin gate fixtures <ID>` proves each against its red and green fixtures. A gate
blocks a fresh install only with a zero-false-positive calibration record; the rest are advisory (repository settings
may promote or demote any gate with a reason).

| gate | enforcement | catches |
|---|---|---|
| PY-ASSERT-TUPLE-1 | blocking | `assert (cond, "msg")` — always true |
| PY-IS-LITERAL-1 | blocking | `x is "text"` / `x is 42` |
| PY-FINALLY-EXIT-1 | blocking | `return` / `break` / `continue` in `finally` swallowing the exception |
| PY-ASYNC-BLOCKING-SLEEP-1 | blocking | `time.sleep` in `async def` |
| PY-UNAWAITED-COROUTINE-1 | blocking | a coroutine called as a statement and never awaited |
| PY-YAML-UNSAFE-LOAD-1 | blocking | `yaml.load` with an unsafe or no Loader |
| PY-REQUESTS-NO-TIMEOUT-1 | blocking | `requests.*` without `timeout` |
| PY-DATETIME-UTCNOW-1 | blocking | `datetime.utcnow()` / `utcfromtimestamp()` |
| PY-DEFAULT-EVALUATED-ONCE-1 | blocking | a default that reads the clock or a random source |
| PY-FASTAPI-DUPLICATE-ROUTE-1 | blocking | the same method and path registered twice |
| PY-ALEMBIC-HEADS-1 | blocking | two heads, a dangling `down_revision`, a duplicate revision id |
| PY-REQUIRES-PYTHON-1 | blocking | `.python-version` outside `requires-python` |
| PY-PYDANTIC-V1-1 | blocking | Pydantic 1 API in a project on Pydantic 2 |
| PY-BARE-EXCEPT-1 | advisory | `except:` / `except BaseException:` that swallows interrupts |
| PY-MUTABLE-DEFAULT-1 | advisory | a list/dict/set default shared between calls |
| PY-SUBPROCESS-SHELL-1 | advisory | a shell command built from run-time values |
| PY-ABSOLUTE-JOIN-1 | advisory | a value from data joined onto a root folder (`root / entry["path"]`), which an absolute value replaces |
| PY-SQL-STRING-1 | advisory | SQL built from values instead of bound parameters |
| PY-TEST-NO-ASSERT-1 | advisory | a test function that asserts nothing |
| PY-TYPE-IGNORE-BARE-1 | advisory | `# type: ignore` with no error code |

### Calibration

Corpus: Cotterpin's own tree (963 Python files) and 5,541 files of 22 widely used packages with their dependencies
(requests, flask, django, fastapi, starlette, pydantic, sqlalchemy, alembic, httpx, rich, click, jinja2, pytest, attrs,
celery, boto3, pyyaml, aiohttp, black, mypy, werkzeug, pandas), 6,504 files in all; every hit of a blocking gate read by
hand.

| gate | hits | verdict |
|---|---|---|
| PY-IS-LITERAL-1 | 1 | true: `result is (NA, NA)` compares a new tuple by identity |
| PY-FINALLY-EXIT-1 | 1 | true: a `return` in a retry loop inside `finally` swallows the generator's error |
| PY-DATETIME-UTCNOW-1 | 3 | true: naive expiry times and a naive event timestamp |
| every other blocking gate | 0 | — (PY-ALEMBIC-HEADS-1, PY-REQUIRES-PYTHON-1 and PY-PYDANTIC-V1-1 have no relevant file in the corpus: proven on fixtures and on real projects in the route tests) |
| PY-BARE-EXCEPT-1 | 64 → 31 | first draft demoted: 33 false (captured or forwarded exceptions); the refined reading is accurate but some catch-alls are deliberate |
| PY-MUTABLE-DEFAULT-1 | 47 | accurate readings; some memo defaults are deliberate |
| PY-SQL-STRING-1 | 78 | mostly drivers interpolating quoted identifiers |
| PY-ABSOLUTE-JOIN-1 | 0 / 66 / 32 | measured 8 Oct 2026 on 430 installed library files, Cotterpin's own 2,138 and its source repository's 1,167: accurate readings (a path from a manifest, a record or an option), but whether one can be absolute is not visible to one file; a first draft's 184 Cotterpin hits fell to 66 once module constants, UPPER_CASE names and short fixed prefixes were read as constants |
| PY-TEST-NO-ASSERT-1 | 1,952 | tests that check through helpers or fixtures |
| PY-TYPE-IGNORE-BARE-1 | 557 | a policy, not a defect |

## Hook guards

| rule | stops | tier |
|---|---|---|
| `python-system-pip` | `pip install/uninstall` with `sudo`, `--break-system-packages` (destructive) or `--user`; `pip install` in a uv project | sensitive write / destructive |
| `python-publish` | `uv publish`, `twine upload`, `setup.py upload/register` (destructive); deprecated `setup.py sdist/bdist_wheel/install` | destructive / sensitive write |
| `python-alembic-remote-db` | `alembic upgrade/downgrade/stamp` against a database not on this machine (destructive); `downgrade base` | destructive / sensitive write |
| `python-blanket-upgrade` | `uv lock --upgrade`, `uv sync --upgrade`, `pip install -U -r`, `pip-compile --upgrade`, `poetry update` | sensitive write |
| `python-requirements-overwrite` | `pip freeze > requirements*.txt` | sensitive write |
| `python-no-prompt` | uv/uvx/pip with `--keyring-provider` (or `UV_/PIP_KEYRING_PROVIDER=`) other than `disabled`; `keyring get/set/del`; `python -m webbrowser`; pytest-playwright `--browser-channel chrome/msedge` | destructive |

`ZERO_TEST_PHRASES` adds pytest's "N deselected" summary (a `-k` that selected nothing) to the kernel's
`zero-tests-ran` advice. Each rule returns before parsing anything when the command cannot be its business: measured
below a millisecond at the median and the 95th percentile (`tests/packs/python/test_python_hooks.py`).

## Refusals

`python-task-refused` (a route step refused its request; the message says why) and one `hook-<rule>` code per guard.
`cotterpin explain <code>` prints each with its fix; the catalogue is [REFUSALS.md](REFUSALS.md).

## Tests

| file | tier | what it proves |
|---|---|---|
| `tests/packs/python/test_python_routes_real.py` | deferred (real_tool) | the ten routes end to end on real projects with the real toolchain |
| `tests/packs/python/test_python_task_route.py` | deferred (real_tool: real node) | the workflow's control flow, argument contract and tables, for all ten routes |
| `tests/packs/python/test_python_gates.py` | commit | every gate's fixtures, the readings behind each blocking gate, a real `cotterpin gate run` |
| `tests/packs/python/test_python_hooks.py` | commit | every guard red and green through the real hook entrypoint, and its cost |
| `tests/packs/python/test_python_tasks.py` | commit | the deterministic pieces on real files |
| `tests/packs/python/test_python_pack_contract.py` | commit | the pack as the registry serves it |
| `tests/packs/python/test_python_no_prompt.py` | commit | no launch in the pack or its tests can raise an OS dialog (static checker, red and green fixtures); the no-prompt environment contract |
| `tests/packs/python/test_python_no_prompt_real.py` | deferred (real_tool) | real uv ignores a customer `uv.toml` keyring under the pack's environment (control: plain environment reads it); real git never runs a configured credential helper (control: it does); `keyring` resolves to its null backend |
