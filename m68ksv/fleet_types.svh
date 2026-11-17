// Copyright (C) 2026 Rodimus
// m68ksv: proposed master bus types for the whole 680x0 family (one type for 68000 / 68008 / 68EC000 / 68010 /
// 68020 / 68EC020; 16-bit users tie the 020-only inputs off). Kept in package m68ksv_fleet_pkg until the fleet merges
// the typedefs below the "to merge" line into chip_pool_pkg (the agent does not touch the master).
package m68ksv_fleet_pkg;
// ---- to merge ----
typedef struct packed {
    logic [31:0] d;          // data in; 16-bit bus on [15:0], 8-bit bus on [7:0]
    logic        dtack_n;    // 68000 / 68008 / 68EC000 / 68010
    logic  [1:0] dsack_n;    // 68020 / 68EC020 dynamic bus sizing
    logic        sterm_n;    // 68020 synchronous termination
    logic        berr_n;
    logic        halt_n;
    logic        reset_n;
    logic        vpa_n;      // 6800 cycles / autovector (000 / 010)
    logic        avec_n;     // autovector (020)
    logic        cdis_n;     // cache disable (020)
    logic  [2:0] ipl_n;      // 68008 DIP48: ipl_n[2] = the IPL2 / IPL0 pin, ipl_n[0] unused
    logic        br_n;
    logic        bgack_n;    // not on 68008 DIP48
    logic        mode;       // 68EC000 MODE (bus width, sampled at reset)
} m68k_i_t;
typedef struct packed {
    logic [31:0] a;          // byte address; 68000 / 68010 drive [23:1], 68008 [19:0] / [21:0], EC020 [23:0]
    logic [31:0] d;
    logic        d_oe;
    logic        as_n;
    logic        uds_n;      // 16-bit bus
    logic        lds_n;
    logic        ds_n;       // 8-bit bus (68008, 68EC000 MODE = 0) / 68020 data strobe
    logic        rw;
    logic  [1:0] siz;        // 68020
    logic  [2:0] fc;
    logic        rmc_n;      // 68020 read-modify-write cycle
    logic        ecs_n;      // 68020
    logic        ocs_n;      // 68020
    logic        dben_n;     // 68020
    logic        ipend_n;    // 68020
    logic        vma_n;      // 000 / 010
    logic        e;          // 000 / 010
    logic        bg_n;
    logic        halt_n;     // HALT driven (double bus fault)
    logic        reset_n;    // RESET instruction
} m68k_o_t;
endpackage
