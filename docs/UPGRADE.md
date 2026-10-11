# Upgrading Cotterpin in a repository

`cotterpin upgrade` moves a repository from the release its lock names to another release your organisation has
approved. It does three things in one step, and writes nothing until you add `--apply`:

1. **Converts your `.cotterpin/` files** to the format the new release reads, if any changed. Every conversion is
   worked out in memory first; nothing is written unless all of them succeed.
2. **Writes the new lock** (`.cotterpin.lock.json`) for the new release, through the same approved-release check as
   `cotterpin library propose` / `apply`. An older lock format is rewritten in the current one.
3. **Starts a fresh shared cache**: every cache entry is keyed by the Cotterpin version, so nothing the old release
   made is reused. Old entries are removed by the normal size limit; nothing outside the repository is touched.

If the new lock is refused — the release is not approved on this machine, the commit is wrong, or the lock changed
meanwhile — your `.cotterpin/` files are put back exactly as they were and the old lock stays.

## Plan

```sh
cotterpin upgrade --source-repo <cotterpin-checkout> --release <release> --source-commit <commit>
```

It prints the release change, the lock format change, each file it would convert, and the exact command that applies
it. The selection — task definitions, compatibility and options — is taken from your current lock; pass
`--manifest-paths`, `--compatibility`, `--overlay` or `--release-descriptor` to change it (a repository with no lock
yet must pass the first three).

## Apply

```sh
cotterpin upgrade --source-repo <cotterpin-checkout> --release <release> --source-commit <commit> --apply
```

Review the changed files with `git diff`, then commit them together with the new lock.

## Options

| Option | Meaning |
|---|---|
| `--source-repo` | a local checkout of Cotterpin that contains the release commit |
| `--release` | the approved release name, for example `v0.3.0` (never `latest` or a branch) |
| `--source-commit` | the release's full commit id |
| `--repository` | the repository to upgrade (default: the current directory) |
| `--apply` | make the change; without it nothing is written |
| `--json` | machine-readable plan or result (always on with `--ci`) |

## When it refuses

| Code | Meaning |
|---|---|
| `upgrade-arguments` | a required name is missing, or there is no lock to take the selection from |
| `upgrade-lock-unreadable` | `.cotterpin.lock.json` exists but cannot be read |
| `upgrade-schema-newer` | a `.cotterpin/` file was written by a newer Cotterpin; upgrade to that release instead |
| `upgrade-schema-gap` | this release has no conversion for a file's format |
| `upgrade-schema-unreadable` | a `.cotterpin/` file has no readable `schemaVersion` |
| `upgrade-refused` | the new lock was refused; your files were restored |

`cotterpin explain <code>` prints the cause, fix and command for each; see [the refusal catalogue](REFUSALS.md).

## For Cotterpin maintainers: changing a file format

A release that changes the format of a versioned `.cotterpin/` file bumps its version in
`cotterpin/kernel/consumer_schema.py` (`CURRENT`) and adds one conversion step per version in `MIGRATIONS`, in the same
commit. A step takes the old file's bytes and returns the new ones, declares exactly the next version, and keeps what
it does not understand (comments included).
