# Java migrations: upgrade Java, remove Lombok, move to Jackson 3

Cotterpin's Java pack ships three migrations. Each one changes your code in small units — one module, or one batch of
classes — and lands each unit as its own commit once it builds and its tests pass. You never edit a manifest or a
workflow; they come with Cotterpin.

| Migration | What it changes | One unit is |
| --- | --- | --- |
| `JAVA-UPGRADE` | Raises the Java release one LTS step (8 → 11 → 17 → 21 → 25), the dependency versions that release needs, and the code the step breaks | the build file that declares the Java release, with every module that inherits it |
| `JAVA-LOMBOK-REMOVAL` | Replaces each Lombok annotation with the plain Java Lombok generated, then removes Lombok from the build | up to 10 Lombok-annotated files of one module; then one final unit for the build |
| `JAVA-JACKSON3-UPGRADE` | Moves Jackson 2 code and build coordinates to Jackson 3 | one module; then one final unit for managed versions |

## Order

- `JAVA-UPGRADE` lands before `JAVA-JACKSON3-UPGRADE`: Jackson 3 needs Java 17. If a module still builds for an older
  Java, the Jackson plan says so and tells you to run `cotterpin pack java migrate-start --manifest JAVA-UPGRADE --next`
  first.
- `JAVA-LOMBOK-REMOVAL` lands before any migration that creates DTOs or DAOs, so new code is never written against
  members Lombok generates.

When you run several migrations as one campaign (`cotterpin campaign plan`), this order is applied for you.

## Running one

```text
cotterpin pack java migrate-plan  --manifest JAVA-UPGRADE              # see every unit first (nothing is changed)
cotterpin pack java migrate-start --manifest JAVA-UPGRADE --next       # start the next unit
cotterpin pack java migrate-drive --tree <tree> --run-id <id>          # long: run it in the background
cotterpin pack java migrate-status --tree <tree> --run-id <id>
```

`migrate-start` prints the run tree and run id to pass to `migrate-drive`. Repeat `migrate-start --next` until it
prints `"complete": true`.

The plan reads what Cotterpin already knows about your repository (`cotterpin pack java facts-query`); it does not
scan your code again. To plan from a saved copy instead, pass `--facts <file>`.

## What happens in one unit

1. **Mechanical changes first.** A Cotterpin tool makes every change that has exactly one correct answer — for
   example `new Integer(5)` → `Integer.valueOf(5)`, a Lombok `@Getter` → the getter Lombok generated,
   `com.fasterxml.jackson.databind` → `tools.jackson.databind`.
2. **Judgement changes next.** Anything the tool will not change on its own — because the replacement behaves
   differently, or Lombok would generate something it does not model — goes to an AI agent with the exact reasons
   and, for Lombok, the exact members to write. A different agent reviews each change. If any review finds a problem,
   the unit stops and every change is undone.
3. **Build and test.** The unit's modules are built with their tests (the build cache is turned off for this run).
   If the compiler reports an error in a file the migration may change, one agent per file fixes it once, it is
   reviewed, and the build runs one more time.
4. **Commit or undo.** A green unit is committed through `cotterpin commit` with a `COTTERPIN-MIGRATION` trailer. A
   unit that is not green is undone, so your next run starts from a clean tree.

## What Cotterpin asks you first

Cotterpin says what it will do and why, and waits for your answer. If you decline — or nobody answers, as in CI — it
takes the slower default, and the migration still works.

| Question | What it does | Why | If you decline |
| --- | --- | --- | --- |
| `toolchain.jdk` (Java version check) | runs `java -version` | a Java upgrade compiles for a newer release; checking first turns a confusing compiler error into a clear message naming the Java version to install | the check is skipped; an older Java fails in the build itself |
| `migrate.run-tree` (working copies in the temporary folder) | creates each run's git worktree under your system temporary folder | keeps the run's checkout and build output out of your repository folder, so your IDE does not index or rebuild it | the working copy is created inside your repository's own `.git` folder |
| box measurements (`cotterpin consent`) | measures cores and memory | sizes how many agents work on judgement changes at once | judgement changes are made one at a time |

Change an answer any time with `cotterpin consent grant <id>` or `cotterpin consent revoke <id>`.

## When a unit stops

Every stop prints what happened, why, and what to run next:

| Status | What happened | What to do |
| --- | --- | --- |
| `NOTHING_CHANGED` | the unit needed no change — it was already migrated | `cotterpin pack java migrate-plan --manifest <ID> --next` plans again from the current code |
| `OUTSIDE_SCOPE` | a file the migration may not change was modified | look at the named files; the unit was undone |
| `RESIDUE` | something the migration must remove is still there (the first one is named) | run `cotterpin pack java migrate-check --manifest <ID> --path <file>` to see every leftover |
| `TOOLCHAIN_TOO_OLD` | the Java that runs your build is older than the target | install a JDK of the target release, point `JAVA_HOME` at it, and start the unit again |
| `BUILD_FAILED` | the build or a test failed after the one repair round | the Maven output named in the result shows the failure; the unit was undone |
| `JUDGEMENT_ISSUE` / `REVIEW_ISSUE` | an agent could not finish a change, or the reviewer refused it (file and line are named) | start the unit again; the next run is told why the last one stopped |

## Limits

- `JAVA-UPGRADE` plans Maven builds. A Gradle build is raised by naming its build file:
  `cotterpin pack java migrate-apply --manifest JAVA-UPGRADE --target <LTS> --path build.gradle`.
- `javax` imports move to `jakarta` only where your build already uses the jakarta namespace (Jakarta EE 9+ APIs,
  Spring Boot 3, Spring 6, Hibernate 6, or `jakarta.*` imports already in the module).
- Lombok features Cotterpin writes out mechanically: constructors, getters/setters (with access levels), `@Data`,
  `@Value`, a simple `@Builder`, `@ToString`/`@EqualsAndHashCode` (with `callSuper` and `Exclude`), `@NonNull` on
  fields, and the `@Slf4j`/`@Log`/`@Log4j`/`@Log4j2`/`@CommonsLog` loggers. Everything else is a judgement change.
- Jackson 3 changes made mechanically: package moves, the renamed exception and serializer types, modules Jackson 3
  has built in, and `ObjectMapper` configured right after it is created. A mapper configured later, stream features,
  date and time features, and custom serializers are judgement changes.
- Only files under `src/main/java` and `src/test/java`, build files (and, for Lombok, `lombok.config`) are ever
  changed.
