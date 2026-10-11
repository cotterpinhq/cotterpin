# The .NET pack

Release 0.3.0-rc1. The .NET language pack is its own distribution, `cotterpin-pack-dotnet` (package
`cotterpin_pack_dotnet/`), installed beside the kernel and admitted by your repository's lock like every pack
([LOCK-AND-PACKS.md](LOCK-AND-PACKS.md)). It gives a .NET repository:

* **one door to the dotnet CLI** — `cotterpin pack dotnet dotnet -- dotnet <anything>`;
* **twenty-one gates** for C#, project-file and container defects, fifteen of them blocking from install;
* **ten hook guards** against the toolchain's destructive or misleading commands;
* **ten task routes** — the ten things a .NET developer does most — each a real route with consent, deterministic
  tools, independently reviewed judgement, one verify lane and a kernel commit;
* one **skill** per route, three route **personas**, and `cotterpin doctor` / `cotterpin init` support.

```sh
pip install cotterpin-pack-dotnet                         # or, from a checkout: pip install -e . -e packaging/cotterpin-pack-dotnet
cotterpin doctor                                          # asks, then checks `dotnet --version` (SDK 8 or newer)
cotterpin pack dotnet task-plan --manifest DOTNET-UPGRADE --option target=10
```

`cotterpin init` recognises a .NET repository by a `*.sln`, `*.slnx`, `*.csproj`, `global.json`,
`Directory.Build.props` or `Directory.Packages.props` at its root (file names only; nothing is read).

## The dotnet door

Every dotnet command in a repository with the pack runs through `cotterpin pack dotnet dotnet -- dotnet ...`. The
kernel's `raw-build-tool` hook rule refuses a bare `dotnet build` and prints the door command with the same arguments
(`dotnet --version`, `--info`, `--list-sdks`, `--list-runtimes` and `--help` stay direct).

| what the door does | why |
|---|---|
| one writer per tree (a lock in the worktree's own git folder) | two builds of one tree race on `bin/`, `obj/` and the restore graph |
| one build at a time per machine (`build`, `test`, `publish`, `restore`, `pack`, `ef`, `package` ...) | parallel MSBuild runs starve each other and the NuGet cache |
| the build's CPU and memory booked with the kernel's capacity accounting | the harness sees the build and does not over-schedule the machine |
| `MSBUILDDISABLENODEREUSE=1`, telemetry and the first-run banner off, English output | a reused MSBuild node holds the tree's files after the build; the evidence must be readable |
| a test run that ran no test exits **88** | `dotnet test` exits 0 when a filter matches nothing ("No test matches the given testcase filter") or a test project has no test |
| the full output kept in `/tmp/cotterpin-dotnet-logs/`, and `--agent-summary` prints only the lines that matter | the log is kept whenever the run fails: read it, never re-run to see it |
| **no OS dialog, ever**: `dotnet dev-certs` (every form) is refused with exit 86 before dotnet starts; the first run never creates the HTTPS development certificate (`DOTNET_GENERATE_ASPNET_CERTIFICATE=false`); `run`/`watch` get `--no-launch-profile`, `ASPNETCORE_URLS=http://127.0.0.1:5080` and `ASPNETCORE_ENVIRONMENT=Development` unless you set them (the door prints what it added), a run asking for HTTPS or a named launch profile is refused, and so is `--interactive` (`--interactive false` passes) | each of those reads or writes the OS certificate store — a macOS keychain dialog, the Windows trust dialog — or lets a NuGet credential provider open a browser sign-in. Trusting a development certificate is the developer's own step, in their own terminal |

Exit codes: dotnet's own, 75 (the queue timed out: nothing ran), 86 (refused before the child ran), 88 (zero tests),
130 (interrupted). `run` and `watch` take the tree lock only (they serve until stopped).

## Gates

`cotterpin gate run` runs them with every other pack's ([GATES.md](GATES.md)); `cotterpin gate fixtures <ID>` proves
each one's red and green fixtures. Blocking gates are certain from the text alone (each module's docstring says what
is and is not matched); advisory gates report a likely defect whose harm depends on something a scan cannot see.

| gate | enforcement | catches |
|---|---|---|
| CS-ASYNC-VOID-1 | blocking | an `async void` method that is not an event handler |
| CS-SYNC-OVER-ASYNC-1 | blocking | `.GetAwaiter().GetResult()` inside an async method |
| CS-ASYNC-SLEEP-1 | blocking | `Thread.Sleep` inside an async method |
| CS-HTTPCLIENT-DISPOSE-1 | blocking | a new `HttpClient` in a `using` (socket exhaustion) |
| CS-THROW-EX-1 | blocking | `throw ex;` of the caught exception (stack trace lost) |
| CS-SQL-INTERP-1 | blocking | an interpolated string passed to `FromSqlRaw`/`ExecuteSqlRaw`/`SqlQueryRaw`/a `SqlCommand` |
| CS-AUTH-ORDER-1 | blocking | `UseAuthorization` before `UseAuthentication` |
| CS-JWT-NOVALIDATE-1 | blocking | `RequireSignedTokens`, `ValidateLifetime` or `RequireExpirationTime` set to false |
| CS-WORKER-NOAWAIT-1 | blocking | an async `ExecuteAsync` with no `await` (host start-up never finishes) |
| CS-HOSTED-SCOPED-1 | blocking | a DbContext injected into a hosted service's constructor |
| CS-HEALTH-UNMAPPED-1 | blocking | `AddHealthChecks()` with no `MapHealthChecks`/`UseHealthChecks` anywhere |
| NET-FLOATING-VERSION-1 | blocking | a `*` in a package version |
| NET-EOL-TFM-1 | blocking | a target framework out of support (`netcoreapp*`, `net5.0`-`net7.0`, .NET Framework before 4.6.2) |
| NET-DUPLICATE-PACKAGE-1 | blocking | one package referenced twice unconditionally in one project |
| NET-ENTRYPOINT-DLL-1 | blocking | a Dockerfile entry point `dotnet X.dll` that no project builds |
| CS-DATETIME-NOW-1 | advisory | `DateTime.Now` / `DateTime.Today` in shipped code |
| CS-LOCK-THIS-1 | advisory | `lock (this)`, `lock (typeof(...))`, `lock ("...")` |
| CS-EMPTY-CATCH-1 | advisory | a catch block with no statement and no comment |
| CS-NULLABLE-DISABLE-1 | advisory | `#nullable disable` in shipped code |
| CS-OTEL-NOEXPORTER-1 | advisory | `AddOpenTelemetry()` with no exporter anywhere |
| NET-SDK-FINAL-IMAGE-1 | advisory | a Dockerfile whose final stage runs on the .NET SDK image |

Scopes: `main` (C# outside test projects), `test`, `all`, `project` (`*.csproj`, `Directory.Build.props`,
`Directory.Packages.props`), `container` (Dockerfiles), `image` (Dockerfiles and project files). A test project is
recognised by its folder name (`tests/`, `*.Tests`, `*.UnitTests`, `*.IntegrationTests`, `*.Specs`); `bin/` and
`obj/` are never read. Every gate is commit tier.

## Hook guards

Each guard judges `dotnet` typed directly and through the door. Tiers are the kernel's ([HOOKS.md](HOOKS.md)):
a destructive action waits for a person's approval, a sensitive write is confirmed.

| rule | tier | stops |
|---|---|---|
| `dotnet-ef-remote-database` | destructive | `dotnet ef database update|drop` with a `--connection` to another host, or a Production environment |
| `dotnet-ef-drop` | destructive | `dotnet ef database drop` |
| `dotnet-ef-remove-applied` | destructive | `dotnet ef migrations remove --force` (reverts an applied migration) |
| `dotnet-nuget-publish` | destructive | `dotnet nuget push` / `dotnet nuget delete` |
| `dotnet-nuget-locals-clear` | sensitive write | `dotnet nuget locals ... --clear` (the machine-wide caches) |
| `dotnet-new-force` | sensitive write | `dotnet new ... --force` (overwrites without a diff) |
| `dotnet-warnings-silenced` | sensitive write | `-p:TreatWarningsAsErrors=false`, `-p:Nullable=disable`, `-p:NoWarn=...`, `-warnaserror-`, `-nowarn` on a build or test |
| `dotnet-quiet-verbosity` | sensitive write | `-v q` / `--verbosity quiet` (and every quiet form through the door) |
| `dotnet-global-tool-install` | sensitive write | `dotnet tool install|update --global` / `--tool-path` |
| `dotnet-os-prompt` | sensitive write | any `dotnet dev-certs`; `dotnet run`/`watch` with an HTTPS URL, an HTTPS `ASPNETCORE_URLS`/`ASPNETCORE_HTTPS_PORT`/Kestrel endpoint, or a named launch profile; any `--interactive` (each opens an OS keychain, certificate or sign-in dialog) |

Every refusal code (`hook-dotnet-*`, `dotnet-task-refused`) is explained by `cotterpin explain <code>`
([REFUSALS.md](REFUSALS.md)). A guard that does not match costs under a millisecond (measured by its test).

## The ten task routes

All ten share one workflow, `cotterpin_pack_dotnet/workflows/dotnet-task.js`, and one shape: **Preflight** (the run's
exact worktree, branch and HEAD) → **Apply** (one pack tool makes every exact change) → **Judgement** (one writer per
file the tool could not decide, each reviewed by a different agent) → **Verify** (one deterministic lane) →
**Closure** (a pass that will not be committed is reverted). The kernel commits the frontier with the manifest's
subject and the trailer `COTTERPIN-DOTNET-TASK: <manifest> <unit id>`.

| route | manifest | one run | skill |
|---|---|---|---|
| `dotnet_upgrade` | DOTNET-UPGRADE | raises one project's target framework, its framework packages and `global.json`; removed APIs become judgement | `dotnet-upgrade` |
| `dotnet_ef_migration` | DOTNET-EF-MIGRATION | raises EF Core and the local `dotnet-ef` tool, runs `dotnet ef migrations add`; proves no pending model change | `dotnet-ef-core-migrations` |
| `dotnet_webapi_endpoint` | DOTNET-WEBAPI-ENDPOINT | adds one resource's endpoints, store and integration tests | `dotnet-web-api-endpoints` |
| `dotnet_nullable` | DOTNET-NULLABLE | enables nullable reference types with the ratchet; each file's warnings become judgement | `dotnet-nullable-reference-types` |
| `dotnet_nuget_vulnerable` | DOTNET-NUGET-VULNERABLE | raises vulnerable direct packages, pins fixed transitive ones, re-checks the advisories | `dotnet-vulnerable-packages` |
| `dotnet_health_otel` | DOTNET-HEALTH-OTEL | adds liveness/readiness probes and OpenTelemetry over OTLP, with probe tests | `dotnet-health-and-telemetry` |
| `dotnet_stj_migration` | DOTNET-STJ-MIGRATION | rewrites Newtonsoft.Json to System.Text.Json with compatible options; the rest is judgement | `dotnet-system-text-json` |
| `dotnet_hosted_worker` | DOTNET-HOSTED-WORKER | adds a hosted background worker with validated options, a scope per run and tests | `dotnet-hosted-services` |
| `dotnet_jwt_auth` | DOTNET-JWT-AUTH | adds JWT bearer authentication, a secure-by-default policy and tests that bad tokens are refused | `dotnet-jwt-authentication` |
| `dotnet_containerise` | DOTNET-CONTAINERISE | writes a multi-stage, non-root Dockerfile and `.dockerignore`; proves the entry assembly is published | `dotnet-containers` |

Each route's runbook (`cotterpin_pack_dotnet/runbooks/<route>.md`) gives what one run does, the commands and the exact
arguments the kernel dispatches.

```text
cotterpin pack dotnet task-plan   --manifest <ID> [--option K=V ...] [--next]
cotterpin pack dotnet task-start  --manifest <ID> --next [--option K=V ...]
cotterpin pack dotnet task-drive  --tree <tree> --run-id <id>     # long: run it in the background
cotterpin pack dotnet task-status --tree <tree> --run-id <id>
```

The workflow's relays run `task-apply`, `task-check`, `task-verify` and `task-revert` (each prints one JSON line;
`task-verify` exits 0 only for COMMIT_READY, 3 when the build lane was busy). The verify lane:

1. refuses an empty change and any change outside the manifest's write set (build output not ignored by git is named
   as such: `dotnet new gitignore` writes the standard `.gitignore`);
2. refuses residue — what the finished task must no longer contain (a framework below the target, a Newtonsoft usage,
   a `#nullable disable`, an advisory still open ...);
3. builds the unit's project and every project that depends on it, and runs each of their test projects through the
   door — a test project that runs no test fails;
4. runs every blocking gate of the pack over the changed files, and the task's own advisory gates over the files the
   task created;
5. runs the task's own proof — EF Core: `dotnet ef migrations has-pending-model-changes`; containerise: `dotnet
   publish` into a folder outside the repository must produce the assembly the entry point runs;
6. only then returns the frontier (paths, byte states, digest) the kernel commits.

A build error or gate finding inside the write set gets ONE repair round (a writer and a reviewer per file), then one
more verify — never a whole second pass.

### What a task asks before it reads or installs anything

| consent | asked by | what it allows | on a decline |
|---|---|---|---|
| `dotnet.package-versions` | every route that writes a package version | `dotnet --list-runtimes` and `dotnet package search <id> --exact-match` (nuget.org through your NuGet configuration) | nothing is probed; the first release of the line is written (`10.0.0`, OpenTelemetry `1.15.0`) and the result says which packages to raise |
| `dotnet.vulnerability-audit` | `dotnet_nuget_vulnerable` | `dotnet list package --vulnerable --include-transitive` (your sources' advisory data) | the route stops before it changes anything |
| `dotnet.run-tree` | `task-start` with no `--tree-root` | the run's worktree in the system temporary folder | the worktree goes inside the repository's own git folder |

`dotnet-ef` is pinned as a LOCAL tool (`.config/dotnet-tools.json`) and restored with `dotnet tool restore`; nothing is
installed onto the machine, and the `dotnet-global-tool-install` guard stops an agent that tries.

## Tests

| test | tier | proves |
|---|---|---|
| `tests/packs/dotnet/test_dotnet_gates.py` | commit | registration and posture, every gate's fixtures, that a blind or trigger-happy gate fails them, the lexer, `cotterpin gate run` |
| `tests/packs/dotnet/test_dotnet_hooks.py` | commit | every guard fires directly and through the door and spares its neighbour; under 1 ms when it does not match |
| `tests/packs/dotnet/test_dotnet_tasks.py` | commit | project-file edits that keep formatting, the recipes' exact rewrites, plans, manifests, routes and their write sets |
| `tests/packs/dotnet/test_dotnet_tasks_real.py` | deferred (real dotnet) | all ten routes on projects made by the real templates reach COMMIT_READY; zero-test, gate and revert refusals |
| `tests/packs/dotnet/test_dotnet_route_real.py` | deferred (real node, real dotnet) | the workflow's control flow, and two whole routes with every relay running the real pack tools |
| `tests/packs/dotnet/test_dotnet_door_real.py` | deferred (real dotnet) | the door's evidence (exit 88 on zero tests), locks, summaries and refusals |

With `COTTERPIN_REAL_TOOLS=require` an absent .NET SDK fails the deferred tier instead of skipping it.
