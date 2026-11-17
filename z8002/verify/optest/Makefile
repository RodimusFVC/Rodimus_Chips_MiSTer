# Fast standalone unit test for z8002.sv's BATCH 8 2026-07-27 opcodes (0x71, 0x5D
# indexed, 0xB0/DAB) -- hand-assembled program with known-good expected values,
# decoupled from the full PolePosition boot (those opcodes only occur 69-96% deep
# into the real MAME boot trace, far past what pp_maincpu co-sim has reached so far).
#   make        build ./obj_dir/Vz8002_optest_tb
#   make run    build + run
#   make clean

VERILATOR ?= verilator
TOP        = z8002_optest_tb
RTL        = ../../rtl

V_SRC = z8002_optest_tb.sv $(RTL)/z8002.sv
C_SRC = sim_main.cpp

VFLAGS = --cc --exe --build -O3 \
         --top-module $(TOP) -o V$(TOP) -Mdir obj_dir \
         -I$(RTL) \
         -Wall -Wno-fatal \
         -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-MULTIDRIVEN \
         -Wno-PINMISSING -Wno-WIDTH -Wno-CASEINCOMPLETE \
         -CFLAGS "-O2 -std=c++17"

all:
	$(VERILATOR) $(VFLAGS) $(V_SRC) $(C_SRC)

run: all
	./obj_dir/V$(TOP)

clean:
	rm -rf obj_dir
