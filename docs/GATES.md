# Cotterpin gates

Gates are small static checks that fail on code which compiles, passes its tests, and still breaks in production. They
need no build and no database: they read your source files. This page is the user guide and the authoring guide for
the gate runtime (PACK-5). The catalogue and readiness bar are in GATE-PACK-V1.md.

## Quick start

```
cotterpin gate list                  # every gate, whether it blocks, and why
cotterpin gate run                   # check the repository on disk
cotterpin gate run TOMAP-1 --json    # one gate, machine-readable
cotterpin gate run --staged --changed --tier commit   # what the commit route runs
```

Exit codes: **0** passed (advisory findings never fail a run), **1** at least one blocking finding, **2** refused before
running (unknown gate, malformed `.cotterpin/gates.yaml`, nothing to check) — the message says what to fix.

## What blocks and what only reports

Each gate ships with a default:

- **blocking** — the gate has a zero-false-positive record on the calibration code. A finding fails the run.
- **advisory** — the gate is useful but can be wrong in ways a text scan cannot see. Findings are printed and counted;
  they never fail a run.

This is the posture from the first install: the zero-false-positive set blocks, everything else is advisory until you
promote it.

A blocking finding blocks while this machine holds a current Trial, Pro or Team licence. In **Watch** (no licence, or
a lapsed one) the run reports it, says "passed in Watch", exits 0, and the agent session's summary lists it — see
[Licensing and billing: Enforce or Watch](LICENSING-AND-BILLING.md#enforce-or-watch-on-this-machine).

### Promote or demote a gate for your repository

`.cotterpin/gates.yaml`:

```yaml
gates:
  CMP-NULL-1:
    enforcement: blocking
    reason: our comparators never see nulls from the database layer; we want this enforced
  TOMAP-1:
    enforcement: advisory
    reason: the reporting module is being rewritten this quarter
exclude:
  - "generated/*"          # patterns match the whole path; * also matches /
packs:
  java:
    mainRoots: [app/src]   # where shipped sources live, if not src/main/java
    testRoots: [app/checks]
    externalBoundaries:    # types MOCK-BEAN-1 treats as external systems (added to its defaults)
      - PaymentGateway
      - "com.example.sms.*"
    seedLocations: [src/test/resources/db]   # only if seed discovery is wrong (see "Wave 7")
    migrationLocations:    # only if discovery cannot find your migrations (see "Wave 4")
      - database/orders                  # one database's migrations
      - [database/billing, shared/sql]   # one database applying two directories together
```

A reason is required for every override, and every run prints each one (`TOMAP-1 demoted to advisory by
.cotterpin/gates.yaml — <reason>`), so a change of enforcement is never silent. Excluded files are counted in every
report. There is no "off": the weakest setting is advisory.

### Allow one finding

When a finding is intentional, say so on that line or the line above, in a comment:

```java
// cotterpin:allow TOMAP-1 ids come from the primary key column, so they are unique
Map<Long, Order> byId = orders.stream().collect(Collectors.toMap(Order::getId, o -> o));
```

The reason is mandatory. A marker without one allows nothing, and the finding says so. Allowed findings are counted in
every report and listed with their reasons by `cotterpin gate run --json` (`allowed`).

## Commands

`cotterpin gate list [--repository DIR] [--json]` — every installed gate: id, effective enforcement, tier, title, and
any override from `.cotterpin/gates.yaml`.

`cotterpin gate run [ID ...] [options]`

| option | meaning |
|---|---|
| `--repository DIR` | the repository to check (default: the current directory) |
| `--tier commit\|deferred` | only gates of that tier |
| `--staged` | check the copies staged for commit (the index), not the files on disk |
| `--changed` | only files added or modified since the last commit (with `--staged`: in this commit) |
| `--path FILE` | only this repository-relative file (repeatable); a whole-tree gate still reads the rest as context |
| `--json` | the full report (below) |
| `--count` | print only `TOTAL: <n>` |
| `--cache` / `--no-cache` | reuse and save results for this run / scan everything again (see *Result cache*) |

`cotterpin gate fixtures [ID ...] [--json]` — proves each gate still tells its red fixtures from its green ones.

Every gate module also runs on its own, with the scanner contract exactly:
`python -m cotterpin_pack_java.gates.tomap_1 [--root DIR] [--count|--json]` (`--count` exits 1 when the total is above
zero, whatever the gate's enforcement).

### The JSON report

```json
{
  "kind": "cotterpin-gate-report", "schemaVersion": 1, "ok": false,
  "total": 1, "blocking": 1, "advisory": 0,
  "findings": [{"file": "svc/src/main/java/a/F.java", "line": 12, "rule": "TOMAP-1",
                "message": "toMap with two arguments (key Order::getId) throws on a duplicate key",
                "remedy": "add a merge function as the third argument, ...", "enforcement": "blocking"}],
  "allowed": [{"file": "...", "line": 40, "rule": "TOMAP-1", "reason": "ids are unique", "...": "..."}],
  "gates": [{"id": "TOMAP-1", "pack": "java", "enforcement": "blocking", "defaultEnforcement": "blocking",
             "tier": "commit", "findings": 1}],
  "overrides": [], "files": 812, "excluded": [], "cache": {"enabled": true, "hits": 6, "misses": 0}
}
```

## How a run works

1. **One walk.** The repository is listed once for every gate. Under version control the list comes from the index
   (tracked files carry their blob id for free) plus modified and untracked-but-not-ignored files, which are hashed from
   disk; ignored files are never read. Outside version control the directory is walked, skipping hidden directories and
   build output (`target`, `build`, `out`, ...).
2. **Scope.** Each gate reads only its scope. The Java pack's scopes are `main` (shipped code), `test` and `all`,
   decided by the conventional `src/<set>/java/` layout (a set whose name contains `test` is test code) or by your
   configured `mainRoots`/`testRoots`. The wave-1 gates read `main` only; the wave-2 gates read `test` only;
   REFLECT-FIELD-1 reads `all` (the calls are in tests, the fields in shipped code). The wave-4 gates read
   `migrations`: SQL files plus the configuration files that say where the migrations are (see *Wave 4*).
3. **File by file.** Every gate that reads a file runs on it before the next file is opened, so each file is read and
   prepared (comments and string literals blanked) once.
4. **Markers and enforcement** are applied, and the report is printed.

### Result cache

Results are content-addressed in the Cotterpin cache (`~/.cache/cotterpin/<pack>/gates`, or `$COTTERPIN_CACHE_DIR`):
per-file results keyed by the scanner's digest and the files' blob ids (stored in 256 buckets by blob-id prefix, so
editing one file rescans only its bucket; one entry per pack and bucket holds every gate's results under its digest, so
a commit touching N files writes about N entries however many gates read them), and each gate's whole result keyed by the scanner's digest and every in-scope
path and blob id, so an unchanged repository costs one read per gate. The scanner digest covers the gate's module and
the pack's shared helpers, so an improved gate never reads an older gate's results. A corrupt or unreadable entry is a
miss, never a clean result; a cache that cannot be written only makes the next run slower.

**The cache is written outside your repository, so it is used only with your consent.** Without it, every run scans
every file again — same results, slower. To allow it: `cotterpin consent grant cache.gate-results` (or `--cache` for
one run). `--no-cache` always rescans.

Measured on a 13,467-file repository (2026-10-04, six wave-1 gates): 8 s with no cache, 10 s for the first run that
fills it, 1 s for an unchanged repository.

## For the commit route (F7)

```python
from cotterpin.kernel import gates
report = gates.run(repository, tier="commit", staged=True, changed=True)
if not report.ok:
    print(gates.render(report))   # what, why, and the exact next command
```

`changed=True` makes a commit answer only for the files it adds or modifies: existing findings elsewhere never block an
unrelated commit, and every finding in a touched file does.

`--changed` and `--path` narrow what is **reported**, never what a whole-tree gate may **read**. A whole-tree gate (one
that compares files: a new migration against the old ones, a query against an entity) still receives every in-scope
file of the repository — the staged copies under `--staged` — and keeps only its findings in the files the run checks.
Without that, a new migration that re-creates a table from an old, unchanged migration would pass every commit, and a
commit that touches a query would not be checked against the entities it did not touch. The reverse is a stated limit:
a commit that renames an entity field reports the queries it breaks only in the files it also touches; a full
`cotterpin gate run` (or the deferred verify) reports the rest.

## Wave 1 — the Java gates

| Gate | Catches | Default | Evidence |
|---|---|---|---|
| **TOMAP-1** | `Collectors.toMap` / `toUnmodifiableMap` / `toConcurrentMap` with two arguments — throws on the first duplicate key | blocking | 0 hits on the calibration repository; streams whose keys are unique by construction (a map's entry set keyed by `getKey`, enum values keyed by identity) are exempt |
| **CACHE-KEY-RUNTIME-1** | A clock or random value read inside a cache annotation's `key` / `keyGenerator` / `condition` / `unless` | blocking | 7 hits, all true |
| **RONLY-WRITE-1** | A persistence write inside `@Transactional(readOnly = true)` — silently not flushed | blocking | 1 hit, true (a multi-line method signature the line-window scanner it replaces missed) |
| **CMP-NULL-1** | A comparator or sort calling `compareTo` with no null handling | advisory | 50 hits; nullability is not visible to a text scan |
| **NULLSAFE-STRING-1** | A validator/parser (`isX`, `validateX`, `parseX`, `fromX`) calling a String method on its parameter before a null check | advisory | 2 hits; whether callers pass null is not visible |
| **CLOCK-ZONE-1** | `Clock.systemUTC()` feeding `LocalDate.now(clock)` and other zone-sensitive reads — "today" is yesterday after local midnight | advisory | 0 hits; a UTC business day is sometimes intended |

All six are `commit` tier (well inside the fast budget) and read shipped sources only. Each gate's own module
docstring says exactly what it matches and what it deliberately does not. Calibration is so far **one** repository
(13,467 source files, every hit checked by hand); the corpus run of GATE-PACK-V1 §4 decides the final classification,
and a false positive found there demotes a gate to advisory.

All six are ported in **absolute mode**: no shrink-only baseline file. Existing findings are handled by `--changed`
(they block only when you touch the file), by an allow marker with a reason, or by demoting the gate with a reason.

## Wave 2 — the Java test gates

Tests that are green and prove nothing. These four read **test sources only** (`src/test/java`, any source set whose
name contains `test`, or your `testRoots`).

| Gate | Catches | Default | Evidence |
|---|---|---|---|
| **MOCK-SUT-1** | The class under test is itself a mock: an `@InjectMocks` field whose type is also `@Mock`ed (or created with `mock(T.class)`); a test named after a class (`FooServiceTest`, `FooServiceIT`, `TestFooService`) with an `@Mock` of that class; a test that calls a method of the object under test which it stubbed (`when(subject.m())` / `doReturn(..).when(subject).m()`) | blocking | 0 hits — see below |
| **PLACEHOLDER-TEST-1** | A test whose every assertion is true by construction: `assertNotNull(new Foo())`, `assertNotNull` of a Mockito-created field or of a variable assigned only from `new`, `assertTrue(true)`, `assertEquals(1, 1)`, `assertDoesNotThrow(() -> {})`, `assertThat(new Foo()).isNotNull()` | blocking | 291 hits, all true |
| **MOCK-BEAN-1** | The code under test replaced through a Spring test context: `@MockBean`/`@MockitoBean` of the class the test is named after; a type that is both a mock bean and `@Autowired` (the test exercises the mock); a `@WebMvcTest`/`@WebFluxTest` that scripts a mocked collaborator's answers; `mock(Foo.class)` in `FooTest` | advisory | 11 hits, each accurately read; see below |
| **VERIFY-ONLY-TEST-1** | A test whose only check is that a mock was called (`verify(..)`, `inOrder.verify(..)`, `then(mock).should()`), with no assertion of a returned value, state or exception | advisory | 1,691 hits, each accurately read; see below |

What each gate deliberately does NOT match is written in its module docstring. In short: ordinary `@InjectMocks` unit
tests with mocked collaborators, a partial mock (a spy with one method stubbed while the test calls another), a
`@SpyBean`, a mock bean in a full `@SpringBootTest`, negative proofs (`verify(x, never())`, `verifyNoInteractions`),
assertions in a same-class helper the test calls, MockMvc `andExpect`, reactive `StepVerifier`, JUnit 4
`@Test(expected = ...)`, an empty `contextLoads()` smoke test, and `assertNotNull` of a value the code under test
returned.

### Calibration (first corpus, 2026-10-04)

One repository: 13,467 source files, 3,200 of them tests, read-only (`cotterpin gate run --repository <corpus>
--no-cache --json MOCK-SUT-1 MOCK-BEAN-1 VERIFY-ONLY-TEST-1 PLACEHOLDER-TEST-1`). Every hit was checked: the small sets
by reading each one, the large sets by an independent re-scan of the raw method text plus a hand-read sample.

| Gate | Hits | True | False positives | Cause of the false positives / why advisory |
|---|---|---|---|---|
| MOCK-SUT-1 | 0 | 0 | 0 | — The first draft flagged every stubbed method of a spy (10 hits, in 2 files). All 10 were partial mocks: the test stubbed one method of the subject and exercised another, whose real code ran. That shape is not a test of a mock, so the rule was narrowed to a test calling the very method it stubbed. |
| PLACEHOLDER-TEST-1 | 291 | 291 | 0 | — (230 `assertNotNull` of a newly constructed object, 57 of a field or variable that cannot be null, 4 `assertTrue(true)`; each re-checked against its declaration) |
| MOCK-BEAN-1 | 11 | 11 read correctly | 11 counted as false | Every hit is a web slice test that scripts a mocked service. That is the framework's documented way to test the web layer, and those tests still prove mappings, status codes and validation, so a finding is not proof the test checks nothing. Advisory: it shows which controllers are never tested against their real collaborators. Mock beans a slice only needs in order to start (never scripted — most of the first draft's 78 hits) are not reported. |
| VERIFY-ONLY-TEST-1 | 1,691 | 1,691 read correctly | ~783 counted as false | An independent re-scan found no assertion, `expect…`, `fail` or BDD `then` in any flagged test (the only look-alikes are the argument matchers `contains(..)` and `argThat(..)`). But 783 are named as delegation checks (`shouldDelegateToService`, `invokesScopeCheck`, `forwards…`), where the call IS the behaviour of a pass-through method; the scan cannot tell those from a missing assertion. The first draft also missed MockMvc `andExpect(..)` (10 false positives, fixed before this record). |

The first corpus is one repository; the corpus run of GATE-PACK-V1 §4 decides the final classification, and a false
positive found there demotes a blocking gate.

### External boundaries (MOCK-BEAN-1)

A mock of an external system — an HTTP client, a mail sender, a message broker, a cloud SDK — is the legitimate use of a
mock and is never a MOCK-BEAN-1 finding. The defaults: `*Client`, `RestTemplate`, `RestOperations`,
`WebServiceTemplate`, `JavaMailSender`, `MailSender`, `KafkaTemplate`, `RabbitTemplate`, `AmqpTemplate`,
`JmsTemplate`, `StreamBridge`, `Clock`, `software.amazon.awssdk.*`, `com.amazonaws.*`, `com.google.cloud.*`,
`com.azure.*`. Add your own under `packs: java: externalBoundaries:` in `.cotterpin/gates.yaml` — they are added to the
defaults. A pattern without a dot matches the simple type name (`PaymentGateway`, `*Gateway`); a pattern with a dot
matches the fully qualified name, resolved through the test's imports (`com.example.sms.*`). A malformed list refuses
the run (exit 2) and says what to write. Changing the list rescans: it is part of the gate's cache key.

### Speed

On the first corpus (3,200 test files) the four gates take about 12 s together without the result cache (the slowest,
PLACEHOLDER-TEST-1, about 5 s); the commit route checks only the files a commit adds or modifies, and an unchanged
repository is one cache read per gate.

## Wave 3 — the Java gates

| Gate | Catches | Default | Evidence |
|---|---|---|---|
| **ENT-IDX-1** | An entity's `@Table` `@Index(columnList)` / `@UniqueConstraint(columnNames)` naming a column the entity does not have — usually the old name after a rename | blocking | 0 hits over 1,346 names in 325 tables; 287 of 287 stale names planted in that code were caught |
| **REFLECT-FIELD-1** | `ReflectionTestUtils.setField` / `getField` naming a field the target's type (with its superclasses) does not have | blocking | 0 hits over 934 judged calls; 182 of 197 planted stale names caught (the other 15 target a type the scan cannot see and are skipped by design) |
| **LLM-STRUCTURED-EXTRACT-1** | A language model's raw text (`response.getContent()`, `...call().content()`, `...text()`) passed straight to `readTree` / `readValue` / `fromJson` | blocking | 5 hits, all true: model output parsed with no fence stripping |
| **NO-STUB-1** | Stubs in shipped code: a `TODO`/`FIXME` method whose only work is a constant return, an `UnsupportedOperationException` or nothing; `UnsupportedOperationException("not implemented")`; a `[STUB]` / `STUB:` / `Stub implementation` note; a `…StubImpl` type | advisory | 26 hits, 25 true, 1 false |
| **DELIVERY-INERT-1** | A decision method (`isX`, `hasX`, `canX`, `shouldX`, `checkX`, `verifyX`, ...) whose whole body is `return true;` or `return false;` | advisory | 1 hit, false |

### Calibration record (first customer repository, 13,467 Java files, 2026-10-04)

Run read-only with `cotterpin gate run <ID> --repository <checkout> --no-cache`; every hit was opened and judged by
hand. The zero-false-positive gates block; the rest are advisory, with the cause of each false positive below.
Scan time is the gate alone over files already read (reading the 13,467 files happens once per run, is shared by every
gate, and took 7 to 10 s on the measuring machine without the result cache).

| Gate | Hits | True | False | Scan time | Notes |
|---|---|---|---|---|---|
| ENT-IDX-1 | 0 | 0 | 0 | 1.7 s | 325 tables and 1,346 names judged (no entity was skipped). Recall checked by renaming the first `columnList` name of every indexed entity file in memory: 287/287 flagged |
| REFLECT-FIELD-1 | 0 | 0 | 0 | 2.9 s | 982 calls: 934 judged, 41 skipped (type or a superclass not in the repository), 7 skipped (interface/abstract target with no construction). In-memory renames: 182/197 flagged |
| LLM-STRUCTURED-EXTRACT-1 | 5 | 5 | 0 | 0.9 s | each parses a model response's `getContent()` directly; the model gateway does not strip fences |
| NO-STUB-1 | 26 | 25 | 1 | 0.7 s | 10 placeholder bodies (e.g. a safety verification that does nothing, a token refresh that returns `false`), 16 self-declared notes. **False positive:** a `Stub implementation` comment left on a method that has since been implemented — a comment cannot be checked against the code under it |
| DELIVERY-INERT-1 | 1 | 0 | 1 | 2.6 s | **False positive:** a framework contract method (`isSourceModified` of a template resource loader) implemented without `@Override`; a one-file scan cannot see that a method implements an outside interface |

Calibration changed three gates before the record above was taken, each change removing a measured false positive:
NO-STUB-1's prose markers count only capitalised (`Stub implementation`, not "tests inject a stub implementation"),
and a history word (`previously`, `replaces the`) on the line before a marker now counts, as sentences wrap; and
DELIVERY-INERT-1 judges a parameterless method only inside a service (`@Service`, `@Component`, ...), because the eight
parameterless hits were all properties of a type (`isSingleton()`, `isLiked()` on a liked item, a session type that is
never "key"), not decisions. NO-STUB-1 also learned to see past argument guards and log lines, which is the shape the
real placeholders had (it found 10 more, all true).

### The deliberate-stub opt-out (NO-STUB-1)

Some placeholders are correct: a no-op adapter for an environment without the external service, an operation a type
refuses on purpose. Say so where the finding is reported, on that line or the line above, with the reason:

```java
public boolean transfer(String code) {
    // TODO remove when the sandbox gets a partner network
    // cotterpin:allow NO-STUB-1 deliberate: the sandbox build has no partner network, refusing is correct
    return false;
}
```

The finding is then counted as allowed and listed with its reason (`cotterpin gate run --json`, `allowed`); it never
blocks. A marker without a reason allows nothing. The same marker form works for every gate: on the reported line or
the line above, `cotterpin:allow <ID> <reason>` — for ENT-IDX-1 that is the line of the `columnList`, for
REFLECT-FIELD-1 the `setField` call, for DELIVERY-INERT-1 the method's declaration line.

### Facts, not a second parser

ENT-IDX-1 and REFLECT-FIELD-1 need other files (an entity's superclass, a test's target class). They read entity,
column and field records through the Java pack's Facts extractors (`cotterpin_pack_java/facts`: the `entity` and
`type` facts every Java manifest reads), applied to exactly the bytes being checked — the staged copy with `--staged`,
the disk otherwise — and only to the files that can matter (files that declare an entity, or a type a call names). The
stored Facts index is keyed by a commit, so it would answer for the last commit rather than for what is being committed.
Each gate lists the extractor code it depends on (`DEPENDS_ON`), which is part of its result-cache digest: a better
extractor re-runs exactly these gates.

**Narrowed runs.** With `--changed` or `--path`, a whole-tree gate still reads every in-scope file of the repository
as context (the staged copies with `--staged`) and keeps only its findings in the files the run checks, so a call naming
a field of an entity the commit did not touch is still judged against that entity.

## Wave 4 — the migration gates (SQL)

These read your database migrations — PostgreSQL SQL — and catch the statements that pass the build and every test that
does not apply migrations, then fail when the migration runs on deploy.

| Gate | Catches | Default | Evidence |
|---|---|---|---|
| **MIG-TBL-1** | A migration creates a table an earlier migration already created, with nothing dropping it in between. Without `IF NOT EXISTS` the statement fails; with it, it silently does nothing and the new definition never takes effect | blocking | 6 hits, all true: each re-declares an existing table with 2 to 19 columns that therefore never exist |
| **SEEDWIDTH-1** | An `INSERT`/`UPDATE` writes a string literal longer than its `VARCHAR(n)`/`CHAR(n)` column (`value too long`) | blocking | 0 hits over 13,708 values measured against a known width |
| **IDX-IMM-1** | An index whose `WHERE` predicate or key expression uses `now()`, `CURRENT_DATE` or another function that is not `IMMUTABLE` (SQLSTATE 42P17); inside an error-catching block the index is silently never created | blocking | 1 hit, true (`CURRENT_DATE` in a partial-index predicate inside an error-catching block) |

All three are `commit` tier and whole-tree gates: each replays every migration of a database in apply order. They run
in about 1–3 s each on 1,072 migrations (100 MB of SQL) with no cache, and in one cache read when nothing changed.

### Where the migrations are

The gates never assume one directory. They read:

- **Flyway**: `spring.flyway.locations` (in `application*.properties`/`.yml` or any properties/YAML file under a
  `src/<set>/resources/` directory, nested, flattened or as a list), `flyway.locations` in `flyway*.conf`,
  `locations` in `flyway.toml`, the Maven plugin's `<locations>` and the Gradle plugin's `locations = [...]`.
  `classpath:X` is `X` under any `src/<set>/resources/`; `filesystem:X` is relative to the configuring module or the
  repository root; `*`, `**` and `{vendor}` work, and sub-directories are included, as Flyway scans them. With no
  location configured anywhere, Flyway's default `classpath:db/migration` applies.
- **Liquibase**: every changelog (a file named `*changelog*.xml|yaml|yml|json`, or the one
  `spring.liquibase.change-log` names), following `include`, `includeAll` and `sqlFile` to SQL files in changelog
  order, plus any SQL file that starts `--liquibase formatted sql`.
- **Your override**: `migrationLocations` under `packs: java:` in `.cotterpin/gates.yaml` replaces discovery (see the
  example above). Each entry is one database: a directory, or a list of directories applied together.

One configured location list in one module is one database. Two services that both keep `db/migration` are two
databases and are never compared. Flyway order is version order (`V1_2__x.sql` is 1.2, so `V10` runs after `V9`), then
repeatable `R__` files; undo files and files without Flyway's naming are not applied. A location holding an unresolved
`${placeholder}`, or one on a remote store (`s3:`), is skipped: the gates never guess.

### What they deliberately do not decide

- **A harmless repeat** — `CREATE TABLE IF NOT EXISTS` that repeats the existing definition word for word (comments and
  spacing aside) when no `ALTER TABLE` has changed the table since — is not a MIG-TBL-1 finding: it changes nothing, so
  it hides nothing. A repair migration that re-declares tables exactly is legitimate.

- **DDL that may not run** — inside an `IF` branch or loop of a `DO` block, after an early `RETURN` there, or in a
  function body — makes the tables and widths it touches *uncertain*, and nothing uncertain is ever reported. Calibration
  found exactly this: a rename inside `IF (the table has the new columns) THEN` made a later `CREATE TABLE IF NOT
  EXISTS` look like a collision when, on a fresh database, the branch does not run. The price is a missed finding, never
  a false one.
- **SQL built at run time** (`EXECUTE '...'`) is a string and is not read. Comments and string literals never match; a
  `--` inside a string is text, not a comment.
- **SEEDWIDTH-1** measures only values whose length is certain: plain `'...'` literals (`''` is one quote) and
  PL/pgSQL variables declared once with one and never reassigned. Escape strings, dollar-quoted strings, casts,
  concatenation and function calls are skipped. Trailing spaces beyond the width are allowed (PostgreSQL drops them).
  The width used is the one in force at that point of the replay.
- **IDX-IMM-1** reads `CREATE INDEX` statements only; a column `DEFAULT now()` is legal. A function that is STABLE
  only for some argument types (a `timestamptz`-to-`date` cast, `to_char`) is not visible to a text scan.

Allow a finding in SQL with a comment on its line or the line above:

```sql
-- cotterpin:allow MIG-TBL-1 old databases may lack this table, so it is declared again on purpose
CREATE TABLE IF NOT EXISTS audit_log (id BIGSERIAL PRIMARY KEY);
```

### Calibration record (2026-10-04)

One repository: 14,629 files, 1,072 Flyway migrations found through `spring.flyway.locations` and `flyway.conf`
(read-only; `cotterpin gate run --repository <checkout> --no-cache`). Every hit was checked by hand against the
migrations it names.

| Gate | Hits | True | False | Notes |
|---|---|---|---|---|
| MIG-TBL-1 | 6 | 6 | 0 | Each hit re-declares an existing table with columns that therefore never exist (2, 2, 5, 8, 15 and 19 missing columns). The scanner it replaces carried 17 accepted collisions: 1 was its own false positive (a re-creation after a rename had freed the name — renames are now followed); 9 are word-for-word repeats in a repair migration, now recognised as harmless; 1 depends on a creation after an early `RETURN` in a `DO` block, and one more (a table that got its name from a rename in that block) was never in its list — both uncertain by the rule above, so not reported: missed true collisions, the accepted price of zero false ones. A first draft of this gate followed a rename inside an `IF` branch as if it always ran and named the wrong earlier migration in one message; that is why DDL that may not run never decides a finding |
| SEEDWIDTH-1 | 0 | 0 | 0 | 13,708 values measured; agrees with the scanner it replaces (0). That scanner stripped `--` inside strings and read widths from the final schema rather than the one in force at each statement; both are fixed |
| IDX-IMM-1 | 1 | 1 | 0 | Agrees with the scanner it replaces (1 hit, which it reported as advisory because the error is caught); here the message says the index is never created, and the gate blocks on its zero-false-positive record |

The calibration corpus of GATE-PACK-V1 §4 decides the final classification; a false positive found there demotes a gate
to advisory.

## Wave 5 — gates that read other files

These four answer a question one file cannot: does the attribute a query names exist on the entity, does the property a
mapper maps exist on both sides, is the class whose method calls itself a proxied bean. Each is a whole-tree gate
(`scan_tree`) that reads entities, beans and classes through `cotterpin_pack_java/gates/model.py`, which runs the Java
Facts store's own extractors (`persistence` for entities, `spring` for beans, the lexer for classes) over the exact
bytes being checked. Entities are found wherever `@Entity`, `@MappedSuperclass` or `@Embeddable` is declared — no
package, module or directory is assumed — and when the model cannot be sure (a superclass outside the repository, a
mapping on getters, a type it cannot locate) the gate reports nothing.

| Gate | Catches | Default | Evidence |
|---|---|---|---|
| **JPQL-1** | A JPQL/HQL query (`createQuery`, Spring Data `@Query`, `@NamedQuery`) or a Criteria `get("name")` naming an attribute the entity does not have, or one that is `@Transient` | blocking | see below |
| **CRITJOIN-1** | A Criteria `join("name")` / `fetch("name")` naming an attribute the entity does not map (absent, or `@Transient`) — the query fails while it is built, on every call | blocking | see below |
| **MAPSTRUCT-DROP-1** | An entity field renamed with the entity's name as a prefix (`status` → `shipmentStatus`) while the class it maps to still says `status`, with no `@Mapping` between them — MapStruct leaves the property null | blocking | see below |
| **CACHE-SELFINVOKE-1** | A Spring bean calling its own `@CacheEvict` / `@CachePut` / `@Caching` write method — the proxy is bypassed and the write never happens | blocking | see below |

### Calibration record (2026-10-04, read-only)

One repository, 13,467 source files (10,267 shipped), every hit checked by hand. "Older tree" is the same repository
before its own repair of Criteria joins, exported read-only, so CRITJOIN-1 is calibrated on real defects rather than on
a tree with none left.

| Gate | Hits | True | False | Sites examined | Hand check |
|---|---|---|---|---|---|
| **JPQL-1** | 1 (older tree: 2) | 1 (2) | 0 | 3,703 literal queries, 7,719 alias references, 1,543 Criteria `get()` calls; every entity's attributes were knowable | A count query selected a field renamed with an entity prefix (the column kept its name) — the previous scanner skipped the SELECT clause. Older tree: a Criteria `get()` on a `@Transient` field |
| **CRITJOIN-1** | 0 (older tree: 7) | 0 (7) | 0 | 0 Criteria joins remain on the current tree | Older tree: exactly the repository's 7 documented defects — 5 joins onto `@Transient` fields, 2 onto names that never existed (one split over three lines) |
| **MAPSTRUCT-DROP-1** | 2 | 2 | 0 | 741 mappers, 1,749 abstract methods, 417 entity mapping methods, 604 entity-prefixed properties | Both confirmed in the generated mapper code: neither property is ever set. The previous scanner missed both because the target's property is inherited |
| **CACHE-SELFINVOKE-1** | 1 | 1 | 0 | 24 self-calls to cache-write methods | A public overload delegating to its cache-evicting sibling (the annotation is written fully qualified, which the previous scanner did not recognise). The 23 others are not reported, by rule: 14 may reach an un-annotated overload of the same arity, 9 come from a caller (or every entry point into a private caller) that writes the same caches itself — the repository's own hand-checked record agrees on every one |

Run time on that repository, all four gates: about 6 s of gate work plus the shared walk; an unchanged tree is one cache
read per gate.

**What each one deliberately does not see** (each module's docstring has the full list):

- JPQL-1 reads only queries made of string literals; queries with `TREAT`, SpEL (`#{...}`) or a native flag are skipped,
  an alias bound by a path join (`JOIN a.items i`) is not resolved, and Hibernate's `id` and `class` are always valid.
  Only the first segment of a path is checked. Attributes of persistent subclasses count (a query over a superclass may
  name them).
- CRITJOIN-1 resolves a receiver only when it is declared `Root<E>`, assigned `q.from(E.class)` or declared
  `Join<?, E>` in the same file; chained receivers and metamodel attributes are skipped.
- MAPSTRUCT-DROP-1 recognises one rename shape — the entity's own name as a prefix — and only for mappers whose
  `@Mapper` is MapStruct's (`org.mapstruct.Mapper`; a MyBatis `@Mapper` is not). Without MapStruct in the code it does
  nothing. Methods with inherited configuration, non-literal `@Mapping` names, an `ERROR` unmapped-target policy, a
  parameter or second source that supplies the property, or a hand-written `set<Name>(` in the mapper are skipped.
- CACHE-SELFINVOKE-1 checks classes that are beans (a stereotype, or the type a `@Bean` method returns), never in
  AspectJ mode, and never `@Cacheable` (a self-call there is slower, not wrong). Cache names are compared as written: a
  caller that evicts the same cache under another spelling is still reported — allow it with a reason, and report it.

### Fixtures for a whole-tree gate

A whole-tree gate's fixtures may share **context** files — `fixtures/<ID>/context/*.java`, the entities a query names,
say — which are read with both colours and never judged themselves, except that a finding on a context file fails the
fixture. Every wave-5 gate ships red, green and context fixtures, and its green fixture carries a `cotterpin:allow`
marker on a real finding.

## Wave 6 — the judgement-heavy gates

| Gate | Catches | Kind, scope | Default |
|---|---|---|---|
| **SPRING-SETFIELD-RESTORE-1** | `ReflectionTestUtils.setField` on an injected bean of a cached Spring test context, never restored — later tests inherit the change | whole tree, test code | blocking |
| **WEBHOOK-FAILCLOSED-1** | A signature/token verifier that accepts when it cannot verify: a `catch` that returns "valid", or a missing-secret guard that does | whole tree, shipped code | blocking |
| **PRINCIPAL-IDENTITY-1** | An endpoint that takes the caller's identity (`requesterId`, `X-Caller-Id`, `body.getCreatedBy()`) from the request instead of the authenticated principal | per file, shipped code | advisory |
| **ASSERTION-REPOINT-1** | A change that only moves a test's expected value to match the code, with nothing else in the change explaining it | change, test code | advisory |

None of them assumes one framework. Contexts are recognised by Spring's own test annotations, Spring's context base
classes, or a repository's own annotation or base class that carries one (resolved by name in the repository, never by
module or directory). Endpoints are recognised for Spring MVC/WebFlux, Jakarta/JAX-RS and Micronaut; no security
framework is assumed — the gate reads only where an identity comes FROM. Verifiers are recognised by name and by the
verification primitives they call, and "accepts" is read from a literal `true`/`false` — one hop into a result type's
constructor when the verifier returns one — never from a factory's name. Each module's docstring lists exactly what it
reads and what it cannot see.

### Calibration record (first customer repository, 2026-10-04, read-only, every hit checked by hand)

13,467 source files (10,267 shipped, 3,200 test). Runs used `cotterpin gate run <ID> --repository <checkout>
--no-cache`; ASSERTION-REPOINT-1 also ran `--staged` on the checkout's staged change and was replayed over history.
Wall time uncached: PRINCIPAL-IDENTITY-1 5.6 s, SPRING-SETFIELD-RESTORE-1 2.8 s, WEBHOOK-FAILCLOSED-1 4.0 s,
ASSERTION-REPOINT-1 0.2 s (all inside the commit tier).

| Gate | Hits | True | False | What was measured, and the cause of each false positive |
|---|---|---|---|---|
| SPRING-SETFIELD-RESTORE-1 | 0 | 0 | 0 | 162 reflective changes to injected beans in cached contexts (218 files call `setField`); every one is restored by a tear-down, a set-up reset, a `finally` or a second set — checked one by one. Control: removing one class's `@AfterEach` in memory is flagged at the unrestored line. **Zero false positives → blocking** |
| WEBHOOK-FAILCLOSED-1 | 0 | 0 | 0 | 9 verifiers in scope (HMAC, payment-provider and one-time-code verifiers); every catch and every missing-secret guard rejects — checked one by one. Control: making one verifier's catch and its missing-secret guard return `true` in memory is flagged twice. **Zero false positives → blocking** |
| PRINCIPAL-IDENTITY-1 | 16 | 15 | 1 | 15 true: an "updated by" audit identity read from the request body (with a fallback to the path id) in one controller's 15 endpoints. 1 false: a `requesterId` request parameter that names the OTHER party of a follow request (the caller is read from the principal in the same method) — a name cannot always say who is acting. **Advisory** |
| ASSERTION-REPOINT-1 | 0 | 0 | 0 | The staged change (tests plus shipped code) is silent, correctly. History replay: 3,000 commits, 768 touching tests, 733 changed expected values on paired assertions; 731 sat in tests whose scenario or set-up changed too, and the other 2 came with shipped code changed in the same commit (a fee schedule; a returned type) — all correctly silent. **Advisory anyway**: a test whose OLD expectation was wrong is indistinguishable from a re-pointed bug, so a correct fix to a wrong test would be blocked |

Every gate's `cotterpin:allow <ID> <reason>` behaviour is tested (a marker with a reason allows and is counted; one
without a reason allows nothing and says so), and each ships red and green fixtures that `cotterpin gate fixtures`
proves.

### Change gates (`scan_change`)

ASSERTION-REPOINT-1 judges a change, not a state, so the runtime hands it a `Change` (from `cotterpin.kernel.gates`):

- `files` — each changed path in the gate's scope → `(text at the last commit, or None for a new file, new text)`;
- `changed` — every path the change adds, copies, modifies or renames, whatever its type or scope;
- `select(scope)` — the pack's own scope rule over `changed`, with the repository's settings, so a gate can ask "does
  this change touch shipped code?".

- `scope_paths` — every path of the gate's scope in the state being judged, changed or NOT, and `read(path)` its judged
  copy (staged, or on disk) — for a gate that must read the unchanged file a change should have touched
  (OKF-CURRENCY-1 reads the knowledge-bundle concepts that describe a changed file).

A change gate's finding stands wherever it points, also in an unchanged file (the concept the change left behind),
unless the run was narrowed with `--path`; allow markers are read from that file as usual. Its fixtures may therefore
carry `cotterpin:expect` in a file that is the same in `before/` and `after/`.

`cotterpin gate run --staged` compares what the commit records (the index) with the last commit; without `--staged`,
the working tree (untracked files included). `--path` narrows which files are read, `exclude:` patterns apply. Outside
version control, or before the first commit, a change gate reports nothing and the run prints a `note:` saying it was
not checked and why; the JSON report lists these under `notes`. Change gates are never cached: their answer depends on
the last commit as well as the files.

The de-stub lane has its own, different conversion check, `DESTUB-REPOINT-1` (`cotterpin_pack_java/destub/repoint.py`):
it judges a mocked-to-real conversion against its target before a receipt exists. The gate judges any commit.

## Whole test classes that never run, or never check

The placeholder-test scanner PLACEHOLDER-TEST-1 was ported from also reported two whole-class shapes. They ship as
their own gates so PLACEHOLDER-TEST-1's per-test record stays what it measured.

| Gate | Catches | Kind, scope | Default |
|---|---|---|---|
| **DISABLED-TEST-1** | A test class switched off as a whole — `@Disabled` (JUnit 5), `@Ignore` (JUnit 4) or a class-level TestNG `@Test(enabled = false)` — that declares tests: none of them runs, and the build stays green | per file, test code | advisory |
| **NO-ASSERT-TEST-1** | A test class (one file) whose tests reach no check at all: no assertion, `verify`, `expect`, `fail`, `then`, `throw` or `assert` statement, in the tests or in any method they call | whole tree, test code | blocking |

DISABLED-TEST-1 does not report a single disabled METHOD (a quarantined test in a running class) or a conditional
switch (`@DisabledOnOs`, `@DisabledIf…`, `@EnabledIf…`). NO-ASSERT-TEST-1 follows the calls the tests make: into the
same file, into classes they extend or implement (by simple name among the test sources, transitively), into
statically imported test-source classes, into `Type.method(..)` of a test-source type, and into the test-source type
an `object.method(..)` receiver is declared with. It NEVER guesses that a call checks nothing: an unqualified call it
cannot find (inherited from a class outside the test sources, a library base class) is assumed to check, and so is a
call on an object of unknown type (a chained call) when any method of that name asserts somewhere in the test sources.
A shared base class's own set-up and tear-down are not followed: they are infrastructure, and they throw when the
infrastructure fails, which says nothing about the tests. An empty-bodied smoke test (`contextLoads() {}`) in a class
with a context to start (a class-level annotation or a superclass) is not reported.

### Calibration record (first customer repository, 2026-10-04, read-only, every hit checked by hand)

13,467 source files, 3,200 test files (3,134 with test methods). DISABLED-TEST-1 0.3 s, NO-ASSERT-TEST-1 9.5 s
uncached (whole tree; the commit route reports only the files a commit touches).

| Gate | Hits | True | False | What was measured, and why the default |
|---|---|---|---|---|
| DISABLED-TEST-1 | 1 | 1 read correctly | — | A class of 2 tests switched off with a written reason: an on-demand maintenance tool kept in the test sources so it can be run by hand. The reading is accurate, but quarantining a class with a written reason is a common, deliberate practice and whether the reason still holds is not visible to a scan. **Advisory** |
| NO-ASSERT-TEST-1 | 2 | 2 | 0 | Only 2 files with test methods contain no check token at all, and both are reported: a class whose single test reads and rewrites a file and swallows its own exceptions (missed by the ported scanner, which only read files named `*Test`), and a diagnostic that only prints a census of the test context (kept on purpose; the owner opts out with `cotterpin:allow NO-ASSERT-TEST-1 <reason>`). Control: 200 real test classes sampled, every line carrying a check removed in memory; 172 were valid mutations, 147 were reported. The other 25 call a helper of a shared base class or an object whose same-named method asserts elsewhere, which the scan deliberately assumes checks. The first draft followed inherited set-up and tear-down too, and the shared base class's set-up hid the diagnostic; and a test method named `size()` that asserts made every `list.size()` count as a check — both fixed before this record. **Zero false positives → blocking** |

## Wave 7 — the customer's remaining scanners

Wave 7 ports the first customer's remaining scanners: 26 Java gates in the four groups below, eight language-neutral
gates in the kernel's own table (*Kernel gates*), and two rules that are not scans (*What else the batch became*).
Each group was calibrated on its own; the per-group records follow its table. Which of them run on every commit and
which in the deferred tier is decided by measured cost (*Commit-tier budget*).

## Wave 7 — persistence, schema and API shape

| Gate | Catches | Kind, scope | Default |
|---|---|---|---|
| **BATCH-INSERT-1** | A loop that runs one native `INSERT` per element (binding the loop variable), or builds a multi-row `INSERT ... VALUES` string in a loop | per file, shipped code | blocking |
| **CONTEXT-QUALIFIER-1** | A required `@Qualifier`/`@Resource(name)` bean that a module's Spring tests cannot see (off under the test profile, or only in test sources not on that module's classpath), so every Spring test of the module fails to start | whole tree, `context` (Java + `pom.xml`) | blocking |
| **ENT-ARRAY-1** | A `List`/`Set`/`Collection` field marked `@JdbcTypeCode(SqlTypes.ARRAY)`: Hibernate binds it as JSON, and every write fails against an array column | per file, shipped code | blocking |
| **SCHEMA-NAME-1** | Two controller-reachable classes with one OpenAPI schema name: springdoc publishes one shape for both | whole tree, shipped code | blocking |
| **JDBC-NULL-1** | `queryForObject(…, Long.class)` unboxed or dereferenced unchecked (SQL NULL, and `SUM/MAX/MIN/AVG` over no rows, return null); `query(…).get(0)` | per file, shipped code | advisory |
| **YODA-EQUALS-1** | `param.equals("literal")` on a parameter that may be null; `cotterpin fix` swaps the operands | per file, shipped code | advisory |

`context` is a Java pack scope: every main and test Java source plus each module's `pom.xml`, which says which modules'
classes (and which `test-jar`s) are on a module's test classpath. CONTEXT-QUALIFIER-1 models Maven modules only; a
repository without them is not judged. SCHEMA-NAME-1 does not read `springdoc.use-fqn`: a project that sets it has no
such collisions and should demote the gate.

### Calibration record (first customer repository, 2026-10-04, read-only, every hit checked by hand)

Runs used `cotterpin gate run <IDs> --repository <checkout> --no-cache` (15,822 files walked, 29 s for all wave-7 and
kernel gates uncached); gates whose defect the repository had already fixed were also replayed, from git objects only,
on the tree before the fix.

| Gate | Hits | True | False | What was measured, and the cause of each false positive |
|---|---|---|---|---|
| BATCH-INSERT-1 | 2 | 2 | 0 | Two join-table links inserted one element per statement (one `unnest` statement would do); the same two the repository's own scanner reports. **Blocking** |
| CONTEXT-QUALIFIER-1 | 0 | 0 | 0 | Current tree silent. On the tree before the repository's incident fix: 4 hits, all 4 true — the four consumers of the one executor bean defined only under `@Profile("!test")` and in another module's test sources, which broke every Spring test of one module; 0 on the fix commit. **Blocking** |
| ENT-ARRAY-1 | 0 | 0 | 0 | Current tree silent (two native-array fields correctly not flagged). On the tree before the repository's array-mapping fix: 18 hits in 8 entities, all 18 true — every one converted to `String[]` by the three commits that fixed it. **Blocking** |
| SCHEMA-NAME-1 | 20 | 20 | 0 | 9 schema names shared by 20 classes; each pair has different fields, and the repository's own published API document carries one shape per name (e.g. four `Entry` classes, one schema). The repository's previous scanner reported none: it missed `@RequestBody(required = false)`, plain return types and nested classes. **Blocking** — these are live defects |
| JDBC-NULL-1 | 0 | 0 | 0 | 39 `queryForObject` and 49 `query`/`queryForList` calls: every single-value result is null-checked, a `COUNT`, or passed on; two older trees silent too. Planting: removing 18 real null checks in memory — the 5 on non-`COUNT` queries are all caught, the 13 on `COUNT(*)` correctly stay silent. **Advisory**: a column the schema declares `NOT NULL` is safe, and the scan cannot see the schema |
| YODA-EQUALS-1 | 4 | 0 | 4 | Each an accurate reading, but all four are private helpers whose only callers already reject or replace null (a validator that returns early on blank input, a caller that maps null to ""). Whether null can arrive is not visible to the scan. **Advisory** |

## What else the batch became

* The customer's "a capability may not cite an artifact the audit writes" scanner is enforced where Cotterpin's audit
  ledger is written, not as a scan: `cotterpin tool audit-record` records a verdict whose evidence closure names the
  ledger or the register (`.cotterpin/audit/ledger/`, `.cotterpin/audit/register/`) as INCONCLUSIVE with the reason,
  so such a verdict can never enter the ledger (`cotterpin/library/tools/audit.py`, `derived`).
* The patch-generation guard (a `git diff --no-index` captured as a patch; applying a patch whose `---`/`+++` sides name
  different files, which git applies as a rename that deletes the target) is the agent hook rule `unsafe-patch`
  ([HOOKS.md](HOOKS.md)).
* The customer's agent-ledger check (an audit verdict citing a backlog) is not a gate either: in Cotterpin the audit
  ledger is written only by `cotterpin tool audit-record`, so the rule lives there (CLOSURE-PLANNING-1 in
  `cotterpin/library/tools/audit.py`): a verdict whose evidence cites a planning document is recorded INCONCLUSIVE
  with the reason, and `audit-plan` sends an existing one back for audit.

## Wave 7 — build, persistence, security and logging gates

| Gate | Catches | Kind, scope | Default |
|---|---|---|---|
| **BUILD-CACHE-RUNALWAYS-1** | The Maven build cache can restore the test run or the install instead of running them: the extension is loaded and `.mvn/maven-build-cache-config.xml` is missing, has no `<runAlways>`, or does not list `maven-surefire-plugin` and `maven-install-plugin` (and `maven-failsafe-plugin` when a POM uses it) | whole tree, `build` (`pom.xml`, `.mvn/*`) | blocking |
| **SENSITIVE-LOG-1** | A log call writes a variable, field or getter named like a secret (`password`, `token`, `apiKey`, `clientSecret`, `cardNumber`, ...) | per file, shipped code | blocking |
| **MOCK-REPOSITORY-BEAN-1** | A test `@Configuration` registers `mock(SomeRepository.class)` as a `@Bean`, replacing the real repository in every test that loads it | whole tree, all Java | blocking |
| **FIXTURE-GENERATED-ID-1** | A Spring-context test sets a literal on a `@GeneratedValue` id and then saves the entity for real — `save` merges a row that does not exist | whole tree, all Java | blocking |
| **ADMIN-ROLE-1** | A handler under an admin path that no annotation and no URL rule of the security configuration restricts to an administrator role | whole tree, shipped code | advisory |
| **N-PLUS-ONE-1** | A repository read (`find…`, `count…`, `exists…`, `createQuery`, ...) inside a loop, a `forEach` or a stream operation — one query per element | whole tree, shipped code | advisory |
| **CROSSPERSON-AUTHZ-1** | A service method taking the caller's id and another person's or row's id with no access check, in a class whose sibling methods make one | per file, shipped code | advisory |

Each module's docstring lists what it reads and what it deliberately does not decide. The repository-specific parts of
the scanners these came from are settings under `packs: java:` in `.cotterpin/gates.yaml`, never code:

```yaml
packs:
  java:
    adminPaths: [admin, backoffice]          # ADMIN-ROLE-1: admin path segments (default: admin)
    adminRoles: [ROLE_ADMIN, ROLE_SUPER_ADMIN]   # ADMIN-ROLE-1: administrator roles (default: ROLE_ADMIN)
    rolesAllowedEnforced: true               # ADMIN-ROLE-1: JSR-250 is switched on, so @RolesAllowed counts
    callerIdPrefixes: [caller, actor, tutor]  # CROSSPERSON-AUTHZ-1: caller-identity parameter prefixes
    accessChecks: [canAccess, isMemberOf]    # CROSSPERSON-AUTHZ-1: methods that answer "may this caller act here?"
    logRedactors: [redact, Redactor.mask]    # SENSITIVE-LOG-1: calls that make a value safe to log
    externalBoundaries: [ImageStoreClient]   # shared with MOCK-BEAN-1: never reported by MOCK-REPOSITORY-BEAN-1
```

Every gate's `cotterpin:allow <ID> <reason>` works on its reported line or the line above (in the cache configuration,
`<!-- cotterpin:allow BUILD-CACHE-RUNALWAYS-1 <reason> -->`); a marker without a reason allows nothing and says so.

### Calibration record (first customer repository, 2026-10-04, read-only, every hit checked by hand)

`cotterpin gate run <ID> --repository <checkout> --no-cache` over 20,236 walked files (10,267 shipped Java sources);
the gates with no hit were run again on the same real files with one defect planted in memory (a control), so a zero
is shown to be a zero that can fire.

| Gate | Hits | True | False | What was measured, and the cause of each false positive |
|---|---|---|---|---|
| BUILD-CACHE-RUNALWAYS-1 | 0 | 0 | 0 | The repository's cache configuration lists both plugins. Controls: dropping either plugin, or the whole configuration, is reported (3 of 3). The checkout under test does not track its `.mvn/`, so the configuration was read from the primary checkout. **Zero false positives → blocking** |
| SENSITIVE-LOG-1 | 3 | 3 | 0 | A raw invitation token and two raw friend-request tokens written at debug/info. A first draft also reported 14 properties of objects named like a secret (`apiKey.getApiKeyId()`, `token.getId()`): those are properties, not the secret, and are no longer reported (`token.getValue()` still is). **Zero false positives → blocking** |
| MOCK-REPOSITORY-BEAN-1 | 0 | 0 | 0 | 23 test configurations with `@Bean` methods, 541 repository types recognised. Control: 20 repository mocks planted as `@Bean` methods — the 17 in configuration classes were all reported; the 3 in classes that are not configurations correctly were not. **Zero false positives → blocking** |
| FIXTURE-GENERATED-ID-1 | 0 | 0 | 0 | 1,384 test classes run a Spring context (most through a base class), 561 entities have a generated id. Control: 459 literal ids planted before a real save, 459 reported. A first draft resolved a variable's type across the whole file and reported 2 request-object setters whose variable name was reused for an entity in another method; types are now resolved within the method. **Zero false positives → blocking** |
| ADMIN-ROLE-1 | 0 | 0 | 0 | Before the security configuration's URL rules were read, 58 handlers were reported — all protected by `requestMatchers("/api/v1/**/admin/**").hasRole(...)`, so all false. **Advisory**: protection by other means (a check inside the handler, a custom annotation, a second filter chain, a rule built from a constant) is invisible to the scan, and a pre-flight `OPTIONS` rule had to be excluded by hand before the record was clean |
| N-PLUS-ONE-1 | 28 | 27 | 1 | 27 reads per loop element (lookups per category, per day of a date range, per referrer, per import row; a stream `map` per plan). 1 false: a loop over one of two constant keyword arrays chosen by a condition. A first draft read a domain class named `Session` as Hibernate's and reported 35 getters; `Session` now counts only where Hibernate's is imported. **Advisory**: whether a read is a cache hit, or the loop is small by design, is not visible |
| CROSSPERSON-AUTHZ-1 | 9 | 1 | 8 | 1 true: the records of any relationship between two people returned to any caller (the relationship is loaded, never compared with the caller). 8 false: an `actorPersonId` used only as an audit stamp while the class authorises by other ids (6), a view counter, a yes/no query. **Advisory**: a name cannot always say who is acting, and checks made by the caller (a controller, an aspect) are invisible. With the repository's own vocabulary as settings (`callerIdPrefixes` with its domain word, `accessChecks` with its relationship predicates) the gate reports 71 methods, 52 of them also reported by the repository's own scanner; those are review questions there too and were not each adjudicated |

N-PLUS-ONE-1 reads its loops from the shared transactions model (`transactions_model.loops`, below), the same model
DB-IN-LOOP-1 and TX-PROXY-1 read.

## Wave 7 — the N+1 family, caching, configuration and seeds

| Gate | Catches | Kind, scope | Default |
|---|---|---|---|
| **DB-IN-LOOP-1** | A database call made once per iteration of a loop — `for`/`while`/`do`, `forEach` (lambda or `repository::save`), a per-element stream step — the N+1 query | per file, shipped code | advisory |
| **TX-PROXY-1** | `@Transactional` (Spring, Jakarta or `javax`) on a `private` or `static` method: the proxy never intercepts it, so the method runs without the transaction it declares | whole tree, shipped code | blocking |
| **CACHE-ERROR-HANDLER-1** | `@EnableCaching` with no `CachingConfigurer.errorHandler()`, a configurer that returns the rethrowing `SimpleCacheErrorHandler`, or a handler that rethrows or leaves callbacks to the rethrowing parent — a cache failure becomes an HTTP 500 instead of a miss | whole tree, shipped code | advisory |
| **CACHE-EVICTION-GAP-1** | A cache name some `@Cacheable` fills that no `@CacheEvict`/`@CachePut` (or code reaching the cache by that name) ever evicts or refreshes | whole tree, shipped code | advisory |
| **HIKARI-POOL-LITERAL-1** | A literal `setMaximumPoolSize`/`setMinimumIdle` on a hand-built Hikari pool while the repository's configuration sets that Hikari property — the configured value is silently ignored | whole tree, shipped code and configuration (`main-config`) | blocking |
| **SEED-RENAME-1** | A SQL seed's `INSERT`/`COPY` column list naming a column (or table) a migration certainly renamed or dropped — every row fails, and a seed loaded ignoring errors leaves the table empty | whole tree, SQL (`sql`) | advisory |

DB-IN-LOOP-1 and TX-PROXY-1 share one model of transactions and database calls,
`cotterpin_pack_java/gates/transactions_model.py` (`database_calls`, `loops`, `database_in_loop`,
`transactional_methods`); any gate that sorts database calls in loops into kinds reads the same model, never a copy.
A database call is recognised by its collaborator's NAME (`…Dao`, `…Repository`, `entityManager`, `…JdbcTemplate`,
`jdbcClient`); entity-manager `persist`/`merge`/`remove` (queued for the flush), calls memoised by
`computeIfAbsent`/`compute`/`merge`, `Optional.map`, and in-memory helpers named as such (`build…`, `to…`, `convert…`)
are not database calls per element.

**Where seeds are.** SEED-RENAME-1 reads the SQL files under a resources directory that are not migrations, or exactly
the files and directories you list:

```yaml
packs:
  java:
    seedLocations: [src/test/resources/db, fixtures/data.sql]
```

A seed belongs to the database whose migrations live in its module (with one database, to that one). Tables and
columns the seeds' own schema statements define are never reported: a test database is often built from a schema dump,
and the seeds load against that dump rather than the migrations. The migrations are replayed with SEEDWIDTH-1's replay,
so a rename or drop that may not run (an `IF` branch of a `DO` block, a function body) never decides a finding.

### Calibration record (first customer repository, 2026-10-04, read-only, every hit checked by hand)

13,467 source files; `cotterpin gate run <ID> --repository <checkout> --no-cache`. Where a gate had no hit, a
**control** changed one real file in memory (never on disk) the way the defect would, and the gate had to flag exactly
the planted line. Wall time uncached, including the shared walk: DB-IN-LOOP-1 5.3 s, TX-PROXY-1 10.5 s (most of it the
walk), CACHE-ERROR-HANDLER-1 1.3 s, CACHE-EVICTION-GAP-1 8–14 s, HIKARI-POOL-LITERAL-1 2.1 s, SEED-RENAME-1 7.6 s.

| Gate | Hits | True | False | What was measured, and the cause of each false positive |
|---|---|---|---|---|
| TX-PROXY-1 | 0 | 0 | 0 | Every `@Transactional` method read. Control: making one real `@Transactional` service method private is flagged at its annotation. **Zero false positives → blocking** |
| HIKARI-POOL-LITERAL-1 | 0 | 0 | 0 | The one hand-built pool reads both sizes from properties. Control: replacing each with a literal is flagged, naming the configuration file that sets the property (shipped configuration is named before test configuration). **Zero false positives → blocking** |
| CACHE-ERROR-HANDLER-1 | 0 | 0 | 0 | The configurer's handler overrides all four callbacks and never throws. Control: removing its `errorHandler()` is flagged at the configurer. **Advisory anyway**: with an in-memory cache a read essentially cannot fail, and whether a cache is remote is decided by a dependency and properties the scan does not judge |
| CACHE-EVICTION-GAP-1 | 30 | 30 read correctly | ~30 counted as false | Each name was searched across the shipped code: none is evicted, refreshed or reached by name anywhere; each appears only in the cache manager's time-to-live registration. Nearly all are reference or configuration data where the time-to-live is the intended refresh — the code does not say whether that staleness is acceptable. The first draft also missed eviction through a helper (`evict(CacheNames.X, key)`): 1 false positive, fixed before this record. The scanner it replaces read only string-literal names and reported 0 |
| DB-IN-LOOP-1 | 80 | 80 read correctly | 29 counted as false | Every hit is a database call or flush executed once per iteration. 29 are deliberate: a flush per parent row to obtain generated ids (13), loops over small fixed lists (keyword lists, a constant set of token columns, enum values, image sizes — 10), per-day/week/month buckets of a date range (4), a chunked batch (1), slug retries (1). A first draft also counted builder methods on a persistence class (`buildScore`) — 3 false positives, fixed |
| SEED-RENAME-1 | 0 | 0 | 0 | 1,072 migrations replayed (872 certain renames and drops); 28 seed files. The first draft reported 35, all false: the tests load the seeds against a schema dump that still defines the dropped columns — hence the rule that the seeds' own schema wins. The scanner it replaces reported 3, all inside renames guarded by an `IF` branch (uncertain by rule, so missed — the accepted price of zero false ones). **Advisory**: with the dump defining every table, nothing on this corpus could be judged |

### What each one deliberately does not see

- DB-IN-LOOP-1 cannot tell a loop over three fixed values, a paging loop (one query per page) or a deliberate
  per-item transaction from an N+1; recursion and calls through a service that queries are not followed.
- TX-PROXY-1 reads only the method's own annotation; a class-level `@Transactional` never applies to private methods
  either, and is not reported. AspectJ mode (`@EnableTransactionManagement(mode = AdviceMode.ASPECTJ)`) turns it off.
- CACHE-ERROR-HANDLER-1 resolves a handler only when `errorHandler()` constructs it (`new X()`, or an anonymous class);
  a handler returned from a field or a bean is not read.
- CACHE-EVICTION-GAP-1 resolves names written as literals or `static final String` constants of the repository; a name
  from a library is never guessed. Code that reaches a cache by a run-time name (an administrator's "clear any cache"
  endpoint) is not counted as evicting a particular cache.
- HIKARI-POOL-LITERAL-1 recognises `HikariConfig`/`HikariDataSource` variables and subclasses; a pool built through a
  builder chain is not read.
- SEED-RENAME-1 reads `INSERT INTO t (columns)` and `COPY t (columns)`; an `INSERT` without a column list, SQL built at
  run time, and a seed whose database cannot be told apart (several, none in its module) are not judged.

## Wave 7 — queries, tests, migrations, templates and configuration

| Gate | Catches | Kind, scope | Default |
|---|---|---|---|
| **ARRAY-LIKE-1** | A Criteria `like`/`notLike` straight on an entity attribute stored as a database array (`String[]`, `columnDefinition = "text[]"`): no LIKE exists for arrays, so the query fails on every call | whole tree, shipped code | blocking |
| **INJECTMOCKS-CTOR-1** | A field-injected bean (`@Autowired`/`@Inject` fields) that gains a constructor while a Mockito `@InjectMocks` test builds it: Mockito uses the constructor and skips field injection, so the fields are null in the test | whole tree, all code | blocking |
| **TRIGGER-FN-1** | `RENAME COLUMN` while a trigger function on that table still reads `NEW.old`/`OLD.old`: every insert and update fails | whole tree, migrations | blocking |
| **VELOCITY-REF-1** | A Velocity `#parse`/`#include` naming a template that does not exist, including each `#set` branch of an interpolated path | whole tree, `templates` | blocking |
| **CONFIG-PARSE-1** | A shipped `application*.yml` / `bootstrap*.yml` that is not valid YAML: the service fails to start | per file, `config` | blocking |
| **DTO-CREATOR-1** | An `@RequestBody` type (or a type it contains) Jackson cannot create: only constructors with parameters, none `@JsonCreator` | whole tree, shipped code | advisory |
| **CACHE-EVICT-COVERAGE-1** | A class that writes a repository a `@Cacheable` method reads, while another class evicts that cache and this one never does | whole tree, shipped code | advisory |

Two new scopes read resource files rather than Java sources: `templates` (files under `src/<set>/resources/` with a
template suffix — `.vm`, `.vtl`, `.vsl`, and the `.html`/`.htm`/`.txt` files templates include) and `config`
(`application*`/`bootstrap*` YAML directly in a non-test `src/<set>/resources/` or its `config/`). Each gate's module
docstring lists exactly what it reads and what it deliberately does not judge.

### Calibration record (first customer repository, 2026-10-04, read-only, every hit checked by hand)

13,472 source files (`cotterpin gate run <IDs> --repository <checkout> --no-cache`). "Older tree" is the same
repository exported read-only (`git archive`) at the commit before its own repair of the defect, so a gate is
calibrated on real defects, not only on a tree with none left. In-memory controls change files in memory only.

| Gate | Hits | True | False | What was measured |
|---|---|---|---|---|
| ARRAY-LIKE-1 | 0 (older tree: 9) | 0 (9) | 0 | 21 `like` calls on the current tree. Older tree: 9 LIKEs on three `String @Nullable []` attributes in four query methods — exactly the methods the repair commit changed. **Blocking** |
| INJECTMOCKS-CTOR-1 | 0 | 0 | 0 | 500 `@InjectMocks` subjects; 363 field-injected beans built by one; 6 beans with a constructor and only `required = false` fields, correctly silent. Control: a constructor planted in memory into each of the 363 beans was caught 363 times. **Blocking** |
| TRIGGER-FN-1 | 0 | 0 | 0 | 1,072 migrations replayed: 2,950 column renames, 44 triggers, 49 functions. Control: with the repository's repair migration removed in memory, exactly its documented incident is reported (a search-vector function still reading the renamed `description`). The repository wraps every rename in `IF EXISTS (… column_name = 'old')`; such a guard is believed (the old column is absent whichever way it goes) only when the new name cannot already exist — any other guard leaves the rename uncertain. **Blocking** |
| VELOCITY-REF-1 | 0 (older tree: 4) | 0 (4) | 0 | 433 directives in 318 templates. Older tree: the 4 renewal-email directives that named a misspelt directory, each listing every dead `#set` branch. **Blocking** |
| CONFIG-PARSE-1 | 0 (older tree: 1) | 0 (1) | 0 | 1 shipped runtime YAML file (the rest of the repository's configuration is `.properties`). Older tree: the history-rewrite incident — a redacted key YAML reads as a broken alias — reported at that line. A repeated key is not judged (Spring refuses one; other loaders keep the last value). **Blocking** |
| DTO-CREATOR-1 | 11 | — | 11 counted as false | Every hit is an accurate reading (a request body whose only constructor takes parameters), but the repository builds under Spring Boot's Maven parent, which compiles with `-parameters`, and Spring Boot registers Jackson's parameter-names module, which can call such a constructor without an annotation. None is provably broken, so all 11 are counted against it. **Advisory** — promote it in a repository that does not keep parameter names |
| CACHE-EVICT-COVERAGE-1 | 102 | — | samples false | 45 classes, 30 caches. Each hit is an accurate reading (a write to a repository a `@Cacheable` method reads, in a class that never evicts a cache another class evicts), but hand-checked samples include writes that cannot change the cached value: user-profile writes against cached XP balances (the first customer's own exemption list says so), custom-sport saves against a cache of system sports. Which columns a cached value depends on is not visible to the scan. The first draft took the feeding repositories from every class that evicts (157 hits, mostly an evictor's unrelated repositories); they now come from what the `@Cacheable` methods read. **Advisory** |

The first customer's eviction scanner carried lists of exempt caches; the port has none (absolute mode): an
intentional gap is a `cotterpin:allow CACHE-EVICT-COVERAGE-1 <reason>` on the write. Its DTO scanner's other rules
(`Serializable`, `serialVersionUID`, entity types in DTOs, collection defaults, naming) are that repository's
conventions and were not ported; nor was its configuration check's own redaction placeholder.

## The .NET gates (the .NET pack)

Twenty-one gates ship in the .NET pack (`cotterpin_pack_dotnet/gates/`), all commit tier. Fifteen block from install:
each is certain from the text alone, and its module's docstring states exactly what is and is not matched (event
handlers are exempt from the async-void gate, a filtered catch from the empty-catch gate, a conditional package
reference from the duplicate gate, a bounded version range from the floating-version gate). Six are advisory because
their harm depends on something a scan cannot see (a local display may want `DateTime.Now`; an exporter may be
attached by the platform). The full table, scopes and fixtures: [PACK-DOTNET.md](PACK-DOTNET.md#gates).

### Calibration record

No .NET customer repository has been measured yet. The blocking set is the defects whose text is the defect —
`async void` that is not a handler, `.GetAwaiter().GetResult()` inside `async`, `throw ex;` of the caught variable,
interpolation inside a `*Raw` SQL call (EF Core's own analyzer EF1002 reports the same shape), a `*` in a version, a
moniker on Microsoft's out-of-support list. Each gate's red fixture marks every flagged line and its green twin holds
the nearest legitimate shape; `tests/packs/dotnet/test_dotnet_gates.py` proves a blind and a trigger-happy copy of every
gate fail its fixtures. A false positive found in the first corpus demotes a gate to advisory, exactly as for the Java
gates.

## Kernel gates (language-neutral, any repository)

Gates that name no programming language live in ONE table, the kernel's own: `cotterpin/kernel/kernel_gates/`
(`__init__.py` holds the `TABLE`; one module per gate; fixtures under `fixtures/<ID>/`). `cotterpin.kernel.gates.
gate_tables` registers it beside the installed packs' tables under the reserved pack id `kernel` — the one registration
path; no pack may take that id — so `cotterpin gate list|run|fixtures`, `.cotterpin/gates.yaml` overrides, allow
markers, the result cache, the process-pool scan and the commit route treat these gates exactly like a pack's. Their
files go in `runtimePackagePaths` of the kernel release descriptor and their fixtures in the root `pyproject.toml`
package data. Which file is source, and which is a test with which test methods, is language knowledge: the kernel
asks the installed packs (`wants`, and a pack's optional `test_file(path)` and `test_methods(path, text)`; the Java
pack declares both). A kernel gate may not name a language or its build tool
(`tests/conformance/test_kernel_language_neutral.py`).

| Gate | Catches | Kind, scope (reports) | Tier | Default |
|---|---|---|---|---|
| **AI-TAG-1** | An AI agent's reasoning or tool-call markup left in a source or configuration file | per file, `source` | commit | blocking |
| **OKF-CURRENCY-1** | A change to a file a knowledge-bundle concept declares as its `resource:`, without the concept (or with only its front matter changed) | change, `change` | commit | advisory |
| **PY-STDLIB-SHADOW-1** | A `.py` file named after a standard-library module (`inspect.py`, `json.py`) in a directory whose files run by path — a script with `#!`/`__main__`, or a test module — so it shadows that module for every import there, including libraries' | whole tree, `python` | commit | blocking |
| **AUDIT-EVIDENCE-1** | A delivery-audit verdict (`.cotterpin/audit/ledger/*.json`) whose entry point names files outside its evidence closure, whose delivered verdict cites a test outside it, whose evidence cites a line past the end of a file, or that contradicts another verdict for the same claim | whole tree, `audited` (`ledger-files`) | commit | blocking |
| **GREEN-NEEDS-TEST-1** | A `VERIFIED-DELIVERED` row whose evidence names no test file that exists now — none at all, or only deleted ones. Reported on the ledger, at the row | whole tree, `ledger` | commit | advisory |
| **CITED-TEST-1** | A test method that proved a delivered capability has disappeared: `cotterpin tool audit-record` records, with every delivered verdict, the test methods each test file of its evidence declared (`testMethods`); a later state where a recorded method is gone is reported on the test file (line 1), a recorded file that is gone on the ledger. Test counts are irrelevant — a swap keeps them equal | whole tree, `ledger` | commit | advisory |
| **SCRIPT-REF-RESOLVES-1** | A document, configuration file or script names `scripts/<path>` (a configured script directory) that is no file of the repository; the finding names the nearest real file — the same file name elsewhere (a move) first, then a similar name | whole tree, `repository` (`script-references`) | deferred | advisory |
| **EVIDENCE-LINE-DRIFT-1** | A knowledge document (`.okf/`, or `knowledgeBundles`) or a delivery-audit ledger cites `path:line` past the end of the file, or for a code symbol written beside it that is now elsewhere in that file | whole tree, `documented` (`knowledge`) | deferred | advisory |

`source` is every file an installed language pack reads as source plus XML, properties, YAML, TOML, INI, CFG, CONF and
SQL files; documentation and prose are never read (they may describe the tags). `change` is every file of the change,
with every walked file readable through `Change.scope_paths`. The ledger gates' scopes are empty in a repository with no
ledger, so they cost nothing there; outside version control the ledger (a hidden directory) is not walked. The document
gates read every walked file that is not binary by its name through a mapping that reads each text only when asked, so
a gate opens just the documents it checks and the files those name; a run narrowed to a change runs one only when the
change touches a file it can report on (its `reports` scope).

OKF-CURRENCY-1 resolves `resource:` the ways bundles write it (repository-relative, `./`, a leading repository-folder
name, `file://` or absolute paths by their tail, a `:<line>` suffix), narrows with a concept's `sentinels:` line only
when the change provably edits another declaration, ignores a documented concept whose own change is front matter only
(a bundle-format migration), and accepts `<!-- okf-currency: no-claim-affected resource=<path> reason=<40+ characters>
-->` on a front-matter-only edit. A large bundle is read once: each concept's `resource:` declaration is kept by blob id
in the run's store, so a commit re-reads only the concepts it changed.

Settings live under `packs: kernel:`:

```yaml
packs:
  kernel:
    scriptDirectories: [scripts, tools]   # SCRIPT-REF-RESOLVES-1 (default: scripts)
    knowledgeBundles: [.okf, docs/kb]     # EVIDENCE-LINE-DRIFT-1 (default: .okf)
```

What each deliberately does not decide is in its module docstring. In short: SCRIPT-REF-RESOLVES-1 skips a path that is
a segment of another tree's path or a URL, an elision, `__init__.py`, placeholder names, a path right after `e.g.`, a line
that itself records the script's removal or plans to write it, whole-line comments in scripts and configuration, and
test files. EVIDENCE-LINE-DRIFT-1 judges a symbol only when it is written within 60 characters of the citation it belongs
to (the nearest one), only for code files, and never repairs a citation — the count is a floor. AUDIT-EVIDENCE-1 never
asks a verdict to close over the audit's own output (`.cotterpin/audit/`) and skips INCONCLUSIVE verdicts.
PY-STDLIB-SHADOW-1 judges only a directory whose files are run by path; a file inside a package shadows nothing.

The ledger is rewritten by `cotterpin tool audit-record`, so a `cotterpin:allow` marker cannot be kept in it: the
structured opt-out of AUDIT-EVIDENCE-1 is the verdict's `notLoadBearing` list, and every other finding on a ledger is
fixed by restoring the test or re-auditing the scope (`cotterpin tool audit-plan --scope <SCOPE>`), never by editing the
ledger. Because AUDIT-EVIDENCE-1 blocks, a commit that rewrites a scope's ledger is held while any verdict in that scope
has such a finding: re-audit it, or demote the gate for the repository with a reason. A CITED-TEST-1 finding on a test
file takes `// cotterpin:allow CITED-TEST-1 <reason>` on its first line; Markdown takes
`<!-- cotterpin:allow <ID> <reason> -->`.

### Calibration record (first customer repository, 2026-10-04, read-only, every hit checked by hand)

The ledger gates ran on that repository's real delivery-audit ledger (1,635 capabilities, 949 verdicts), converted in
memory to Cotterpin's ledger layout beside every tracked file read from disk, each delivered row's `testMethods` taken
from the last commit (what the audit would have recorded).

| Gate | Hits | True | False | What was measured, and the cause of each false positive |
|---|---|---|---|---|
| AI-TAG-1 | 0 | 0 | 0 | 14,762 files in scope at the current tree; on the commit of the repository's incident, 1 hit, true (the closing reasoning tag that broke its build). **Blocking** |
| OKF-CURRENCY-1 | 0 | 0 | 0 | Replay of the last 800 commits (121 changed a documented file). A first version flagged 6 concepts in a bundle-format migration whose documented file was itself a concept with only its front matter changed — fixed (that shape is ignored). Planting: leaving each concept the history updated behind its file, 127 of 143 are caught (the rest are correctly narrowed by sentinels or are documented concepts whose change was front matter only). **Advisory**: the history was held by the customer's own blocking check, so this is agreement rather than independent evidence, and a change can leave every claim of a concept true |
| PY-STDLIB-SHADOW-1 | 0 | 0 | 0 | 2,000 Python files in two repositories; the 2 files named after a standard-library module there both sit inside packages, where they shadow nothing, and are correctly silent. **Zero false positives → blocking** |
| AUDIT-EVIDENCE-1 | 2 | 2 | 0 | An implementation outside its verdict's closure (only its interface was closed over), and a test cited 140 lines past its end. Control: 547 of 549 closure gaps planted in memory were reported. A first draft reported 7 more: 4 names that are no test file of the repository (`spec.ts` shorthand, a nested test class, a field access, another repository's file) and 3 tests the verdict disclaimed as "named only" or "do not rest on". **Zero false positives → blocking** |
| GREEN-NEEDS-TEST-1 | 17 | 7 | 10 | 2 rows with no test at all; 5 proven only by front-end specs in another repository (accurate for this repository). **10 false**: proven by tests in a language no installed pack reads (script tests) — the scan cannot see a test no pack recognises. The scanner it replaces knew those two conventions by name and reported 7. **Advisory** |
| CITED-TEST-1 | 0 | 0 | 0 | 409 delivered rows, 392 with recorded methods over 258 test files. Controls: renaming one recorded method is flagged on the test file; deleting the file is flagged on the ledger. History replay: 82 commits removed a test method from a file now in a delivered closure — many replaced a placeholder (an instantiation check) with stronger tests, or converted a mocked test to a real one. Each would be an accurate reading, but a removed method is not always a lost proof. **Advisory** |
| SCRIPT-REF-RESOLVES-1 | 679 | 427 | 141 | Checked mechanically first: none of the 679 paths exists on disk. Then by kind: 427 stale instructions, usage strings and settings (moved or removed scripts in runbooks, READMEs, `--help` text, an agent settings file, the protected-file list of an instruction file); 111 historical records (session summaries, archive documents) that name a removed script on purpose — exactly what the allow marker is for; 141 false in intent: 93 evidence records quoting paths inside another tree (a test fixture under a temporary root, written repository-relative), 14 specs describing scripts that are absent or planned, 12 patch files for scripts still to be written, 8 lines of a health check that looks FOR the missing file, 7 forward-reference fields, 4 paths relative to another package, 3 illustrations and test-case data. **Advisory**: a record and an instruction look the same. A first draft also reported 19 lines that say the script is gone or still to be written; those words now excuse the line. The repository's own scanner reported 602 citations of `.py` paths only; 584 of them are among these (the rest name this repository through an absolute path or its checkout's name, which this gate never reads as this repository) |
| EVIDENCE-LINE-DRIFT-1 | 55 | 40 | 15 | 28 symbols moved away from the cited line (by 5 to 1,376 lines) and 12 lines past the end of the file. 15 false: the symbol beside the citation is what the cited code calls, extends or uses (an annotation type, a constant's value, a callee), several symbols paired with several citations in one phrase, or an absence claim ("contains no `.sessionManagement(...)`"). **Advisory**. A first draft judged citations of Markdown documents and every symbol on the line (211 hits, most false); documents are now judged only past their end, and a symbol only beside its own citation |

## Commit-tier budget

A commit runs only the `commit` tier, and within it only the gates whose scope the staged change touches (a docs-only
change runs no Java gate); a commit-tier run imports and digests only the gates of its tier. Every gate runs inside the
same result cache and process-pool scan and reads only its declared scope. A per-file gate costs a commit almost
nothing (its result is cached per blob: all 24 commit-tier per-file gates together take under 1 ms of scanning per
changed Java file). A whole-tree gate's cached result is keyed by every file in its scope, so ANY change in its scope
re-runs it whole: its warm cost per commit is its cost over its whole scope. That decides the tier: a new gate is
`commit` only when one commit that changes one file in its scope pays at most **1 s** for it on the first customer
repository (20,668 tracked files, 10,267 shipped Java sources); otherwise it is `deferred`, where it still blocks — at
the deferred verify the push gate requires.

Measured 2026-10-04 on a scratch copy of that repository through the real CLI (`cotterpin gate run <ID> --staged
--changed --cache`, warm, one file of the gate's scope changed and staged, the CLI's fixed cost subtracted; the machine
was shared, so each figure is the lower of two runs and good to about ±0.5 s):

| Gate | Warm cost of one commit in its scope | Tier |
|---|---|---|
| BUILD-CACHE-RUNALWAYS-1 | 0.1 s (`pom.xml`, `.mvn/*` only) | commit |
| PY-STDLIB-SHADOW-1 | 0.2 s | commit |
| VELOCITY-REF-1 | 0.5 s (templates only) | commit |
| CACHE-ERROR-HANDLER-1 | 0.5 s (0.07 s of scanning) | commit |
| HIKARI-POOL-LITERAL-1 | < 0.1 s (0.08 s of scanning) | commit |
| AUDIT-EVIDENCE-1, GREEN-NEEDS-TEST-1, CITED-TEST-1 | nothing unless the change touches a ledger (their report scope) | commit |
| ADMIN-ROLE-1 | 1.8 s | deferred |
| ARRAY-LIKE-1 | 1.9 s | deferred |
| DTO-CREATOR-1 | 2.0 s | deferred |
| EVIDENCE-LINE-DRIFT-1 | 3.0 s (reads every knowledge document on a change to one) | deferred |
| TX-PROXY-1 | 3.2 s | deferred |
| INJECTMOCKS-CTOR-1 | 3.4 s | deferred |
| CONTEXT-QUALIFIER-1 | 4.3 s | deferred |
| CACHE-EVICTION-GAP-1 | 6.9 s | deferred |
| SCRIPT-REF-RESOLVES-1 | 8.1 s (reads every document on a change to one) | deferred |
| SCHEMA-NAME-1 | 9.4 s | deferred |
| MOCK-REPOSITORY-BEAN-1 | 13 s | deferred |
| CACHE-EVICT-COVERAGE-1 | 15 s | deferred |
| SEED-RENAME-1 | 15 s (replays every migration) | deferred |
| TRIGGER-FN-1 | 15 s (replays every migration) | deferred |
| FIXTURE-GENERATED-ID-1 | 37 s | deferred |
| N-PLUS-ONE-1 | 53 s | deferred |

The per-file gates of wave 7 (BATCH-INSERT-1, ENT-ARRAY-1, JDBC-NULL-1, YODA-EQUALS-1, SENSITIVE-LOG-1,
CROSSPERSON-AUTHZ-1, DB-IN-LOOP-1, CONFIG-PARSE-1, AI-TAG-1) and the change gate OKF-CURRENCY-1 (which keeps every
concept's `resource:` by blob id, so it re-reads only the concepts a commit changes) are all `commit`.
`tests/packs/java/test_java_gates.py` pins the exact deferred set; `tests/perf/` pins the commit tier's own speed.

**The commit tier before and after wave 7** (2026-10-04, the real CLI, `cotterpin gate run --tier commit --staged
--changed --cache`, warm, median of 3, on the same machine one after the other; the machine was shared, load average
about 25, so differences under about 0.5 s are within its noise):

| Change | Before (28 commit-tier gates) | After (46 commit-tier gates) |
|---|---|---|
| First customer repository, docs only | 1.6 s | 2.3 s |
| First customer repository, one shipped Java file | 1.9 s | 2.5 s |
| First customer repository, five Java files of one module | 1.9 s | 2.7 s |

In-process on the same repository, without the CLI's start-up, the docs-only run is no slower after (before 2.1 to
3.9 s, after 1.3 to 3.1 s, over alternating runs at that load). Three things keep the added gates off a commit's
critical path: a commit-tier run loads and digests only the gates of its tier (a deferred gate's module is never
imported), cache entries are read and written on a few threads, and the kernel's scope test reads a file's suffix
without building a path object (it was asked 120,000 times per run). `tests/perf/test_speed_budgets.py` holds the hook,
the commit tier and the per-file cost to the speed-integrated tree plus 10 %, measured sample by sample in turn with it on
the same machine.

## Calibration summary (waves 1 to 7 and the kernel gates)

Every gate was calibrated read-only on the first customer repository (13,467 source files, 2026-10-04) with every hit
checked by hand; the per-wave sections above carry the detail. A gate blocks from install only with a zero-false-positive
record there; `tests/packs/java/test_java_gates.py` pins the exact blocking set of the Java pack and
`tests/kernel/test_kernel_gates.py` that of the kernel.

| Wave | Blocking (zero false positives) | Advisory (and why) |
|---|---|---|
| 1 | CACHE-KEY-RUNTIME-1, RONLY-WRITE-1, TOMAP-1 | CLOCK-ZONE-1 (no hits to calibrate on), CMP-NULL-1 and NULLSAFE-STRING-1 (nullability is not visible to a text scan) |
| 2 | MOCK-SUT-1 (0 hits), PLACEHOLDER-TEST-1 (291 hits, all true) | MOCK-BEAN-1 (11 hits, slice tests that still prove the web layer), VERIFY-ONLY-TEST-1 (1,691 hits, ~783 delegation checks) |
| 3 | ENT-IDX-1, LLM-STRUCTURED-EXTRACT-1, REFLECT-FIELD-1 | NO-STUB-1 (26 hits, 1 false), DELIVERY-INERT-1 (1 hit, false) |
| 4 | IDX-IMM-1, MIG-TBL-1, SEEDWIDTH-1 | — |
| 5 | CACHE-SELFINVOKE-1, CRITJOIN-1, JPQL-1, MAPSTRUCT-DROP-1 | — |
| 6 | SPRING-SETFIELD-RESTORE-1, WEBHOOK-FAILCLOSED-1 | PRINCIPAL-IDENTITY-1 (16 hits, 1 false), ASSERTION-REPOINT-1 (a wrong old expectation looks like a re-pointed bug) |
| whole test classes | NO-ASSERT-TEST-1 (2 hits, both true) | DISABLED-TEST-1 (1 hit, a deliberate quarantine with a written reason) |
| 7: persistence, schema, API | BATCH-INSERT-1, CONTEXT-QUALIFIER-1, ENT-ARRAY-1, SCHEMA-NAME-1 | JDBC-NULL-1 (NOT NULL columns are not visible), YODA-EQUALS-1 (4 hits, callers never pass null) |
| 7: build, security, logging | BUILD-CACHE-RUNALWAYS-1 (0 hits, 3/3 controls), FIXTURE-GENERATED-ID-1 (0 hits, 459/459 controls), MOCK-REPOSITORY-BEAN-1 (0 hits, 17/17 controls), SENSITIVE-LOG-1 (3 hits, all true) | ADMIN-ROLE-1 (protection outside annotations and URL rules is invisible), N-PLUS-ONE-1 (28 hits, 1 false), CROSSPERSON-AUTHZ-1 (9 hits, 8 false) |
| 7: N+1, caching, seeds | HIKARI-POOL-LITERAL-1, TX-PROXY-1 | DB-IN-LOOP-1 (80 hits, 29 deliberate), CACHE-EVICTION-GAP-1 (30 hits, reference data on a time-to-live), CACHE-ERROR-HANDLER-1 (an in-memory cache cannot fail a read), SEED-RENAME-1 (nothing judgeable on the corpus) |
| 7: queries, templates, configuration | ARRAY-LIKE-1, CONFIG-PARSE-1, INJECTMOCKS-CTOR-1, TRIGGER-FN-1, VELOCITY-REF-1 | DTO-CREATOR-1 (parameter names are a build setting the scan cannot see), CACHE-EVICT-COVERAGE-1 (which data a cache depends on is not visible) |
| kernel | AI-TAG-1, PY-STDLIB-SHADOW-1, AUDIT-EVIDENCE-1 (2 hits, both true) | OKF-CURRENCY-1 (agreement with the customer's own check, not independent evidence), GREEN-NEEDS-TEST-1 (17 hits, 10 false: tests no installed pack reads), CITED-TEST-1 (a removed method is not always a lost proof), EVIDENCE-LINE-DRIFT-1 (55 hits, 15 false), SCRIPT-REF-RESOLVES-1 (679 hits, 141 false in intent) |

The calibration corpus of GATE-PACK-V1 §4 decides the final classification; a false positive found there demotes a
blocking gate to advisory.

## The Angular pack's gates

The Angular pack (`cotterpin_pack_angular/gates/`) ships twenty-one gates over TypeScript sources, `package.json` and
`tsconfig*.json` with the same contract, runner, cache and opt-out as every other pack: twelve block from install
(each a defect by construction — a focused test, `@ts-nocheck`, an unawaited Playwright assertion, framework packages
at different majors, an unpinned dependency, a private `rxjs/internal` import, a lazy route made eager by a static
import, an unregistered HTTP interceptor, a route after `'**'`, a shadowed duplicate route, an empty test, an
`expect` with no matcher) and nine are advisory. Their table, fixtures and calibration record (2,645 TypeScript and
JSON files of real Angular code and generated projects, 0 blocking hits) are in [PACK-ANGULAR.md](PACK-ANGULAR.md#code-gates).

## Adding a gate

One gate is one module plus its fixtures plus one table row — nothing else in the runtime changes.

1. **Module**: `cotterpin_pack_java/gates/<id in lower case, dashes as underscores>.py` (e.g. `MOCK-SUT-1` →
   `mock_sut_1.py`), declaring:
   - `TITLE` — what it catches, one line; `WHY` — what breaks; `REMEDY` — what to do, followable by a stranger;
   - `SCOPE` — `main`, `test` or `all` (Java sources), `migrations` (SQL migrations and the files that locate them),
     `sql` (every SQL file plus those configuration files, whatever `migrationLocations` says — SEED-RENAME-1) or
     `main-config` (shipped Java sources plus application properties/YAML — HIKARI-POOL-LITERAL-1);
     or `templates` / `config` (resource files, see *Wave 7*);
   - **exactly one of** `scan(text) -> [(line, message)]` when the answer depends on one file's bytes (cached per
     blob); `scan_tree(files: dict[path, text]) -> [(path, line, message)]` when it needs other files, e.g. an
     entity's fields for a query check (cached per tree); or `scan_change(change) -> [(path, line, message)]` when it
     judges a CHANGE against the last commit (see *Change gates* above; never cached);
   - optionally `OPTIONS` — the `packs: java:` setting names the gate reads; it is then called `scan(text, options)`
     (or `scan_tree(files, options)`) with just those settings, and they are part of its cache key (MOCK-BEAN-1 reads
     `externalBoundaries`). A new setting also needs adding to `source.SETTINGS` and its validation;
   - optionally, for a whole-tree gate, a `settings` keyword on `scan_tree(files, settings=None)`: it then receives the
     pack's whole section of `.cotterpin/gates.yaml` (the wave-4 gates read `migrationLocations`), and its cached result
     is keyed by it. A whole-tree gate always sees the whole repository; a narrowed run keeps only the findings in the
     files it checks;
   - optionally `DEPENDS_ON` — further source files that decide the gate's answer (the pack's Facts extractors): read
     other files' facts through those extractors, not a parser of your own, and list them so they join the gate's
     digest;
   - the standalone entry point at the end:
     ```python
     if __name__ == "__main__":
         from cotterpin.kernel.gates import standalone
         raise SystemExit(standalone("MOCK-SUT-1"))
     ```
   Match against `source.strip(text)` (comments and string literals blanked, offsets kept) so prose and log messages
   never match. Test-code gates share `cotterpin_pack_java/gates/testcode.py` (annotated fields, `@Test` methods,
   same-class helpers, naming conventions); whole-tree gates that read entities, beans and types share `model.py`.
   SQL gates use `sql.lex(text)` the same way, `sql.migration_sets(files, settings)` for the migrations of each
   database in apply order, and `sql.conditional(lexed, offset)` to tell a statement that may not run. `source` also
   provides `top_level_arguments`, `closing`, `statement_start`, `line_of` and `static_import`. Start with a cheap
   substring test (`if "@InjectMocks" not in text: return []`): most files never contain the trigger.
2. **Fixtures**: `cotterpin_pack_java/gates/fixtures/<ID>/red/` — every line that must be flagged carries a
   `cotterpin:expect` comment — and `fixtures/<ID>/green/`, which must stay silent (a green fixture may carry a
   `cotterpin:allow` marker to prove the opt-out). `cotterpin gate fixtures <ID>` must pass: a red fixture is flagged
   on exactly its expected lines, and a gate without both colours fails ("no fixture, no ship"). A fixture folder may
   be a small repository (`red/src/main/resources/db/migration/V1__a.sql`, configuration files); files are named by
   their path inside it. A whole-tree gate's red folder is ONE case over all its files: a file without
   `cotterpin:expect` is a context file (the earlier migration a later one collides with, an entity's superclass, the
   class a test names) and must stay silent, and the folder must expect at least one finding. Context shared by both
   colours goes in `fixtures/<ID>/context/` (read with both, never judged, but a finding on one fails the fixture). A
   change gate's fixtures are CASES: `<colour>/<case>/before/` (the last commit) and `<colour>/<case>/after/` (the
   change), each a small repository tree such as `src/test/java/...`; a file only under `after/` is new.
3. **Table row** in `cotterpin_pack_java/gates/__init__.py` `TABLE`: `{"id", "enforcement", "tier", "why"}`.
   `blocking` only with a zero-false-positive calibration record, written in `why`; otherwise `advisory`. `tier` is
   `commit` only for a gate whose measured warm cost for one changed file in its scope fits the commit budget
   (*Commit-tier budget*); a gate that executes a build or tests, or costs more, is `deferred` — it still runs at the
   deferred verify the push gate requires, and `tests/packs/java/test_java_gates.py` pins the exact deferred set.
4. **Release**: the Java pack ships as its own distribution. Add the module and fixtures to `packagePaths` in
   `cotterpin_pack_java/pack-release-descriptor.json` (sorted, one-line JSON — the list is exactly the pack's files),
   and make sure the `package-data` globs in `packaging/cotterpin-pack-java/pyproject.toml` cover every fixture file
   type.
5. **Tests** in `tests/packs/java/` — at least the cases of the scanner being ported, including the shapes it must NOT
   flag.

A new language pack ships the same `gates` concern (`cotterpin_pack_<id>/gates/__init__.py`): `TABLE`, `load(id)`,
`wants(path)`, `select(scope, paths, settings)`, `fixture_dir(id)`, and optionally `PRUNE`, `SHARED_SOURCES`,
`validate_settings(settings)`, `fixture_name(relative)` (the repository path a stored fixture file stands for, when a
package cannot carry it as is — the kernel stores `.cotterpin/` as `dot-cotterpin/`), and the test discovery the
kernel's ledger gates ask for: `test_file(path) -> bool` and `test_methods(path, text) -> {name: line} | None`. The
runtime (`cotterpin/kernel/gates.py`) never names a language.

A gate that names no language — it checks documents, records or configuration any repository has — belongs to the
kernel's own table, `cotterpin/kernel/kernel_gates/__init__.py`, which has exactly that contract (pack id `kernel`,
settings under `packs: kernel:`) and is the only home for such gates. Its modules, fixtures and tests follow the same
steps, with the files declared in `runtimePackagePaths` of `cotterpin/release/manifests/release-descriptor-v1.json`,
the fixtures in the root `pyproject.toml` package data, and tests in `tests/kernel/`. A kernel gate may not name a
language or its build tool (`tests/conformance/test_kernel_language_neutral.py`).

## Wave 9: input contracts, and the Java and Terraform gates

The runtime holds every gate to three contracts on its inputs (docs/product/hooks/commit-and-packs.md):
`gate-input-oversized` (an oversized input in a narrowed run is a blocking finding, never a silent skip),
`gate-population-zero` (a gate that declares `POPULATION` and judged nothing in a repository its pack serves fails,
unless it declares `VACUOUS_ALLOWED` with a reason; the standalone scanner prints `EVALUATED: <n> <subject>`) and
`gate-fixture-outside-population` (a pack gate's red fixture must be a path its scope selects; measured on the shipped
fixtures: 1 of 92 red files was not, NO-ASSERT-TEST-1's `XmlCleanupTool.java`, now under `src/test/java/`). A fixture
folder may declare the pack settings it runs under in `settings.json`.

| Gate | Pack | Tier | Enforcement | Calibration |
|---|---|---|---|---|
| OWNER-AUTHZ-1 | java | commit | advisory | built from the safety-pause create/resume/cancel trio; 166 hits on the first customer's 10,267 shipped sources with the default helper names (the repository's helper is configured through `authzChecks`), not yet hand-checked |
| CACHE-EVICT-TEST-VACUOUS-1 | java | commit | advisory | 25 hits on the first customer's 3,200 test sources, not yet hand-checked; a presence asserted in a shared set-up method is invisible to the per-method scan |
| CONTEXT-CIRCULAR-1 | java | commit | advisory | 0 cycles on the first customer's main tree (2,150 beans, 10,356 resolved injection edges; field, setter, constructor, Lombok and inherited injection, names resolved by package and import). A first draft keyed beans by simple name and reported a 29-bean cycle that was two classes sharing a name in different packages. The dynamic half is the Java pack's deferred door `java-context-circular` (each application module's own `@SpringBootTest` context built with circular references refused; docs/product/hooks/commit-and-packs.md), proven on a real Spring Boot 3.5 application whose permissive test configuration hid a field-injection cycle |
| INFRA-FALLBACK-1 | java | commit | advisory | 0 hits on the first customer's shipped sources |
| FIXTURE-VOCAB-1 | java | commit | advisory | 6 hits on the first customer's 13,467 Java sources, not hand-checked (a value written only by a migration, a script or another service is invisible to a scan of the shipped Java). A first draft that also read type/kind/mode columns had 177 hits — open vocabularies a test may invent; 5 more were negative tests' deliberately invalid values (`INVALID_STATUS`, `NOT_A_PHASE`), now recognised by name |
| SAFETY-CATCH-FAIL-CLOSED-1 | java | commit | advisory | 4 hits on 10,267 shipped sources; 2 hand-checked, both true (an unparsable age ignored so a safety filter answers safe; a fatigue check that skips its warnings on any error). A first draft that judged every catch of a safety class had 31 hits; the 27 extra were catches around notifications, logs and audit records (reporting, not deciding — 3 spot-checked), now outside the population |
| CLIENT-AUTHZ-SOURCE-1 | java | commit | advisory | 1 hit on 10,267 shipped sources, true: a coach-authorization guard that lists the coach's client ids and asks `contains()`, the source the settled ruling replaced with the active-relationship query |
| HEALTH-WINDOW-1 | java | commit | advisory | 1 hit on 10,267 shipped sources (a cache health check over a running total), not hand-checked; a first draft also reported a domain value's `isHealthy()` (a measurement, not a health check), now excluded |
| KMS-IMMUTABLE-POLICY-READS-1 | terraform | commit | blocking | an immutable key policy without the provider reads cannot be planned again and cannot be repaired |
| TF-ACCOUNT-BOUNDARY-1 | terraform | commit | blocking | judged only against the boundary the repository declares (`accountBoundary` under `packs: terraform:`) |
