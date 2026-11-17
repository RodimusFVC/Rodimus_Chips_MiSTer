#!/bin/sh
# Assembles the Dormann test variants with as65 1.42 (Linux i386 binary in as65_142.zip from the Dormann repo).
# Usage: build.sh <path-to-as65>
set -e
cd "$(dirname "$0")"
AS=${1:-as65}
asm() { x=; case $1 in *.a65c) x=-x;; esac; "$AS" -l -m -s2 -w $x -h0 "$1" "-o$2" >/dev/null 2>&1; [ -s "$2" ] || { echo "as65 failed: $1"; exit 1; }; }
cfg() { # cfg <src> <dst> key=val...
  src=$1; dst=$2; shift 2; cp "$src" "$dst"
  for kv in "$@"; do k=${kv%%=*}; v=${kv#*=}; sed -i "s/^$k *= *[0-9a-fA-F]*/$k = $v/" "$dst"; done
}
asm 6502_functional_test.a65 6502_functional_test.hex
cfg 6502_functional_test.a65 func_nodec.a65 disable_decimal=1
asm func_nodec.a65 func_nodec.hex
# decimal: NMOS default (A,C), NMOS all flags (Bruce Clark NMOS N/V/Z/C), 65C02 all flags
cfg 6502_decimal_test.a65 dec_nmos_ac.a65   cputype=0
cfg 6502_decimal_test.a65 dec_nmos_all.a65  cputype=0 chk_n=1 chk_v=1 chk_z=1
cfg 6502_decimal_test.a65 dec_c02_all.a65   cputype=1 chk_n=1 chk_v=1 chk_z=1
cfg 6502_decimal_test.a65 dec_816_all.a65   cputype=2 chk_n=1 chk_v=1 chk_z=1
# 2A03: decimal-mode ADC/SBC must give exactly the binary-mode A and NVZC (cputype 3 added here)
cfg 6502_decimal_test.a65 dec_2a03_all.a65  cputype=3 chk_n=1 chk_v=1 chk_z=1
python3 - dec_2a03_all.a65 <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
blk='''        if  cputype = 3
A6502       lda HA      ; 2A03: decimal mode is binary
            sta AR
            lda HNVZC
            sta NF
            sta VF
            sta ZF
            sta CF
            rts
S6502       jmp A6502
        endif

        end TEST'''
s=s.replace('        end TEST', blk, 1)
open(p,'w').write(s)
PY
for v in dec_nmos_ac dec_nmos_all dec_c02_all dec_816_all dec_2a03_all; do asm $v.a65 $v.hex; done
# 65C02 extended opcodes: WDC (all), Rockwell (bit ops, no WAI/STP), 65SC02 (neither)
cfg 65C02_extended_opcodes_test.a65c c02_wdc.a65c  wdc_op=1 rkwl_wdc_op=1
cfg 65C02_extended_opcodes_test.a65c c02_rkwl.a65c wdc_op=0 rkwl_wdc_op=1
cfg 65C02_extended_opcodes_test.a65c c02_sc02.a65c wdc_op=0 rkwl_wdc_op=0
for v in c02_wdc c02_rkwl c02_sc02; do asm $v.a65c $v.hex; done
ls -la *.hex
