# Running Cotterpin with no code of your own, and adding to it safely

Cotterpin 0.3.0 ships everything a repository used to supply as code: the task-manifest validator, the run-scratch
cleanup, the task-profile registry, the audit predicates and the lane plan. A repository now needs only data. When it
wants something the product does not ship (its own task kind, manifest, route, gate, hook, skill or agent), it
declares it in one file, and Cotterpin runs it only at the bytes its approved lock pins (ADR-004).

## 1. A repository with no adapter module

Commit three things:

| File | What it holds |
|---|---|
| `.cotterpin/policy.yaml` | your settings; optionally `layout:` (below) |
| `.cotterpin.lock.json` | the release you approved (written by the release-approval step, never by hand) |
| your data | task manifests, routing and contracts, workflows and runbooks, wherever `layout` says they live |

Then run any task command without `--module-declaration`:

```
cotterpin legacy --worktree . --library-lock .cotterpin.lock.json -- start --worktree . ...
```

Cotterpin checks the lock against your checkout first, exactly as before, and then uses its own parts:

| Part | What it does |
|---|---|
| manifest validator (`cotterpin/kernel/manifest_validation.py`) | every manifest is registered in your routing and contracts files, every workflow and runbook it routes to exists, ids and tasks are unique across the folder, a deleted manifest is no longer referenced, and the manifest has the shape the kernel runs (driver, concurrency, heartbeat, iteration, success). Anything one task kind requires beyond that is that kind's own check. |
| run-scratch cleanup (`cotterpin/kernel/never_land.py`) | between steps, deletes untracked files under `neverLandPaths` and restores tracked ones from your commit; refuses, naming the files, if anything else changed, if the branch or commit moved, or if another run still holds this checkout |
| task profiles (`cotterpin/kernel/profile_registry.py`) | a product kind `<kind>` is the module `cotterpin.profiles.<kind with - as _>`; your own kinds come from your extensions (section 3) |
| audit predicates | a capability row is green when its `verdict` is `DELIVERED` and its `conformance` is not `DIVERGENT`; an open finding must appear in your register as `` `<id>` `` |
| lane plan (`cotterpin/kernel/lane_planner.py`) | each step records which runs hold work in the repository and whether their claims overlap. It is information only: it never blocks a step and never measures your machine. |

If your lock pins a `.cotterpin/workflow.json` adapter declaration, keep passing
`--module-declaration .cotterpin/workflow.json`; Cotterpin tells you so if you forget. An existing adapter can also
drop any field it no longer needs: a `RepositoryServices` field left as `None` gets the product part.

## 2. Where your files live: `layout`

The standard layout needs no settings. To keep files elsewhere, name only what differs, in `.cotterpin/policy.yaml`:

```yaml
layout:
  manifestDir: ops/manifests
  routing: ops/routing.json
  contracts: ops/contracts.json
  workflowDir: ops/workflows
  runbookDir: ops/runbooks
  neverLandPaths: [scratch, state/watermark.json]
```

Every field of the layout is accepted in camelCase; an unknown field or a path outside the repository is refused with
its name. On a machine set up in hardened mode, the administrator puts the same mapping in the repository's row of
the root registry as `consumerLayout`, so tasks dispatched by the root supervisor find your workflows and runbooks too.

## 3. Adding to Cotterpin: `.cotterpin/extensions.json`

```json
{
  "kind": "cotterpin-consumer-extensions",
  "schemaVersion": 1,
  "namespace": "acme",
  "profiles": [{"kind": "lint-frontier", "class": "acme_ext.profiles:LintFrontier",
                "sourcePaths": ["acme_ext/__init__.py", "acme_ext/profiles.py"]}],
  "manifests": [{"id": "ACME-LINT", "sourcePaths": ["ops/manifests/ACME-LINT.json"]}],
  "routes": [{"task": "acme_lint", "sourcePaths": ["ops/workflows/lint.js", "ops/runbooks/lint.md"]}],
  "gates": [{"id": "no-print", "check": "acme_ext.gates:no_print", "sourcePaths": ["acme_ext/gates.py"]}],
  "hooks": [{"hook": "pre-commit", "name": "format", "step": "acme_ext.hooks:format",
             "sourcePaths": ["acme_ext/hooks.py"]}],
  "skills": [{"name": "lint", "sourcePaths": ["skills/lint/SKILL.md"]}],
  "agents": [{"name": "linter", "sourcePaths": ["ops/agents/linter.md"]}]
}
```

Every section is optional. The rules:

- **Your additions are known by your namespace.** Cotterpin finds a profile, route, gate, hook, skill or agent as
  `<namespace>:<name>` (a manifest declares `"profile": {"kind": "acme:lint-frontier"}`); a manifest id starts with
  your namespace in capitals (`ACME-`) and its `pack` is your namespace.
- **You add; you never replace.** A namespace that is a product owner (`kernel`, `cotterpin`, an installed pack), or a
  name the product already ships (a profile kind, task manifest, route, agent, gate, skill or agent-hook rule), is
  refused. The product's names come from its real registries: profile kinds from the profile registry, gate ids from
  the gate registry (compared without case), skills and agents from where the kernel library and each pack ship them,
  hook names from the `cotterpin hook` rule table. This follows the recommendation in ADR-004 question 3.
- **Hook steps attach only to git's step hooks** (`pre-commit`, `commit-msg`, `pre-push`, ...). Cotterpin's own step
  for that git hook (installed by `cotterpin hooks install`) runs each declared step, in order, at its approved bytes;
  the first that fails stops git with its exit code.
- **Only approved bytes run.** When your release is approved, the declaration and every file in every `sourcePaths`
  are pinned in the lock (`consumerExtensions`). Before any of them is read or imported, every pinned byte is checked
  again. An edited file, a declaration the lock does not include, or a file the declaration uses but the lock does not
  pin stops the run. Approve a new lock to change them.
- **Code is imported only from your checkout.** A `module:attribute` must name a module whose file, and every package
  `__init__.py` above it, is in that entry's `sourcePaths`. A product module (`cotterpin…`) cannot be named.

Check your additions at any time:

```
cotterpin extensions check     # valid, adds without replacing, and at the approved bytes
cotterpin extensions list      # every addition by the name Cotterpin finds it under
```

A profile class is an ordinary `cotterpin.profiles.base.HarnessProfile` subclass whose `kind` is the full
`<namespace>:<kind>` name.

## 4. What each refusal means

| Code | What happened |
|---|---|
| `extension-invalid` | the declaration, or a file it names, is not in the form Cotterpin reads |
| `extension-clash` | an addition reuses a product name |
| `extension-edited` | a file an addition uses changed after the lock approved it |
| `extension-unpinned` | the declaration or one of its files is not in the approved lock |
| `extension-undeclared` | a task asked for an addition the declaration does not have |

`cotterpin explain <code>` prints the fix and the exact next command for each.

## 5. What is not finished

- Extension routes, gates and skills are declared, validated, pinned and resolvable (`ExtensionSet.resolve` /
  `ExtensionSet.attribute`), but the route registry, the gate runtime and the skill generator do not run them yet;
  extension profiles, manifests, agents and git-hook steps are used today.
