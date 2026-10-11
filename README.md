# Cotterpin

**Guardrails for AI coding agents.**

Your agent ran the suite, saw green, and told you it was finished. It wasn't. Cotterpin checks every "done" on your
machine, before the commit: real builds, the tests your change actually reaches, an adversary that tries to break the
fix, and receipts bound to the exact inputs they checked. It works with the agents you already use: Claude Code,
Codex and Grok.

| | |
|---|---|
| Website | <https://cotterpin.io> |
| PyPI (where Cotterpin is released) | [pypi.org/project/cotterpin](https://pypi.org/project/cotterpin/) |
| npm (name reservation) | [npmjs.com/package/cotterpin](https://www.npmjs.com/package/cotterpin) |
| Changelog | <https://cotterpin.io/changelog.html> |

## Status

**Cotterpin 0.3.0 is the first working release, and it is in preparation.** It will be released on
[PyPI](https://pypi.org/project/cotterpin/). Until then, the packages named `cotterpin` on PyPI and
[npm](https://www.npmjs.com/package/cotterpin) are name reservations that install nothing useful. Watch this
repository's releases or <https://cotterpin.io/changelog.html> for 0.3.0.

**Founding Developers:** the first 50 developers on each language pack use Cotterpin Pro free.
[See the offer and apply](https://cotterpin.io/pricing/#founding).

## What is in this repository

| Folder | What it holds |
|---|---|
| [`docs/`](docs/) | The developer documentation: the same pages Cotterpin installs with itself. Start with [QUICKSTART.md](docs/QUICKSTART.md). |
| [`install/`](install/) | The installer scripts, so you can read exactly what they do before you run them. |

Cotterpin's source is not published here: it is proprietary software (see [LICENSE.md](LICENSE.md)).

## Installing (from 0.3.0)

On macOS, or in Ubuntu under Windows WSL:

```sh
curl -fsSL https://cotterpin.io/install.sh | sh -s -- --pack java    # the packs you use: java python angular dotnet terraform
```

The installer asks before it checks your machine and again before it installs anything, needs no administrator
password, and prints the commands instead if you say no. Its source is [install/install.sh](install/install.sh). The
whole walk-through, from install to a first green run, is [docs/QUICKSTART.md](docs/QUICKSTART.md).

## Your code stays on your machine

Cotterpin runs locally. It never receives your source, diffs or prompts: only your chosen model provider sees your
code, under your own account. What Cotterpin reads and sends, and when it asks first, is in
[docs/PRIVACY.md](docs/PRIVACY.md) and [docs/CONSENT-AND-BOX.md](docs/CONSENT-AND-BOX.md).

## Language packs

Java, Python, Angular, .NET and Terraform: [docs/LOCK-AND-PACKS.md](docs/LOCK-AND-PACKS.md) and each
`docs/PACK-*.md`.

## Reporting a problem

- A bug: `cotterpin report-bug` shows you exactly what a report carries before anything is sent
  ([docs/OBSERVABILITY.md](docs/OBSERVABILITY.md)).
- A security issue: see [SECURITY.md](SECURITY.md). Please do not open a public issue for it.

## Licence

Proprietary. © 2026 Cotterpin Technologies Ltd. See [LICENSE.md](LICENSE.md).
