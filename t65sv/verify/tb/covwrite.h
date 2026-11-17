// Coverage builds (verilator --coverage-*): COV_WRITE() at the end of main writes the counters to $COV_OUT
// (default coverage.dat). It has to run before static destruction (a static destructor deadlocks in Verilator).
#pragma once
#if VM_COVERAGE
#include "verilated_cov.h"
#include <cstdlib>
#define COV_WRITE() do { const char* f_ = getenv("COV_OUT"); \
  Verilated::threadContextp()->coveragep()->write(f_ ? f_ : "coverage.dat"); } while (0)
#else
#define COV_WRITE() do {} while (0)
#endif
