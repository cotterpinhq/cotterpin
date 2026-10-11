# Java build tools: Maven and Gradle

Cotterpin builds and tests Java projects with the build tool the project already uses, the way the project and your
own settings say. It never replaces your settings, and it asks before it looks at anything on your machine.

## Which tool, and which executable

| Project has | Cotterpin uses |
|---|---|
| `pom.xml` | Maven |
| `settings.gradle(.kts)` or `build.gradle(.kts)` | Gradle |
| both | whichever `.cotterpin/java.json` names: `{"buildTool": "maven"}` or `{"buildTool": "gradle"}` |

Cotterpin uses the project's own wrapper when it has a complete one, because the wrapper pins the build-tool version
the project was built with:

- Maven: `mvnw` (`mvnw.cmd` on Windows) with `.mvn/wrapper/maven-wrapper.properties`.
- Gradle: `gradlew` (`gradlew.bat` on Windows) with `gradle/wrapper/gradle-wrapper.properties` and
  `gradle-wrapper.jar`.

If the wrapper is incomplete, Cotterpin tells you which file is missing and uses `mvn` or `gradle` from your `PATH`.
If neither exists, it stops before running anything and tells you how to install the tool or add the wrapper
(`mvn wrapper:wrapper`, `gradle wrapper`). A wrapper script that is not executable is run with `sh`, and Cotterpin
tells you to fix it with `chmod +x mvnw`.

Every Maven run that goes through `cotterpin pack java maven -- mvn ...` uses the wrapper the same way. You still type
`mvn`.

## Your settings are honoured and never overwritten

Maven reads `~/.m2/settings.xml`, `$MAVEN_HOME/conf/settings.xml`, `.mvn/maven.config` and `MAVEN_ARGS` itself, and
Gradle reads `~/.gradle/gradle.properties` and its init scripts itself. Cotterpin passes no settings file, mirror,
repository or proxy of its own, and it writes none of those files. Your own `-s`, `-gs` and `-t` (Maven) or `-g` and
`-I` (Gradle) options are passed through unchanged:

```
cotterpin pack java build-tool compile -- -s ~/work/settings.xml
```

`cotterpin pack java build-tool info` shows the mirrors, repositories and proxies a build will use. It never shows a
user name, password, passphrase, private key, token, or the login part of a URL. Servers are listed by id only. Any
`-D`/`-P` option whose name looks like a credential is shown as `<redacted>`.

## Which Java version

The project says which Java version it needs: `maven.compiler.release` (or the compiler plugin's `<release>`), or the
Gradle toolchain (`JavaLanguageVersion.of(21)`, `jvmToolchain(21)`, `sourceCompatibility`). If you allow the Java scan
(below), Cotterpin finds that version among your installed JDKs and builds with it, even when your default Java is
different. It uses a JDK of exactly that version if you have one, otherwise the closest newer one. If `JAVA_HOME`
already matches, `JAVA_HOME` is used. For Gradle, the JDKs it finds are passed as
`org.gradle.java.installations.paths`, and Gradle chooses the toolchain the build script asks for.

If no installed JDK is suitable, Cotterpin says which version to install, for example `sdk install java 21-tem`.

## What Cotterpin asks before looking

| Question | What is read | Why | If you decline |
|---|---|---|---|
| `toolchain.jdk-scan`: Installed Java versions | `$JAVA_HOME`, `/usr/libexec/java_home -V` (macOS), the SDKMAN (`$SDKMAN_DIR` or `~/.sdkman`) and asdf (`$ASDF_DATA_DIR` or `~/.asdf`) install directories, `~/.m2/toolchains.xml`, and each JDK's `release` file | to build with the Java version the project needs | the build uses `JAVA_HOME`, or the `java` on your `PATH`, exactly as it is set now. Nothing is scanned |
| `toolchain.build-settings`: Build tool settings | `~/.m2/settings.xml`, `$MAVEN_HOME/conf/settings.xml`, a `-s`/`-gs` file you pass, `~/.gradle/gradle.properties` (never a credential) | to show which mirror, repository and proxy your builds will use | Maven and Gradle still read your settings themselves, unchanged. Cotterpin does not open them |

Cotterpin asks once, on a terminal, and remembers your answer. To change an answer, run
`cotterpin consent grant <id>` or `cotterpin consent revoke <id>`. To answer for one command only, add
`--consent toolchain.jdk-scan` or `--no-consent`. In a non-interactive shell or in CI, an unanswered question counts
as declined.

Finding the wrapper or the tool on your `PATH` reads only the project and `PATH`. It is the default every decline falls
back to, so Cotterpin does not ask about it.

## Commands

```
cotterpin pack java build-tool info [--root DIR] [--json]
cotterpin pack java build-tool compile [--module DIR ...] [-- settings options]
cotterpin pack java build-tool test --module DIR com.example.FooTest#bar [com.example.BazTest ...] [-- settings options]
```

A module is a directory relative to the project root. `.` is the root project. For Gradle, modules come from the
`include` lines of `settings.gradle(.kts)`, including `project(':x').projectDir = file('dir')`. Gradle module lists
that are computed in code, and `includeBuild` composite builds, are not seen.

`test` runs exactly the tests you name: `-Dtest=` for Maven (built with the Maven build cache off) and `--tests` for
Gradle. The result is decided by the test reports this run wrote, not by the exit code alone. Maven reports are in
`target/surefire-reports` and `target/failsafe-reports`, and Gradle reports are in `build/test-results/test`.

| Exit | Meaning | What to do |
|---|---|---|
| 0 | every named test ran and passed | nothing |
| 1 | a named test failed | read the failure in the report or the build log |
| 2 | the request was refused before anything ran (wrong selector, unknown module, an option after `--` that is not a settings option) | follow the message |
| 86 | the reports and the exit code disagree | read the build log. Its path is printed first |
| 88 | the build exited 0, but no fresh report holds a named test, or the test was skipped | check the test name, and check that the test compiles. A test that did not run proves nothing |

The build log is always kept when a build fails. Read it instead of running the build again.

## Box Budget calibration

When the Box Budget is installed and you allow its calibration run, Cotterpin times one compile of the project's
smallest module. This prices the `build` kind of work on your machine, so a slower machine gets smaller batches.
A compile that fails leaves the `build` work unpriced.

## The door's own refusals (wave nine)

`cotterpin pack java maven -- mvn ...` refuses, before anything queues: a `package`/`install`/`deploy` while a path held
in this checkout is dirty (`build-held-path-dirty`; `cotterpin hold check --dirty` names them), and a test-phase run
with no `-Dtest`/`-Dit.test` selector unless `COTTERPIN_FULL_SUITE_APPROVAL` names a request a person approved, bound to
`java-full-suite:<reactor root>` (`hook-java-unscoped-test`). The agent hook refuses the same command first
(`java-unscoped-test`, destructive), and `-pl` without `-am` (`java-pl-without-am`). A receipt run scheduled by a
product route (`--destub-receipt`) keeps its own selection contract and is not judged here.
