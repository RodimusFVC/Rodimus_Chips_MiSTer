# mc3417

Motorola MC3417 CVSD decoder (3-bit coincidence): a SystemVerilog port of MAME's `mc3417_device` in `hc55516.cpp`.
One `clk` domain; a bit is taken on each falling edge of `bclk`; `integ` = the signed 24-bit integrator output.

Not the same model as [`hc55516`](../hc55516/) (Williams; a smaller fixed-constant integrator). The MC3418 (4-bit
coincidence, MAME `mc3418_device`, same source file) differs only in the shift-register length and constants; Exidy
440 uses two of each.

## From the source header

```
 SPDX-License-Identifier: BSD-3-Clause
 Based on MAME src/devices/sound/hc55516.cpp (license:BSD-3-Clause, copyright-holders: Aaron Giles, Jonathan Gevaryahu)
 Copyright (C) 2026 Rodimus
```

## Files

| File | md5 |
|---|---|
| `rtl/mc3417.sv` | de550b25 |

Imported 2026-11-15 from `Exidy` (`rtl/sound/`; header brought to the repo standard, code unchanged).

## Fleet copies

- Identical: Exidy (Mouse Trap CVSD, Venture-type sound board; pool type `mc3417`)
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.
