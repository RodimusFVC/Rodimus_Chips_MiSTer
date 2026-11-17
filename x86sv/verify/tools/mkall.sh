#!/bin/bash
# Concatenate the split RTL into the one drop-in file rtl/x86sv_all.sv
R=$(dirname "$(realpath "$0")")/../../rtl
{
    echo "// Copyright (C) 2026 Rodimus"
    echo "// x86sv: 8088 / 8086 CPU core, all modules in one file (generated from rtl/x86sv_*.sv by verify/tools/mkall.sh)"
    for f in x86sv_alu.sv x86sv_biu.sv x86sv_biu16.sv x86sv_eu.sv x86sv.sv x86sv16.sv; do echo; tail -n +3 "$R/$f"; done
} > "$R/x86sv_all.sv"
