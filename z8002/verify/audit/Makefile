# EXHAUSTIVE z8002 opcode-coverage audit (2026-08-09). Reuses z8002_optest_tb.sv
# (real production z8002.sv + behavioral memory) and sweeps all 65536 first words.
#   make run    build + sweep -> ours_illegal.txt
#   ../../  then: python3 audit_report.py
VERILATOR ?= verilator
TOP        = z8002_optest_tb
RTL        = ../../rtl
TB         = ../optest

V_SRC = $(TB)/z8002_optest_tb.sv $(RTL)/z8002.sv
C_SRC = audit_main.cpp

VFLAGS = --cc --exe --build -O3 \
         --top-module $(TOP) -o V$(TOP) -Mdir obj_dir \
         -I$(RTL) -I$(TB) \
         -Wall -Wno-fatal \
         -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-MULTIDRIVEN \
         -Wno-PINMISSING -Wno-WIDTH -Wno-CASEINCOMPLETE \
         -CFLAGS "-O2 -std=c++17"

all:
	$(VERILATOR) $(VFLAGS) $(V_SRC) $(C_SRC)

run: all
	./obj_dir/V$(TOP)

clean:
	rm -rf obj_dir ours_illegal.txt
