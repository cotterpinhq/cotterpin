# Git hooks, agent settings and git hosts

Cotterpin works alongside the tools you already use. It never overwrites one of your hooks, never edits a settings
file outside your repository without showing you the exact change and asking, and never needs a git host. Before it
changes anything it tells you **what** it will do, **where**, **why**, and **what happens if you say no** — and saying
no (or running without a terminal and without `--yes`) always leaves things exactly as they were.

## `cotterpin hooks` — run Cotterpin's step, then your own hooks

```sh
cotterpin hooks status [--json]      # what runs on commit and push today, and which hook managers you use
cotterpin hooks install [--dry-run] [--yes]
cotterpin hooks uninstall
```

All three take `--repository <path>` (default: the current folder).

### What `install` does

1. Finds what git runs today: your `core.hooksPath` from any config (repository, user or system), or the default
   hooks folder git reports with `git rev-parse --git-path hooks`.
2. Recognises the hook managers in use: **husky** (`.husky/`), **pre-commit** (`.pre-commit-config.yaml`),
   **lefthook** (`lefthook.yml` and its variants), a configured `core.hooksPath`, or plain scripts in the hooks folder.
3. Shows you the plan and asks. If you approve, it writes small scripts into Cotterpin's own folder inside your git
   directory (`<git common dir>/cotterpin/hooks`) and points this repository's `core.hooksPath` at it.

Each script runs Cotterpin's step for that hook (today `pre-commit` and `pre-push`), then the hook that was active
before — at its original path, with the same arguments and the same input. In a repository whose
`.cotterpin/checks.yaml` declares deferred checks, the `pre-push` step is the push gate (ADR-005 F7; see
[QUICKSTART.md](QUICKSTART.md) §7): it reads the local verdict of the deferred checks for exactly the commits being
pushed, in well under a second, and refuses the push while that verdict is red, still running or missing (a missing
one is started in the background). A repository without deferred checks has no verdict to wait for, and its pushes go
on to your own hooks. This is the only place the push gate is installed; `cotterpin init` offers the same
installation. If you decline, no hook is installed and nothing reads the verdict before a push, but the deferred
verify still runs after `cotterpin commit` (`cotterpin verify-deferred --status` shows it). **If either fails, git
stops**, exactly as
it did before. Hooks without a Cotterpin step simply hand over to yours. A hook that is not executable is not run,
which is what git itself does.

None of your hook files is created, moved or edited. Your husky, pre-commit and lefthook files stay byte-for-byte as
they were, and a linked worktree shares the same installation.

### What `uninstall` does

It puts `core.hooksPath` back to the exact value it had before (or removes it if there was none) and deletes only the
files Cotterpin wrote. If another tool changed `core.hooksPath` in the meantime, Cotterpin leaves that new value alone
and tells you. If another tool rewrote one of Cotterpin's scripts, that file is kept and named.

### Hook managers: what to know

| Manager | What happens | What to do |
|---|---|---|
| husky | Runs after Cotterpin's step. Husky sets `core.hooksPath` again whenever its install script runs (usually during `npm install`) | If `cotterpin hooks status` says "NOT active", run `cotterpin hooks install` again; it chains after husky |
| pre-commit | Runs after Cotterpin's step | `pre-commit install` refuses to run while `core.hooksPath` is set, so run it **before** `cotterpin hooks install` (or uninstall, run it, and install again) |
| lefthook | Runs after Cotterpin's step | Run `lefthook install` **before** `cotterpin hooks install`; lefthook writes into whatever folder git uses for hooks |
| a shared `core.hooksPath` (e.g. company hooks in your user config) | Runs after Cotterpin's step; your user config is never changed | Nothing |
| plain scripts in the hooks folder | Run after Cotterpin's step, including hooks you add there later | Nothing |

### Refusals

Every refusal ends with `Next:` and the exact command to run.

| Situation | What Cotterpin does |
|---|---|
| Not inside a git checkout | Refuses: `cd` into your repository |
| A file Cotterpin did not write is already in its hooks folder | Refuses and names the file; it never overwrites it |
| Cotterpin's hooks are installed but another tool changed one of them | Refuses to install again: uninstall, then install |
| Cotterpin's folder is active but its record of your original setting is missing | Refuses and gives the `git config` command to restore your setting |
| Cotterpin was removed but its hooks are still installed | The hook says Cotterpin's step was skipped and why; your own hooks still run and decide |
| You decline, or there is no terminal and no `--yes` | Nothing is written; exit status 1 |

Exit status: 0 done (or already installed, or dry run), 1 declined, 2 refused.

## Agent settings — project first, your user files only with your approval

When Cotterpin needs a coding agent to allow something, it changes the **project's** settings file inside the
repository and prints the exact diff. A file outside the repository — your user-level agent settings, or a repository
path that is a link to one — is never written unless Cotterpin first shows you the exact diff and you approve it.
Declining leaves the file byte-for-byte unchanged, and Cotterpin uses project settings instead. File permissions are
kept when a file is updated, and a settings file that is not valid JSON is never overwritten.

## `cotterpin pr` — optional pull requests, on any host or none

Nothing in Cotterpin needs a git host: commits, checks and verification work in any clone. Opening a pull request is
an optional convenience.

```sh
cotterpin pr [--base <branch>] [--head <branch>] [--title T] [--body B] [--remote origin] [--host <kind>] \
             [--print-url] [--yes]
```

| Host | With your approval and the tool installed | Otherwise |
|---|---|---|
| GitHub | runs `gh pr create` | prints the compare address to open |
| GitLab | runs `glab mr create` | prints the new merge request address |
| Azure DevOps | runs `az repos pr create` | prints the pull request address |
| Bitbucket | (no official tool) | prints the new pull request address |

Cotterpin asks before it even looks for the host's tool, because running it acts on your account. Declining, a
missing tool, or `--print-url` prints the address instead. `--head` defaults to your current branch and `--base` to
the remote's default branch; if git does not know it, Cotterpin asks you to pass `--base` (or run
`git remote set-head origin --auto` once). For a self-hosted server, name its kind with `--host github|gitlab|bitbucket|azure`.

Exit status: 0 created or address printed, 1 the host's tool ran and failed (the address is printed too), 2 refused
(no remote, no branch, unknown host).
