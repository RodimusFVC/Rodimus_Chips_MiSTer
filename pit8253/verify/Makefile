# pit8253 lockstep rig. Build output goes outside the repo.
OUT   ?= /Work/Projects/verilator_local_files/Rodimus_Chips_MiSTer/pit8253
RTL   := $(abspath ../rtl/pit8253.sv)
TB    := $(abspath tb_pit8253.cpp)
REFH  := $(abspath pit_ref.h)
VFLAGS := --cc --exe --build -j 4 -O3 -Wall -Wno-fatal -public-flat-rw --top-module pit8253 \
          -CFLAGS "-std=c++17 -O2 -I$(abspath .)"

.PHONY: all lint build run clean_note
all: lint build run

lint:
	verilator --lint-only -Wall --top-module pit8253 -GPIT8254=0 $(RTL)
	verilator --lint-only -Wall --top-module pit8253 -GPIT8254=1 $(RTL)

build: $(OUT)/obj_8253/Vpit8253 $(OUT)/obj_8254/Vpit8253

$(OUT)/obj_8253/Vpit8253: $(RTL) $(TB) $(REFH)
	verilator $(VFLAGS) -GPIT8254=0 -CFLAGS -DPIT8254=0 -Mdir $(OUT)/obj_8253 $(RTL) $(TB)

$(OUT)/obj_8254/Vpit8253: $(RTL) $(TB) $(REFH)
	verilator $(VFLAGS) -GPIT8254=1 -CFLAGS -DPIT8254=1 -Mdir $(OUT)/obj_8254 $(RTL) $(TB)

# full suite on both chip variants: directed + sweep + 8 seeds x 25 M random clocks each
run: build
	$(OUT)/obj_8253/Vpit8253 all
	$(OUT)/obj_8254/Vpit8253 all
