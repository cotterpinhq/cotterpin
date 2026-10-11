# Java generators: create what your repository is missing

Five manifests in the Java pack create code your repository does not have yet. Each one plans from the pack's Facts
store (it never re-reads your code to discover what another manifest already found), splits the work into small
units, writes and reviews the units in parallel, and proves them with ONE build before anything is committed.

| Manifest | What it creates | One unit is | How it is proved |
|---|---|---|---|
| `JAVA-CREATE-UNIT-TESTS` | a real unit test, with no mocks, for a class that has logic and no collaborators, and no test yet | one class | the new test classes run, each with at least one test and no failure |
| `JAVA-CREATE-INTEGRATION-TESTS` | a Spring integration test for a repository or controller that no Spring test covers | one class | the new test classes run against the real Spring context |
| `JAVA-CREATE-DAOS` | the repository for an entity that has none, in your project's own style (Spring Data interface, DAO class, or DAO interface plus implementation) | one entity | the affected modules compile |
| `JAVA-CREATE-DTOS` | request and response DTOs plus mappers for endpoints that accept or return entities, and the controller methods changed to use them | the entities that share controllers | the affected modules compile |
| `JAVA-CREATE-API-ENDPOINTS` | a REST controller for a service capability **you name**, with validated request DTOs and DTO responses | one declared capability | the affected modules compile |

## Quick start

```text
cotterpin pack java generate-plan  --generator unit-tests            # shows what would be created; creates nothing
cotterpin pack java generate-start --generator unit-tests            # plans, creates the run checkout, starts the run
cotterpin pack java generate-drive  --tree <tree> --run-id <run id>  # long-running: run it in the background
cotterpin pack java generate-status --tree <tree> --run-id <run id>
```

Useful options: `--units N` (at most N units in this run, default 8, at most 32), `--unit <class>` (only this one,
repeatable), `--facts facts.json` (plan from a saved `cotterpin pack java facts-query` answer instead of the Facts
store), `--base <ref>` (plan and branch from this commit).

Endpoint creation never guesses what to expose. Name the service and its methods:

```text
cotterpin pack java generate-start --generator api-endpoints --capability OrderService#placeOrder,cancelOrder
```

## How names and places are chosen

Every choice is the majority of what your repository already does, and the plan records why
(`generate-plan --full` shows it): test class suffix (`Test`/`Tests`), integration test suffix and the Spring test
base class your module already uses, Testcontainers when the module depends on it, repository style, suffix, base type
and package, DTO suffixes (`Response`, `Request`, `Dto`, ...), DTO package and whether DTOs are records, MapStruct or
plain mappers, controller package and base-path prefix. Where your project has no example yet, a stated default is
used (`Test`, `IntegrationTest`, Spring Data `JpaRepository`, `Dto`/`Request`, a `dto` package beside the
controllers).

## What runs, in order

1. **Identity check** — the run confirms it is in the checkout, branch and commit it was given.
2. **Write** — one writer per unit, several at once (see "How many at once"). Each writer writes only its unit's
   files, into the run's scratch directory, and runs `cotterpin pack java generate-check` until it is clean. A unit
   that is still not clean gets exactly one more attempt with the problems listed.
3. **Review** — one independent reviewer per unit, never the writer, accepts or rejects it.
4. **Verify** — one command, `cotterpin pack java generate-lane`, does the rest: it confirms every unit was accepted,
   checks every file again, puts the files in place (a file it creates must not already exist; a file it changes must
   be exactly as it was when the plan was made), runs one build through the pack's Maven command
   (`test-compile`, or `test` of exactly the new test classes; build cache off; only the affected modules and what they
   need), and judges each unit by its own result. If anything fails, it puts every file back as it was.
5. **Commit** — the kernel commits exactly the planned files with the trailer `GENERATE-RECEIPT: <receipt id>`.

## Checks a written unit must pass (`generate-check`)

| Rule | Applies to | Refuses |
|---|---|---|
| `GEN-MISSING` / `GEN-EXTRA` | every unit | a planned file not written, or a file the plan does not name |
| `GEN-PACKAGE` / `GEN-TYPE` / `GEN-BRACES` | every file | a package or class name that does not match its planned place; unbalanced braces |
| `GEN-NO-TEST` / `GEN-NO-ASSERT` | tests | no test method, or a test that asserts nothing |
| `GEN-MOCK` | tests | any Mockito or Spring mocking (`@Mock`, `@MockBean`, `mock(`, `when(`, `verify(` ...) |
| `GEN-SUBJECT-UNUSED` / `GEN-FAKE-SUBJECT` | tests | a test that never uses the class under test, or subclasses it |
| `GEN-SPRING-UNIT` / `GEN-NO-CONTEXT` | unit / integration tests | a Spring context in a unit test; none in an integration test |
| `GEN-DAO-SHAPE` | repositories | a shape other than your project's repository style |
| `GEN-DTO-PURITY` / `GEN-FORBIDDEN-IMPORT` | DTOs, controllers | an entity or persistence annotation in a DTO; an entity or repository imported where it must not be |
| `GEN-MAPPER` | mappers | a mapper that does not map its entity and DTOs |
| `GEN-ENTITY-EXPOSED` / `GEN-ENDPOINT-LOST` | controllers | an endpoint that still accepts or returns an entity, or an endpoint that disappeared |
| `GEN-CONTROLLER` / `GEN-UNVALIDATED-BODY` / `GEN-NO-CONSTRAINTS` | new endpoints | a missing handler or mapping, a request body without `@Valid`, a request DTO without constraints |

## Order between manifests

Repository and DTO creation run after Lombok removal (`JAVA-LOMBOK-REMOVAL`); endpoint creation runs after DTO
creation. When you start a run by hand, the planner enforces the first rule itself: if a class it reads or writes
beside still uses Lombok, it stops and names the classes:

```text
REFUSED: JAVA-CREATE-DAOS runs after Lombok removal, and 1 class(es) it reads or writes beside still use Lombok
(shop.order.Customer). ... Run the JAVA-LOMBOK-REMOVAL manifest first, then plan again.
```

An endpoint whose method returns an entity that has no DTO yet stops the same way, with the command to create it.

## What Cotterpin asks you first

- **Where the run checkout goes.** Cotterpin asks before it creates a checkout outside your repository (in the temp
  directory). If you decline, or the shell is not interactive, the checkout is created inside your repository at
  `.cotterpin/runs/<run id>` and hidden from `git status` through your repository's own `.git/info/exclude`; nothing
  is written outside your repository. `--tree-root <dir>` is your own choice and is used as given.
- **How many at once.** Writers and reviewers run as many at a time as the Box Budget allows for model calls. Without
  your consent to measure this machine (and without a width you declared in `.cotterpin/box.yaml`), they run one at a
  time.
- **Scratch files.** If `.m2-local/` is not already ignored, Cotterpin adds `/.m2-local/` to your repository's
  `.git/info/exclude` and says so; the run's scratch files never show in `git status`.

## When it refuses

| You see | Why | Do |
|---|---|---|
| `this Cotterpin install has no Java Facts store` | planning needs facts | `cotterpin pack java facts-query --kind ... > facts.json`, then add `--facts facts.json` |
| `has nothing to create for [...]` | that class is covered already, or is not something this manifest creates | `cotterpin pack java generate-plan --generator <g> --units 32` to see the candidates |
| `the base commit has no approved library lock` | Cotterpin is not installed in this repository yet | install Cotterpin and commit its files; nothing was created |
| `creates endpoints only for a capability you declare` | endpoints are never inferred | add `--capability <Service>#<method>,...` |
| `provider 'codex'` | only the Claude provider gives every unit an independent reviewer today | use `--provider claude` |
| `the stored plan ... was changed after it was written` | a plan is bound to its digest | start again with `generate-start` |
