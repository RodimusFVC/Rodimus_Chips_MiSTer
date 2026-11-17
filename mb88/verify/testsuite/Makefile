# MB88xx differential test suite.
#
# The oracle is MAME's cpu/mb88xx core, compiled UNMODIFIED out of
# "Useful Stuff/mame/mb88" (reached through the mame_mb88 symlink, which exists
# only so make does not have to cope with the space in "Useful Stuff").
# mame_shim/emu.h supplies the slice of MAME framework those files use.

MAME      := mame_mb88
SHIM      := mame_shim
OBJ       := obj

CXX       ?= g++
CXXFLAGS  := -std=c++17 -O2 -g -I$(SHIM) -I$(MAME) -I. -Wall -Wno-unused-variable -Wno-unused-but-set-variable

MAME_OBJS := $(OBJ)/mb88xx.o $(OBJ)/mb88dasm.o
HDRS      := $(SHIM)/emu.h oracle.h
SUITE_OBJS:= $(OBJ)/oracle.o

BINS      := bootstrap

all: $(BINS)

bootstrap: $(OBJ)/bootstrap_main.o $(SUITE_OBJS) $(MAME_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

$(OBJ)/mb88xx.o: $(MAME)/mb88xx.cpp $(HDRS) | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ)/mb88dasm.o: $(MAME)/mb88dasm.cpp $(HDRS) | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ)/%.o: %.cpp $(HDRS) | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ):
	mkdir -p $(OBJ)

clean:
	rm -rf $(OBJ) $(BINS) obj_dir

.PHONY: all clean

# ---------------------------------------------------------------- suite (RTL)
VERILATOR ?= verilator
TOP        = mb88_suite_tb
RTL        = ../../rtl

# MB88 defaults to this core's copy; override to validate another core's copy:
#   make suite MB88=/Work/Projects/Arcade-Kangaroo_MiSTer/rtl/cpu/mb88_sv/mb88_core.sv
MB88 ?= $(RTL)/mb88_core.sv
# add MB88DEF=+define+MB88_NO_OWR for cores without the o_wr strobe
MB88DEF ?=
V_SRC = mb88_suite_tb.sv $(MB88)
C_SRC = suite_main.cpp oracle.cpp $(MAME)/mb88xx.cpp $(MAME)/mb88dasm.cpp

VFLAGS = --cc --exe --build -O3 $(MB88DEF) \
         --top-module $(TOP) -o V$(TOP) -Mdir obj_dir --public-flat-rw \
         -I$(RTL) \
         -Wall -Wno-fatal \
         -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-MULTIDRIVEN \
         -Wno-PINMISSING -Wno-PINNOTFOUND -Wno-WIDTH -Wno-CASEINCOMPLETE \
         -CFLAGS "-O2 -std=c++17 -I$(CURDIR)/$(SHIM) -I$(CURDIR)/$(MAME) -I$(CURDIR)"

suite:
	$(VERILATOR) $(VFLAGS) $(V_SRC) $(C_SRC)

smoke: suite
	./obj_dir/V$(TOP) --ctx 2 --begin 0x00 --end 0x0f

.PHONY: suite smoke
