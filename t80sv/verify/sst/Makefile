# Test bench for t80sv_T80pa and the VHDL T80pa (see README.md).
# Needs Verilator 5 (5.044 used), GHDL with --synth (5.1.1 used; only for the VHDL), python3, git, curl.
#
#   make vectors         SingleStepTests/z80 v1 + ZEXDOC/ZEXALL into vectors/, JSON -> vectors/sst_txt
#   make sv              obj_sv/VT80pa     t80sv_T80pa (../../rtl), Mode 0
#   make vhdl            obj_vhdl/VT80pa   VHDL T80pa (vhdl/, patched T80 0250) through ghdl --synth
#   make sst EXE=sv TAG=x    all SingleStepTests + interrupt timing -> results/sv_x_*
#   ./check.sh x         both cores: SST, irq, sv == vhdl, pin-by-pin compare
#   make zex EXE=sv      ZEXDOC + ZEXALL (hours) -> results/sv_zex{doc,all}.log
#   make modes ORIG=dir  Modes 1 / 2 / 3, patched vs the t80sv rtl/ in ORIG, pin by pin
#   make lint            verilator --lint-only -Wall on all drop-in tops
SV   = ../../rtl
VH   = vhdl
PY   = python3 -I
VFLAGS = --cc --exe --build -j 0 --no-timing -Wno-fatal -Wno-lint -Wno-style \
	--x-assign fast --x-initial fast --noassert -O3 -CFLAGS "-O2 -std=c++17"
SV_SRC = $(SV)/t80sv_alu.sv $(SV)/t80sv_mcode.sv $(SV)/t80sv_core.sv $(SV)/t80sv.sv $(SV)/t80sv_tops.sv
VH_MOD = T80_Pack T80_Reg T80_ALU T80_MCode T80 T80pa
BENCH  = sst_main.cpp harness.h cpu_t80.h

all: sv vhdl
sv: obj_sv/VT80pa
vhdl: obj_vhdl/VT80pa

obj_sv/VT80pa: $(SV_SRC) T80pa_sv.sv gen_sv/t80.vlt gen_sv/t80_wz.h $(BENCH)
	verilator $(VFLAGS) --Mdir obj_sv --top-module T80pa -CFLAGS -DCPU_T80 -CFLAGS -I../gen_sv \
		gen_sv/t80.vlt $(SV_SRC) T80pa_sv.sv sst_main.cpp

# ghdl --synth drops the concurrent "DI_Reg <= DI;" of T80.vhd (GHDL 5.1.1): put it back
gen_vhdl/t80pa_synth.v: $(foreach m,$(VH_MOD),$(VH)/$(m).vhd)
	rm -rf gen_vhdl; mkdir -p gen_vhdl
	cp $(foreach m,$(VH_MOD),$(VH)/$(m).vhd) gen_vhdl/
	cd gen_vhdl && ghdl --synth --std=08 -fsynopsys --out=verilog -gMode=0 \
		$(foreach m,$(VH_MOD),$(m).vhd) -e T80pa > t80pa_synth.v.raw 2> synth.log
	awk '/^module /{m=$$2} {print} m ~ /^t80_[0-9]/ && $$0 == "  wire [7:0] di_reg;" {print "  assign di_reg = di;"; n++} \
		END{if (n != 1) exit 1}' gen_vhdl/t80pa_synth.v.raw > gen_vhdl/t80pa_synth.v

# WZ and Fw are not on the ports: find the netlist registers behind them
gen_vhdl/t80_wz.h: gen_vhdl/t80pa_synth.v
	mod=$$(grep -o '^module t80_[0-9_]*' gen_vhdl/t80pa_synth.v | head -1 | cut -d' ' -f2); \
	reg=$$(grep -E '^  assign wz = n[0-9]+;' gen_vhdl/t80pa_synth.v | head -1 | sed -E 's/.*= (n[0-9]+);.*/\1/'); \
	test -n "$$reg"; \
	echo "#define T80_WZ(top) top->rootp->T80pa__DOT__u0__DOT__$$reg" > gen_vhdl/t80_wz.h; \
	printf '`verilator_config\npublic_flat_rw -module "%s" -var "%s"\n' $$mod $$reg > gen_vhdl/t80.vlt; \
	fw=$$(grep -E '^  assign fw = n[0-9]+;' gen_vhdl/t80pa_synth.v | head -1 | sed -E 's/.*= (n[0-9]+);.*/\1/'); \
	if [ -n "$$fw" ]; then echo "#define T80_QF(top) top->rootp->T80pa__DOT__u0__DOT__$$fw" >> gen_vhdl/t80_wz.h; \
	printf 'public_flat_rw -module "%s" -var "%s"\n' $$mod $$fw >> gen_vhdl/t80.vlt; fi

obj_vhdl/VT80pa: gen_vhdl/t80_wz.h $(BENCH)
	verilator $(VFLAGS) --Mdir obj_vhdl --top-module T80pa +1364-2005ext+v -CFLAGS -DCPU_T80 -CFLAGS -I../gen_vhdl \
		gen_vhdl/t80.vlt gen_vhdl/t80pa_synth.v sst_main.cpp

# Strobe positions of T80pa relative to SingleStepTests' one-sample convention (same for every instruction)
DELTA = --delta 0 1 -1 --delta 0 0 -1 --delta 1 0 0 --delta 2 0 -1 --delta 3 0 -1
EXE ?= sv
TAG ?= run
sst:
	mkdir -p results
	./obj_$(EXE)/VT80pa --verbose 0 $(DELTA) sst vectors/sst_txt/*.txt > results/$(EXE)_$(TAG)_sst.tsv 2> results/$(EXE)_$(TAG)_sst.err
	./obj_$(EXE)/VT80pa irq > results/$(EXE)_$(TAG)_irq.tsv 2>&1
	./obj_$(EXE)/VT80pa --m1wait irq > results/$(EXE)_$(TAG)_irq_m1wait.tsv 2>&1
	$(PY) tools/sst_report.py results/$(EXE)_$(TAG)_sst.tsv > results/$(EXE)_$(TAG)_summary.md
	grep '\*\*all' results/$(EXE)_$(TAG)_summary.md

# one opcode file with the first failures printed: make sst-one OP=ed_b0
sst-one:
	./obj_$(EXE)/VT80pa --verbose 5 $(DELTA) sst vectors/sst_txt/$(OP).txt

# about 3 hours each; copies the binary so a rebuild does not disturb the runs
zex:
	mkdir -p results/bin && cp obj_$(EXE)/VT80pa results/bin/VT80pa_$(EXE)
	results/bin/VT80pa_$(EXE) zex vectors/zex/zexdoc.com > results/$(EXE)_zexdoc.log 2>&1 & \
	results/bin/VT80pa_$(EXE) zex vectors/zex/zexall.com > results/$(EXE)_zexall.log 2>&1 & wait
	grep -c '  OK' results/$(EXE)_zexdoc.log results/$(EXE)_zexall.log

# Modes 1 (fast Z80), 2 (8080), 3 (GB): the same 100 tests per opcode file run as code for that mode;
# every pin at every half T-state and REG must match between t80sv as received (ORIG=.../rtl) and patched
# for modes 2 and 3 (mode 1 changes like mode 0).
ORIG_SRC = $(foreach f,t80sv_alu t80sv_mcode t80sv_core t80sv t80sv_tops,$(ORIG)/$(f).sv)
obj_m%_fix/VT80pa: $(SV_SRC) T80pa_mode.sv gen_sv/t80.vlt $(BENCH)
	verilator $(VFLAGS) --Mdir obj_m$*_fix --top-module T80pa +define+MODE=$* -CFLAGS -DCPU_T80 -CFLAGS -I../gen_sv \
		gen_sv/t80.vlt $(SV_SRC) T80pa_mode.sv sst_main.cpp
obj_m%_orig/VT80pa: T80pa_mode.sv gen_orig/t80.vlt $(BENCH)
	test -n "$(ORIG)" || { echo "set ORIG= to the rtl/ directory of t80sv as received"; exit 1; }
	verilator $(VFLAGS) --Mdir obj_m$*_orig --top-module T80pa +define+MODE=$* -CFLAGS -DCPU_T80 -CFLAGS -I../gen_orig \
		gen_orig/t80.vlt $(ORIG_SRC) T80pa_mode.sv sst_main.cpp
modes: $(foreach m,1 2 3,obj_m$(m)_fix/VT80pa obj_m$(m)_orig/VT80pa)
	mkdir -p results
	for m in 1 2 3; do for v in orig fix; do \
		./obj_m$${m}_$$v/VT80pa pindump /dev/null 100 vectors/sst_txt/*.txt > results/pins_m$${m}_$$v.txt 2>/dev/null & \
	done; done; wait
	@for m in 1 2 3; do cmp -s results/pins_m$${m}_orig.txt results/pins_m$${m}_fix.txt && \
		echo "mode $$m: identical" || echo "mode $$m: differs"; done
	rm -f results/pins_m?_*.txt

TOPS = t80sv_T80s t80sv_T80pa t80sv_T80se t80sv_T80sed t80sv_T8080se t80sv_GBse t80sv_T80a t80sv_T80as \
	t80sv_T80 t80sv_T80pa_phx t80sv_T80_phx
lint:
	for t in $(TOPS); do echo "== $$t"; verilator --lint-only -Wall $(SV)/t80sv_lint.vlt $(SV)/t80sv_all.sv --top-module $$t 2>&1 | \
		grep '^%' || true; done

# Test data. The JSON is only parsed; the ZEX programs only run inside the simulated CPU.
SST_REPO = https://github.com/SingleStepTests/z80.git
SST_REV  = ebe1875d48f374bcfd4b505d8eb8ee751568b5f7
ZEX_URL  = https://raw.githubusercontent.com/anotherlin/z80emu/1c418fa0d719abab9273131113defbe276101d95/testfiles
vectors: vectors/sst/v1/00.json vectors/zex/zexall.com vectors/sst_txt/00.txt
vectors/sst/v1/00.json:
	rm -rf vectors/sst
	git clone -q --filter=blob:none --sparse $(SST_REPO) vectors/sst
	cd vectors/sst && git sparse-checkout set v1 && git checkout -q $(SST_REV)
vectors/zex/zexall.com:
	mkdir -p vectors/zex
	cd vectors/zex && for f in zexdoc.com zexall.com zexdoc.z80 zexall.z80; do curl -sfLO $(ZEX_URL)/$$f; done
	cd vectors/zex && shasum -c ../../zex.sha1
vectors/sst_txt/00.txt: vectors/sst/v1/00.json
	$(PY) tools/sst_convert.py vectors/sst/v1 vectors/sst_txt

clean:
	rm -rf obj_* gen_vhdl results/bin

.PHONY: all sv vhdl sst sst-one zex modes lint vectors clean
