# TMS5220 cosim: MAME tms5220.cpp (extracted by gen_oracle.py) vs ../rtl/tms5220.sv, sample for sample.
# `make check` also regenerates the tables from MAME's tms5110r.hxx and compares them with ../rtl/tms5220_tables.vh.
all: check
gen/tms5220_tables.vh: gen_tables.cpp mame_src/tms5110r.hxx
	mkdir -p gen && g++ -std=c++17 -o gen/gen_tables gen_tables.cpp && ./gen/gen_tables > $@
oracle5220.cpp: gen_oracle.py mame_src/tms5220.cpp
	python3 -I gen_oracle.py
obj/Vtms5220: ../rtl/tms5220.sv ../rtl/tms5220_tables.vh oracle5220.cpp cosim.cpp
	verilator -cc -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-lint -Wno-style -I../rtl -I. -CFLAGS "-std=c++17 -w" \
	    -exe --Mdir obj --top-module tms5220 ../rtl/tms5220.sv cosim.cpp
	$(MAKE) -C obj -f Vtms5220.mk -j8 >/dev/null
check: gen/tms5220_tables.vh obj/Vtms5220
	cmp gen/tms5220_tables.vh ../rtl/tms5220_tables.vh && echo "tables: identical to MAME tms5110r.hxx"
	./obj/Vtms5220 polepos2bi_tms_traffic.txt
clean:
	rm -rf obj gen oracle5220.cpp
.PHONY: all check clean
