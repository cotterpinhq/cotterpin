# Tool-call rules: shell, git and file-write policy

The hook rules that judge an agent's shell commands, git commands and file writes (`cotterpin hook PreToolUse` /
`PostToolUse` on Bash, Read, Edit, Write, MultiEdit and NotebookEdit). Each rule declares ONE risk tier, and the tier
alone decides what happens ([HOOKS.md](../HOOKS.md), [SECURITY-MODEL.md](../SECURITY-MODEL.md)):

| Tier | What happens |
|---|---|
| read | runs; the rule's words reach the agent (after a command: as context it must act on) |
| sensitive write | the developer confirms this one action (refused when nobody can be asked) |
| destructive | refused until a person approves that exact action: `cotterpin approve <id>` |

A rule's code is `hook-<rule id>`; `cotterpin explain hook-<rule id>` says why it exists. Every rule is a pure reading of
the event and the repository: it writes nothing, and it runs a subprocess only after the command shape it exists for has
matched. On every other call a rule costs at most a millisecond and runs no `git` (`tests/perf/test_tool_rules_budget.py`).

## Repository settings: `toolRules` in `.cotterpin/policy.yaml`

Rules that encode a repository's own rulings read them here. A repository that sets nothing gets none of them.

```yaml
toolRules:
  protectedBranches: [main]          # commit-on-protected-branch, push-to-protected-branch
  approvalTokens: ["HUMAN-APPROVED-*"] # self-approval-token (this is also the default)
  frozen: ["frozen/*"]               # product-freeze
  archives: ["archive/*"]            # protected-archive
  sourceRoots: ["src/*"]             # shell-edit-source (time-keeping copies), route-only-source; packs add theirs
  routeOnlySource: true              # route-only-source
  deferredScopes: [cloudflare]       # cloudflare-scope
  bannedShapes: [heredoc]            # shell-heredoc
  deployScripts: [scripts/deploy.sh] # swa-in-checkout's exception
  auditLedger: [".audit/*"]          # audit-ledger-write, ledger-adhoc-read (beside .cotterpin/audit/ledger/**)
  harnessSurfaces: [".agents/*"]     # harness-surface-in-consumer (beside the built-in list)
  worktreeBudget: 8                  # worktree-add-budget
  worktreeRoot: ../worktrees         # worktree-add-budget: worktrees only here (relative to the MAIN checkout)
  reapLanded: true                   # worktree-add-budget, unlanded-work, cotterpin clean: no parked work left
  noStash: true                      # worktree-add-budget: no stash is created; destructive-git says WIP commit
  liveOutputFilter: any              # live-output-filter: every live producer, not only builds (default builds)
  testDoor: "python3 tools/ci/run_suite.py --delta HEAD --staged"  # test-run-unscoped: the delta door it names
```

Cotterpin's own repository protects `main`, bans heredocs, defers Cloudflare work, filters no live output, keeps
its worktrees in `../worktrees` beside the main checkout, reaps what has landed and bans stashes.

## Commits

| Rule | Tier | Finds | Next |
|---|---|---|---|
| `batch-commit` (enforced by default) | sensitive | a commit that leaves modified tracked files behind within an hour of the last commit; a staged file a hold pattern holds — the refusal NAMES the pattern; `*.bak-*` settings backups are held built in; a path whose hold pattern this commit removes while another worktree has it modified | `git add <files> && cotterpin commit ...` (paths a `git add` joined to the commit by `&&` names count as staged — not a dry run, `-p`/`-i`/`-e`/`-N`, an add a later `git reset`/`restore --staged` undoes, or one joined by `;`/`||`; `.` is the folder the add runs in) |
| `commit-on-protected-branch` | destructive | a commit while HEAD is a `protectedBranches` branch | commit on a topic branch and open a pull request |
| `push-to-protected-branch` | destructive | a `git push` that updates a `protectedBranches` branch on the remote: a refspec naming it (`main`, `HEAD:main`, `refs/heads/main`), no refspec from a checkout on it, or every branch (`--all`, `--mirror`, `:`) — refused before the push starts, whether or not the repository's pre-push hook (`push-protected-branch`) is installed | push your own branch and open a pull request |
| `commit-in-flight` | destructive | builds, test runs, Agent/Task/Workflow dispatches (read-only too) and file edits while a `cotterpin commit` holds the commit reservation (`<git common dir>/cotterpin/commit-reservation.json`, owner alive — `cotterpin commit` holds it for its whole route) | wait for the commit, then retry |
| `live-commit-kill` | destructive | `kill`/`pkill`/`killall` of a `cotterpin commit` process tree whose processes used the processor in the last minute — by pid, by process group (`kill -- -<pgid>`, `kill -TERM -<pgid>`, `pkill -g`), or by `pgrep ... \| xargs kill` | wait; a gate takes minutes |
| `zero-tests-ran` (enforced by default) | read after the command; destructive before a commit | a test command whose output says no test ran (pytest: `collected 0 items`, every test deselected, or exit code 5); then the session's next commit, until a run of the same runner RAN tests and passed (`testsRan` in the hook's own trajectory; `pytest --version` or a collect-only listing clears nothing). A line of readers only (`cat`, `sed`, read-only `git` such as `log`, `show`, `branch`, `worktree list`) is never a test run, whatever text it prints | fix the selection and run it again |

## Test scope

The full suite is the BASELINE: the deferred verify runs it after the commit, and its measured impact map is what a
delta run selects from. A test run by hand is the DELTA.

| Rule | Tier | Finds | Next |
|---|---|---|---|
| `test-run-unscoped` (enforced by default) | destructive | `pytest` / `python -m pytest` with no test file named, or naming a folder (an option's value such as `-k` or `--ignore` is not a selection; `--version`, `--collect-only` run nothing); `python -m unittest` with no module, or `discover`; the repository's `testDoor` run without any of the door's own options and without a test file | stage the change and run the `testDoor` (or name the test files the change reaches), then rerun only a failing test's file; a language pack judges its own build tool (`java-unscoped-test` for Maven) |
| `perf-run-by-hand` (enforced by default) | destructive | a run that selects speed budgets: a path inside a `perf` folder, `-m perf` (not `-m 'not perf'`), or the suite runner pointed at one | commit, and read the numbers from the `perf numbers` section of the deferred verify's log; its perf phase runs them alone, and only on a machine whose load is read and quiet |

## Git commands that lose work

| Rule | Tier | Finds |
|---|---|---|
| `destructive-git` | destructive (a worktree prune or remove: sensitive) | `reset --hard`, `push --force` (`--force-with-lease=<ref>` too), `clean -f`, folder-wide `checkout`/`restore` (a glob or `<folder>/` without `--` too), `checkout -f`/`switch --discard-changes`, `stash clear`, `branch -D`; `stash drop <ref>` unless `git stash show -p <sha> \| git apply --reverse --check` passes from the checkout's top AND every untracked file a `stash push -u` stored is back byte for byte (run by the rule; the refusal names the hunks and files); `worktree prune` while registrations exist; a hand-typed `worktree remove` (`--force` of a dirty tree named as such) — `cotterpin clean` is the route. With `noStash`, the next step offered is a WIP commit, never a stash |
| `unsaved-revert` | destructive | a per-file `checkout`/`restore` of a file with uncommitted changes (with or without `--`); only a `git diff` that saves a whole patch of them (not `--stat`, `--name-only`, `--cached`) counts as saved; the refusal prints the exact line that saves them first (`git diff -- f > <git common dir>/cotterpin/reverts/f.patch && ...`) |
| `archive-restore` | destructive | `git show <rev>:p > tracked` (or `\| tee tracked`, or `git cat-file -p`), `checkout`/`restore --source <rev> [--] tracked` (after any `cd` on the line) when `<rev>` is not an ancestor of HEAD — merge with `git merge-file` or `git apply --3way` |
| `run-worktree-restore` | destructive | a restore or edit in the worktree of a run whose journal is not `completed`, unless the run's `land.patch` — written only by `cotterpin clean --export <run>` (an agent's own write of a `land.patch` is refused by this rule) — has the same `git patch-id` as ALL its work: staged, unstaged and untracked |
| `tree-transfer-verify` | read after the command | `git checkout <tree> [--] p` / `git restore --source` that exited 0 but left `p` different from `<tree>:p` (blob compared with `git hash-object`; a folder with `git diff --quiet`) |
| `git-add-failed` | read after the command | a `git add` that failed part-way, with what is staged now |
| `cd-into-git-dir` | sensitive | leaving the shell inside `.git`, including `cd "$(git rev-parse --git-dir\|--git-common-dir\|--absolute-git-dir\|--git-path <x>)"` (resolved with git) |

## Patches

| Rule | Tier | Finds |
|---|---|---|
| `patch-header-safety` | destructive | `diff -u` captured (into a `.patch`/`.diff`, or any file the line then applies) or piped into an applier without `-L` labels naming the same path on both sides; `git apply` (of a file, `< file` or `cat file \|`) of a patch whose `---`/`+++` paths differ with no `/dev/null` or rename lines (git applies a rename: the target disappears) |
| `patch-apply-conflicts` | read after the command | `git apply --3way`, `am`, `stash pop\|apply` or `cherry-pick` output saying `with conflicts` or `CONFLICT (...)`, even when it exited 0 |

## Worktrees and runs

| Rule | Tier | Finds |
|---|---|---|
| `live-run-protection` | destructive (a commit or a write: sensitive) | a commit, a removal of the run's worktree, or (wave nine) any file-tool or shell write into the checkout a live run started from |
| `worktree-add-budget` | destructive | `git worktree add` while the repository holds its budget of linked worktrees not yet landed (a live run's own unit checkouts, inside the folder its journal keeps, do not count: the run removes them); by policy: an add outside `worktreeRoot`; with `reapLanded`, a new worktree or branch (`worktree add`, `branch <name>`, `checkout -b`, `switch -c`) while a worktree whose branch has landed, a branch merged into the main checkout's HEAD, a stash, or an entry of `worktreeRoot` that is not a registered worktree or its venv is left behind (a branch just started from that HEAD is in flight, not landed); with `noStash`, `git stash` / `push` / `save` / `store` — `cotterpin clean` lists and removes landed worktrees and merged branches once approved |
| `worktree-write-lease` | destructive | a write into a worktree that another LIVE agent session has claimed (`<its git folder>/cotterpin-lease.json`), including a git command that changes files there (`git -C <tree> ...`, `cd <tree> && git ...`) |
| `child-checkout-escape` | destructive | with `COTTERPIN_CHILD` set: `cd`/`pushd`, `git -C`, a path (absolute, `~`, relative such as `../other/x`, or an option's value such as `--git-dir=...`) or a Read that reaches another registered checkout |
| `ignored-config-advisory` | read after the call | a file missing in a linked worktree that the main checkout has and git ignores |

## Shell shapes

| Rule | Tier | Finds |
|---|---|---|
| `shell-heredoc` | destructive | a here-document operator on the command line (inside `sh -c '...'` too), where `bannedShapes` lists `heredoc` |
| `write-then-consume` | destructive | one line that writes a file and later hands it (`-F`, `--file`, `@file`) to a commit or another refusable command |
| `backup-in-checkout` | destructive | creating `*.bak*`, `*-backup-*`, `*.backup`, `*~`, `*.orig`, `*.ag4-backup-*` (or a `cp`/`mv`/`install`/`ln -b` backup) inside any git checkout — backups go to scratch |
| `self-approval-token` | destructive | exporting or setting as a command's environment a name in `approvalTokens`, or a value that contains one anywhere (`"$(echo HUMAN-APPROVED-x)"`) |
| `swa-in-checkout` | destructive | `swa deploy` / `npx @azure/static-web-apps-cli deploy` run in a checkout (after the line's `cd`s) or with one as the artifact folder (`--app-location <x>` or `=<x>`) |
| `shell-edit-source` | sensitive (time-keeping copies: destructive) | shell rewrites of tracked files; `cp -p`/`--preserve[=timestamps]`, `install -p`, `rsync -a`, `ditto`, `tar -x` (without `-m`), `unzip` (without `-D`) onto a source root, tracked or not |
| `release-cache-bytecode` | destructive | `python` without `-B` whose program or `PYTHONPATH` names the release cache, or that runs IN it (after a `cd`); any program run with such a `PYTHONPATH` (`pytest`) |

## Settings and policy

| Rule | Tier | Finds |
|---|---|---|
| `agent-settings-self-edit` | destructive when it widens (allow added, deny/ask removed, hooks, default mode, `disableAllHooks`, any other permission key, any top-level key but `model`, `theme`, `outputStyle` and a few like them — `statusLine`, `env`, `enabledPlugins`, `apiKeyHelper` and unknown keys widen); otherwise sensitive, including the fix of a file that does not parse (judged by what the fix grants over `{}`) | a write to the agent tool's own settings, plugins or hook scripts; a SHELL write into a skill folder (`.claude/skills`, `.codex/skills`, the repository's or the home folder's) is a sensitive write |
| `agent-settings-post-hash` | read after the command | an agent settings file modified after the command started (the start recorded by the hook for the same tool use) |
| `settings-unparseable` | destructive | every call but reads and the fix itself while an agent settings file does not parse; the error names the line. Each hook call parses the small settings files afresh |
| `denied-path-shell-write` | destructive before; read after | a shell write (or a `git checkout`/`restore`/`rm`/`mv` of the path) to a path the agent's own `Edit(...)`/`Write(...)` deny rules forbid; after the command, such a file changed while it ran |
| `policy-self-edit` | destructive | a write to a `.cotterpin` policy surface (a `git checkout`/`restore` of one included) — changes go through `cotterpin hook set` / `cotterpin approve` |
| `hold-remove` | destructive | `cotterpin hold remove` (or `python -m cotterpin hold remove`) from an agent — a hold keeps a dirty path out of builds and deploys, and only the developer releases one, in their own terminal |
| `harness-surface-in-consumer` | destructive | harness machinery written in a repository that consumes Cotterpin (only `.cotterpin/**` and the lock file are its own) |
| `product-freeze`, `protected-archive`, `cloudflare-scope`, `route-only-source` | destructive | the repository's frozen paths, archives (delete or truncate, after any `cd`; removing a folder that holds one), deferred Cloudflare work, a commit on a protected branch (one a `git switch` or `cd` earlier on the line reaches included), and hand edits of source whose FILE is outside a live run's worktree |
| `audit-ledger-write`, `ledger-adhoc-read` | destructive | writing the audit ledger, or measuring it with an ad-hoc program, the ledger named or piped in (`cotterpin audit query` reads it) |

## Reading before writing

| Rule | Tier | Finds |
|---|---|---|
| `okf-read-before-write` | destructive | an Edit, Write, Agent, Task or Workflow call, or a shell command that writes a file, before every knowledge concept (`.okf/**.md`) the latest prompt named or had injected was read WHOLE since it last changed |
| `skill-read-before-write` | destructive | the same for skills (`skills/<name>/SKILL.md`) the prompt pointed at and every skill the active route (`COTTERPIN_ROUTE_TASK`) declares; and a `cotterpin skill read` whose text is hidden (redirected, piped or `--json`) |
| `hook-module-import-check` | read after the edit | an edit or shell write of hook code (`cotterpin/hooks/**`, a pack's `hooks.py`, or a product module the hook code imports) that no longer imports, checked at once in a fresh `python -B` |

A read counts when the agent's Read tool read the file with no offset or limit after it last changed (the agent tool's
transcript says so), or when `cotterpin skill read <name|path>` printed it — that command stamps the content's sha256 in
`<git common dir>/cotterpin/reads/`, so an edit of the file needs a fresh read. Only that command writes the stamps: an agent's own write under `<git common dir>/cotterpin/reads/` is refused by `approval-integrity`.
