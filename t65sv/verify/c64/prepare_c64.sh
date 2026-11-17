#!/bin/sh
# prepare_c64.sh <C64_MiSTer checkout>: verification-only inputs for the mini-C64 (not part of the core)
#   gen/vic.v           GHDL conversion of rtl/video_vicII_656x.vhd (PAL VIC-II)
#   gen/mos6526.v       C64_MiSTer CIA
#   gen/basic_kernal.hex, gen/chargen.hex   ROM images from rtl/roms/std_C64.mif, chargen.mif
set -e
SRC=$1; cd "$(dirname "$0")"; mkdir -p gen; cd gen
cp $SRC/rtl/video_vicII_656x.vhd $SRC/rtl/mos6526.v .
rm -f work-obj93.cf
ghdl -a -fsynopsys -fexplicit video_vicII_656x.vhd
ghdl --synth -fsynopsys -fexplicit -gregisteredAddress=true -gemulateRefresh=true -gemulateLightpen=true \
     -gemulateGraphics=true --out=verilog video_vicii_656x 2>/dev/null | sed -e 's/\bdo\b/do_o/g' > vic.v
python3 -I ../mif2hex.py $SRC/rtl/roms/std_C64.mif basic_kernal.hex
python3 -I ../mif2hex.py $SRC/rtl/roms/chargen.mif chargen.hex
echo "gen/ ready: $(wc -l < vic.v) lines VIC, ROM md5 $(md5sum basic_kernal.hex | cut -c1-8)"
