# z8002 differential test suite.
#
# The oracle is MAME's cpu/z8000 core, compiled UNMODIFIED out of
# "Useful Stuff/mame/z8000" (reached through the mame_z8000 symlink, which exists
# only so make does not have to cope with the space in "Useful Stuff").
# mame_shim/emu.h supplies the small slice of the MAME framework those files use.

MAME      := mame_z8000
SHIM      := mame_shim
OBJ       := obj

CXX       ?= g++
CXXFLAGS  := -std=c++17 -O2 -g -I$(SHIM) -I$(MAME) -I. -Wall -Wno-enum-compare -Wno-unused-variable

MAME_SRCS := $(MAME)/z8000.cpp $(MAME)/8000dasm.cpp
MAME_OBJS := $(OBJ)/z8000.o $(OBJ)/8000dasm.o
SUITE_OBJS:= $(OBJ)/oracle.o

BINS      := bootstrap

all: $(BINS)

bootstrap: $(OBJ)/bootstrap_main.o $(SUITE_OBJS) $(MAME_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^

$(OBJ)/z8000.o: $(MAME)/z8000.cpp | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ)/8000dasm.o: $(MAME)/8000dasm.cpp | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ)/%.o: %.cpp | $(OBJ)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ):
	mkdir -p $(OBJ)

# Regenerate the opcode map from MAME's table (checked in; only needed if that
# table ever changes).
opinfo:
	python3 tools/gen_opinfo.py

clean:
	rm -rf $(OBJ) $(BINS)

.PHONY: all clean opinfo

# ---------------------------------------------------------------- suite (RTL)
# The differential suite links the Verilated DUT against the same oracle objects.

VERILATOR ?= verilator
TOP        = z8002_suite_tb
RTL        = ../../rtl

V_SRC = z8002_suite_tb.sv $(RTL)/z8002.sv
C_SRC = suite_main.cpp oracle.cpp $(MAME)/z8000.cpp $(MAME)/8000dasm.cpp

VFLAGS = --cc --exe --build -O3 \
         --top-module $(TOP) -o V$(TOP) -Mdir obj_dir \
         -I$(RTL) \
         -Wall -Wno-fatal \
         -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNOPTFLAT -Wno-MULTIDRIVEN \
         -Wno-PINMISSING -Wno-WIDTH -Wno-CASEINCOMPLETE \
         -CFLAGS "-O2 -std=c++17 -Wno-enum-compare -I$(CURDIR)/$(SHIM) -I$(CURDIR)/$(MAME) -I$(CURDIR)"

suite:
	$(VERILATOR) $(VFLAGS) $(V_SRC) $(C_SRC)

# Quick smoke run over a small opcode window.
smoke: suite
	./obj_dir/V$(TOP) --ctx 2 --begin 0x2100 --end 0x21FF

.PHONY: suite smoke
