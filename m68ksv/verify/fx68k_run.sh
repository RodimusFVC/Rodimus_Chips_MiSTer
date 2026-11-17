#!/bin/bash
# Run the fx68k suite probe from its build dir (fx68k reads microrom.mem / nanorom.mem from the current directory):
#   fx68k_run.sh <build dir> [fxprobe options] <suite .bin files>      (options: see tb/fxprobe.cpp)
set -e
B=$(realpath "$1"); shift
args=()
for a in "$@"; do
    if [ -e "$a" ]; then args+=("$(realpath "$a")"); else args+=("$a"); fi
done
cd "$B"
exec ./fxprobe "${args[@]}"
