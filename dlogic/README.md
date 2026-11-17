# dlogic

## From the source header

```
 Discrete logic engine: runs a TTL board's netlist (MAME netlist -> tools/dlogic/nl2dl.py -> dl2bin.py, MRA index 0)
 as a timed event simulation, so a discrete-logic game is a program, not logic. Bit-exact with the reference model
 (Pong core: the dlsim.cpp evaluator, lockstep on a per-tick FNV hash of every net).
 v1: one processing element, sequential FSM (correctness baseline; real time needs the multi-lane version).
 Copyright (C) 2026 Rodimus
 Redistribution and use in source and synthesized forms, with or without
 modification, are permitted provided that the following conditions are met:
 Redistributions of source code must retain the above copyright notice,
```

## Files

| File | md5 |
|---|---|
| `dlogic_engine.sv` | 7d27558d |
| `dlogic_cell.sv` | ecfcee35 |
| `dlogic_raster.sv` | 876c9b54 |
| `dlogic_video.sv` | 64f1defd |

Imported 2026-10-29 from `RodimusCoresMaster` (`rtl/logic/`).

## Fleet copies

- Identical: Pong, RodimusCoresMaster
- Different: -

## License

License: BSD-3-Clause (own work, Rodimus). See `LICENSE`.
