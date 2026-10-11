#!/usr/bin/env bash
# setup-runtime.sh — relink a decrypted PS5 ELF and assemble an AnyPS5 runtime.
#
# Prereqs (run once from the repo root, inside nix-shell):
#   cmake --build build --parallel && cmake --build build --target libs --parallel
# so that build/core/relinker/relinker and build/core/libs/libs/*.prx exist.
#
# Usage:
#   ./setup-runtime.sh <input.elf> <output-dir> [relinker options...]
#
# <input.elf> MUST be a clean, DECRYPTED PS5 executable, with its decrypted
# modules in sce_module/ (or sce_modules/ or prx/) beside it — or point at them
# with  --sce-module-path <dir>  passed through as a relinker option.
#
# An encrypted .pkg / PFS / .ffpfsc container is NOT valid input: decrypt and
# extract it first (that needs a jailbroken PS5's per-title keys and is out of
# scope for this tool). Public homebrew (e.g. ps5-doom) ships a usable ELF.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELINKER="$REPO/build/core/relinker/relinker"
LIBS_SRC="$REPO/build/core/libs/libs"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: $0 <input.elf> <output-dir> [relinker options...]"
INPUT="$1"; OUTDIR="$2"; shift 2

[ -x "$RELINKER" ] || die "relinker not built: $RELINKER  (run the full build first)"
[ -d "$LIBS_SRC" ] || die "system libs not built: $LIBS_SRC  (cmake --build build --target libs)"
[ -f "$INPUT" ]    || die "input not found: $INPUT"

# Guard against the most common mistake: handing it an encrypted container.
magic="$(head -c 4 "$INPUT" | od -A n -t x1 | tr -d ' \n')"
if [ "$magic" != "7f454c46" ]; then
  die "input is not an ELF (magic=$magic, expected 7f454c46 = '\\x7fELF').
       AnyPS5 needs a DECRYPTED eboot/ELF, not a .pkg / PFS / .ffpfsc container.
       Extract & decrypt the title first; an encrypted dump cannot be relinked."
fi

mkdir -p "$OUTDIR"
APP="$OUTDIR/app.elf"

echo ">> relinking:  $INPUT  ->  $APP"
"$RELINKER" "$@" "$INPUT" "$APP"

n_prx="$(find "$LIBS_SRC" -maxdepth 1 -name '*.prx' | wc -l)"
echo ">> populating $OUTDIR/libs/ with $n_prx AnyPS5 system .prx libraries"
mkdir -p "$OUTDIR/libs"
cp -f "$LIBS_SRC"/*.prx "$OUTDIR/libs/"
mkdir -p "$OUTDIR/app0"   # relinker also drops converted sce_module/ here

cat <<EOF

Runtime layout ready: $OUTDIR
  app.elf    the relinked native executable
  libs/      $n_prx AnyPS5 system libraries
  app0/      <-- copy the title's own resources here (plus any converted
                 sce_module/ dir the relinker printed above)

Run it (NixOS: via steam-run, so a generic ELF finds a loader + Vulkan):
  cd "$OUTDIR" && steam-run ./app.elf
  # force the discrete GPU:        ANYPS5_GPU=NVIDIA steam-run ./app.elf
  # software Vulkan fallback:      ANYPS5_GPU=llvmpipe steam-run ./app.elf
EOF
