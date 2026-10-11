# The Angular / TypeScript pack (`cotterpin-pack-angular`)

Release 0.3.0-rc1. The Angular pack is a language pack exactly like the Java pack ([LOCK-AND-PACKS.md](LOCK-AND-PACKS.md)):
its own distribution (`cotterpin-pack-angular`, package `cotterpin_pack_angular/`), found through the
`cotterpin.packs` entry point, admitted only when a repository's lock pins its bytes. It brings ten work routes, the
`ng` door, agent hook guards, twenty-one code gates, ten skills and three route personas.

Install beside the kernel: `pip install cotterpin-pack-angular` (from a checkout:
`pip install -e . -e packaging/cotterpin-pack-angular`). `cotterpin init` recognises an Angular repository by its
`angular.json`; `cotterpin doctor` may check `node` and `npm` (each probe only with your consent).

The toolchain is the workspace's own: `node`, `npm`, and the Angular CLI from the workspace's `node_modules` —
never a global install, never `npx -y` fetching whatever is newest.

## The ten routes

Every route is one planned unit per run on the product kernel (consent, receipts, verification, a kernel commit of the
frontier), run with the same four commands:

```text
cotterpin pack angular task-plan  --task <task> [options]    # what the run would do; changes nothing
cotterpin pack angular task-start --task <task> [options]    # plan, create the run checkout, start the kernel
cotterpin pack angular task-drive --tree <tree> --run-id <id> # long: run it in the background
cotterpin pack angular task-status --tree <tree> --run-id <id>
```

| `--task` | route / manifest | deterministic step (a tool) | judgement (a writer, reviewed by another agent) | verified by |
|---|---|---|---|---|
| `upgrade` | `angular_upgrade` / `ANGULAR-UPGRADE` | `ng update @angular/core@N+1 @angular/cli@N+1` (+ Material, SSR) and its migrations; a jump over a major is refused | compiler errors of the new major (repair round) | every framework package on N+1 (residue), the installed core and CLI, build, unit tests |
| `node-ts` | `angular_node_ts_upgrade` / `ANGULAR-NODE-TS-UPGRADE` | TypeScript to the highest release in `@angular/compiler-cli`'s peer range; `engines.node` and `.nvmrc` from `@angular/core`'s `engines` | errors the newer compiler reports (repair round) | the installed TypeScript is the target and inside the range, build, unit tests |
| `standalone` | `angular_standalone_migration` / `ANGULAR-STANDALONE-MIGRATION` | `ng generate @angular/core:standalone --mode=<next mode>` (convert, prune, bootstrap — one per run) | every `TODO(standalone-migration)` the schematic leaves | no `standalone: false` or TODO left for the mode, build, unit tests |
| `feature` | `angular_add_feature` / `ANGULAR-ADD-FEATURE` | `ng generate component features/<name>` and one `loadComponent` route before the wildcard | the component and its spec from `--brief` | the route present, the build lists the feature as a LAZY chunk, unit tests |
| `api` | `angular_add_api_service` / `ANGULAR-ADD-API-SERVICE` | a typed `HttpClient` service, a functional interceptor registered in `provideHttpClient(withInterceptors([...]))`, specs on the real HttpClient with `HttpTestingController` | the model and extra calls from `--brief` | the interceptor registered, no deprecated HTTP module, build, unit tests |
| `rxjs` | `angular_rxjs_upgrade` / `ANGULAR-RXJS-UPGRADE` | RxJS to the highest release inside Angular's peer range; `rxjs/operators` imports, `throwError(value)` and positional `subscribe` callbacks rewritten | each `toPromise()` (`lastValueFrom` or `firstValueFrom`, by what the caller means) | no deprecated form left, the installed RxJS, build, unit tests |
| `strict` | `angular_strict_fix` / `ANGULAR-STRICT-FIX` | `strict` and Angular's strict template flags on in `tsconfig.json` (comments kept); `tsc` (and `ng lint`) list the errors | every file with an error, the compiler's messages as reasons | no compiler error, NO suppression added, build, unit tests |
| `lazy` | `angular_lazy_bundle` / `ANGULAR-LAZY-BUNDLE` | a baseline production build; each eager `component:` route used nowhere else becomes `loadComponent` | — | lazy chunks for each converted component and a SMALLER initial bundle, budgets kept, unit tests |
| `e2e` | `angular_add_e2e` / `ANGULAR-ADD-E2E` | `@playwright/test`, `playwright.config.ts` (`webServer` = the workspace's `ng serve`, `forbidOnly`), `e2e/*.e2e.ts`, ignores, an `e2e` script | the journeys from `--brief` | Playwright ran at least one test and none failed, build, unit tests |
| `audit` | `angular_npm_audit_fix` / `ANGULAR-NPM-AUDIT-FIX` | `npm audit fix` — never `--force`; fixes needing a new major are listed, not applied | — | npm reports no fixable vulnerability left, the count did not grow, the lock file intact, build, unit tests |

What every run shares (one workflow, `cotterpin_pack_angular/workflows/angular-task.js`, the routes' runbooks in
`cotterpin_pack_angular/runbooks/`):

1. **Preflight** — the run checkout, branch `cotterpin/<block id>` and base commit proven by git, and the kernel's
   child marker for a harness dispatch.
2. **Apply** — `cotterpin pack angular task-apply`: the workspace's packages installed (copied from a checkout with a
   byte-identical lock file, else `npm ci`), then the task's deterministic step. Judgement items name a file inside
   the task's write set and the exact reasons.
3. **Judgement / Review** — one writer per item at the Box Budget's width, each reviewed by a different agent; any
   ISSUE stops the pass.
4. **Verify** — `cotterpin pack angular task-verify`: something changed; every change inside the write set; no
   residue; the pack's blocking gates (and the task's own) clean on the changed files; the production build and the
   unit tests through the `ng` door; the task's own evidence; then the frontier. One repair round for compile or test
   errors in the write set.
5. **Closure** — a pass that will not be committed is restored by `cotterpin pack angular task-revert` (rollback: every
   changed path inside the write set back to the base commit, untracked new files deleted, anything outside it left
   alone and reported).

The kernel commits the frontier with the manifest's subject and the trailer `COTTERPIN-ANGULAR-TASK: <manifest> <block
id>`. Campaign order (`orderAfter`): `node-ts`, `standalone` and `audit` after `upgrade`; `lazy` after `standalone`.

## What Cotterpin asks you first

Each question says what, where from, why, and what happens if you decline; the answer is recorded in the plan, so the
unattended run never asks and never decides on its own.

| Question | When | If you decline |
|---|---|---|
| `angular.npm-registry` — downloads from the npm registry | planning `upgrade`, `node-ts`, `rxjs`, `e2e`, `audit` | npm runs `--offline` from your npm cache and stops naming any version it lacks; `audit` refuses (an advisory report comes only from the registry) |
| `angular.browser-download` — Playwright's Chromium | planning `e2e` | the plan refuses: the tests never run in the installed Google Chrome, which would open your keychain and profile |
| `toolchain.angular.node` — `node --version` | planning `node-ts` | not checked; `.nvmrc` names the newest major Angular's own range names |
| `angular.run-tree` — run checkouts in the temporary folder | `task-start` | the checkout is made inside the repository at `.cotterpin/runs/<run id>`, hidden from `git status` |

## The `ng` door

`cotterpin pack angular ng -- ng <command>` runs the workspace's own CLI with one run per checkout at a time (a lock in
the checkout's git folder; a second caller waits, then exits 3: run it again), `CI=1` and no analytics prompt,
`ng test` once (`--watch=false`), `ng add` with `--skip-confirmation`, `ng serve` refused (it
never exits). A test run that executed NO test fails even when `ng` exited 0. The last line is a JSON summary with the
test counts and, on failure, the compiler errors by file and line. The kernel's `raw-build-tool` guard sends a direct
`ng` here.

### No OS dialogs (NO-OS-PROMPT-1)

Cotterpin never makes macOS (or any OS) ask you for a password, keychain access or permission. A Karma `ng test`
through the door runs in a **bundled** Chromium — `CHROME_BIN` when the project sets one to a Chromium build, else
Playwright's Chromium, else Puppeteer's — through the door's own Karma launcher, `CotterpinChromeHeadless`:
`ChromeHeadless` with `--use-mock-keychain --password-store=basic --no-first-run --no-default-browser-check` and a
throwaway profile. The launcher lives in a Karma configuration the door writes under
`node_modules/.cache/cotterpin-angular/` (never a tracked file); it applies your own `karmaConfig` first, so nothing
you configured is lost. A `--browsers` naming any other browser is refused. With no bundled Chromium the door refuses
and names the command that gets one (`npx -y playwright install chromium`): it never starts the Google Chrome
installed on your machine, which asks the keychain for "Chrome Safe Storage". The end-to-end route uses Playwright's
Chromium only, with the same switches in `playwright.config.ts`.

## Hook guards

| Rule | Stops | Tier |
|---|---|---|
| `angular-npm-audit-force` | `npm audit fix --force` (new majors, Angular's included, in one step) | sensitive write |
| `angular-npm-peer-override` | `npm install --force` / `--legacy-peer-deps` (a tree whose peers do not fit) | sensitive write |
| `angular-update-skips-major` | `ng update @angular/core@<N+2 or later>` or `@latest` with the installed major known | sensitive write |
| `angular-update-unsafe-flags` | `ng update --force` / `--allow-dirty` | sensitive write |
| `angular-karma-browser` | a Karma run (`ng test`, `npm test`, `karma start`) outside the door's no-prompt launcher: plain `ChromeHeadless` starts the installed Chrome, which asks the macOS keychain | destructive |
| `angular-global-install` | `npm install -g`, `yarn global add`, `pnpm add -g` | sensitive write |
| `angular-lockfile-delete` | `rm package-lock.json` (or another lock file), `git rm` of one | sensitive write |
| `angular-long-running` | `ng serve` in the foreground; Karma `ng test` (or `npm test` running it) in watch mode | sensitive write |
| `angular-playwright-update-snapshots` | `playwright test -u` / `--update-snapshots` | sensitive write |
| `angular-strict-weakened` | an edit of `tsconfig*.json` that switches a strict check off | sensitive write |
| `angular-suppression-added` | an edit of a `.ts` file that adds `@ts-nocheck`, `@ts-ignore` or `eslint-disable` | sensitive write |
| `angular-budget-raised` | an edit of `angular.json` that raises a bundle budget | sensitive write |

Each refusal code (`hook-angular-*`) is explained by `cotterpin explain <code>` ([REFUSALS.md](REFUSALS.md)). A guard
costs under 1 ms on a call it does not match (`tests/perf/test_angular_hook_budget.py`).

## Code gates

Twelve block from install — each is a defect BY CONSTRUCTION and the calibration found no false positive — and nine
report only (advisory: a finding needs a person's judgement). Every gate has a red fixture it must flag on exactly the
marked lines and a green twin it must leave silent (`cotterpin gate fixtures NG-...`), under
`cotterpin_pack_angular/gates/fixtures/<ID>/`.

| Gate | Enforcement | Catches |
|---|---|---|
| NG-FOCUSED-TEST-1 | blocking | `fdescribe` / `fit` / `.only` — the runner skips every other test |
| NG-TS-NOCHECK-1 | blocking | `// @ts-nocheck` — the whole file is never type-checked |
| NG-E2E-NOAWAIT-1 | blocking | an unawaited Playwright web-first assertion or page action — never checked |
| NG-VERSION-SKEW-1 | blocking | framework packages declared at different majors in one `package.json` |
| NG-DEP-UNPINNED-1 | blocking | a dependency declared `*`, `latest`, `x` or empty — every install resolves differently |
| NG-RXJS-INTERNAL-1 | blocking | an import from `rxjs/internal/...` (private, changes in minor releases) |
| NG-LAZY-STATIC-IMPORT-1 | blocking | a lazily loaded route target also imported eagerly and used — it stays in the initial bundle |
| NG-INTERCEPTOR-UNREGISTERED-1 | blocking | an HTTP interceptor no other source file names — it never runs |
| NG-ROUTE-WILDCARD-ORDER-1 | blocking | a route after `'**'` in the same array — unreachable |
| NG-ROUTE-DUPLICATE-PATH-1 | blocking | a sibling route with the same path where the first always wins |
| NG-SPEC-EMPTY-1 | blocking | a test case with an empty body — passes and checks nothing |
| NG-EXPECT-NO-MATCHER-1 | blocking | `expect(value)` with no matcher called — checks nothing |
| NG-SKIPPED-TEST-1 | advisory | `xit` / `xdescribe` / `.skip('...')` |
| NG-TS-IGNORE-1 | advisory | `// @ts-ignore` (`@ts-expect-error` is the safer form) |
| NG-DOM-WRITE-1 | advisory | `innerHTML` / `outerHTML` / `insertAdjacentHTML` / `document.write` with a computed value |
| NG-BYPASS-SANITIZER-1 | advisory | `bypassSecurityTrust*` on a computed value |
| NG-NESTED-SUBSCRIBE-1 | advisory | a `subscribe` inside a `subscribe` callback |
| NG-RXJS-TOPROMISE-1 | advisory | deprecated `.toPromise()` |
| NG-E2E-FIXED-WAIT-1 | advisory | `page.waitForTimeout(...)` / `browser.sleep(...)` in an end-to-end test |
| NG-STRICT-OFF-1 | advisory | a strict check switched off in `tsconfig*.json` |
| NG-HTTP-MODULE-1 | advisory | deprecated `HttpClientModule` / `HttpClientTestingModule` |

Every gate reads TypeScript with comments, string literals and regular expressions blanked (same length, same lines),
so a word in a comment or a string never matches. Opt out of one finding with `// cotterpin:allow <ID> <reason>`.

### Calibration record

Every hit hand-checked. Blocking gates: 0 hits in all of it.

| Corpus | Files read | Blocking hits | Advisory hits (all accurate readings) |
|---|---|---|---|
| projects `ng new` generates for Angular 19, 20 and 22 | 55 | 0 | 0 |
| gothinkster/angular-realworld-example-app | 85 | 0 | 7 (5 `HttpClientTestingModule`, 1 nested subscribe in a retry timer, 1 `@ts-ignore`) |
| angular/angular: `packages/examples`, `adev/src/content/examples`, two integration apps | 973 | 0 | 3 (`bypassSecurityTrust*` in the security guide's own example and a game) |
| angular/components: `src/components-examples`, `docs/src` | 1,532 | 0 | 8 (sanitizer bypasses and `innerHTML` writes in the docs viewer, 2 `toPromise`, 2 testing modules) |

## Skills and personas

Skills (`cotterpin_pack_angular/skills/`): `angular-upgrade`, `angular-node-ts-upgrade`, `angular-standalone-migration`,
`angular-add-feature`, `angular-api-service`, `angular-rxjs-upgrade`, `angular-strict-mode`, `angular-lazy-loading`,
`angular-e2e-playwright`, `angular-npm-audit` — each says when to use the route, the steps, and the traps.
Personas (`cotterpin_pack_angular/agents/`): `angular-task-relay` (runs one pack command, copies its JSON line),
`angular-task-writer` (closes one file's items, never suppresses), `angular-task-reviewer` (accepts or raises an issue,
never edits).

## Tests

* fast tier: `tests/packs/angular/test_angular_gates.py` (every fixture; a blind gate fails red, a noisy one green),
  `test_angular_hooks.py` (each guard's red and green commands through the real protocol reader),
  `test_angular_tools.py` (versions, workspace, evidence parsers on the CLI's real output, the door, every rewrite,
  the plan store, verify's refusals, revert, the launcher up to the kernel), `test_angular_routes.py` (the kernel
  resolves and accepts all ten routes; `cotterpin tool route-check` finds nothing);
* deferred tier (real tools): `test_angular_workflow.py` (the shared workflow under real node, every branch) and
  `test_angular_routes_real.py` — each of the ten routes end to end on a workspace generated by the real
  `ng new` (19, 20 or 22), the real CLI, npm, compiler, test runner and Playwright; only the model is doubled; every
  run must end COMMIT_READY and land as one clean commit;
* perf: `tests/perf/test_angular_hook_budget.py`.

## Limits

* One workspace per repository, at the repository root (`angular.json` beside `.git`); a workspace in a subfolder is
  refused at plan time.
* `api` needs a standalone application config (`app.config.ts`): run `standalone` first on a module-based app.
* `lazy` converts routes in `app.routes.ts`; routes in `RouterModule.forRoot` arrays are module-based (run
  `standalone` first).
* `audit` never applies a fix that needs a new major; it names it.
* The gates read TypeScript, `package.json` and `tsconfig*.json`; templates (`.html`) are judged by the Angular
  compiler itself through `strictTemplates`.
