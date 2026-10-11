# Platforms and repository shapes

ADR-005 F15 rows X6 (Linux first-class, Windows stated) and X8 (repository shapes). This page is for developers
installing Cotterpin on their own machine and repository.

## Which operating systems are supported

| You run | Supported | What Cotterpin does |
|---|---|---|
| macOS | yes | Cached build output is restored with APFS copy-on-write clones (`cp -c`). |
| Linux (x86_64, aarch64, containers) | yes, developer mode | Cached build output is restored with `cp -a --reflink=auto`: a copy-on-write reflink on btrfs and xfs, a normal copy on other file systems. Machine load is read from `/proc` (only with your consent, see below). |
| Windows Subsystem for Linux (WSL 2) | yes, developer mode, exactly as Linux | Detected from the kernel release string (it contains `microsoft`) and named `wsl`; it takes the Linux code path. |
| Native Windows (PowerShell, cmd, Git Bash, Cygwin, MSYS) | no | Cotterpin stops at start-up, changes nothing, and tells you to use WSL 2. |

Hardened mode (root supervisor, process isolation) is still macOS only; see
`cotterpin/platform/manifests/platform-linux-v1.json` and `platform-wsl-v1.json` for what remains to be built there.

Cached output is never restored with hard links on any platform: a build that rewrote a hard-linked file would
silently change the shared cache entry for every later run.

### `cotterpin platform`

```
cotterpin platform           # e.g. "linux (Linux 6.8.0-45-generic): supported."
cotterpin platform --json    # {"kind": "wsl", "family": "linux", "supported": true, "notes": [...], ...}
```

Exit code 0 when supported, 2 when not. It reads only the operating-system name and kernel release that Python
already holds (`uname`). It measures no hardware, opens no file and runs no command, so it needs no consent.

Under WSL, if the current directory is on a Windows drive (`/mnt/c/...`), it tells you to clone under your Linux home
instead: that file system is case-insensitive and much slower for builds.

### On native Windows

```
{"ok": false, "code": "platform-adapter-not-implemented", "platform": "windows",
 "message": "Cotterpin did not start: it does not run on native Windows. Nothing was changed. Why: ...",
 "fix": "wsl --install   (in an administrator PowerShell, once), then open the Ubuntu shell, clone the repository
         inside the Linux home directory (not under /mnt/c) and run cotterpin there"}
```

`cotterpin --version` still answers on every platform.

### Measuring machine load on Linux needs your consent

To decide how much work may run side by side, Cotterpin can read `/proc/cpuinfo` (cores), `/proc/meminfo` (total and
available memory), `/proc/stat` (CPU idle time, read twice about 0.1 s apart) and `/proc/vmstat` (whether the machine
swapped during the reading). The values stay on this machine. It does this only after you allow
"live load sampling" (`cotterpin consent`). If you decline, or have not answered, nothing is read and work runs one
task at a time. The refusal you see says exactly that and names `cotterpin consent`.

The reading fails safe: a missing or malformed value, a counter that goes backwards or does not move, or any swapping
during the reading means "do not start more work", never a guessed capacity.

## Repository shapes

### `cotterpin repo-shape`

```
cotterpin repo-shape                         # the repository containing the current directory
cotterpin repo-shape --repository path/to/project
cotterpin repo-shape --json
```

Exit codes: 0 supported (notes only), 1 at least one shape must be fixed first, 2 the path is not inside a git
repository. It reads your repository with `git` only — no lock is taken and nothing is written.

| Shape | Result | What you see / do |
|---|---|---|
| Project in a subfolder of a larger repository | supported | Git state and cache keys use the repository root; the subfolder is reported as `projectSubdirectory`. |
| Submodules (this repository contains some) | supported | Listed; each submodule is its own repository and is not part of this repository's checks. |
| This repository is a submodule | supported | Cotterpin works on this repository only; the superproject is named. |
| Shallow clone (`git clone --depth N`) | supported | When the start of a push range is older than the downloaded history, Cotterpin stops instead of checking an empty range. Next: `git fetch --unshallow`. |
| Sparse checkout | supported | The number of tracked files not on disk is reported. Checks that need them report them missing. Next: `git sparse-checkout add <directory>` or `git sparse-checkout disable`. |
| Existing linked worktrees (`git worktree add`) | supported | Reported as a linked worktree. |
| Spaces or non-ASCII characters in the path | supported | Every git call uses NUL-separated output; nothing is split on spaces. |
| Windows line endings on checkout (`core.autocrlf=true`) | supported | Cached results are keyed by committed content (git object ids), so CRLF and LF checkouts of the same commit share cache entries. |
| Git LFS files never downloaded | **stopped** | The working files are small text pointers; builds and checks would read the pointer. Next: `git lfs install && git lfs pull`. |
| Two tracked paths differing only by letter case, on a case-insensitive file system (macOS default, Windows drives) | **stopped** | One file silently overwrites the other on disk. Next: rename one, e.g. `git mv -f -- 'readme.MD' 'readme.MD.renamed'`, and commit. On a case-sensitive file system this is only a note (it will break for macOS and Windows colleagues). |

Case-insensitivity is taken from git's own `core.ignorecase`, which git measured when the repository was created;
Cotterpin does not write test files to find out.

### For integrators: the shallow-safe push range

`cotterpin.kernel.repository_shape.push_range_base(root, tip, refs)` returns the merge-base of `tip` with the first of
`refs` (remote default branch, then local) that exists. It returns `None` when none exists or histories are unrelated
with full history, and raises `RepositoryShapeError("history-too-shallow", fix="git fetch --unshallow")` when a
shallow clone lacks the shared history. A commit or push route must call it instead of treating a failed
`git merge-base` as an empty range. `require_supported(path)` raises the first "stopped" shape for routes that must
not start on an unsafe checkout.
