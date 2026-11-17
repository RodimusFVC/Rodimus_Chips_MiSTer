# dsnd_engine verification: the RTL against the instruction-set model (dsnd_model.h), sample by sample.
#   make          build + check.py: random programs, directed EXP / RCP / NOISE-guard programs and control mutants
#                 (each mutant must FAIL), at every TICK the fleet uses; the model-only renderer (dsnd_run) must
#                 write the lockstep's WAVs
#   make fleet    also every shipped program (MRA index 5) of the cores in FLEET, each at its core's TICK
# Build output and generated programs go to OUT, outside the repo. ram_sim.sv (sim dpram_dc) is VerilatorMaster's.
PROJ    := $(abspath $(CURDIR)/../../..)
OUT     ?= $(PROJ)/verilator_local_files/Rodimus_Chips_MiSTer/dsnd_engine
VMASTER ?= $(PROJ)/VerilatorMaster_MiSTer
RAMSIM  := $(VMASTER)/common/ram_sim.sv
RTL     := $(abspath ../rtl/dsnd_engine.sv)
FLEET   ?= Exidy Galaxian Phoenix SegaVICDual SpaceInvaders
# TICK -> the clock of a core that runs it (sets FS = CLK_HZ / TICK for event times and the WAV rate)
TICKS   := 832 917 1024
CLK_832  := 39936000
CLK_917  := 44000000
CLK_1024 := 30936960
MUTANTS := noguard nooutr
VFLAGS  := -cc -O3 --x-assign fast --x-initial fast --noassert -Wno-fatal -Wno-lint -Wno-style -exe --top-module dsnd_engine

BINS := $(foreach t,$(TICKS),$(OUT)/t$(t)/Vdsnd_engine $(OUT)/t$(t)/dsnd_run) $(foreach m,$(MUTANTS),$(OUT)/mut_$(m)/Vdsnd_engine)
.PHONY: all build fleet
all: build
	python3 -I check.py $(OUT)
fleet: build
	python3 -I check.py $(OUT) --fleet $(FLEET)
build: $(BINS)

$(OUT)/t%/Vdsnd_engine: $(RTL) $(RAMSIM) dsnd_lockstep.cpp dsnd_model.h
	mkdir -p $(OUT)/t$*
	verilator $(VFLAGS) -GTICK=$* --Mdir $(OUT)/t$* $(RTL) $(RAMSIM) $(CURDIR)/dsnd_lockstep.cpp \
	    -CFLAGS "-I$(CURDIR) -DTICK=$* -DCLK_HZ=$(CLK_$*)"
	$(MAKE) -C $(OUT)/t$* -f Vdsnd_engine.mk -j8 OPT_FAST="-O2" >/dev/null

$(OUT)/t%/dsnd_run: dsnd_run.cpp dsnd_model.h
	mkdir -p $(OUT)/t$*
	g++ -O2 -std=gnu++17 -DTICK=$* -DCLK_HZ=$(CLK_$*) -I$(CURDIR) -o $@ $(CURDIR)/dsnd_run.cpp

# control mutants (TICK 832): the kit with one model behaviour removed; mutate.py writes the mutated copy
$(OUT)/mut_%/Vdsnd_engine: $(RTL) $(RAMSIM) dsnd_lockstep.cpp dsnd_model.h mutate.py
	mkdir -p $(OUT)/mut_$*
	python3 -I mutate.py $* $(OUT)/mut_$*/src
	verilator $(VFLAGS) -GTICK=832 --Mdir $(OUT)/mut_$* $(RTL) $(RAMSIM) $(OUT)/mut_$*/src/dsnd_lockstep.cpp \
	    -CFLAGS "-I$(OUT)/mut_$*/src -DTICK=832 -DCLK_HZ=$(CLK_832)"
	$(MAKE) -C $(OUT)/mut_$* -f Vdsnd_engine.mk -j8 OPT_FAST="-O2" >/dev/null
