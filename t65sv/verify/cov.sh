#!/bin/sh
# cov.sh <download dir>: Verilator line coverage of rtl/ over the main suites; writes results/coverage.txt (per file,
# merged over all builds and instances, plus every point never executed) and annotated sources in build/cov/annot
# (those show the minimum over instances, so a line only one configuration can reach shows 0 there).
set -e
cd "$(dirname "$0")"; V=$(pwd); DL=${1:?usage: cov.sh <download dir>}
C="--coverage-line"
./build_tb.sh cov_ls lockstep.cpp lockstep $C
./build_tb.sh cov_prog progrun.cpp lockstep $C
./build_tb.sh cov_wdc  progrun.cpp solo -GC02=1 $C
./build_tb.sh cov_rkwl progrun.cpp solo -GC02=2 $C
./build_tb.sh cov_syn  progrun.cpp solo -GC02=3 $C
./build_tb.sh cov_2a03 progrun.cpp solo -GC02=0 -GNO_DECIMAL=1 $C
./build_tb.sh cov_c02dir c02dir.cpp solo -GC02=1 $C
./build_tb.sh cov_sstls sst.cpp lockstep $C
./build_tb.sh cov_sstwdc sst.cpp solo -GC02=1 $C
OUT=cov_816 EXTRA=$C ./build816.sh
OUT=cov_816dir CPP=c816dir.cpp EXTRA=$C ./build816.sh
OUT=cov_p816 CPP=progrun816.cpp EXTRA=$C ./build816.sh
mkdir -p build/cov; rm -f build/cov/*.dat
D=tests/dormann
COV_OUT=build/cov/rnd.dat    ./build/cov_ls random 1 5000000 > /dev/null
COV_OUT=build/cov/rnd3.dat   ./build/cov_ls random 3 5000000 > /dev/null
COV_OUT=build/cov/sweep.dat  ./build/cov_ls sweep > /dev/null
COV_OUT=build/cov/func.dat   ./build/cov_prog --hex $D/6502_functional_test.hex --start 0400 --pass 3469 > /dev/null
COV_OUT=build/cov/dec.dat    ./build/cov_prog --hex $D/dec_nmos_all.hex --start 0200 --stop 024b --check 000b=00 > /dev/null
COV_OUT=build/cov/wdc.dat    ./build/cov_wdc --mode 1 --hex $D/c02_wdc.hex --start 0400 --pass 24f1 > /dev/null
COV_OUT=build/cov/wdcd.dat   ./build/cov_wdc --mode 1 --hex $D/dec_c02_all.hex --start 0200 --stop 024b --check 000b=00 > /dev/null
COV_OUT=build/cov/rkwl.dat   ./build/cov_rkwl --mode 1 --hex $D/c02_rkwl.hex --start 0400 --pass 2569 > /dev/null
COV_OUT=build/cov/syn.dat    ./build/cov_syn --mode 1 --hex $D/c02_sc02.hex --start 0400 --pass 2434 > /dev/null
COV_OUT=build/cov/2a03.dat   ./build/cov_2a03 --hex $D/func_nodec.hex --start 0400 --pass 336d > /dev/null
COV_OUT=build/cov/c02dir.dat ./build/cov_c02dir > /dev/null
COV_OUT=build/cov/sstls.dat  ./build/cov_sstls --quiet $DL/sstbin/6502 > /dev/null || true
COV_OUT=build/cov/sstwdc.dat ./build/cov_sstwdc --mode 1 --quiet $DL/sstbin/wdc65c02 > /dev/null || true
COV_OUT=build/cov/816.dat    ./build/cov_816 --quiet --limit 500 $DL/sst816bin > /dev/null
COV_OUT=build/cov/816dir.dat ./build/cov_816dir > /dev/null
COV_OUT=build/cov/p816.dat   ./build/cov_p816 --hex tests/dormann/6502_functional_test.hex --start 0400 --max 3000000 --stall 7 > /dev/null || true
verilator_coverage --write build/cov/all.dat build/cov/*.dat
rm -rf build/cov/annot
verilator_coverage --annotate build/cov/annot --annotate-min 1 build/cov/all.dat > /dev/null 2>&1
python3 cov_summary.py build/cov/all.dat > results/coverage.txt
