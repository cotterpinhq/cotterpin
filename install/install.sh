#!/bin/sh
# Cotterpin installer for macOS and Linux (including Windows WSL).
#
#   curl -fsSL https://cotterpin.io/install.sh | sh
#   sh install.sh --yes          # answer yes to both questions
#   sh install.sh --print-only   # check nothing, install nothing: print the commands
#
# It asks twice, and does nothing you have not agreed to:
#   1. May it check this machine? It reads version numbers only. Nothing leaves the machine.
#   2. May it install what is missing? Everything goes in your home folder; no admin password, no sudo.
# A "no", or no terminal to ask in, prints the commands instead. It never changes `pyenv global`,
# `.python-version` or your system Python: Cotterpin gets its own environment (uv tool install).
set -eu

UV_VERSION=0.12.23
PYTHON_VERSION=3.13.14
PYTHON_MINIMUM=3.11
UV_MINIMUM=0.5.0
COTTERPIN_SPEC=${COTTERPIN_SPEC:-cotterpin}
BIN_DIR=${COTTERPIN_BIN_DIR:-$HOME/.local/bin}
UV_URL=${COTTERPIN_INSTALL_UV_URL:-https://github.com/astral-sh/uv/releases/download}
PATH_MARKER="# added by the Cotterpin installer"

# uv's published release checksums for UV_VERSION, carried here so a download is checked against this script, not
# only against the server it came from.
uv_sha256() {
  case $1 in
    aarch64-apple-darwin) echo 50487ae565ccd96e499056b4674d438f4c53170202617b4c759defe0c6a1b544 ;;
    x86_64-apple-darwin) echo 960da44cb4b73685206ddd250b19e0a117fa41095710c1038f081f5cb613efb4 ;;
    x86_64-unknown-linux-gnu) echo 9167d72b3319674b6303c4cbe071854bba13ebdf3d76b1a7cbdc175471fb66d6 ;;
    aarch64-unknown-linux-gnu) echo 6524bd338177ed50d035d39354e12545e993bbeba2ecbddf0480c5b3a81d313f ;;
    *) echo "" ;;
  esac
}

say() { printf '%s\n' "$*"; }
die() { printf 'cotterpin installer: %s\n' "$*" >&2; exit 1; }

usage() {
  say "Usage: sh install.sh [--yes | --print-only] [--pack <name>]..."
  say "  --yes         answer yes to both questions (check this machine, install what is missing)"
  say "  --print-only  check nothing and install nothing; print the commands to run yourself"
  say "  --pack NAME   add a language pack: java, python, angular, dotnet or terraform (repeat for more)"
}

mode=ask
packs=""
with_packs=""
expect_pack=n
for argument in "$@"; do
  if [ "$expect_pack" = y ]; then
    case $argument in
      java|python|angular|dotnet|terraform) packs="$packs $argument"; with_packs="$with_packs --with cotterpin-pack-$argument" ;;
      *) die "unknown language pack: $argument (java, python, angular, dotnet or terraform)" ;;
    esac
    expect_pack=n
    continue
  fi
  case $argument in
    --yes|-y) mode=yes ;;
    --print-only|--no) mode=print ;;
    --pack) expect_pack=y ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $argument" ;;
  esac
done
[ "$expect_pack" = n ] || die "--pack needs a name: java, python, angular, dotnet or terraform"

# An AI agent never answers for the person: it gets the commands, and the person runs them.
if [ -n "${CLAUDECODE:-}" ] && [ "$mode" != print ]; then
  say "An AI agent is running this installer, so it will not ask or install: these are the commands for you to run."
  mode=print
fi

# Answers come from the terminal even when the script itself arrives on stdin (curl ... | sh).
if [ "$mode" = ask ]; then
  input=${COTTERPIN_INSTALL_INPUT:-/dev/tty}
  if ( exec 3<"$input" ) 2>/dev/null; then
    exec 3<"$input"
  else
    say "No terminal to ask in, so nothing is checked or installed: these are the commands to run yourself."
    mode=print
  fi
fi

ask() {
  case $mode in
    yes) say "$1 [y/N] y (--yes)"; return 0 ;;
    print) return 1 ;;
  esac
  printf '%s [y/N] ' "$1"
  answer=""
  IFS= read -r answer <&3 || answer=""
  case $answer in y|Y|yes|Yes|YES) return 0 ;; esac
  return 1
}

# "y" when version $1 is at least $2 (major.minor.patch, missing parts count as 0).
at_least() {
  printf '%s\n%s\n' "$2" "$1" | awk -F. '
    NR == 1 { for (i = 1; i <= 3; i++) need[i] = $i + 0 }
    NR == 2 { for (i = 1; i <= 3; i++) { have = $i + 0
                if (have > need[i]) { print "y"; exit } if (have < need[i]) { print "n"; exit } }
              print "y" }'
}

# ── where are we (uname only: no probe) ─────────────────────────────────────────────────────────────────────────────
system=$(uname -s)
machine=$(uname -m)
case $machine in arm64|aarch64) arch=aarch64 ;; x86_64|amd64) arch=x86_64 ;; *) arch=$machine ;; esac
case $system in
  Darwin) platform=macOS; target=$arch-apple-darwin ;;
  Linux)
    case $(uname -r) in *[Mm]icrosoft*) platform="Windows (WSL)" ;; *) platform=Linux ;; esac
    target=$arch-unknown-linux-gnu ;;
  MINGW*|MSYS*|CYGWIN*|Windows*)
    die "Cotterpin runs inside WSL on Windows. In PowerShell (as administrator) run: wsl --install
then restart, open Ubuntu, and run this installer there." ;;
  *) die "Cotterpin supports macOS and Linux (including Windows WSL); this is $system." ;;
esac
[ -n "$(uv_sha256 "$target")" ] || die "Cotterpin has no build of uv for $platform on $machine."

case $BIN_DIR in "$HOME"/*) shown_bin="~${BIN_DIR#"$HOME"}" ;; *) shown_bin=$BIN_DIR ;; esac
case ${SHELL:-} in
  */zsh) profile=$HOME/.zshrc ;;
  */bash) if [ "$system" = Darwin ]; then profile=$HOME/.bash_profile; else profile=$HOME/.bashrc; fi ;;
  *) profile=$HOME/.profile ;;
esac
shown_profile="~${profile#"$HOME"}"

print_commands() {
  say ""
  say "To install Cotterpin yourself (skip any step you already have):"
  say "  # uv $UV_VERSION, which installs Python tools; check its checksum against https://github.com/astral-sh/uv/releases"
  say "  curl -fsSLO $UV_URL/$UV_VERSION/uv-$target.tar.gz"
  say "  echo '$(uv_sha256 "$target")  uv-$target.tar.gz' | shasum -a 256 -c -    # Linux: sha256sum -c -"
  say "  tar -xzf uv-$target.tar.gz && mkdir -p $shown_bin && cp uv-$target/uv uv-$target/uvx $shown_bin/"
  say "  # Python $PYTHON_VERSION, only if you have no Python $PYTHON_MINIMUM or newer"
  say "  $shown_bin/uv python install $PYTHON_VERSION"
  say "  # Cotterpin, in its own environment"
  say "  $shown_bin/uv tool install --python $PYTHON_VERSION $COTTERPIN_SPEC${with_packs:- --with cotterpin-pack-<language>}"
  say "  # $shown_bin on your PATH"
  say "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> $shown_profile"
  say "Then open a new terminal and, in your repository, run: cotterpin init"
}

say "Cotterpin installer — $platform ($machine)"
say ""
say "Cotterpin would like to check this machine for what it needs:"
say "  Python $PYTHON_MINIMUM or newer, git, and uv (installs Python tools)."
say "  It only reads version numbers. Nothing leaves this machine."
if ! ask "Check now?"; then
  [ "$mode" = print ] || say "Nothing was checked."
  print_commands
  exit 0
fi

# ── the check: version numbers only ─────────────────────────────────────────────────────────────────────────────────
say ""
problems=""

# Apple's git is a stub that opens an installer window when the command line tools are missing: look first.
git_ok=n
if [ "$system" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then
  say "  missing  Apple's command line tools (they provide git)"
  problems=clt
elif command -v git >/dev/null 2>&1; then
  say "  ok       $(git --version 2>/dev/null)"
  git_ok=y
else
  say "  missing  git"
  problems=git
fi

uv_bin=""
for candidate in "$BIN_DIR/uv" "$(command -v uv 2>/dev/null || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] || continue
  version=$("$candidate" --version 2>/dev/null | awk '{print $2}') || version=""
  if [ -n "$version" ] && [ "$(at_least "$version" "$UV_MINIMUM")" = y ]; then
    uv_bin=$candidate
    say "  ok       uv $version ($candidate)"
    break
  fi
done
[ -n "$uv_bin" ] || say "  missing  uv"

python_bin=""
for name in python3.13 python3.12 python3.11 python3; do
  candidate=$(command -v "$name" 2>/dev/null) || continue
  version=$("$candidate" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null) || continue
  if [ "$(at_least "$version" "$PYTHON_MINIMUM")" = y ]; then
    python_bin=$candidate
    say "  ok       Python $version ($candidate)"
    break
  fi
done
[ -n "$python_bin" ] || say "  missing  Python $PYTHON_MINIMUM or newer"

others=""
old_ifs=$IFS
IFS=:
for directory in $PATH; do
  [ -n "$directory" ] && [ "$directory" != "$BIN_DIR" ] && [ -x "$directory/cotterpin" ] && \
    others="$others $directory/cotterpin"
done
IFS=$old_ifs

on_path=n
case ":$PATH:" in *":$BIN_DIR:"*) on_path=y ;; esac
[ "$on_path" = y ] || say "  missing  $shown_bin on your PATH"

case $problems in
  clt)
    say ""
    say "Apple's command line tools must be installed first. A window opens; it takes about 10 minutes."
    if ask "Open Apple's installer now?"; then
      xcode-select --install || true
      say "When it has finished, run this installer again."
    else
      say "Run it yourself with: xcode-select --install — then run this installer again."
    fi
    exit 3 ;;
  git)
    say ""
    say "git needs your administrator password to install, so the installer leaves it to you:"
    say "  sudo apt update && sudo apt install -y git"
    say "Then run this installer again."
    exit 3 ;;
esac

# ── the plan, and the second question ───────────────────────────────────────────────────────────────────────────────
say ""
say "To finish, Cotterpin would like to install, in your home folder (no admin password):"
[ -n "$uv_bin" ] || say "  - uv $UV_VERSION, checked against its published checksum"
if [ -n "$python_bin" ]; then
  python_choice=$python_bin
else
  python_choice=$PYTHON_VERSION
  say "  - Python $PYTHON_VERSION, through uv (your other Pythons are left alone)"
fi
say "  - Cotterpin ($COTTERPIN_SPEC${packs:+, with the language packs:$packs}), in its own environment"
[ "$on_path" = y ] || say "  - a line in $shown_profile that puts $shown_bin on your PATH"
if ! ask "Install them?"; then
  say "Nothing was installed."
  print_commands
  exit 0
fi

# ── install ─────────────────────────────────────────────────────────────────────────────────────────────────────────
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else die "no shasum or sha256sum to check the download with"; fi
}

mkdir -p "$BIN_DIR"
if [ -z "$uv_bin" ]; then
  workdir=$(mktemp -d)
  trap 'rm -rf "$workdir"' EXIT
  archive=$workdir/uv.tar.gz
  expected=$(uv_sha256 "$target")
  case $UV_URL in
    file://*)
      # a local copy (an offline mirror, or a test): it may carry its own checksum, a download never does
      cp "${UV_URL#file://}/$UV_VERSION/uv-$target.tar.gz" "$archive"
      expected=${COTTERPIN_INSTALL_UV_SHA256:-$expected} ;;
    *)
      say "Downloading uv $UV_VERSION ..."
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 -o "$archive" "$UV_URL/$UV_VERSION/uv-$target.tar.gz"
      elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only -O "$archive" "$UV_URL/$UV_VERSION/uv-$target.tar.gz"
      else
        die "neither curl nor wget is installed to download uv"
      fi ;;
  esac
  actual=$(sha256_of "$archive")
  [ "$actual" = "$expected" ] || die "the uv download does not match its published checksum; nothing was installed.
  expected $expected
  got      $actual"
  tar -xzf "$archive" -C "$workdir"
  cp "$workdir/uv-$target/uv" "$workdir/uv-$target/uvx" "$BIN_DIR/"
  chmod 755 "$BIN_DIR/uv" "$BIN_DIR/uvx"
  uv_bin=$BIN_DIR/uv
  say "Installed uv $UV_VERSION in $shown_bin (checksum verified)."
fi

if [ -z "$python_bin" ]; then
  say "Installing Python $PYTHON_VERSION ..."
  "$uv_bin" python install "$PYTHON_VERSION"
fi

say "Installing Cotterpin ..."
# $with_packs is unquoted on purpose: it is zero or more `--with cotterpin-pack-<name>` pairs from a fixed list
# shellcheck disable=SC2086
UV_TOOL_BIN_DIR=$BIN_DIR "$uv_bin" tool install --force --python "$python_choice" "$COTTERPIN_SPEC" $with_packs

if [ "$on_path" = n ] && ! grep -qF "$PATH_MARKER" "$profile" 2>/dev/null; then
  printf '\nexport PATH="%s:$PATH"  %s\n' "$BIN_DIR" "$PATH_MARKER" >> "$profile"
  say "Added $shown_bin to your PATH in $shown_profile."
fi

say ""
say "Cotterpin is installed: $("$BIN_DIR/cotterpin" --version 2>/dev/null || echo "$BIN_DIR/cotterpin")"
for other in $others; do
  say "Note: another cotterpin is at $other and may run instead of this one. Remove it if you no longer use it."
done
case $(pwd) in
  /mnt/[a-z]/*) say "Note: this folder is on the Windows drive, which is slow under WSL. Keep repositories in your Linux home (~)." ;;
esac
[ "$on_path" = y ] || say "Open a new terminal so your PATH includes $shown_bin."
[ -n "$packs" ] || say "Add the language pack for your code, e.g.: sh install.sh --pack java   (java, python, angular, dotnet, terraform)"
say "Next, in your repository: cotterpin init, then cotterpin doctor --install (your languages' tools, asked first)"
