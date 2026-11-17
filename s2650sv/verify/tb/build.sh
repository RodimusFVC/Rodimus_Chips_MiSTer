#!/bin/bash
# Build the lockstep harness: variants A (VER_B=0) / B (VER_B=1) x return stack MLAB (1) / registers (0)
cd "$(dirname "$0")"
for V in a b; do for M in 1 0; do ./build1.sh $V $M & done; done; wait
ls -la lockstep_*
