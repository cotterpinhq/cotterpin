# Quickstart: from install to your first green run

Target: under 10 minutes on a machine that already has git and one agent CLI. You need no administrator rights,
no AWS account and no hardware key. Those are for the optional enterprise mode only.

Cotterpin asks before it looks at your machine. Every check says **what** it will read, **where from** and **why**.
You can say no to any of them. A check you decline is skipped and Cotterpin uses its safe default. In a script or CI
job nothing is probed unless you pass `--consent`.

## 1. Install (about 1 minute)

On macOS, or in Ubuntu under Windows WSL:

```sh
curl -fsSL https://cotterpin.io/install.sh | sh -s -- --pack java    # the packs you use: java python angular dotnet terraform
```

It asks twice and does nothing you have not agreed to:
1. May it check this machine? It reads version numbers only (Python, git, uv), and nothing leaves the machine.
2. May it install what is missing? These go in your home folder, with no admin password: uv (checked against its
   published checksum), Python 3.13.14 through uv when you have no Python 3.11 or newer, and Cotterpin in its own
   environment.

If you say no, it prints the commands instead. It never changes `pyenv global`, `.python-version` or your system
Python. On native Windows, `irm https://cotterpin.io/install.ps1 | iex` explains WSL and offers `wsl --install`.
The script is `packaging/installer/install.sh`, so you can read it before you run it.

To install by hand instead: Cotterpin needs Python 3.11 or newer, and the built-in `python3` on macOS is 3.9.

```sh
uv tool install --python 3.13 cotterpin --with cotterpin-pack-java   # or: pipx install --python python3.12 cotterpin
cotterpin --version                                                  # names the packs it found
```

The packs are `cotterpin-pack-java`, `-python`, `-angular`, `-dotnet` and `-terraform`. Without the right one,
`cotterpin init` (next step) says no language pack recognised your repository. To get enterprise mode (AWS-backed authority, release signing and hardware
keys), install `cotterpin[enterprise]` instead. You don't need it for anything on this page.

**The short way: `cotterpin setup`.** In your repository, `cotterpin setup` walks you through every step on this
page that sets something up, one at a time. For each step it says what the step is, why you might want it, and
whether it is recommended. You install it, skip it for now, or stop, and the next `cotterpin setup` carries on where
you stopped. It starts by measuring this machine (with your yes), so later steps run as much in parallel as the
machine can take. `cotterpin setup --quick` installs every recommended step, after listing them.
`cotterpin setup --status` shows each step, and `--add <step>` or `--remove <step>` changes your mind later. See
[ONBOARDING-COMMANDS.md](ONBOARDING-COMMANDS.md#cotterpin-setup). The sections below are the same steps one at a time.
Later, `cotterpin speed` lists what would make your work faster here, applies only what you accept, and reports
before → after from commits made on a quiet machine
([ONBOARDING-COMMANDS.md](ONBOARDING-COMMANDS.md#cotterpin-speed)).

## 2. Set up your repository (under 1 minute)

```sh
cd path/to/your-repository
cotterpin init
```

`init` asks once whether it may list the file names at the top of your repository. It uses them to pick a language
pack (it looks for `pom.xml`, `mvnw`, `build.gradle` and similar names). It never reads file contents. If you say no,
pick the pack yourself:

```sh
cotterpin init --pack java
```

It writes three things, all inside the repository:

| File | What it is | What to do |
|---|---|---|
| `.cotterpin/policy.yaml` | what this repository selects: developer mode and its packs | review, then commit |
| `.cotterpin.lock.json` | pins this Cotterpin version and each pack's digest | commit |
| `.gitignore` (one marked block) | ignores `.cotterpin/local/`, Cotterpin's per-developer state | commit |

It never overwrites an existing policy or lock. Use `--dry-run` to see the plan without writing anything.

## 3. Check your machine (1–2 minutes)

```sh
cotterpin doctor
```

You get one line per prerequisite:

```
  PASS  git: git 2.44.0
  PASS  Python: Cotterpin runs on Python 3.12.4; python3 on PATH is 3.12.4
  FIX   node: node was not found on PATH
        why: the product workflows that drive a run execute on Node.js
        fix: install Node.js 18 or newer: `brew install node` (macOS), `sudo apt install nodejs` (Debian/Ubuntu) or https://nodejs.org
  PASS  agent CLI: claude 2.1.3
  PASS  JDK (java): 21.0.2
  PASS  Maven (mvn): the repository's ./mvnw provides it
  PASS  provider sign-in: signed in: claude
  PASS  free disk space: 120.3 GiB free
```

Run each `fix:` command, then run `cotterpin doctor` again until no line says FIX. A `SKIP` line is a check you
declined. Its `to check it:` line gives the command that runs only that check.

## 4. Sign in to a provider (1 minute, if doctor said so)

```sh
claude auth login        # or: codex login
cotterpin connect        # confirms the sign-in; Cotterpin stores no provider secret
```

## 5. Commit the setup

```sh
git add .cotterpin .cotterpin.lock.json .gitignore
cotterpin commit -m "Set up Cotterpin"
```

A repository fresh from `init` declares no checks yet, so this commit runs only Cotterpin's own staged-set checks.

## 6. Your first green run

Declare your own checks in `.cotterpin/checks.yaml` (the format is in
[CONTRACT-AND-EXTENSIONS.md](CONTRACT-AND-EXTENSIONS.md) and `cotterpin/kernel/consumer_checks.py`), then pin them.
Your checks run your tests, so name the interpreter of your project's own environment, the one with your test runner
and packages, under `tools`. Cotterpin's own (the one pipx made) has neither, and `cotterpin doctor` says FIX until
the line is there:

```yaml
tools:
  python: ~/src/your-repository/.venv/bin/python   # absolute, or under your home with ~/
```

```sh
cotterpin update         # pins .cotterpin/checks.yaml and its resolver in .cotterpin.lock.json
git add .cotterpin .cotterpin.lock.json && git commit -m "Declare our checks"
cotterpin check          # runs your repository's own checks through Cotterpin
```

`cotterpin init` pins the catalog for you when it already exists. Whenever you change the catalog or its resolver,
run `cotterpin update` again and commit the lock with it: a check can only be dropped or changed in a commit that
shows the change to a reviewer. Until then `cotterpin check` refuses and names `cotterpin update`
(`cotterpin explain check-policy-unpinned`).

Both kinds of commit also go through `cotterpin commit`, and a commit is never judged by checks it adds or weakens:

* **The commit that adds the catalog** (HEAD pins none) is judged by the catalog it adds, once the staged lock pins
  it. `cotterpin commit` says so: `adopting commit: …`.
* **A commit that changes the catalog, its resolver, the policy or the lock** is judged by the catalog and resolver
  committed at HEAD; the new ones apply from the next commit. `cotterpin commit` says so in one line. Dropping a check
  and, in the same commit, breaking what it guards is refused by the check you dropped.

Product routes run a task end to end through Cotterpin, for example the Java de-stub route (ADR-005 F4/F10). They
start from here once they are installed with your pack. `cotterpin pack java --help` lists the pack's tools.

## 7. The everyday loop: commit in seconds, verify before the push

Give each check a tier. A check that runs a whole test suite or a build is `tier: deferred`; everything else stays in
the default `commit` tier (`cotterpin check --profile` measures which is which). A check whose verdict reads comment
text, or depends on anything besides its declared files, says `reuse: never`.

```yaml
checks:
  - {selector: tools.checks.test_lint, route: pre-commit}                       # commit tier, receipt reused
  - {selector: tools.checks.test_suite, route: pre-commit, tier: deferred}      # runs before the push
```

```sh
cotterpin hooks install  # once: chains Cotterpin's push gate in front of your own pre-push hook (it asks first)
git add -p
cotterpin commit -m "…"  # the commit tier against what you staged, then git commit; the deferred checks start detached
git push                 # allowed with a green deferred verdict for exactly what you push
```

* **`cotterpin commit`** runs only the commit tier, against the staged snapshot, and refuses a staged file whose
  working copy differs. A check the staged change cannot affect reuses its receipt and costs nothing. Then it commits
  and starts the deferred tier detached, over everything you have not pushed yet.
* **`git push`** asks the push gate. Green: the push goes. Red: refused, naming the log of the failing run. Still
  running, or no verdict yet: refused, with the command that waits for it
  (`cotterpin verify-deferred --wait`); a missing verdict is launched for you. A verdict belongs to the exact tree
  it judged, so a green verdict for an earlier commit never lets a later one through. The gate answers in under a
  second.
* **Parallel.** How many checks run at once is sized to your machine only with your consent
  (`cotterpin consent`, see [CONSENT-AND-BOX.md](CONSENT-AND-BOX.md)), or from widths you declare in
  `.cotterpin/box.yaml`. Without either, everything runs one at a time: slower, never different.

Cotterpin develops itself with exactly this loop: DEVELOPING-COTTERPIN.md.

## Changing your mind

```sh
cotterpin uninstall      # this repository: lists what it will remove, then asks
cotterpin --uninstall    # this whole machine: every repository it set up, caches, settings, your seat, itself
cotterpin cache du       # how much disk Cotterpin's cache uses, and its cap
cotterpin cache gc       # shrink the cache to its cap (default 10 GiB; --max-size 2G to choose)
cotterpin cache clear    # empty the cache; the next runs rebuild what they need
```

`uninstall` removes exactly what Cotterpin added. On an untouched repository, `git status` is clean afterwards. A file
you committed or edited is yours, so it is kept, and the command to remove it is printed.

`cotterpin --uninstall` removes Cotterpin from the whole machine. It lists every group first: the repositories it set
up, its caches, its configuration folder, this machine's seat on your licence, any administrator parts of a hardened
install, and finally Cotterpin itself. It says why each one goes and how to remove anything it keeps by hand, then
asks once. Answer `e` to keep an export of the audit log first. Run `cotterpin --uninstall --dry-run` to see the list
without changing anything. See [ONBOARDING-COMMANDS.md](ONBOARDING-COMMANDS.md) for every option.
