// Copyright (C) 2026 Rodimus
// m68ksv: execution unit - micro-sequencer (M10K microcode + decode ROMs), register file, address unit, ALU glue,
// exception / interrupt control. Bus width lives in the BIU; this unit only starts word / byte bus cycles.
// Oracles: Tom Harte / SingleStepTests 680x0 suite (68000), fx68k / MAME m68000 for timing (checkpoint 2). Own code.
//
// Micro-cycle = 4 phase enables (e1 e2 e3 e0). Per micro-instruction: e0 starts it (and any bus cycle it names);
// e1 latches the branch condition / FIN decision and the write-data selection; e2 forms the next micro-address and
// latches the operands (register-file reads), the bus address check and the write data; e3 latches ALU + AU results
// and writes the AU result to the register file; the next e0 writes the ALU result back (DESIGN.md 2).

module m68ksv_eu #(
    parameter int CPU = 68000,
    parameter int RES = 0             // control storage: 0 = BRAM-heavy (microcode / decode ROMs in M10K), 1 = logic-heavy
                                      // (two-level control store m68ksv_ucs*, drom1 in logic); same behaviour clock for clock
) (
    input  logic        clk,
    input  logic        rst,          // synchronous, active high
    input  logic        e0, e1, e2, e3,
    input  logic        e0w,          // the e0 slot also while e0 waits for the bus (FC changes there: fx68k T1)
    input  logic  [1:0] ph,           // phase counter: 0 after e0, 1 after e1, 2 after e2, 3 after e3
    // BIU
    output logic        bq_go,        // with e0: a bus cycle starts in the micro-cycle that begins now
    output logic  [2:0] bq_op,        // BUS_* of that cycle
    output logic        bq_byte,
    output logic        bq_lw,        // 68020: this read is the high word of a long operand (BIU32 runs one long access)
    output logic        bq_rmc,       // 68020: CAS / CAS2 locked sequence (RMC held, no bus grant) from this access on
    output logic        bq_lock,      // 68020: inside a CAS / CAS2 locked sequence (registered: BR does not hold its cycles back)
    output logic [31:0] b_addr,       // registered at e1 (S1) of a bus cycle, held until the next one
    output logic [15:0] b_dout,
    output logic  [2:0] b_fc,
    output logic        b_abort,      // address error on the current cycle (registered at e1): no data strobes
    output logic        b_ghost,      // 68010 loop mode: opcode prefetch served internally, no bus cycle (held from e2)
    output logic        b_ghost_s2,   // the same decision for the cycle in its first micro-cycle (valid at e2: S2)
    input  logic [15:0] b_din,
    input  logic        b_dv,         // read data valid (with e3)
    input  logic        b_iack_av,    // IACK ended with VPA (autovector)
    input  logic        b_iack_sp,    // IACK ended with BERR (spurious)
    input  logic        b_berr,       // bus error on the current cycle (with e3)
    input  logic  [2:0] ipl,          // interrupt request level (active high, synchronised)
    input  logic        int_pend,     // interrupt pending (level > mask or level-7 edge, from the top)
    output logic  [2:0] int_lvl,      // level being acknowledged (latched with the decision to take it)
    output logic  [2:0] int_inl,      // the level latch as the pending logic sees it (fx68k inl)
    output logic        bq_want,      // the micro-instruction starting at the next e0 names a bus cycle
    output logic        rsto,         // RESET instruction drives RESET_n
    output logic        halted,
    output logic        stopped,
    // debug / harness
    output logic        dbg_fin,      // instruction boundary (with e0)
    output logic [10:0] dbg_upc,
    output logic [31:0] dbg_pc,
    output logic [15:0] dbg_sr,
    output logic [15:0] dbg_ir,
    output logic [15:0] dbg_irc,
    input  logic  [4:0] dbg_ra,       // register read port: 0-7 D0-D7, 8-14 A0-A6, 15 USP, 16 SSP
    output logic [31:0] dbg_rd,       // register dbg_ra as of the previous clock
    output logic [31:0] dbg_vbr,      // 68010 control registers (0 on the 68000 family)
    output logic  [2:0] dbg_sfc,
    output logic  [2:0] dbg_dfc,
    // 68020 (constant 0 elsewhere): cache control to the BIU, control-register debug outputs
    output logic  [1:0] cc_cacr,      // CACR E / F
    output logic        cc_clr,       // clear the whole cache (CACR C written 1; also after reset)
    output logic        cc_ce,        // clear the entry CAAR selects (CACR CE written 1)
    output logic  [5:0] cc_idx,       // CAAR index bits 7-2
    output logic  [1:0] dbg_cacr,
    output logic [31:0] dbg_caar
`ifdef M68KSV_TESTLOAD
    ,
    input  logic        tl_en,
    input  logic [15:0][31:0] tl_r,   // D0-D7 A0-A6, [15] unused
    input  logic [31:0] tl_usp,
    input  logic [31:0] tl_ssp,
    input  logic [15:0] tl_sr,
    input  logic [31:0] tl_pc,
    input  logic [15:0] tl_ir,
    input  logic [15:0] tl_irc,
    output logic [10:0] tl_aeupc,     // harness: micro-address and prefetch address of the last address error
    output logic [31:0] tl_aefpc
`endif
);
import m68ksv_upkg::*;

localparam bit IS020 = (CPU == 68020) || (CPU == 68021);   // 68020 / 68EC020 logic (folds away elsewhere)
localparam bit IS010 = (CPU == 68010) || IS020;   // the 68010 features (VBR, SFC / DFC, MOVEC / MOVES, frames, ...)
localparam bit ISLM  = (CPU == 68010);            // 68010 only: loop mode
localparam logic [15:0] SR_MASK = IS020 ? 16'hf71f : 16'ha71f;   // 68020: T1 T0 S M
// checkpoint 5: the micro-word codes that occur in this build's ROM set (rtl/gen/m68ksv_ucode.py emit_umask, any word
// incl. dead ones and the zero padding). The decode of a code that never occurs is gated off, so the logic behind it
// folds away in that build (exact: uw only ever holds a ROM word or its reset value 0)
localparam logic [15:0] UM_SQ = IS020 ? UM020_SQ : IS010 ? UM010_SQ : UM000_SQ;
localparam logic [31:0] UM_CD = IS020 ? UM020_CD : IS010 ? UM010_CD : UM000_CD;
localparam logic [31:0] UM_DW = IS020 ? UM020_DW : IS010 ? UM010_DW : UM000_DW;
localparam logic [7:0] UM_AD = IS020 ? UM020_AD : IS010 ? UM010_AD : UM000_AD;
localparam logic [31:0] UM_XA = IS020 ? UM020_XA : IS010 ? UM010_XA : UM000_XA;
localparam logic [15:0] UM_XB = IS020 ? UM020_XB : IS010 ? UM010_XB : UM000_XB;
localparam logic [15:0] UM_XD = IS020 ? UM020_XD : IS010 ? UM010_XD : UM000_XD;
localparam logic [63:0] UM_MS = IS020 ? UM020_MS : IS010 ? UM010_MS : UM000_MS;
localparam logic [63:0] UM_FX = IS020 ? UM020_FX : IS010 ? UM010_FX : UM000_FX;
localparam logic  [7:0] UM_CA = IS020 ? UM020_CA : IS010 ? UM010_CA : UM000_CA;     // decoded-class source (drom2)

// ------------------------------------------------------------------------------------------------ state
// register file: MLAB copies m68ksv_rf (DESIGN.md 4); entries 0-14 D0-D7 A0-A6, 15 USP, 16 SSP
logic [15:0] sr, srt;
logic [31:0] fpc;                 // next prefetch address
logic [15:0] ir, irn, irc;
logic        iack_late;           // spurious IACK: IRC taken at the next e0 slot
logic [31:0] at, dt, im, res, pcx, aur, fa;
logic [15:0] finfo, mask;
logic  [6:0] cnt;
logic  [7:0] vec;
logic        aux, auxn;
logic        g0;                  // group-0 exception processing in progress
logic        ae_q;                // the current micro-instruction's bus access faulted: its register / SR writes are cancelled
logic        bwait, late;         // e0 held back for the bus / the current micro-instruction started after such a wait
logic        mc2;                 // the current micro-instruction is the second micro-cycle of a bus cycle
logic [15:0] s_finfo;             // group-0 information of the cycle in progress (taken on a bus error)
logic        s_bn;                // the cycle in progress is an exception-processing access (I/N = 1)
logic        berr_now;
logic        aepc_f;              // group-0 stacked PC (68000 family): fpc (address error after a bus wait), else pc68 - both
                                  // stay as the fault left them until EXC0's first word (LDAEPC) takes them (cp5; generator check)
logic [31:0] pc68, pc68_e2;       // the 68000's PC register (stacked by a bus error) and its value after this e2
logic [15:0] aeir;                // stacked IR: the next opcode for words with field ai (fx68k) (68010 / 68020 builds)
logic        aeir_n;              // 68000 family: the stacked IR (and the access word's IR bits) is IRN, else IR - both stay
                                  // as the fault left them (a FIN word's dispatch moves IRN to IR) until the pushes (cp5)
logic        rsto_r, halt_r, stop_r;
logic        trace_pend;
// 68010 control registers and the extension-word latch of MOVEC / MOVES (constant 0 outside the 68010)
logic [31:0] vbr;
logic  [2:0] sfc, dfc;
logic [15:0] cx;
// 68020: saved full-format extension word, instruction address (format-2 frames), cache control registers
logic [15:0] xw, cx2;
logic [31:0] ppc, caar;
logic [31:0] xt;                  // memory-indirect pointer (full-format extension word)
logic        bo_xp;               // the cycle's read data goes to XT
logic  [1:0] cacr;                // E (enable), F (freeze); CE / C are write-only pulses to the cache (BIU)
logic        c_clr, c_ce;
// 68010 format-8 frame: captured at the fault, pushed, reloaded by RTE (the same registers both ways)
logic [15:0] ssw, dob, dib, f8sr;
logic [23:0] aur_f;
logic [10:0] ua_res;              // micro-address to resume at
logic        fin_f, stage_f, trace_f, g0ae;
logic        ae_jmp;              // 68020: the address error was a JMP's target fetch
logic  [1:0] lay_f, bd_f, lm_f;
logic  [3:0] ver_f;
logic  [5:0] bo_fx;
logic        f8cap, f8cap2;       // capture the faulting word's AUR after its e3
logic  [1:0] bo_ly;
logic        bo_rr;
logic        f8ld;                // the cycle's read data goes to a frame register (RTE), not DT

// micro-sequencer
logic [UW20-1:0] uq, uw;          // ROM output (next micro-instruction), current micro-instruction (the fields of later
                                  // members above UW / UW10 are constant 0 in the 68000 family / 68010)
logic [10:0] ua_r, upc, uret;
/* verilator lint_off UNUSED */      // (read by the RES = 1 control store and the 68010 ROM)
logic        ua_ce;               // ua_r is loaded this clock (reset, test load, e2) ...
logic [10:0] ua_n;                // ... with this value: a ROM read one clock ahead (RES = 1 micro ROM, 68010 ROM)
/* verilator lint_on UNUSED */
logic [10:0] c_cont, c_body;
logic  [1:0] c_sz;
logic  [5:0] c_aluop;
logic  [2:0] c_ca;
logic        c_nofl;


// microword fields
logic  [3:0] u_sq;  logic [10:0] u_nxt; logic [F_CD_W-1:0] u_cd; logic [2:0] u_bus; logic [3:0] u_ba; logic [1:0] u_bs;
logic  [1:0] u_bd;  logic [1:0] u_bf;  logic [4:0] u_dw; logic [F_AA_W-1:0] u_aa;  logic [3:0] u_ab; logic [2:0] u_ad;
logic  [1:0] u_as;  logic [5:0] u_op;  logic [4:0] u_xa; logic [3:0] u_xb;  logic [3:0] u_xd; logic [1:0] u_xs;
logic        u_fl;  logic [F_MS_W-1:0] u_ms; logic u_bn, u_ai, u_iq, u_pl; logic [1:0] u_fh, u_lk, u_lh;
logic  [3:0] u_pu, uq_pu;
logic  [1:0] u_sf, uq_sf;           // 68010 fields (constant 0 elsewhere): MOVES function code, extra ALU destination
logic  [2:0] u_xe;
assign u_sf  = IS010 ? uw[F_SF_LSB +: F_SF_W] : 2'd0;
assign uq_sf = IS010 ? uq[F_SF_LSB +: F_SF_W] : 2'd0;
assign u_xe  = IS010 ? uw[F_XE_LSB +: F_XE_W] : 3'd0;
logic  [5:0] u_fx, uq_fx;          // 68010 format-8 frame fields
logic  [2:0] u_x1, uq_x1;
logic  [1:0] uq_ly;
logic        uq_rr;
assign u_fx  = IS010 ? uw[F_FX_LSB +: F_FX_W] : 6'd0;
assign uq_fx = IS010 ? uq[F_FX_LSB +: F_FX_W] : 6'd0;
assign u_x1  = IS010 ? uw[F_X1_LSB +: F_X1_W] : 3'd0;
assign uq_x1 = IS010 ? uq[F_X1_LSB +: F_X1_W] : 3'd0;
assign uq_ly = IS010 ? uq[F_LY_LSB +: F_LY_W] : 2'd0;
assign uq_rr = IS010 ? uq[F_RR_LSB] : 1'b0;
logic  [5:0] u_c2;
logic  [4:0] u_m2;                 // 68020 fields (constant 0 elsewhere): extra conditions, misc, saved-extension index,
logic        u_xw;                 // write data
logic  [3:0] u_d2;
assign u_d2  = IS020 ? uw[F_D2_LSB +: F_D2_W] : 4'd0;
assign u_c2  = IS020 ? uw[F_C2_LSB +: F_C2_W] : 6'd0;
assign u_m2  = IS020 ? uw[F_M2_LSB +: F_M2_W] : 5'd0;
assign u_xw  = IS020 ? uw[F_XW_LSB] : 1'b0;
assign u_sq  = uw[F_SQ_LSB  +: F_SQ_W];
assign u_nxt = uw[F_NXT_LSB +: F_NXT_W];
assign u_cd  = uw[F_CD_LSB  +: F_CD_W];
assign u_bus = uw[F_BUS_LSB +: F_BUS_W];
assign u_ba  = uw[F_BA_LSB  +: F_BA_W];
assign u_bs  = uw[F_BS_LSB  +: F_BS_W];
assign u_bd  = uw[F_BD_LSB  +: F_BD_W];
assign u_bf  = uw[F_BF_LSB  +: F_BF_W];
assign u_dw  = uw[F_DW_LSB  +: F_DW_W];
assign u_aa  = uw[F_AA_LSB  +: F_AA_W];
assign u_ab  = uw[F_AB_LSB  +: F_AB_W];
assign u_ad  = uw[F_AD_LSB  +: F_AD_W];
assign u_as  = uw[F_AS_LSB  +: F_AS_W];
assign u_op  = uw[F_OP_LSB  +: F_OP_W];
assign u_xa  = uw[F_XA_LSB  +: F_XA_W];
assign u_xb  = uw[F_XB_LSB  +: F_XB_W];
assign u_xd  = uw[F_XD_LSB  +: F_XD_W];
assign u_xs  = uw[F_XS_LSB  +: F_XS_W];
assign u_fl  = uw[F_FL_LSB];
assign u_ms  = uw[F_MS_LSB  +: F_MS_W];
assign u_bn  = uw[F_BN_LSB];              // address error: I/N bit of the access word (exception-processing access)
assign u_iq  = uw[F_IQ_LSB];
assign u_lk  = uw[F_LK_LSB +: 2];          // address error: the word's An write is kept (1: after a bus wait, 2: always)
assign u_pl  = uw[F_PL_LSB];              // address error after a bus wait: the next word's T1 PC load ran during the wait
assign u_ai  = uw[F_AI_LSB];              // address error: stacked IR (and access word IR bits) = the next opcode
assign u_pu  = uw[F_PU_LSB +: F_PU_W];     // the 68000's PC register (pc68) is loaded in this word
assign u_fh  = uw[F_FH_LSB +: F_FH_W];     // long-op flags in two steps (low word, then the held long flags)
assign u_lh  = uw[F_LH_LSB +: 2];          // ALU register write: 1 low word only (long op / An), 2 high word only
assign uq_pu = uq[F_PU_LSB +: F_PU_W];

logic [2:0] uq_bus;
logic [1:0] uq_bs;
assign uq_bus = uq[F_BUS_LSB +: F_BUS_W];
assign uq_bs  = uq[F_BS_LSB  +: F_BS_W];

// ------------------------------------------------------------------------------------------------ decode pipeline
// irn -> drom1 / drom4e (1 clk) -> class -> drom2 (1 clk) -> kinds -> drom3 (1 clk) -> routine addresses
function automatic logic [3:0] modeidx(input logic [5:0] ea);
    case (ea[5:3])
    3'd0: modeidx = 4'd0;  3'd1: modeidx = 4'd1;  3'd2: modeidx = 4'd2;  3'd3: modeidx = 4'd3;
    3'd4: modeidx = 4'd4;  3'd5: modeidx = 4'd5;  3'd6: modeidx = 4'd6;
    default: case (ea[2:0])
        3'd0: modeidx = 4'd7; 3'd1: modeidx = 4'd8; 3'd2: modeidx = 4'd9; 3'd3: modeidx = 4'd10; 3'd4: modeidx = 4'd11;
        default: modeidx = 4'd15;
        endcase
    endcase
endfunction

function automatic logic mode_ok(input logic [3:0] v, input logic [3:0] mi);
    if (v[3]) mode_ok = (v == V_CALT) && ((mi == 4'd2) || ((mi >= 4'd5) && (mi <= 4'd8)));   // 68020 only
    else case (v[2:0])
    V_NOEA:   mode_ok = 1'b1;
    V_ALL:    mode_ok = mi <= 4'd11;
    V_ALT:    mode_ok = mi <= 4'd8;
    V_CTRL:   mode_ok = (mi == 4'd2) || ((mi >= 4'd5) && (mi <= 4'd10));
    V_MALT:   mode_ok = (mi >= 4'd2) && (mi <= 4'd8);
    V_CTRLPD: mode_ok = (mi == 4'd2) || ((mi >= 4'd4) && (mi <= 4'd8));
    V_CTRLPI: mode_ok = (mi == 4'd2) || (mi == 4'd3) || ((mi >= 4'd5) && (mi <= 4'd10));
    V_DATA:   mode_ok = (mi != 4'd1) && (mi <= 4'd11);
    default:  mode_ok = 1'b0;
    endcase
endfunction

function automatic logic [1:0] szrule(input logic [2:0] r, input logic [15:0] op);
    case (r)
    SZR_STD:  szrule = (op[7:6] == 2'd3) ? 2'd1 : op[7:6];
    SZR_MOVE: szrule = (op[13:12] == 2'd1) ? 2'd0 : (op[13:12] == 2'd3) ? 2'd1 : 2'd2;
    SZR_A8:   szrule = op[8] ? 2'd2 : 2'd1;
    SZR_B:    szrule = 2'd0;
    SZR_W:    szrule = 2'd1;
    SZR_L:    szrule = 2'd2;
    SZR_BIT:  szrule = (op[5:3] == 3'd0) ? 2'd2 : 2'd0;
    default:  szrule = op[6] ? 2'd2 : 2'd1;      // SZR_B6
    endcase
endfunction

logic [35:0] d1q;                 // [35]: 68020 validity bit 3 (0 elsewhere)
logic  [8:0] d1lp, d1lpr;         // 68010: loopable() of IRN's / IR's opcode row for EA modes Dn / An / (An), (An)+, -(An)
logic  [2:0] lp_irn;              // loopable(IRN) / loopable(IR) (cp5: from m68ksv_drom1lp_010, registered two clocks after
logic  [1:0] lp_ir;               // IRN / IR change; read by X1_LMDZ at the e0 that ends the NPF word that loaded IRN, and by
                                  // X1_SRF, whose word never starts right after an IR change)
logic  [7:0] d4q;
logic [33:0] d2q;                 // [33]: 68020 change-of-flow class (T0 trace; 0 elsewhere)
logic [10:0] d3qa, d3qb;
logic  [7:0] d_cls;
logic  [3:0] d_mi;
logic  [1:0] d_cat;

// per-member ROM sets (rtl/gen/m68ksv_ucode.py): 68000 family / 68010; only the selected set is instantiated
logic  [7:0] d_cls_q;
logic  [7:0] d3aa, d3ab;
generate
if (IS020) begin : g_rom020
    if (RES == 1) begin : g_lh
        m68ksv_ucs_020      ucs   (.clk(clk), .ce(ua_ce), .an(ua_n), .q(uq));
        m68ksv_drom1_020_lh drom1 (.clk(clk), .a(irn[15:6]), .q(d1q));
    end else begin : g_bh
        m68ksv_urom_020     urom  (.clk(clk), .a(ua_r), .q(uq));
        m68ksv_drom1_020    drom1 (.clk(clk), .a(irn[15:6]), .q(d1q));
    end
    assign d1lp = 9'd0;
    assign d1lpr = 9'd0;
    m68ksv_drom4e_020 drom4e (.clk(clk), .a(irn[5:0]),  .q(d4q));
    m68ksv_drom2_020  drom2  (.clk(clk), .a(d_cls_q), .q(d2q));
    m68ksv_drom3_020  drom3  (.clk(clk), .aa(d3aa), .ab(d3ab), .qa(d3qa), .qb(d3qb));
end else if (IS010) begin : g_rom010
    logic [UW10-1:0] uq10;
    if (RES == 1) begin : g_lh
        m68ksv_ucs_010        ucs     (.clk(clk), .ce(ua_ce), .an(ua_n), .q(uq10));
        m68ksv_drom1_010_lh   drom1   (.clk(clk), .a(irn[15:6]), .q(d1q[34:0]));
        m68ksv_drom1lp_010_lh drom1lp (.clk(clk), .aa(irn[15:6]), .ab(ir[15:6]), .qa(d1lp), .qb(d1lpr));
    end else begin : g_bh
        m68ksv_urom_010       urom    (.clk(clk), .ce(ua_ce), .an(ua_n), .q(uq10));   // 1,024 + 512 words, read ahead (cp6)
        m68ksv_drom1_010      drom1   (.clk(clk), .a(irn[15:6]), .q(d1q[34:0]));
        m68ksv_drom1lp_010    drom1lp (.clk(clk), .aa(irn[15:6]), .ab(ir[15:6]), .qa(d1lp), .qb(d1lpr));
    end
    assign uq = {{(UW20-UW10){1'b0}}, uq10};
    assign d1q[35] = 1'b0;
    m68ksv_drom4e_010 drom4e (.clk(clk), .a(irn[5:0]),  .q(d4q));
    m68ksv_drom2_010  drom2  (.clk(clk), .a(d_cls_q), .q(d2q[32:0]));
    assign d2q[33] = 1'b0;
    m68ksv_drom3_010  drom3  (.clk(clk), .aa(d3aa), .ab(d3ab), .qa(d3qa), .qb(d3qb));
end else begin : g_rom000
    logic [UW-1:0] uq0;
    if (RES == 1) begin : g_lh
        m68ksv_ucs      ucs   (.clk(clk), .ce(ua_ce), .an(ua_n[UA000_W-1:0]), .q(uq0));
        m68ksv_drom1_lh drom1 (.clk(clk), .a(irn[15:6]), .q(d1q[34:0]));
    end else begin : g_bh
        m68ksv_urom     urom  (.clk(clk), .a(ua_r[UA000_W-1:0]), .q(uq0));   // compacted ROM (cp6): every address < 1,024
        m68ksv_drom1    drom1 (.clk(clk), .a(irn[15:6]), .q(d1q[34:0]));
    end
    assign uq = {{(UW20-UW){1'b0}}, uq0};
    assign d1q[35] = 1'b0;
    assign d1lp = 9'd0;
    assign d1lpr = 9'd0;
    m68ksv_drom4e drom4e (.clk(clk), .a(irn[5:0]),  .q(d4q));
    m68ksv_drom2  drom2  (.clk(clk), .a(d_cls_q), .q(d2q[32:0]));
    assign d2q[33] = 1'b0;
    m68ksv_drom3  drom3  (.clk(clk), .aa(d3aa), .ab(d3ab), .qa(d3qa), .qb(d3qb));
end
endgenerate

assign d_mi  = modeidx(irn[5:0]);
assign d_cat = (d_mi == 4'd0) ? 2'd0 : (d_mi == 4'd1) ? 2'd1 : (d_mi == 4'd11) ? 2'd3 : 2'd2;
always_comb begin
    if (irn[15:6] == 10'h139) d_cls = d4q;
    else begin
        case (d_cat)
        2'd0: d_cls = d1q[7:0];
        2'd1: d_cls = d1q[15:8];
        2'd2: d_cls = d1q[23:16];
        default: d_cls = d1q[31:24];
        endcase
        if (d_cat == 2'd2 && !mode_ok(d1q[35:32], d_mi)) d_cls = IS020 ? CLS20_ILL : CLS_ILL;
        // 68020 TRAPcc: Scc's (d16,PC) / (d8,PC,Xn) / #imm slots (5xFA / 5xFB / 5xFC)
        if (IS020 && irn[15:12] == 4'h5 && irn[7:3] == 5'b11111 && irn[2:0] >= 3'd2 && irn[2:0] <= 3'd4)
            d_cls = CLS20_TRAPCC;
    end
end
// class register (stage 2): drom2 is addressed one clock later; the whole chain is ready five clocks after IRN is
// loaded, one clock before the FIN micro-instruction's next address is formed (its e2, at least six clocks later)
always_ff @(posedge clk) d_cls_q <= d_cls;
// 68010 loop mode: loopable(IRN) (entry check, X1_LMDZ) and loopable(IR) (idle words of a loop rebuilt by a format-8 RTE,
// X1_SRF) from m68ksv_drom1lp_010 by the EA mode, registered
always_ff @(posedge clk) begin
    lp_irn <= !ISLM ? 3'd0 : (d_mi == 4'd0) ? d1lp[2:0] : (d_mi == 4'd1) ? d1lp[5:3] :
              (d_mi == 4'd2 || d_mi == 4'd3 || d_mi == 4'd4) ? d1lp[8:6] : 3'd0;
    lp_ir  <= !ISLM ? 2'd0 : (ir[5:3] == 3'd0) ? d1lpr[1:0] : (ir[5:3] == 3'd1) ? d1lpr[4:3] :
              (ir[5:3] == 3'd2 || ir[5:3] == 3'd3 || ir[5:3] == 3'd4) ? d1lpr[7:6] : 2'd0;
end

logic [10:0] d_body;
logic  [3:0] d_k1, d_k2;
logic  [5:0] d_aluop;
logic  [2:0] d_ca, d_szr;
logic        d_nofl, d_priv;
logic  [1:0] d_sz;
assign d_body  = d2q[10:0];
assign d_k1    = d2q[14:11];
assign d_k2    = d2q[18:15];
assign d_aluop = d2q[24:19];
assign d_ca    = d2q[27:25];
assign d_szr   = d2q[30:28];
assign d_nofl  = d2q[31];
assign d_priv  = d2q[32];
assign d_sz    = szrule(d_szr, irn);

function automatic logic [3:0] kind3(input logic [3:0] k, input logic [1:0] sz);
    case (k)
    K_RD:    kind3 = (sz == 2'd2) ? K3_RDL : K3_RDW;
    K_IMM:   kind3 = (sz == 2'd2) ? K3_IMML : K3_IMMW;
    K_IMMB:  kind3 = K3_IMMW;
    K_ADDR:  kind3 = K3_ADDR;
    K_JMP:   kind3 = K3_JMP;
    K_JSR:   kind3 = K3_JSR;
    K_LEA:   kind3 = K3_LEA;
    K_PEA:   kind3 = K3_PEA;
    K_TAS:   kind3 = K3_TAS;
    K_MVRM:  kind3 = (sz == 2'd2) ? K3_MVRML : K3_MVRMW;
    K_MVMR:  kind3 = (sz == 2'd2) ? K3_MVMRL : K3_MVMRW;
    K_XWD:   kind3 = K3_XWD;           // 68010 (MOVES extension word)
    K_CLRW:  kind3 = K3_CLRW;          // 68010 (CLR without the read)
    default: kind3 = 4'd15;
    endcase
endfunction
assign d3aa = {kind3(d_k1, d_sz), d_mi};
assign d3ab = {kind3(d_k2, d_sz), d_mi};

logic d_bcc_q, d_bsr_q;
assign d_bcc_q = d_cls_q == (IS020 ? CLS20_BCC : CLS_BCC);
assign d_bsr_q = d_cls_q == (IS020 ? CLS20_BSR : CLS_BSR);

// routine chain: [k1 routine] [k2 routine] body
logic [10:0] d_bodyx, d_first, d_cont;
logic        d_u1, d_u2;
always_comb begin
    d_bodyx = d_body;
    if (d_bcc_q) d_bodyx = (irn[7:0] == 8'd0) ? UA_BCC_W : (IS020 && irn[7:0] == 8'hff) ? U20_BCC_L : UA_BCC_S;
    if (d_bsr_q) d_bodyx = (irn[7:0] == 8'd0) ? UA_BSR_W : (IS020 && irn[7:0] == 8'hff) ? U20_BSR_L : UA_BSR_S;
    d_u1 = (d_k1 != K_NONE) && (d3qa != UA_SKIP);
    d_u2 = (d_k2 != K_NONE) && (d3qb != UA_SKIP);
    if (d_u1) begin
        d_first = d3qa;
        d_cont  = d_u2 ? d3qb : d_bodyx;
    end else if (d_u2) begin
        d_first = d3qb;
        d_cont  = d_bodyx;
    end else begin
        d_first = d_bodyx;
        d_cont  = d_bodyx;
    end
end
// exception entries for the I/N bit of a group-0 access word (in_exc_nx)
function automatic logic is_exc(input logic [10:0] a);
    is_exc = (a == UA_TRACE) || (a == UA_INT) || (a == UA_PRIV) || (a == UA_ILL) || (a == UA_LA) || (a == UA_LF);
endfunction
// decode result register (free-running): valid one clock after drom3, i.e. five clocks after IRN is loaded; the FIN
// micro-instruction forms its next address at its e2, at least six clocks after IRN is loaded (the generator keeps
// FIN out of the word that starts the final prefetch)
logic [10:0] q_first, q_cont, q_bodyx;
logic        q_exc;           // q_first is a group 1 / illegal / privilege entry (in_exc_nx below, without the compare)
logic  [1:0] q_sz;
logic  [5:0] q_aluop;
logic  [2:0] q_ca;
logic        q_nofl, q_priv;
logic        q_flow;          // 68020: the decoded instruction changes the flow (T0 trace)
always_ff @(posedge clk) q_flow <= IS020 && d2q[33];
always_ff @(posedge clk) begin
    q_first <= d_first;
    q_exc   <= is_exc(d_first);
    q_cont  <= d_cont;
    q_bodyx <= d_bodyx;
    q_sz    <= d_sz;
    q_aluop <= d_aluop;
    q_ca    <= d_ca;
    q_nofl  <= d_nofl;
    q_priv  <= d_priv;
end

// ------------------------------------------------------------------------------------------------ operand selection
logic [3:0] ix_dx, ix_ax, ix_dy, ix_ay, ix_rxe, ix_rye, ix_mreg, ix_ryea;
logic       xbank, ybank;
logic [3:0] m_idx;
logic       pdmode, aupd;
logic [3:0] mi_ir;
assign mi_ir   = modeidx(ir[5:0]);
assign ix_dx   = {1'b0, ir[11:9]};
assign ix_ax   = {1'b1, ir[11:9]};
assign ix_dy   = {1'b0, ir[2:0]};
assign ix_ay   = {1'b1, ir[2:0]};
assign ix_ryea = {mi_ir == 4'd1, ir[2:0]};
assign xbank   = (ir[7:3] == 5'b01001);                   // EXG Ax,Ay
assign ybank   = (ir[7:3] == 5'b01001) || (ir[7:3] == 5'b10001);
assign ix_rxe  = {xbank, ir[11:9]};
assign ix_rye  = {ybank, ir[2:0]};
assign pdmode  = ir[5:3] == 3'd4;
logic       exg_dd;
assign exg_dd  = (ir[15:12] == 4'hc) && (ir[8:3] == 6'b101000);
assign aupd    = (ir[5:3] == 3'd4) || (ir[5:3] == 3'd3);
// m_idx = lowest set bit of the MOVEM mask, kept in a register updated together with the mask (e0)
logic [3:0]  m_ld, m_nx, m_ldt;
logic [15:0] m_rest;
assign m_rest = mask & ~(16'd1 << m_idx);
always_comb begin
    m_ld = 4'd0;
    m_nx = 4'd0;
    m_ldt = 4'd0;
    for (int i = 15; i >= 0; i--) begin
        if (irc[i]) m_ld = i;
        if (m_rest[i]) m_nx = i;
        if (IS010 && dt[16 + i]) m_ldt = i;
    end
end
assign ix_mreg = pdmode ? ~m_idx : m_idx;

// register file read ports: X (ALU A), B (ALU B), A (address unit / bus address), D (write data), N (index)
logic [3:0]  ix_px, ix_pb, ix_pa, ix_pd;
always_comb begin
    case (u_xa)
    XA_DX:   ix_px = ix_dx;
    XA_DY:   ix_px = ix_dy;
    XA_AY:   ix_px = ix_ay;
    XA_AX:   ix_px = UM_XA[XA_AX] ? ix_ax : ix_ryea;
    XA_RXE:  ix_px = ix_rxe;
    XA_RYE:  ix_px = ix_rye;
    XA_SP:   ix_px = UM_XA[XA_SP] ? 4'd15 : ix_ryea;
    XA_RC:   ix_px = cx[15:12];
    XA_RCO:  ix_px = IS020 ? {1'b0, cx[8:6]} : ix_ryea;                // 68020: bit-field offset register
    XA_RCC:  ix_px = IS020 ? {1'b0, cx[2:0]} : ix_ryea;                // 68020: CAS compare register
    XA_RCL:  ix_px = IS020 ? {1'b0, cx[14:12]} : ix_ryea;              // 68020: bit-field insert register
    XA_AYLK: ix_px = ix_ay;
    XA_CA:   ix_px = (c_ca == CA_DX) ? ix_dx : (UM_CA[CA_DY] && c_ca == CA_DY) ? ix_dy : ix_ryea;
    default: ix_px = ix_ryea;
    endcase
    case (u_xb)
    XB_RC:   ix_pb = IS020 ? {1'b0, cx[14:12]} : ix_ryea;             // 68020: Dl / Dq of MUL.L / DIV.L
    XB_RCH:  ix_pb = IS020 ? {1'b0, cx[2:0]} : ix_ryea;               // Dh / Dr
    XB_DX:   ix_pb = ix_dx;
    XB_DY:   ix_pb = ix_dy;
    XB_AX:   ix_pb = ix_ax;
    XB_AY:   ix_pb = ix_ay;
    XB_RYE:  ix_pb = UM_XB[XB_RYE] ? ix_rye : ix_ryea;
    default: ix_pb = ix_ryea;
    endcase
    case (u_aa)
    AA_AX:   ix_pa = ix_ax;
    AA_FBX:  ix_pa = IS020 ? ix_ax : ix_ay;
    AA_SP, AA_SSP: ix_pa = 4'd15;
    AA_AY:   ix_pa = ix_ay;
    default: ix_pa = (u_ba == BA_AX) ? ix_ax : (u_ba == BA_SP) ? 4'd15 : ix_ay;
    endcase
    case (u_dw)
    DW_MRL, DW_MRH: ix_pd = ix_mreg;
    DW_AYL, DW_AYH: ix_pd = (UM_DW[DW_AYL] || UM_DW[DW_AYH]) ? ix_ay : ix_ryea;
    DW_RC1, DW_RCL: ix_pd = cx[15:12];
    default:        ix_pd = ix_ryea;
    endcase
end
// Three register-file copies serve the read ports; each read address is registered every clock and the data is used
// at e2 (operands, bus address / data) or e0 (old value for a byte / word merge), never in the clock after a write:
//   copy XN: X (ALU A) or N (index register; the generator checks a micro-instruction never uses both)
//   copy A:  A (address-unit base and bus address)
//   copy BW: B (ALU B) or D (write data; never both), and in phases 2-3 W (merge source of the e0 ALU write)
// Entry 15 / 16 = USP / SSP: A7 is entry 15 + S, so an S change needs no copy or swap.
function automatic logic [4:0] phys(input logic [3:0] ix, input logic s, input logic m);
    phys = (ix == 4'd15 && s) ? (m ? 5'd17 : 5'd16) : {1'b0, ix};       // 68020: entry 17 = MSP (S and M set)
endfunction
logic msp, msp_n;                 // 68020: A7 is the MSP (S and M set), now / after this e0 (0 elsewhere)
assign msp   = IS020 && sr[12];
assign msp_n = IS020 && sr_n[12];
logic [31:0] rd_xn, rd_a, rd_bw;
logic [31:0] r_px, r_pb, r_pa, r_pd, r_xn;
logic  [4:0] p_osp;
assign p_osp = sr[13] ? 5'd15 : 5'd16;       // inactive stack pointer (MOVE USP)
logic  [4:0] p_ctl;                           // MOVEC register-file control registers: USP; 68020 ISP / MSP
assign p_ctl = (IS020 && cx[2]) ? 5'd16 : (IS020 && cx[1:0] == 2'd3) ? 5'd17 : p_osp;
assign r_px  = rd_xn;
assign r_pb  = rd_bw;
assign r_pa  = rd_a;
assign r_pd  = rd_bw;
// index operand (brief extension word in IRC; 68020: scaled, or from the saved full-format extension word, field xw)
logic [15:0] ixw;
logic [31:0] r_xn0;
assign ixw   = (IS020 && u_xw) ? xw : irc;
assign r_xn0 = ixw[11] ? rd_xn : {{16{rd_xn[15]}}, rd_xn[15:0]};
always_comb begin
    if (!IS020) r_xn = r_xn0;
    else case (ixw[10:9])
    2'd0:    r_xn = r_xn0;
    2'd1:    r_xn = {r_xn0[30:0], 1'b0};
    2'd2:    r_xn = {r_xn0[29:0], 2'b00};
    default: r_xn = {r_xn0[28:0], 3'b000};
    endcase
end

// effective-address operand: register (Dn / An modes), immediate (IM) or memory operand (DT), per read port (ALU A / B:
// resolved in the operand source decode below)
logic        eav_reg, eav_imm;
logic [31:0] eav_d;
assign eav_reg = mi_ir <= 4'd1;
assign eav_imm = mi_ir == 4'd11;
assign eav_d = eav_reg ? r_pd : eav_imm ? im : dt;

// operation size of the current micro-instruction
logic [1:0] xsz;
assign xsz = (u_xs == XS_OPSZ) ? c_sz : (u_xs == XS_BYTE) ? 2'd0 : (u_xs == XS_WORD) ? 2'd1 : 2'd2;

// AU increment / decrement amount
logic       a7sel;
logic [2:0] incv;
always_comb begin
    case (u_aa)
    AA_AY:   a7sel = ir[2:0] == 3'd7;
    AA_AX:   a7sel = ir[11:9] == 3'd7;
    AA_SP, AA_SSP: a7sel = 1'b1;
    default: a7sel = 1'b0;
    endcase
    case (u_as)
    AS_OPSZ: incv = (c_sz == 2'd0) ? (a7sel ? 3'd2 : 3'd1) : (c_sz == 2'd1) ? 3'd2 : 3'd4;
    AS_BYTE: incv = a7sel ? 3'd2 : 3'd1;
    AS_WORD: incv = 3'd2;
    default: incv = (c_sz == 2'd0) ? (a7sel ? 3'd2 : 3'd1) : 3'd2;     // AS_OPW
    endcase
end

// displacement - 2 (branches, PC-relative): narrow subtractors, then sign extension
logic  [8:0] bd8m2, d8m2;
logic [16:0] bd16m2;
assign bd8m2  = {ir[7], ir[7:0]} - 9'd2;
assign d8m2   = {irc[7], irc[7:0]} - 9'd2;
assign bd16m2 = {irc[15], irc} - 17'd2;
logic [31:0] au_a, au_b;
always_comb begin
    case (u_aa)
    AA_AY, AA_AX, AA_SP, AA_SSP: au_a = r_pa;
    AA_AT:   au_a = at;
    AA_FPC:  au_a = fpc;
    AA_PCX:  au_a = pcx;
    AA_DT:   au_a = dt;
    AA_FBY, AA_FBX: au_a = (IS020 && !irc[7]) ? r_pa : 32'd0;          // 68020 full format: base, 0 when BS
    AA_FBP:  au_a = !IS020 ? 32'd0 : irc[7] ? 32'd2 : fpc;             // (with ab M2: the extension word's address / 0)
    AA_XT:   au_a = IS020 ? xt : 32'd0;
    AA_BFA:  au_a = IS020 ? bf_ea : 32'd0;
    default: au_a = 32'd0;
    endcase
    case (u_ab)
    AB_INC:  au_b = {29'd0, incv};
    AB_DEC:  au_b = -{29'd0, incv};
    AB_P2:   au_b = 32'd2;
    AB_M2:   au_b = 32'hffff_fffe;
    AB_P4:   au_b = 32'd4;
    AB_M4:   au_b = 32'hffff_fffc;
    AB_D16:  au_b = {{16{irc[15]}}, irc};
    AB_D8:   au_b = {{24{irc[7]}}, irc[7:0]};
    AB_BD8:  au_b = {{23{bd8m2[8]}}, bd8m2};
    AB_BD16: au_b = {{15{bd16m2[16]}}, bd16m2};
    AB_D8M2: au_b = {{23{d8m2[8]}}, d8m2};
    AB_XN:   au_b = r_xn;
    AB_IRCH: au_b = {irc, 16'd0};
    AB_IRCZ: au_b = {16'd0, irc};
    AB_DT:   au_b = dt;
    default: au_b = 32'd0;
    endcase
end

logic [31:0] xa_v, xb_v;
// ALU A operand: the micro-instruction's source is first resolved to one of the data sources below (a small decode
// shared by all bits), then one flat 32-bit mux
localparam logic [3:0] XQ_ZERO = 4'd0, XQ_RPX = 4'd1, XQ_IM = 4'd2, XQ_DT = 4'd3, XQ_AT = 4'd4, XQ_RES = 4'd5,
                       XQ_FPC = 4'd6, XQ_PCX = 4'd7, XQ_VBR = 4'd8, XQ_SR = 4'd9, XQ_IRC = 4'd10, XQ_IRQ8 = 4'd11,
                       XQ_QUICK = 4'd12, XQ_ONE = 4'd13, XQ_CCR = 4'd14, XQ_FC = 4'd15;
logic [3:0] xq, xq_eav, xbq;
assign xq_eav = eav_reg ? XQ_RPX : eav_imm ? XQ_IM : XQ_DT;           // EA operand: Dn / An, #imm or memory
always_comb begin
    case (u_xa)
    XA_ONE:   xq = XQ_ONE;
    XA_EAV:   xq = xq_eav;
    XA_EAVM:  xq = (eav_reg && ir[2:0] == ir[11:9]) ? XQ_AT : xq_eav;   // MUL source: Dn's copy in AT when it is Dx itself
    XA_DX, XA_DY, XA_AY, XA_AX, XA_RXE, XA_RYE, XA_SP: xq = XQ_RPX;
    XA_DT:    xq = XQ_DT;
    XA_IM:    xq = XQ_IM;
    XA_RES:   xq = XQ_RES;
    XA_QUICK: xq = XQ_QUICK;
    XA_IRC:   xq = XQ_IRC;
    XA_SR:    xq = XQ_SR;
    XA_AT:    xq = XQ_AT;
    XA_FPC:   xq = XQ_FPC;
    XA_CA:    case (c_ca)                                               // the decoded class's source
              CA_DX, CA_DY: xq = XQ_RPX;
              CA_IM:    xq = XQ_IM;
              CA_QUICK: xq = XQ_QUICK;
              CA_SR:    xq = XQ_SR;
              CA_EAV:   xq = xq_eav;
              CA_CCR:   xq = (IS010 && UM_CA[CA_CCR]) ? XQ_CCR : XQ_ZERO;
              default:  xq = XQ_ZERO;
              endcase
    XA_IRQ8:  xq = XQ_IRQ8;
    XA_OSP:   xq = XQ_RPX;
    // 68010: control register (SFC / DFC / USP / VBR by the MOVEC code), extension-word register, CCR, PCX
    XA_CTL:   xq = !IS010 ? XQ_ZERO : !cx[11] ? XQ_FC :                // 68020: VBR / CAAR, CACR on XQ_FC
                   IS020 ? ((cx[1:0] == 2'd1 || cx[1:0] == 2'd2) ? XQ_VBR : XQ_RPX) : (cx[0] ? XQ_VBR : XQ_RPX);
    XA_RC:    xq = IS010 ? XQ_RPX : XQ_ZERO;
    XA_RCO, XA_RCC, XA_RCL: xq = IS020 ? XQ_RPX : XQ_ZERO;
    XA_CCR:   xq = IS010 ? XQ_CCR : XQ_ZERO;
    XA_PCX:   xq = IS010 ? XQ_PCX : XQ_ZERO;
    XA_AYLK:  xq = (IS010 && ir[2:0] == 3'd7) ? XQ_AT : XQ_RPX;      // LINK A7: the decremented A7 (Musashi)
    default:  xq = XQ_ZERO;
    endcase
    case (xq)
    XQ_RPX:   xa_v = r_px;
    XQ_IM:    xa_v = im;
    XQ_DT:    xa_v = dt;
    XQ_AT:    xa_v = at;
    XQ_RES:   xa_v = res;
    XQ_FPC:   xa_v = fpc;
    XQ_PCX:   xa_v = IS010 ? pcx : 32'd0;
    XQ_VBR:   xa_v = (IS020 && cx[1]) ? caar : IS010 ? vbr : 32'd0;
    XQ_SR:    xa_v = {16'd0, sr};
    XQ_IRC:   xa_v = {{16{irc[15]}}, irc};
    XQ_IRQ8:  xa_v = {{24{ir[7]}}, ir[7:0]};
    XQ_QUICK: xa_v = {28'd0, ir[11:9] == 3'd0, ir[11:9]};
    XQ_ONE:   xa_v = 32'd1;
    XQ_CCR:   xa_v = IS010 ? {27'd0, sr[4:0]} : 32'd0;
    XQ_FC:    xa_v = (IS020 && cx[1]) ? {30'd0, cacr} : IS010 ? {29'd0, cx[0] ? dfc : sfc} : 32'd0;
    default:  xa_v = 32'd0;
    endcase
    // ALU B operand: the same scheme (the EA operand resolved first)
    case (u_xb)
    XB_EAV:  xbq = eav_reg ? XB_DX : eav_imm ? XB_IM : XB_DT;              // EA operand (r_pb / IM / DT)
    XB_DX, XB_DY, XB_AX, XB_AY, XB_RYE: xbq = XB_DX;
    XB_RC, XB_RCH: xbq = IS020 ? XB_DX : XB_ZERO;
    XB_DT, XB_RES, XB_IM, XB_SR, XB_AT, XB_M2, XB_M4: xbq = u_xb;
    default: xbq = XB_ZERO;
    endcase
    case (xbq)
    XB_DX:   xb_v = r_pb;
    XB_DT:   xb_v = dt;
    XB_RES:  xb_v = UM_XB[XB_RES] ? res : 32'd0;           // (no ROM set uses xb RES)
    XB_IM:   xb_v = im;
    XB_SR:   xb_v = {16'd0, sr};
    XB_AT:   xb_v = at;
    XB_M2:   xb_v = 32'hffff_fffe;
    XB_M4:   xb_v = 32'hffff_fffc;
    default: xb_v = 32'd0;
    endcase
end

// ------------------------------------------------------------------------------------------------ condition codes
function automatic logic cctest(input logic [3:0] c, input logic [4:0] f);
    logic n, z, v, cc;
    n = f[3]; z = f[2]; v = f[1]; cc = f[0];
    case (c)
    4'h0: cctest = 1'b1;          4'h1: cctest = 1'b0;
    4'h2: cctest = ~cc & ~z;      4'h3: cctest = cc | z;
    4'h4: cctest = ~cc;           4'h5: cctest = cc;
    4'h6: cctest = ~z;            4'h7: cctest = z;
    4'h8: cctest = ~v;            4'h9: cctest = v;
    4'ha: cctest = ~n;            4'hb: cctest = n;
    4'hc: cctest = n == v;        4'hd: cctest = n != v;
    4'he: cctest = ~z & (n == v); default: cctest = z | (n != v);
    endcase
endfunction
logic cc_ir, cc_irq;                // cc_irq: latched at e2 for the ALU (Scc result at e3; SR / IR do not change between)
assign cc_ir = cctest(ir[11:8], sr[4:0]);

// interrupts: pending flag from the top (synchronised on the phase enables like the 68000); the level is latched
// at the FIN decision and used for IACK, the autovector and the new mask
logic       irq_pend, irq_npf, npf_now, in_exc;
logic [1:0] iq_early;            // the interrupt sample word waited for the bus: 1 level latched, 2 decision latched
logic [2:0] ilvl;
logic [2:0] inl_v;
logic       inl_ovr;
assign int_inl = inl_ovr ? inl_v : int_lvl;
// 68020 (cp4b): the pending interrupt also needs the sampled level to be above the mask (or 7) now - with one micro-cycle
// per clock the level latch (e0) and the decision (e2) see the same sample, so a level withdrawn before the decision is
// not acknowledged at a level the mask would refuse (with the 68000 phases a falling edge between them clears int_pend)
assign irq_pend = int_pend && (!IS020 || (ipl == 3'd7) || (ipl > sr[10:8]));
assign npf_now  = u_iq;                                         // the IRC -> IR micro-word: interrupt sample point
assign ilvl     = int_lvl;

// divider
logic [15:0] dv_r, dv_q, dv_d;
logic        dv_sq, dv_sr, dv_z, dv_ov, dv_done, dv_s_r;
logic        dv_ovl;
logic  [4:0] dv_ext;              // DIVU: extra micro-cycles of the 68000's first 15 steps
logic        dv_dsn;              // DIVS: divisor negative
logic  [3:0] dv_q1;               // DIVS: ones in quotient bits 15-1
always_comb begin
    dv_q1 = 4'd0;
    for (int i = 1; i < 16; i++) dv_q1 = dv_q1 + {3'd0, dv_q[i]};
end
assign dv_ovl = dv_sq ? (dv_q > 16'h8000) : (dv_s_r && dv_q > 16'h7fff);

// ------------------------------------------------------------------------------------------------ 68010 loop mode
// (data sheet 7.1.3; User's Manual appendix A). lm: loop mode active; lbase: address of the looped instruction;
// lw0 / lw1: looped opcode / DBcc opcode (the displacement word is -4); lm_db: the looped instruction's prefetch of the
// displacement word has run (its FIN goes to the DBcc loop word); lmd: idle words before the loop word (timing class);
// lm_dyz: the DBcc counter's low word is 0 (the next DBcc expires); lm_dyzv: lm_dyz valid (else the normal DBcc
// microcode runs, its fetches still internal); lq_*: the looped instruction's decode, kept for its dispatch.
logic        lm, lm_db, lm_cand, lm_dyz, lm_dyzv, lm_cap, lmc_q, ghost;
logic        lm_keep;             // the loop registers still hold the loop of the last fault (no loop entered since)
logic [23:0] lbase;
logic [15:0] lw0, lw1, ghost_d;
logic  [1:0] lmd;
logic [10:0] lq_first, lq_cont, lq_bodyx;
logic        lq_exc;
logic  [1:0] lq_sz;
logic  [5:0] lq_aluop;
logic  [2:0] lq_ca;
logic        lq_nofl;
// loopable one-word instructions (data sheet table 7-3) -> {loopable, idle words}: cp5 - the table lives in the generator
// (rtl/gen/m68ksv_ucode.py loopable(), m68ksv_drom1lp_010): lp_irn / lp_ir above
// DBcc counter written by the looped instruction (<ea>,Dn forms with Dn = the counter): keep the slow DBcc
function automatic logic lm_wdy(input logic [15:0] op, input logic [2:0] dy);
    lm_wdy = (op[15:12] == 4'h8 || op[15:12] == 4'h9 || op[15:12] == 4'hc || op[15:12] == 4'hd) &&
             !op[8] && (op[7:6] != 2'd3) && (op[11:9] == dy);
endfunction

logic cond;
always_comb begin
    case (u_cd)
    CD_T:      cond = 1'b1;
    CD_CC:     cond = cc_ir;
    CD_SZL:    cond = c_sz == 2'd2;
    CD_CNTNZ:  cond = cnt != 7'd0;
    CD_CNTGT1: cond = cnt > 7'd1;
    CD_MASKNZ: cond = mask != 16'd0;
    CD_DBEXP:  cond = res[15:0] == 16'hffff;
    CD_VSET:   cond = sr[1];
    CD_AUX:    cond = aux;
    CD_IRQ:    cond = irq_pend || trace_pend;
    CD_SUP:    cond = UM_CD[CD_SUP] && sr[13];
    CD_DIVZ:   cond = dv_z;
    CD_DIVOV:  cond = dv_ov || (dv_done && dv_ovl);
    CD_PD:     cond = UM_CD[CD_PD] && aupd;
    CD_BIT16:  cond = xa_q[4];               // bit number >= 16 (register destination), latched by the previous word
    CD_DIVOVU: cond = dv_ov && !dv_s_r;
    CD_DVNEG:  cond = dv_sr;
    CD_NSET:   cond = UM_CD[CD_NSET] && (IS010 ? auxn : sr[3]);     // CHK: Dn < 0 (68010 / 68020: CD_CHKX)
    CD_SPUR:   cond = UM_CD[CD_SPUR] && b_iack_sp;
    // 68010: MOVEC control register code valid (extension word still in IRC), MOVES direction, RTE format
    CD_CRVALID: cond = IS010 && ((irc[11:0] == 12'h000) || (irc[11:0] == 12'h001) || (irc[11:0] == 12'h800) ||
                                 (IS020 && ((irc[11:0] == 12'h002) || (irc[11:0] == 12'h802) || (irc[11:0] == 12'h803) ||
                                            (irc[11:0] == 12'h804))) ||
                                 (irc[11:0] == 12'h801));
    CD_CXDR:   cond = IS010 && cx[11];
    CD_FMT0:   cond = IS010 && (dt[15:12] == 4'h0);
    CD_FMT8:   cond = IS010 && (dt[15:12] == 4'h8);
    CD_VERSOK: cond = IS010 && (ver_f == 4'd0);
    CD_RRSET:  cond = IS010 && ssw[15];
    CD_SSWRM:  cond = IS010 && ssw[11];
    CD_SSWIF:  cond = IS010 && ssw[13];
    CD_SSWRW:  cond = IS010 && ssw[8];
    CD_LMX:    cond = ISLM && (cc_ir || lm_dyz);
    CD_CHKX:   cond = IS010 && (aux || auxn);            // CHK: Dn > bound or Dn < 0
    default:   cond = 1'b0;
    endcase
    // 68020 conditions (field c2): full-format extension word (xw: saved by FEA_*), ...
    if (IS020 && u_c2 != C2_NONE) case (u_c2)
    C2_FULLX:  cond = irc[8];                            // extension word in IRC is the full format
    C2_XBDN:   cond = !xw[5];                            // base displacement null (or reserved size 00)
    C2_XBDL:   cond = xw[4];                             // base displacement long
    C2_XNOPRE: cond = xw[6] || xw[2];                    // no index before the indirection (IS, or post-indexed)
    C2_XNIND:  cond = xw[2:0] == 3'd0;                   // no memory indirection
    C2_XNPOST: cond = xw[6] || !xw[2];                   // no index after the indirection
    C2_XODN:   cond = !xw[1];                            // outer displacement null
    C2_XODL:   cond = xw[0];                             // outer displacement long
    C2_ISEC:   cond = CPU == 68021;                      // 68EC020
    C2_MUL64:  cond = cx[10];                            // MUL.L 64-bit product
    C2_DVZL:   cond = dl_z;                              // DIV.L by zero
    C2_DVOVL:  cond = dl_ov;                             // DIV.L overflow found before the steps
    C2_DVOVL2: cond = dl_ov2;                            // DIV.L signed quotient out of range
    C2_TOPW:   cond = ir[2:0] == 3'd2;                   // TRAPcc.W
    C2_TOPL:   cond = ir[2:0] == 3'd3;                   // TRAPcc.L
    C2_BFMOD:  cond = ir[9:8] == 2'd2 || ir[10:8] == 3'd4 || ir[10:8] == 3'd7;   // BFCHG / BFCLR / BFSET / BFINS
    C2_BFEXT:  cond = ir[8];                             // BFEXTU / BFEXTS / BFFFO (writes Dn)
    C2_BF5:    cond = ({4'd0, bf_off[2:0]} + {1'b0, bf_w}) > 7'd32;      // memory field reaches a fifth byte
    C2_SZB:    cond = c_sz == 2'd0;                      // byte operation
    C2_CHK2X:  cond = cx[11] && aux2;                    // CHK2 out of bounds
    C2_ZSET:   cond = sr[2];                             // Z (CAS / CAS2 compare equal)
    C2_FMT1:   cond = dt[15:12] == 4'h1;                 // RTE frame formats
    C2_FMT2:   cond = dt[15:12] == 4'h2;
    C2_FMT9:   cond = dt[15:12] == 4'h9;
    C2_FMTA:   cond = dt[15:12] == 4'ha;
    C2_FMTB:   cond = dt[15:12] == 4'hb;
    C2_MSET:   cond = sr[12];                            // M (master stack)
    C2_CPRD:   cond = ir[8:6] == 3'd4;                   // coprocessor: cpSAVE (reads first) / cpGEN; the response in DT:
    C2_CPGEN:  cond = ir[8:6] == 3'd0;                   // null (function 01000, CA clear) / null with CA or busy (00100)
    // (cp5, User's Manual 7.4.4 p. 7-31: null = bits 13-9 00100, bit 8 IA (interrupts allowed: not serviced here, the
    // response is read again at once), bit 14 PC (not implemented); busy, 7.4.3 p. 7-30: function 00100)
    C2_CPNULL: cond = (dt[13:9] == 5'b00100) && !dt[15];
    C2_CPAGAIN: cond = ((dt[13:9] == 5'b00100) && dt[15]) || (dt[12:8] == 5'b00100);
    default:   cond = 1'b0;
    endcase
end

// ------------------------------------------------------------------------------------------------ bus address / data
// bus address, registered at e1 (S1): a register source is read on copy A, whose read address is taken from the next
// micro-instruction at e0 (forwarded when the e0 ALU write hits that register)
logic [31:0] ba_e1, r_pa_e1, fwd_v;
// 68010: exception vector address = VBR + 4 x vector (+ 2 for the low word)
logic [31:0] vba;
assign vba = vbr + {22'd0, vec, u_ba == BA_VEC2, 1'b0};
logic        fwd_hit;
assign r_pa_e1 = fwd_hit ? fwd_v : rd_a;
always_comb begin
    case (u_ba)
    BA_AT:    ba_e1 = at;
    BA_AUR:   ba_e1 = aur;
    BA_AY, BA_AX, BA_SP: ba_e1 = r_pa_e1;
    BA_VEC:   ba_e1 = IS010 ? vba : {22'd0, vec, 2'b00};
    BA_VEC2:  ba_e1 = IS010 ? vba : {22'd0, vec, 2'b10};
    BA_BKPT:  ba_e1 = IS020 ? {27'd0, ir[2:0], 2'b00} : 32'd0;          // 68020: breakpoint number on A4-A2
    // 68020 coprocessor interface register: CPU space type 2, Cp-ID on A15-13, the register by the instruction type
    // (reads: response $00, save $04 / restore $06; writes: command $0A (cpGEN), restore $06, condition $0E)
    BA_CPS:   ba_e1 = IS020 ? {12'd0, 4'h2, ir[11:9], 8'd0, (u_bus == BUS_WR) ?
                                   ((ir[8:6] == 3'd0) ? 5'h0a : (ir[8:6] == 3'd5) ? 5'h06 : 5'h0e) :
                                   ((ir[8:6] == 3'd4) ? 5'h04 : (ir[8:6] == 3'd5) ? 5'h06 : 5'h00)} : 32'd0;
    BA_FA:    ba_e1 = IS010 ? fa : fpc;
    BA_ATIRC: ba_e1 = {at[31:16], irc};
    BA_DT:    ba_e1 = dt;
    BA_IACKA: ba_e1 = {28'hfffffff, ilvl, 1'b1};
    default:  ba_e1 = fpc;
    endcase
end

logic [31:0] ba_q;            // bus address of the current cycle (registered at e1)
logic        ae_e1, ae;       // address error, found at e1 and registered (used from e2 on)

logic        bact;            // a bus cycle started at the last e0 (first micro-cycle of it)
logic  [2:0] bo_op;
assign berr_now = mc2 && b_berr && (bo_op != BUS_IACK);      // BERR on IACK: spurious interrupt
assign f8ld = IS010 && (((bo_fx >= FX_LSSW) && (bo_fx <= FX_LAURL)) || (IS020 && bo_fx == FX_LSSW20));
logic  [1:0] bo_bd;
logic        bo_byte;
logic        bo_bkpt;         // 68010: the cycle is a breakpoint acknowledge (no data taken)
logic        bo_cps;          // 68020: the cycle addresses a coprocessor interface register (BERR: F-line)
// loop mode: an opcode prefetch of one of the three loop words runs without a bus cycle (ghost cycle). Decided from
// the bus address registered at e1 (ba_q), so it is known at e2 (the BIU's first use: S2 strobes); the loop-mode
// updates (ghost, lm_db, lm off on a real opcode fetch) are taken at e2 of the cycle's first micro-cycle
logic [23:0] lwd;
logic        lw_in, lw_pf, ghost_c, lm_rf, lm_post, lm_db_post;
assign lwd     = ba_q[23:0] - lbase;                                     // offset from the looped instruction
assign lw_in   = (lwd[23:3] == 21'd0) && !lwd[0] && !(lwd[2] && lwd[1]);   // ba_q = lbase, lbase + 2 or lbase + 4
assign lw_pf   = ISLM && lm && bact && (bo_op == BUS_NPE || bo_op == BUS_NPF);   // opcode prefetch in loop mode
assign ghost_c = lw_pf && lw_in;
assign lm_rf   = lw_pf && !lw_in;                                        // a real opcode fetch: loop mode ends
assign lm_post    = lm && !lm_rf;                                        // lm / lm_db after this cycle's update
assign lm_db_post = !lm_rf && (lm_db || (ghost_c && lwd[2]));
// read data -> DT (bus word destination bd, byte cycle): from the bus at the end of a read (e3), or - 68010 RTE completed
// by software (x1 SWDONE, at e0) - from DIB with the saved destination; one source for both (same per-slice writes)
logic        sw_ld;
logic [15:0] ld_d;
logic  [1:0] ld_bd;
logic        ld_byte;
assign sw_ld   = IS010 && !b_dv && (u_x1 == X1_SWDONE);    // the SWDONE word's write is at e0 (b_dv: e3)
assign ld_d    = sw_ld ? dib : b_din;
assign ld_bd   = sw_ld ? bd_f : bo_bd;
assign ld_byte = sw_ld ? ssw[9] : bo_byte;

// address error: odd word access (68020: odd instruction fetch only - its data accesses may have any alignment)
assign ae_e1 = bact && (IS020 ? (bo_op == BUS_NPE || bo_op == BUS_NPF) :
                                ((bo_op != BUS_TAS) && (bo_op != BUS_IACK) && !bo_byte)) && ba_e1[0];

// bus write data: the source / half / special selection is decoded at e1 (the microword is stable from e0), the data
// (incl. the register-file copy BW, valid at e2) is muxed and latched into b_dout at e2. 68010 format-8 frame words
// (field fx with dw X10) are decoded here too: slot A / B words go through the IM / RES sources or a special word
localparam logic [2:0] DWS_RES = 3'd0, DWS_DT = 3'd1, DWS_IM = 3'd2, DWS_PCX = 3'd3, DWS_FA = 3'd4, DWS_RBW = 3'd5,
                       DWS_AT = 3'd6, DWS_SPEC = 3'd7;
localparam logic [4:0] DWX_ZERO = 5'd0, DWX_SRT = 5'd1, DWX_IR = 5'd2, DWX_FINFO = 5'd3, DWX_DTB3 = 5'd4, DWX_TASB = 5'd5,
                       // 68010
                       DWX_FMT = 5'd6, DWX_SR = 5'd7, DWX_CCR = 5'd8, DWX_SCC = 5'd9, DWX_FMT8 = 5'd10, DWX_SSW = 5'd11,
                       DWX_DOB = 5'd12, DWX_IIB = 5'd13, DWX_DIB = 5'd14, DWX_I0 = 5'd15, DWX_I1 = 5'd16, DWX_IR10 = 5'd17,
                       DWX_IRN = 5'd18, DWX_AURH = 5'd19, DWX_AURL = 5'd20, DWX_VEC = 5'd21, DWX_MASK = 5'd22,
                       DWX_CNT = 5'd23,
                       // 68020
                       DWX_PPCH = 5'd24, DWX_PPCL = 5'd25, DWX_F2 = 5'd26, DWX_F1 = 5'd27, DWX_SRTS = 5'd28,
                       DWX_FB = 5'd29, DWX_SSW20 = 5'd30, DWX_CPW = 5'd31;
logic [2:0] dws_d, dws_q;
logic [4:0] dwx_d, dwx_q;
logic       dwh_d, dwh_q, dw_we_q, dw_dup_q;
logic [2:0] dws_eav;
assign dws_eav = eav_reg ? DWS_RBW : eav_imm ? DWS_IM : DWS_DT;
always_comb begin
    dws_d = DWS_SPEC; dwx_d = DWX_ZERO; dwh_d = 1'b0;
    case (u_dw)
    DW_RESL:  dws_d = DWS_RES;
    DW_RESH:  begin dws_d = DWS_RES; dwh_d = 1'b1; end
    DW_DTL:   if (UM_DW[DW_DTL]) dws_d = DWS_DT;
    DW_DTH:   if (UM_DW[DW_DTH]) begin dws_d = DWS_DT; dwh_d = 1'b1; end
    DW_EAVL:  if (UM_DW[DW_EAVL]) dws_d = dws_eav;
    DW_EAVH:  if (UM_DW[DW_EAVH]) begin dws_d = dws_eav; dwh_d = 1'b1; end
    DW_EAV1:  begin dws_d = dws_eav; dwh_d = c_sz == 2'd2; end
    DW_PCXL:  dws_d = DWS_PCX;
    DW_PCXH:  begin dws_d = DWS_PCX; dwh_d = 1'b1; end
    DW_SRT:   dwx_d = DWX_SRT;
    DW_IR:    dwx_d = DWX_IR;
    DW_FINFO: dwx_d = DWX_FINFO;
    DW_FAL:   dws_d = DWS_FA;
    DW_FAH:   begin dws_d = DWS_FA; dwh_d = 1'b1; end
    DW_MRL:   dws_d = DWS_RBW;
    DW_MRH:   begin dws_d = DWS_RBW; dwh_d = 1'b1; end
    DW_AYL:   if (UM_DW[DW_AYL]) dws_d = DWS_RBW;
    DW_AYH:   if (UM_DW[DW_AYH]) begin dws_d = DWS_RBW; dwh_d = 1'b1; end
    DW_IML:   dws_d = DWS_IM;
    DW_IMH:   begin dws_d = DWS_IM; dwh_d = 1'b1; end
    DW_ATL:   dws_d = DWS_AT;
    DW_ATH:   begin dws_d = DWS_AT; dwh_d = 1'b1; end
    DW_DTB3:  dwx_d = DWX_DTB3;
    DW_TASB:  dwx_d = DWX_TASB;
    DW_FMT:   if (IS010) dwx_d = DWX_FMT;
    DW_SRW:   if (IS010) dwx_d = DWX_SR;
    DW_CCRW:  if (IS010) dwx_d = DWX_CCR;
    DW_SCC:   if (IS010) dwx_d = DWX_SCC;
    DW_RC1:   if (IS010) begin dws_d = DWS_RBW; dwh_d = 1'b1; end
    DW_RCL:   if (IS010) dws_d = DWS_RBW;
    DW_X10:   if (IS010) case (u_fx)
        FX_FMT8: if (UM_FX[FX_FMT8]) dwx_d = DWX_FMT8;
        FX_SSW:  dwx_d = DWX_SSW;
        FX_DOB:  dwx_d = DWX_DOB;
        FX_IIB:  dwx_d = DWX_IIB;
        // 68020 address error (2026-11-16): the data input buffer (+2C / +2E) holds the fault address, as WinUAE writes it
        FX_DIB:  if (IS020 && g0ae) dws_d = DWS_FA; else dwx_d = DWX_DIB;
        FX_DIBH: if (IS020 && g0ae) begin dws_d = DWS_FA; dwh_d = 1'b1; end
        FX_I0:   dwx_d = DWX_I0;
        FX_I1:   dwx_d = DWX_I1;
        FX_IR:   dwx_d = DWX_IR10;
        FX_IRN:  dwx_d = DWX_IRN;
        FX_SLAH: if (lay_f[1]) dwx_d = DWX_SRT;  else begin dws_d = DWS_IM;  dwh_d = 1'b1; end
        FX_SLAL: if (lay_f[1]) dwx_d = DWX_VEC;  else dws_d = DWS_IM;
        FX_SLBH: if (lay_f[0]) dwx_d = DWX_MASK; else begin dws_d = DWS_RES; dwh_d = 1'b1; end
        FX_SLBL: if (lay_f[0]) dwx_d = DWX_CNT;  else dws_d = DWS_RES;
        FX_AURH: dwx_d = DWX_AURH;
        FX_AURL: dwx_d = DWX_AURL;
        FX_SSW20: if (IS020) dwx_d = DWX_SSW20;
        default: ;
        endcase
    default:  ;
    endcase
    // 68020 write data (field d2): instruction address of a format-2 frame, format / vector words
    if (IS020 && u_d2 != D2_NONE) begin
        dws_d = DWS_SPEC; dwh_d = 1'b0; dwx_d = DWX_ZERO;
        case (u_d2)
        D2_RUH:  begin dws_d = DWS_RBW; dwh_d = c_sz == 2'd2; end         // CAS update register (long: high word first)
        D2_RUL:  dws_d = DWS_RBW;
        D2_PPCH: dwx_d = DWX_PPCH;
        D2_PPCL: dwx_d = DWX_PPCL;
        D2_F2:   dwx_d = DWX_F2;
        D2_F1:   dwx_d = DWX_F1;
        D2_SRTS: dwx_d = DWX_SRTS;
        D2_FB:   dwx_d = DWX_FB;
        D2_CPW:  dwx_d = DWX_CPW;
        default: dwx_d = DWX_ZERO;
        endcase
    end
end
logic [15:0] dw_spec, dw_v, b_dout_r;
logic        b_dup_r;
logic [31:0] dw_32;
always_comb begin
    case (dwx_q)
    DWX_SRT:   dw_spec = srt;
    DWX_IR:    dw_spec = IS010 ? aeir : aeir_n ? irn : ir;
    DWX_FINFO: dw_spec = IS010 ? finfo : {aeir_n ? irn[15:5] : ir[15:5], finfo[4:0]};
    DWX_DTB3:  dw_spec = {8'd0, dt[31:24]};
    DWX_TASB:  dw_spec = {8'd0, 1'b1, dt[6:0]};
    DWX_FMT:   dw_spec = IS010 ? {6'd0, vec, 2'b00} : 16'd0;          // format 0 / vector offset
    DWX_SR:    dw_spec = IS010 ? sr : 16'd0;
    DWX_CCR:   dw_spec = IS010 ? {11'd0, sr[4:0]} : 16'd0;
    DWX_SCC:   dw_spec = IS010 ? {8'd0, {8{cc_ir}}} : 16'd0;
    // 68010 format-8 frame words
    DWX_FMT8:  dw_spec = IS010 ? {4'h8, 2'b00, vec, 2'b00} : 16'd0;
    DWX_SSW:   dw_spec = IS010 ? ssw : 16'd0;
    DWX_DOB:   dw_spec = IS010 ? dob : 16'd0;
    DWX_IIB:   dw_spec = IS010 ? irc : 16'd0;
    DWX_DIB:   dw_spec = IS010 ? dib : 16'd0;
    DWX_I0:    dw_spec = IS010 ? {fin_f, c_cont == c_body, 4'd0, lay_f, bd_f, trace_f, lm_f, hold_xvc} : 16'd0;
    DWX_I1:    dw_spec = IS010 ? {hold_nzm, hold_x0, 2'b00, ua_res} : 16'd0;
    DWX_IR10:  dw_spec = IS010 ? ir : 16'd0;
    DWX_IRN:   dw_spec = IS010 ? irn : 16'd0;
    DWX_AURH:  dw_spec = IS010 ? {8'd0, aur_f[23:16]} : 16'd0;
    DWX_AURL:  dw_spec = IS010 ? aur_f[15:0] : 16'd0;
    DWX_VEC:   dw_spec = IS010 ? {8'd0, vec} : 16'd0;
    DWX_MASK:  dw_spec = IS010 ? mask : 16'd0;
    DWX_CNT:   dw_spec = IS010 ? {9'd0, cnt} : 16'd0;
    DWX_PPCH:  dw_spec = IS020 ? ppc[31:16] : 16'd0;
    DWX_PPCL:  dw_spec = IS020 ? ppc[15:0] : 16'd0;
    DWX_F2:    dw_spec = IS020 ? {4'h2, 2'b00, vec, 2'b00} : 16'd0;
    DWX_F1:    dw_spec = IS020 ? {4'h1, 2'b00, vec, 2'b00} : 16'd0;
    DWX_SRTS:  dw_spec = IS020 ? (srt | 16'h2000) : 16'd0;
    DWX_FB:    dw_spec = IS020 ? {4'hb, 2'b00, vec, 2'b00} : 16'd0;
    // coprocessor command (cpGEN: the extension word) / condition (cpScc / cpDBcc / cpTRAPcc: extension bits 5-0, cpBcc:
    // opcode bits 5-0) / restore format word (0: m68ksv does not read it from the EA, REPORT.md)
    DWX_CPW:   dw_spec = !IS020 ? 16'd0 : (ir[8:6] == 3'd0) ? irc : (ir[8:6] == 3'd1) ? {10'd0, irc[5:0]} :
                         (ir[8:7] == 2'b01) ? {10'd0, ir[5:0]} : 16'd0;
    // 68020 SSW: FB / RB = instruction fetch fault (stage B), DF, RM, RW, SIZ (byte / word), FC
    // 68020 SSW (format B): FC 0, FB / RB = an instruction fetch faulted (stage B, re-run), RC 0, DF = a data cycle
    // faulted (re-run), RM, R/W, SIZE (byte 01 / word 10), FC2-0 - from m68ksv's own SSW (68010 layout: IF bit 12, RM 10,
    // BY 8, RW 7). (cp4b: DF was not set for data faults, so RTE treated every data fault as completed in software.)
    // (2026-11-16) address error (g0ae): RB and RC set, FB / FC / DF clear - MC68020 User's Manual 6.2.1 p. 6-22 ("the
    // fault bits ... are not set ... the rerun bits alone show the cause"; RB and RC, or only RC: m68ksv sets both, a
    // change of flow to an odd address leaves the whole pipe to refill), so RTE re-runs the fetch; the low half (data
    // cycles only, per the manual) as WinUAE's 68020 core builds it: RW, SIZE word, FC of the faulting fetch ($3066 in
    // supervisor mode). #unverified: WinUAE (newcpu.cpp Exception_normal, "partially implemented only") writes $0066 -
    // no RB / RC; no real 68020 has settled it. If evidence shows this is wrong, fix it (REPORT.md "SSW back to the manual")
    DWX_SSW20: dw_spec = !IS020 ? 16'd0 : g0ae ? {2'b00, 2'b11, 4'd0, 1'b0, 1'b1, 2'b10, 1'b0, ssw[2:0]} :
                         {1'b0, ssw[12], 1'b0, ssw[12], 3'b000, !ssw[12], ssw[10], ssw[7], ssw[8] ? 2'b01 : 2'b10,
                                  1'b0, ssw[2:0]};
    default:   dw_spec = 16'd0;
    endcase
    case (dws_q)
    DWS_RES: dw_32 = res;
    DWS_DT:  dw_32 = dt;
    DWS_IM:  dw_32 = im;
    DWS_PCX: dw_32 = pcx;
    DWS_FA:  dw_32 = fa;
    DWS_RBW: dw_32 = rd_bw;
    DWS_AT:  dw_32 = at;
    default: dw_32 = {16'd0, dw_spec};
    endcase
    dw_v = dwh_q ? dw_32[31:16] : dw_32[15:0];
end

logic [2:0] fc_v, fc_nx;
assign fc_v = b_fc;
logic [1:0] uq_bf;
assign uq_bf = uq[F_BF_LSB +: F_BF_W];
always_comb begin       // function code of a cycle starting at this e0 (S0), from the next word and the new SR
    if (uq_sf == SF_SSW) fc_nx = ssw[2:0];          // 68010 re-run
    else if (uq_bus == BUS_NPE || uq_bus == BUS_NPF) fc_nx = sr_n[13] ? 3'd6 : 3'd2;
    else if (uq_sf == SF_SFC) fc_nx = sfc;          // 68010 MOVES
    else if (uq_sf == SF_DFC) fc_nx = dfc;
    else case (uq_bf)
        BF_PROG: fc_nx = sr_n[13] ? 3'd6 : 3'd2;
        BF_SUPD: fc_nx = 3'd5;
        BF_CPU:  fc_nx = 3'd7;
        default: fc_nx = sr_n[13] ? 3'd5 : 3'd1;
    endcase
end

// ------------------------------------------------------------------------------------------------ next micro-address
// The branch condition and the FIN decision are latched at e1 (cond_q, fin_q, irq_q); the next micro-address is
// formed from them and loaded at e2 (an address error found at e2 overrides it); the ROM output is taken at e0.
logic        fin_t;           // FIN taken by the current micro-instruction
logic        fin_q, cond_q, irq_q;
logic [10:0] upc_next, d_disp;
logic        in_exc_nx;       // the next instruction boundary dispatches to a group 1 / illegal / privilege exception
always_comb begin
    fin_t = 1'b0;
    case (u_sq)
    SQ_FIN:   fin_t = 1'b1;
    SQ_FINC:  fin_t = !cond;
    SQ_FINNC: fin_t = cond;
    SQ_RSM:   fin_t = IS010 && fin_f;       // 68010: continue - dispatch, or the saved micro-address
    default:  fin_t = 1'b0;
    endcase
end
// in_exc_nx = is_exc(d_disp), formed per branch (the decoded entries' test registered with them: q_exc / lq_exc)
always_comb begin
    if (trace_pend)                    begin d_disp = UA_TRACE; in_exc_nx = is_exc(UA_TRACE); end
    else if (ISLM && lm_db)            begin                                                  // no interrupt here
        d_disp    = lm_dyzv ? (U10_DBL1 - {9'd0, lmd}) : q_first;
        in_exc_nx = lm_dyzv ? is_exc(U10_DBL1 - {9'd0, lmd}) : q_exc;
    end
    else if (npf_now ? ((iq_early == 2'd2) ? irq_npf : irq_pend) : irq_q)
                                       begin d_disp = UA_INT;   in_exc_nx = is_exc(UA_INT); end
    else if (q_priv && !sr[13])        begin d_disp = UA_PRIV;  in_exc_nx = is_exc(UA_PRIV); end
    else if (ISLM && u_x1 == X1_LMC)   begin d_disp = lq_first; in_exc_nx = lq_exc; end   // loop word: the looped instruction again
    else                               begin d_disp = q_first;  in_exc_nx = q_exc; end
    if (fin_q) upc_next = d_disp;
    else case (u_sq)
        SQ_CONT:  upc_next = c_cont;
        SQ_BODY:  upc_next = UM_SQ[SQ_BODY] ? c_body : u_nxt;
        SQ_BT:    upc_next = cond_q ? u_nxt : upc + 11'd1;
        SQ_BF:    upc_next = cond_q ? upc + 11'd1 : u_nxt;
        SQ_RET:   upc_next = UM_SQ[SQ_RET] ? uret : u_nxt;
        SQ_RSM:   upc_next = UM_SQ[SQ_RSM] ? ua_res : u_nxt;
        default:  upc_next = u_nxt;       // NXT CALL FINC FINNC
    endcase
end

// the 68000's PC register (pc68): loaded where the 68000 microcode loads its PC (field pu, DESIGN.md 5) - at the e0
// that starts the word (its T1: AU -> PC) from fpc / PCX / AUR, or at the word's e2 (its T3: bus -> PC) from fpc,
// fpc -/+ 2, PCX, AT or the vector address; a bus error stacks it as it stands after the faulting cycle's e2
logic [31:0] pc68_f;
assign pc68_f = fpc + ((u_pu == PU_FPCM2) ? 32'hffff_fffe : (u_pu == PU_FPCP2) ? 32'd2 : 32'd0);
always_comb begin
    case (u_pu)
    PU_FPC, PU_FPCM2, PU_FPCP2: pc68_e2 = pc68_f;
    PU_PCX:  pc68_e2 = pcx;
    PU_AT:   pc68_e2 = at;
    PU_VEC:  pc68_e2 = {22'd0, vec, 2'b00};
    default: pc68_e2 = pc68;
    endcase
end

// ------------------------------------------------------------------------------------------------ ALU / AU
// operands and the resolved ALU op are latched at e2; ALU / AU results at e3 (one clock at least)
logic [31:0] xa_q, xb_q, aua_q, aub_q;
logic  [5:0] aop_d, aop;
logic [31:0] alu_res_add, alu_res_oth;
logic  [4:0] ccr_q;                       // flags of the last e3 (combinational from the e3 registers q_*, see below)
logic  [2:0] hold_xvc;                    // the long op's X V C held for FH_CM
logic        hold_ld;                     // hold_xvc is loaded in the clock after an FH_LO / FH_HD word's e3
logic  [1:0] xsz_q;                       // operand size, latched at e2 (u_xs / c_sz change at e0 only)
logic        alu_cin_q;                   // ALU X input, latched at e2 (sr changes at e0, hold_x0 at e3 only)
logic  [1:0] rsrc_q;                      // result source latched at e2: 3 the adder, 2 PACK / UNPK, 1 another EU (ops above 31) result, 0 the ALU's other results
logic  [3:0] xsel_d, xsel_q;              // which EU result (decoded from the op and IR[10:8] at e2)
logic        a_adc, a_adv, a_adc16, a_adv16, a_abc, a_abv, a_sbc, a_sbv, a_sho, a_shv, a_bitz;
logic  [1:0] hold_nzm;
logic        hold_x0;                     // X before the FH_LO word (carry-in of an FH_HD op)
logic        fhlo_q, fhcm_q, fhhd_q, fhl_q;  // the word's fh mode (and long size), latched at e2 with the operands
logic  [1:0] alu_nzm, alu_nsz, nzm_q, nsz_q;
logic        ad_sub_q, ad_usex_q, ad_neg_q, ad_ysw_q, ad_ysb_q, bcd_neg_q, rsub_q, divr_q;
logic  [2:0] ad_fsz_q;
logic  [3:0] rsel_q;
// ALU result source per op (codes R_* in m68ksv_alu)
function automatic logic [3:0] alu_rsel(input logic [5:0] op);
    case (op)
    OP_PASS, OP_MVL, OP_MVH: alu_rsel = 4'd1;
    OP_SEXT: alu_rsel = 4'd2;
    OP_ADD, OP_SUB, OP_CMP, OP_ADDX, OP_SUBX, OP_NEG, OP_NEGX, OP_ADDA, OP_SUBA, OP_CMPA: alu_rsel = 4'd3;
    OP_AND:  alu_rsel = 4'd4;
    OP_OR:   alu_rsel = 4'd5;
    OP_EOR:  alu_rsel = 4'd6;
    OP_NOT:  alu_rsel = 4'd7;
    OP_CLR:  alu_rsel = 4'd8;
    OP_ABCD, OP_SBCD, OP_NBCD: alu_rsel = 4'd9;
    OP_EXT:  alu_rsel = 4'd10;
    OP_SWAP: alu_rsel = 4'd11;
    OP_SHF, OP_SHF1: alu_rsel = 4'd12;
    OP_BIT:  alu_rsel = 4'd13;
    OP_SCC, OP_TAS: alu_rsel = 4'd14;
    OP_MUL, OP_DIVR: alu_rsel = 4'd15;
    default: alu_rsel = 4'd0;            // b: TST SHFI CHK DIVO DIVZ
    endcase
endfunction
assign aop_d = (u_op == OP_DEC) ? c_aluop : u_op;
logic [2:0] shtype;
assign shtype = (ir[7:6] == 2'd3) ? {ir[8], ir[10:9]} : {ir[8], ir[4:3]};
// 16 x 16 multiply in a DSP block with its output register: the product of the operands latched at e2 is ready one
// clock later, so the microcode latches the operands one micro-instruction before the one that takes the product
// MUL timing: MULU 38 + 2 x (ones in the source), MULS 38 + 2 x (01 / 10 pairs in {source, 0})
logic [15:0] mul_t;
logic  [4:0] mul_n;
assign mul_t = ir[8] ? (xa_q[15:0] ^ {xa_q[14:0], 1'b0}) : xa_q[15:0];
always_comb begin
    mul_n = 5'd0;
    for (int i = 0; i < 16; i++) mul_n = mul_n + {4'd0, mul_t[i]};
end
// MUL / DIV.W idle micro-cycle counts (fields ms LDCNTMUL / LDCNTDIV, loaded into cnt at e0). 68020 (2026-11-16,
// timing): registered every clock, so the two popcounts are not in front of cnt. Same values: they come from xa_q / ir
// (MUL; xa_q changes at e2 only, two or more clocks before the e0) and the divider registers (DIV; changed by the DINIT /
// DSTEP words before the LDCNTDIV word). The 68000 / 68010 builds load the combinational value as before.
logic [6:0] cnt_mul_c, cnt_div_c, cnt_mul_r, cnt_div_r;
assign cnt_mul_c = 7'd16 + {2'd0, mul_n};
assign cnt_div_c = !dv_s_r ? 7'd14 + {2'd0, dv_ext} :
                   7'd52 - {3'd0, dv_q1} + (dv_dsn ? (dv_sr ? 7'd1 : 7'd0) : (dv_sr ? 7'd2 : 7'h7f));
always_ff @(posedge clk) if (IS020) begin cnt_mul_r <= cnt_mul_c; cnt_div_r <= cnt_div_c; end
logic signed [16:0] mul_a, mul_b;
logic signed [33:0] mul_p;
assign mul_a = {ir[8] & xa_q[15], xa_q[15:0]};
assign mul_b = {ir[8] & xb_q[15], xb_q[15:0]};
always_ff @(posedge clk) mul_p <= mul_a * mul_b;
// DIVU / DIVS result (quotient and remainder with their signs) enters the ALU on the product input
logic [15:0] dq_out, dr_out;
logic [31:0] alu_mp;
assign dq_out = dv_sq ? -dv_q : dv_q;
assign dr_out = dv_sr ? -dv_r : dv_r;
assign alu_mp = divr_q ? {dr_out, dq_out} : mul_p[31:0];

m68ksv_alu #(.IS010(IS010)) alu (
    .op(aop), .sz(xsz_q), .a(xa_q), .b(xb_q), .cin(alu_cin_q), .shtype(shtype), .bitop(ir[7:6]),
    .cond(cc_irq), .mp(alu_mp), .rsel(rsel_q), .rsub(rsub_q), .ad_sub(ad_sub_q), .ad_usex(ad_usex_q), .ad_neg(ad_neg_q), .ad_ysw(ad_ysw_q),
    .ad_ysb(ad_ysb_q), .ad_fsz(ad_fsz_q), .bcd_neg(bcd_neg_q),
    .res_add(alu_res_add), .res_oth(alu_res_oth), .f_adc(a_adc), .f_adv(a_adv), .f_adc16(a_adc16), .f_adv16(a_adv16),
    .f_abc(a_abc), .f_abv(a_abv), .f_sbc(a_sbc), .f_sbv(a_sbv), .f_sho(a_sho), .f_shv(a_shv), .f_bitz(a_bitz),
    .nzm(alu_nzm), .nsz(alu_nsz)
);
// ops numbered above 31 are handled here
logic [31:0] xres;
logic  [1:0] xnzm, xnsz;
logic        chk_t, chk_l, chk_dn, chk_dz;
logic signed [15:0] chk_d, chk_b;
assign chk_d = xb_q[15:0];
assign chk_b = xa_q[15:0];
// trap at the bound check when bound - Dn sets N or V (68000 microcode test, fx68k / MAME), else when Dn < 0
logic [15:0] chk_df;
assign chk_df = chk_b - chk_d;
// 68020 CHK.L: the same test on 32 bits (signed Dn > bound)
logic [31:0] chk_dfl;
assign chk_l   = IS020 && (xsz_q == 2'd2);
assign chk_dfl = xa_q - xb_q;
assign chk_t   = chk_l ? (chk_dfl[31] | ((xa_q[31] != xb_q[31]) && (chk_dfl[31] != xa_q[31]))) :
                         (chk_df[15] | ((chk_b[15] != chk_d[15]) && (chk_df[15] != chk_b[15])));
assign chk_dn  = chk_l ? xb_q[31] : chk_d[15];
assign chk_dz  = chk_l ? (xb_q == 32'd0) : (chk_d == 16'sd0);
// 68020 CHK undefined V / C (WinUAE newcpu_common.cpp setchkundefinedflags, 68020 / 030 branch; real-hardware-derived
// tables): when the instruction traps (Dn < 0 or Dn > bound), V = overflow of bound - Dn and C = (Dn < 0) ? (Dn > bound
// or bound >= 0) : (bound >= 0); else V = C = 0. N / Z: Dn < 0 / Dn = 0 (chk_dn / chk_dz)
logic chk_v20, chk_c20, chk_bn;
assign chk_bn  = chk_l ? xa_q[31] : chk_b[15];
assign chk_v20 = (chk_t | chk_dn) & (chk_l ? ((xa_q[31] != xb_q[31]) && (chk_dfl[31] != xa_q[31])) :
                                             ((chk_b[15] != chk_d[15]) && (chk_df[15] != chk_b[15])));
assign chk_c20 = (chk_t | chk_dn) & (!chk_bn | (chk_dn & chk_t));
// 68020 MUL.L: 33 x 33 signed product in DSP blocks (operands loaded once, m2 MULL; a register stage on each side).
// The operands are taken from the operand registers at e3 of the m2 MULL word (cp4b; they hold that word's operands,
// and the product is read two words later, MULLH). Only the 68020 builds have the multiplier: elsewhere the product is
// a constant 0 (Quartus 17 does not fold a multiplier whose operand registers are never loaded; fold-away fix)
logic signed [65:0] mul_lp;
generate
if (IS020) begin : g_mull
    logic signed [32:0] mul_la, mul_lb;
    always_ff @(posedge clk) begin
        if (e3 && u_m2 == M2_MULL) begin
            mul_la <= {cx[11] & xa_q[31], xa_q};
            mul_lb <= {cx[11] & xb_q[31], xb_q};
        end
        mul_lp <= mul_la * mul_lb;
    end
end else begin : g_nomull
    assign mul_lp = 66'sd0;
end
endgenerate
// 68020 bit-field unit: BFINIT (offset, width, byte address), stage 1 (BFP: funnel shift, masks -> registers), results
// (BF / BF5) from the registers
logic [31:0] bf_off, bf_ea;
logic  [5:0] bf_w;                // 1-32
logic        bf_mem;
logic  [5:0] bf_o6;
logic [63:0] bf_d64;
/* verilator lint_off UNUSED */
logic [63:0] bf_fs, bf_xa2;       // (only the top long is read)
/* verilator lint_on UNUSED */
logic [31:0] bf_fl, bf_tm, bf_fq, bf_new, bf_m32, bf_i32, bf_dat, bf_xu, bf_ffo, bf_rot, bf_mr;
logic  [7:0] bf_new5;
logic [31:0] bf_flq, bf_tmq;      // stage-1 registers: field left-aligned, top mask
logic [39:0] bf_mq, bf_iq;        // mask / inserted value: {long, fifth byte} (register form: the circular long)
logic [39:0] bf_mc, bf_ic, bf_mm;
logic  [5:0] bf_pos;
logic        bf_n, bf_z;
logic  [4:0] bf_o5r, bf_ir5, bf_xs5;
logic  [5:0] bf_ur;
logic        bf_memr;
assign bf_mem = ir[5:3] != 3'd0;
assign bf_o6  = bf_mem ? {3'd0, bf_off[2:0]} : {1'b0, bf_off[4:0]};
// Stage-1 shift amounts, registered every clock from offset / width / IR (bit-field margin, 2026-11-16): BFINIT loads
// bf_off / bf_w at its e0 and BFP's e3 follows three clocks later at the earliest (the phases of the next word); IR is
// the BF instruction throughout. In the 64-bit frame the field is bits 64 - bf_ur .. 63 - o6 (bf_ur = o6 + width);
// bf_ir5 = (64 - bf_ur) % 32 places the inserted value's low width bits there (as a 32-bit rotate); bf_xs5 = 32 -
// width (0 for 32) right-aligns the field.
always_ff @(posedge clk) begin
    bf_o5r  <= bf_o6[4:0];
    bf_ur   <= bf_o6 + bf_w;
    bf_ir5  <= 5'd0 - bf_o6[4:0] - bf_w[4:0];
    bf_xs5  <= 5'd0 - bf_w[4:0];
    bf_memr <= bf_mem;
end
// (the start's one-clock form, SAT-proved equal: bf_tm = ~(32'hffffffff >> bf_w); bf_fl = the top long of
// {xb, xt[7:0], 24'd0} (memory) / {xb, xb} (register) << o6; bf_mc / bf_ic = {bf_tm, 32'd0} / {xa_q << (32 - width),
// 32'd0} >> o6, bits 63:24 (memory) or the two longs ORed (register); bf_xu = bf_flq >> (32 - width))
// x >= c for a constant c, as plain logic (a comparison operator becomes a carry chain per bit in yosys)
function automatic logic bf_ge(input logic [5:0] x, input int c);
    logic g, e;
    g = 1'b0; e = 1'b1;
    for (int i = 5; i >= 0; i--) begin g = g | (e & x[i] & !c[i]); e = e & (x[i] == c[i]); end
    bf_ge = (c <= 0) || ((c < 64) && (g || e));
endfunction
always_comb begin
    for (int k = 0; k < 32; k++) bf_tm[k] = bf_ge(bf_w, 32 - k);                           // the top width bits
    for (int k = 0; k < 40; k++)                                                           // memory: frame 63:24
        bf_mm[k] = bf_ge(bf_ur, 40 - k) && !bf_ge({1'b0, bf_o5r}, 40 - k);
    for (int k = 0; k < 32; k++)                                                           // register: circular
        bf_mr[k] = (bf_ge(bf_ur, 32 - k) && !bf_ge({1'b0, bf_o5r}, 32 - k)) || bf_ge(bf_ur, 64 - k);
end
assign bf_mc  = bf_memr ? bf_mm : {bf_mr, 8'd0};
assign bf_d64 = {xb_q, bf_memr ? xt[7:0] : xb_q[31:24], xb_q[23:0]};   // memory: offset < 8, bits 23:0 not reached
assign bf_fs  = bf_d64 << bf_o5r;
assign bf_fl  = bf_fs[63:32];
assign bf_xa2 = {xa_q, xa_q} << bf_ir5;
assign bf_rot = bf_xa2[63:32];                                       // xa_q rotated left by bf_ir5
assign bf_ic  = bf_mc & {bf_rot, bf_rot[31:24]};
always_ff @(posedge clk) if (IS020 && e3 && aop == OP_BFP) begin
    bf_flq <= bf_fl; bf_tmq <= bf_tm; bf_mq <= bf_mc; bf_iq <= bf_ic; bf_w1q <= bf_w[4:0] - 5'd1;
end
assign bf_fq  = bf_flq & bf_tmq;                                  // the field, left aligned
assign bf_xu  = bf_flq >> bf_xs5;
always_comb begin
    // first set bit from the top (or the width when the field is 0), as a tree: the first non-zero byte, then the bit
    // in it (the same result as scanning bit 31 down to 0)
    bf_pos = bf_w;
    for (int k = 0; k < 4; k++)                   // (the highest non-zero byte assigns last)
        if (bf_fq[8 * k +: 8] != 8'd0) begin
            bf_pos = {1'b0, 2'd3 - k[1:0], 3'd0};
            for (int j = 0; j < 8; j++) if (bf_fq[8 * k + j]) bf_pos[2:0] = 3'd7 - j[2:0];
        end
end
// (BFFFO: the offset + position, registered in two steps below - BF follows BFP by one micro-instruction or more)
logic  [5:0] bf_posq;
assign bf_ffo = (bf_mem ? bf_off : {27'd0, bf_off[4:0]}) + {26'd0, bf_posq};
// extract / find-first-one results registered every clock from the stage-1 registers (BF always follows BFP by one
// micro-instruction or more; offset / width are set at BFINIT)
logic [31:0] bf_xuq, bf_ffoq;
always_ff @(posedge clk) begin bf_xuq <= bf_xu; bf_posq <= bf_pos; bf_ffoq <= bf_ffo; end
assign bf_m32 = bf_mq[39:8];
assign bf_i32 = bf_iq[39:8];
assign bf_dat = xb_q;
always_comb begin
    case (ir[10:8])
    3'd2:    bf_new = bf_dat ^ bf_m32;
    3'd4:    bf_new = bf_dat & ~bf_m32;
    3'd6:    bf_new = bf_dat | bf_m32;
    default: bf_new = (bf_dat & ~bf_m32) | bf_i32;
    endcase
    case (ir[10:8])
    3'd2:    bf_new5 = xt[7:0] ^ bf_mq[7:0];
    3'd4:    bf_new5 = xt[7:0] & ~bf_mq[7:0];
    3'd6:    bf_new5 = xt[7:0] | bf_mq[7:0];
    default: bf_new5 = (xt[7:0] & ~bf_mq[7:0]) | bf_iq[7:0];
    endcase
end
// BFINS: N / Z of the inserted value (its top bit / its low width bits) through masks taken from the stage-1 top mask
// (bf_tmq = the top width bits, registered at BFP; the width does not change between BFP and BF): the low width bits
// are its mirror image, the top bit of the field the highest of them. The same as xa_q[width - 1] /
// (xa_q << (32 - width)) == 0
logic [31:0] bf_lmq, bf_lmc;
logic  [4:0] bf_w1q;              // width - 1, registered at BFP
always_comb begin
    for (int i = 0; i < 32; i++) begin bf_lmq[i] = bf_tmq[31 - i]; bf_lmc[i] = bf_tm[31 - i]; end
end
assign bf_n = (ir[10:8] == 3'd7) ? xa_q[bf_w1q] : bf_flq[31];
assign bf_z = (ir[10:8] == 3'd7) ? ((xa_q & bf_lmq) == 32'd0) : (bf_fq == 32'd0);
// CHK2 / CMP2 undefined N / V: WinUAE newcpu_common.cpp setchk2undefinedflags, 68020 / 030 branch, case by case
// (ln / un / vn: lower / upper / value negative; eq: value equals a bound; lgu: lower > upper; ltl gtl ltu gtu: value
// vs lower / upper; s1 / s2 / s3: sign of lower - value / upper - value / value - lower, 32-bit wrapping)
function automatic logic [1:0] c2nv(input logic ln, input logic un, input logic vn, input logic eq, input logic lgu,
                                    input logic ltl, input logic gtl, input logic ltu, input logic gtu,
                                    input logic s1, input logic s2, input logic s3);
    logic n, v;
    n = 1'b0; v = 1'b0;
    if (!eq) begin
        if (ln && !un) begin
            if (ltl) n = 1'b1;
            if (!vn && ltu) n = 1'b1;
            if (!vn && !s1) begin v = 1'b1; n = gtu; end
        end else if (!ln && un) begin
            if (!vn || gtu) n = 1'b1;
            if (gtl && !s2) begin v = 1'b1; n = 1'b0; end
        end else if (!ln && !un && lgu) begin
            if (gtu && ltl) n = 1'b1;
            if (vn && s1) v = 1'b1;
            if (vn && !s1) n = 1'b1;
        end else if (!ln && !un) begin
            if ((!vn && ltl) || gtu) n = 1'b1;
            if (vn && s2) begin v = 1'b1; n = 1'b1; end
        end else if (lgu) begin
            if (!vn || (gtu && ltl)) n = 1'b1;
            if (!vn && s3) begin n = 1'b0; v = 1'b1; end
        end else begin
            if (ltl || (vn && gtu)) n = 1'b1;
            if (!vn && s3) begin n = 1'b1; v = 1'b1; end
        end
    end
    c2nv = {n, v};
endfunction
// 68020 CHK2 / CMP2 (2026-11-16: WinUAE's rule, gencpu.cpp i_CHK2 + newcpu_common.cpp setchk2undefinedflags, 68020 / 030
// branch - real-hardware-derived tables; was Musashi's "signed when the lower bound's sign bit is set"). The bounds are
// sign-extended to 32 bits (.B / .W), the value is Dn's sign-extended low part or all of An; signed 32-bit compares.
// Z = value equals a bound; C (unless Z) = out of bounds: lower <= upper: value < lower or value > upper, lower > upper
// (the range wraps): value > upper and value < lower. N / V: setchk2undefinedflags (c2nv below).
// Two steps (2026-11-16, timing): the compare word's e3 registers the two subtractions (value - lower, value - upper:
// 33-bit sign, bit 31 and six partial ORs of bits 30:0), the three operand signs (c2_*1); the clock after it
// registers Z / C / N / V from those (c2_cq .. c2_vq). The flag word (the next micro-word, so four or more clocks
// later) reads only the second step: the same values as the one-clock compare gave.
logic [31:0] c2_lb, c2_ub, c2_v;
logic        aux2;
logic        c2_cq, c2_zq, c2_nq, c2_vq;   // step 2: Z / C / N / V (the CHK2 flag word uses these: compare and flag mux in separate clocks)
logic [32:0] c2_dl, c2_du;         // value - lower, value - upper (33-bit signed)
logic        c2_ltl1, c2_ltu1, c2_dl31, c2_du31, c2_ln1, c2_un1, c2_vn1, c2_lgu1;   // step 1 (registered)
logic  [5:0] c2_lor6, c2_uor6;    // step 1: ORs of bits 30:26 / 25:21 / 20:16 / 15:11 / 10:5 / 4:0 of each difference
logic        c2_lor1, c2_uor1;
logic        c2_nzl, c2_nzu, c2_eq, c2_gtl, c2_gtu;
always_comb begin
    case (c_sz)                     // (the compare words take the instruction's size: xsz_q = c_sz there)
    2'd0: begin
        c2_lb = {{24{xt[7]}}, xt[7:0]};
        c2_ub = {{24{dt[7]}}, dt[7:0]};
        c2_v  = cx[15] ? xa_q : {{24{xa_q[7]}}, xa_q[7:0]};
    end
    2'd1: begin
        c2_lb = {{16{xt[15]}}, xt[15:0]};
        c2_ub = {{16{dt[15]}}, dt[15:0]};
        c2_v  = cx[15] ? xa_q : {{16{xa_q[15]}}, xa_q[15:0]};
    end
    default: begin
        c2_lb = xt;
        c2_ub = dt;
        c2_v  = xa_q;
    end
    endcase
    c2_dl  = {c2_v[31], c2_v} - {c2_lb[31], c2_lb};
    c2_du  = {c2_v[31], c2_v} - {c2_ub[31], c2_ub};
end
always_ff @(posedge clk) if (IS020 && e3 && aop == OP_CHK2) begin
    c2_ltl1 <= c2_dl[32];                   // value < lower
    c2_ltu1 <= c2_du[32];                   // value < upper
    c2_dl31 <= c2_dl[31];
    c2_du31 <= c2_du[31];
    c2_lor6 <= {|c2_dl[30:26], |c2_dl[25:21], |c2_dl[20:16], |c2_dl[15:11], |c2_dl[10:5], |c2_dl[4:0]};
    c2_uor6 <= {|c2_du[30:26], |c2_du[25:21], |c2_du[20:16], |c2_du[15:11], |c2_du[10:5], |c2_du[4:0]};
    c2_ln1  <= c2_lb[31];
    c2_un1  <= c2_ub[31];
    c2_vn1  <= c2_v[31];
end
// lower > upper from the raw bounds (no size mux): one subtraction DT - XT with a zero column after bit 7 and after
// bit 15 (0 - 0 - borrow passes the borrow on and shows it), so c2_gs[8] / [17] / [34] = the borrow out of bit 7 / 15 /
// 31 = unsigned DT < XT on 8 / 16 / 32 bits; XOR the two sign bits = signed. Registered every clock: c_sz, XT and DT
// are loaded at least one micro-word before the compare word and stay until the instruction ends, so the value step 2
// reads after the compare word is the same
/* verilator lint_off UNUSED */
logic [34:0] c2_gs;                // (only the three borrow taps are read)
/* verilator lint_on UNUSED */
assign c2_gs = {1'b0, dt[31:16], 1'b0, dt[15:8], 1'b0, dt[7:0]} - {1'b0, xt[31:16], 1'b0, xt[15:8], 1'b0, xt[7:0]};
always_ff @(posedge clk) if (IS020) c2_lgu1 <= (c_sz == 2'd0) ? (c2_gs[8] ^ dt[7] ^ xt[7]) :
                                                (c_sz == 2'd1) ? (c2_gs[17] ^ dt[15] ^ xt[15]) : (c2_gs[34] ^ dt[31] ^ xt[31]);
// step 2: value vs lower / upper; s1 / s2 / s3 = sign bits of the 32-bit wrapping differences lower - value, upper -
// value, value - lower (lower - value is negative when value - lower is positive and not $80000000, or is $80000000)
assign c2_lor1 = |c2_lor6;                  // bits 30:0 of value - lower not all zero
assign c2_uor1 = |c2_uor6;
assign c2_nzl = c2_dl31 | c2_lor1;
assign c2_nzu = c2_du31 | c2_uor1;
assign c2_eq  = !c2_nzl || !c2_nzu;
assign c2_gtl = !c2_ltl1 && c2_nzl;          // value > lower
assign c2_gtu = !c2_ltu1 && c2_nzu;          // value > upper
always_ff @(posedge clk) if (IS020) begin
    c2_zq <= c2_eq;
    c2_cq <= !c2_eq && (c2_lgu1 ? (c2_gtu && c2_ltl1) : (c2_ltl1 || c2_gtu));
    {c2_nq, c2_vq} <= c2nv(c2_ln1, c2_un1, c2_vn1, c2_eq, c2_lgu1, c2_ltl1, c2_gtl, c2_ltu1, c2_gtu,
                           c2_dl31 ^ c2_lor1, c2_du31 ^ c2_uor1, c2_dl31);
end
logic [15:0] pk_s, up_s;          // 68020 PACK / UNPK sums
assign pk_s = (ir[3] ? {xa_q[7:0], xa_q[15:8]} : xa_q[15:0]) + xb_q[15:0];
assign up_s = {4'd0, xa_q[7:4], 4'd0, xa_q[3:0]} + xb_q[15:0];
logic        mul_lv;
assign mul_lv = cx[11] ? (mul_lp[63:32] != {32{mul_lp[31]}}) : (mul_lp[63:32] != 32'd0);
// 68020 DIV.L: 64 / 32 restoring divider, one quotient bit per micro-cycle (DVLSTEP), on magnitudes
logic [31:0] dl_r, dl_q, dl_d;
logic        dl_sq, dl_sr, dl_z, dl_ov;
logic [63:0] dl_nd, dl_md;
logic [32:0] dl_t, dl_ts;
logic        dl_ov2;
assign dl_nd  = {cx[10] ? xb_q : (cx[11] ? {32{dl_q[31]}} : 32'd0), dl_q};     // dividend (Dq latched by DVLINIT)
assign dl_md  = (cx[11] && dl_nd[63]) ? -dl_nd : dl_nd;
assign dl_t   = {dl_r, dl_q[31]};
assign dl_ts  = dl_t - {1'b0, dl_d};
assign dl_ov2 = dl_sq ? (dl_q > 32'h80000000) : (cx[11] && dl_q[31]);
// DIV.L overflow N / Z (2026-11-16: WinUAE newcpu_common.cpp divul_overflow / divsl_overflow, 68020 / 030), registered
// at DVLHI (dl_q = Dq, xb_q = Dr, dl_d = |divisor|, dl_sq = divisor sign): N = Dq < 0, Z = Dq = 0; DIVS.L with a 64-bit
// dividend: Dr = 0: Z = 1, N = 0; Dr < 0, divisor < 0 and Dr > divisor: N = Z = 0; else Dq = 0: Z = 1, N = 0; else
// Z = 0, N = Dq[31] ^ Dr[31]
// Two steps (2026-11-16, timing): DVLHI registers the parts (dlo_*1: 64-bit DIVS.L, Dq = 0, Dq < 0, Dr = 0, Dr < 0,
// divisor < 0 and Dr < 0, the sign and six partial ORs of Dr + |divisor|); the clock after it registers N / Z from them.
// The overflow flag word comes three or more clocks after DVLHI, so it reads the same values as before.
logic        dlo_n, dlo_z, dlo_hgt;
logic        dlo_s641, dlo_qz1, dlo_q311, dlo_rz1, dlo_r311, dlo_hc1, dlo_ss1;
logic  [5:0] dlo_so6;
logic [32:0] dlo_sum;
assign dlo_sum = {xb_q[31], xb_q} + {1'b0, dl_d};                  // Dr + |divisor| (> 0: Dr > divisor when it is negative)
assign dlo_hgt = dlo_hc1 && !dlo_ss1 && (dlo_so6 != 6'd0);
always_ff @(posedge clk) if (IS020) begin
    dlo_z <= dlo_s641 ? (dlo_rz1 || (!dlo_hgt && dlo_qz1)) : dlo_qz1;
    dlo_n <= dlo_s641 ? (!dlo_rz1 && !dlo_hgt && !dlo_qz1 && (dlo_q311 ^ dlo_r311)) : dlo_q311;
end
// result: the adder enters the last mux level (r_add_q, latched at e2); ops above 31 (x_ext_q) from the EU
logic [31:0] xres_e;
// DIV.L quotient / remainder with their signs
logic [31:0] dl_qo, dl_ro;
assign dl_qo = dl_sq ? -dl_q : dl_q;
assign dl_ro = dl_sr ? -dl_r : dl_r;
always_comb begin
    xsel_d = 4'd0;
    if (IS020) case (aop_d)
    OP_EXTB:  xsel_d = 4'd1;
    OP_MULLL: xsel_d = 4'd2;
    OP_MULLH: xsel_d = 4'd3;
    OP_DVLQ:  xsel_d = 4'd4;
    OP_DVLR:  xsel_d = 4'd5;
    OP_BF:    xsel_d = (ir[10:8] == 3'd1 || ir[10:8] == 3'd3) ? 4'd6 : (ir[10:8] == 3'd5) ? 4'd8 : 4'd9;
    OP_BF5:   xsel_d = 4'd10;
    OP_PACK:  xsel_d = 4'd11;
    OP_UNPK:  xsel_d = 4'd12;
    OP_UNPKH: xsel_d = 4'd13;
    default: ;
    endcase
    case (xsel_q)
    4'd1:  xres_e = {{24{xb_q[7]}}, xb_q[7:0]};
    4'd2:  xres_e = mul_lp[31:0];
    4'd3:  xres_e = mul_lp[63:32];
    4'd4:  xres_e = dl_qo;
    4'd5:  xres_e = dl_ro;
    // BFEXTU / BFEXTS (IR bit 9): the field right-aligned, BFEXTS with the field's sign in the bits above it (bf_lmc = the
    // low width bits of the current width, as bf_xuq) - the same as the arithmetic shift of bf_flq by 32 - width (cp5)
    4'd6:  xres_e = bf_xuq | ({32{bf_flq[31] & ir[9]}} & ~bf_lmc);
    4'd8:  xres_e = bf_ffoq;
    4'd9:  xres_e = bf_new;
    4'd10: xres_e = {24'd0, bf_new5};
    // PACK: (source word + adjustment) digits 11-8, 3-0 (memory form: the bytes as read, low byte first); UNPK: byte
    // digits to word nibbles 11-8, 3-0, + adjustment (UNPKH: its high byte); flags unchanged
    default: xres_e = alu_res_oth;
    endcase
end
// PACK / UNPK sums (adders on the operand registers) enter one mux level before the adder result
logic [31:0] xres_pk;
assign xres_pk = (xsel_q == 4'd11) ? {xb_q[31:8], pk_s[11:8], pk_s[3:0]} : (xsel_q == 4'd12) ? {16'd0, up_s} : {24'd0, up_s[15:8]};
// (sources 2 / 1 exist only on the 68020: elsewhere rsrc_q is never 2 / 1 and they read as source 0, so the 68020
// result logic - MUL.L product, DIV.L, bit-field and PACK / UNPK registers - folds away)
always_comb begin
    case (rsrc_q)
    2'd3:    xres = alu_res_add;
    2'd2:    xres = IS020 ? xres_pk : alu_res_oth;
    2'd1:    xres = IS020 ? xres_e : alu_res_oth;
    default: xres = alu_res_oth;
    endcase
end
// N / Z rule and size of the micro-instruction (the ops above 31 and CHK / DIV / MOVE.l steps override the ALU's)
always_comb begin
    xnzm = alu_nzm;
    xnsz = alu_nsz;
    case (aop)
    OP_CHK, OP_DIVO, OP_MVL, OP_MVH, OP_DIVZ: xnzm = 2'd2;
    OP_DIVR: begin xnzm = 2'd0; xnsz = 2'd1; end
    OP_EXTB, OP_DVLQ: if (IS020) begin xnzm = 2'd0; xnsz = 2'd2; end
    OP_MULLL, OP_MULLH, OP_DVLR, OP_DVLO, OP_BFP, OP_BF, OP_BF5, OP_CHK2, OP_PACK, OP_UNPK, OP_UNPKH: if (IS020) xnzm = 2'd2;
    default: ;
    endcase
end

// flags (cp4b flag-path split). At e3 the raw terms of the ALU and of the EU's own ops are registered (q_*), and
// for each flag the index of the term that supplies it (q_xi .. q_ci, decoded from the op / fh mode, which are stable
// since e2); ccr_q is the selected terms. ccr_q is read only at the next e0 (ccr_f -> sr_n), where it equals what the
// former e3 register held. The held X V C of a long op (FH_LO / FH_HD) is loaded one clock after the e3 from the same
// terms (indices q_hx .. q_hc). Rules unchanged:
//   ALU ops: X N Z V C from the op (ADD / SUB / CMP / ADDX / SUBX / NEG / NEGX / CMPA: adder; ABCD / SBCD / NBCD:
//   BCD; shifts; BIT; TAS; logic / EXT / SWAP / MUL / PASS: V = C = 0), else the inputs (X = alu_cin, N Z V C = SR);
//   ops above 31 / CHK / DIV / MOVE.l steps: the EU's rules (X from SR); fh LO: the low word's X V C, CM: the held ones
//   (long) or no change (byte / word).
// term indices: X 0 sr4 1 cin 2 adc 3 adc16 4 abc 5 sbc 6 sho 7 hold2
//               N 0 zero 1 one 2 sr3 3 tasn 4 chkdn 5 chk010 6 xa15 7 xa31 8 mn 9 bfn 10 xb31
//               Z 0 zero 1 one 2 sr2 3 bitz 4 tasz 5 chkdz 6 xaloz 7 mvhz 8 mz 9 bfz 10 c2z 11 xbhiz
//               V 0 zero 1 one 2 sr1 3 adv 4 adv16 5 abv 6 sbv 7 sr1|shv 8 shv 9 mlv 10 hold1
//               C 0 zero 1 sr0 2 adc 3 adc16 4 abc 5 sbc 6 sho 7 shfic 8 c2c 9 hold0
logic        q_adc, q_adv, q_adc16, q_adv16, q_abc, q_abv, q_sbc, q_sbv, q_sho, q_shv, q_cin;
logic        q_shfic, q_mlv, q_c2c, q_c2v, q_chkv, q_chkc;
logic        q_nf, q_zf;              // N / Z of the KEEP rule, selected at e3 (cp5: their terms are shallow)
logic  [2:0] q_xi, q_hx;
logic  [3:0] q_ni, q_zi, q_vi, q_ci, q_hv, q_hc;    // (q_ni / q_zi: decoded at e2, cp5)
logic  [2:0] fx_i, fhx_i;            // indices decoded at e3 (registered into q_*)
logic  [3:0] fv_i, fc_i, fhv_i, fhc_i;
logic  [2:0] fd_xx, fd_lx;            // decode temporaries of the block below
logic  [3:0] fd_xv, fd_xc, fd_lv, fd_lc;
logic        fd_sx;
always_comb begin
    // one case on the op: the term indices of the op's own flags (x*: X N Z V C) and of the low word's X V C of a long op
    // (l*: FH_LO); the ALU ops take X from the X input unless they set it, the EU's ops from SR (index 0)
    fd_sx = shtype[1:0] != 2'b11;
    fd_xx = 3'd1; fd_xv = 4'd2; fd_xc = 4'd1; fd_lx = 3'd1; fd_lv = 4'd2; fd_lc = 4'd1;
    case (aop)
    OP_PASS, OP_AND, OP_OR, OP_EOR, OP_NOT, OP_CLR, OP_TST, OP_EXT, OP_SWAP, OP_MUL:
             begin fd_xv = 4'd0; fd_xc = 4'd0; fd_lv = 4'd0; fd_lc = 4'd0; end
    OP_ADD, OP_SUB, OP_ADDX, OP_SUBX, OP_NEGX, OP_NEG:
             begin fd_xx = 3'd2; fd_xv = 4'd3; fd_xc = 4'd2; fd_lx = 3'd3; fd_lv = 4'd4; fd_lc = 4'd3; end
    OP_CMP:  begin fd_xv = 4'd3; fd_xc = 4'd2; fd_lv = 4'd4; fd_lc = 4'd3; end
    OP_CMPA: begin fd_xv = 4'd3; fd_xc = 4'd2; fd_lv = 4'd3; fd_lc = 4'd2; end
    OP_ABCD: begin fd_xx = 3'd4; fd_xv = 4'd5; fd_xc = 4'd4; fd_lx = 3'd4; fd_lv = 4'd5; fd_lc = 4'd4; end
    OP_SBCD, OP_NBCD: begin fd_xx = 3'd5; fd_xv = 4'd6; fd_xc = 4'd5; fd_lx = 3'd5; fd_lv = 4'd6; fd_lc = 4'd5; end
    OP_SHFI: begin fd_xv = 4'd0; fd_xc = 4'd7; fd_lv = 4'd0; fd_lc = 4'd7; end
    OP_SHF:  begin fd_xx = fd_sx ? 3'd6 : 3'd1; fd_xv = 4'd7; fd_xc = 4'd6; fd_lx = fd_sx ? 3'd6 : 3'd1; fd_lv = 4'd7; fd_lc = 4'd6; end
    OP_SHF1: begin fd_xx = fd_sx ? 3'd6 : 3'd1; fd_xv = 4'd8; fd_xc = 4'd6; fd_lx = fd_sx ? 3'd6 : 3'd1; fd_lv = 4'd8; fd_lc = 4'd6; end
    OP_TAS:  begin fd_xv = 4'd0; fd_xc = 4'd0; fd_lv = 4'd0; fd_lc = 4'd0; end
    // CHK: N Z of Dn, V = C = 0 (fx68k, MAME); 68010 (Musashi; undocumented): N changes only when CHK traps
    // 68020 (WinUAE setchkundefinedflags): V / C of the trap test (terms 11 / 10)
    OP_CHK:  begin fd_xx = 3'd0; fd_xv = IS020 ? 4'd11 : 4'd0; fd_xc = IS020 ? 4'd10 : 4'd0; end
    OP_DIVR: begin fd_xx = 3'd0; fd_xv = 4'd0; fd_xc = 4'd0; end
    // overflow: N = 1 Z = 0 V = 1 C = 0 (fx68k, MAME); 68010 (Musashi): N Z unchanged; 68020 (WinUAE setdivuflags): DIVU
    // keeps C (the 68020 comment there says C = 0, its code leaves C: the code is what ran)
    OP_DIVO: begin fd_xx = 3'd0; fd_xv = 4'd1; fd_xc = (IS020 && !ir[8]) ? 4'd1 : 4'd0; end
    // MOVE.l flag steps: low word (N Z, V = C = 0) / high word (N, Z sticky, V C kept)
    OP_MVL:  begin fd_xx = 3'd0; fd_xv = 4'd0; fd_xc = 4'd0; end
    OP_MVH:  fd_xx = 3'd0;
    // 68020: EXTB.L; MUL.L low (flags) / high; DIV.L quotient (flags) / remainder / overflow; bit fields; CHK2
    OP_EXTB, OP_DVLQ: if (IS020) begin fd_xx = 3'd0; fd_xv = 4'd0; fd_xc = 4'd0; end
    OP_MULLL: if (IS020) begin fd_xx = 3'd0; fd_xv = 4'd9; fd_xc = 4'd0; end
    OP_MULLH, OP_DVLR, OP_BFP, OP_BF5, OP_PACK, OP_UNPK, OP_UNPKH: if (IS020) fd_xx = 3'd0;
    OP_DVLO:  if (IS020) begin fd_xx = 3'd0; fd_xv = 4'd1; fd_xc = 4'd0; end
    OP_BF:    if (IS020) begin fd_xx = 3'd0; fd_xv = 4'd0; fd_xc = 4'd0; end
    OP_CHK2:  if (IS020) begin fd_xx = 3'd0; fd_xv = 4'd12; fd_xc = 4'd8; end
    OP_DIVZ: begin
        fd_xx = 3'd0;                                                      // 68010 (Musashi): flags unchanged
        if (!IS010) begin fd_xv = 4'd0; fd_xc = 4'd0; end
    end
    default: ;
    endcase
    fhx_i = fd_xx; fhv_i = fd_xv; fhc_i = fd_xc;
    // long op in two steps (68000 16-bit ALU): the low word's flags, later the long op's (FH_CM; byte / word ops:
    // the flags stay as they are)
    if (fhlo_q)      begin fx_i = fd_lx; fv_i = fd_lv; fc_i = fd_lc; end
    else if (fhcm_q) begin
        if (fhl_q) begin fx_i = 3'd7; fv_i = 4'd10; fc_i = 4'd9; end
        else       begin fx_i = 3'd0; fv_i = 4'd2; fc_i = 4'd1; end
    end else         begin fx_i = fd_xx; fv_i = fd_xv; fc_i = fd_xc; end
end
// N / Z term indices (the same rules), decoded at e2 from the op and fh mode being latched there (cp5: q_nf / q_zf take
// the selected term at e3 with the index from a register); a byte / word FH_CM word keeps N / Z (2: sr)
function automatic logic [7:0] nzsel(input logic [5:0] op, input logic cm, input logic l, input logic i8);
    logic [3:0] n, z;
    n = 4'd2; z = 4'd2;
    case (op)
    OP_BIT:  z = 4'd3;
    OP_TAS:  begin n = 4'd3; z = 4'd4; end
    OP_CHK:  begin n = (IS010 && !IS020) ? 4'd5 : 4'd4; z = 4'd5; end
    OP_DIVR: begin n = 4'd0; z = 4'd0; end
    // DIVU / DIVS overflow; 68020 (WinUAE setdivuflags / setdivsflags): DIVU N |= dividend < 0, Z kept; DIVS N / Z of
    // the quotient magnitude's low byte unless the overflow was found at the start ("absolute overflow")
    OP_DIVO: if (IS020) begin n = i8 ? 4'd12 : 4'd11; z = i8 ? 4'd12 : 4'd2; end
             else begin n = IS010 ? 4'd2 : 4'd1; z = IS010 ? 4'd2 : 4'd0; end
    OP_DVLO:  if (IS020) begin n = 4'd13; z = 4'd13; end
    OP_MVL:  begin n = 4'd6; z = 4'd6; end
    OP_MVH:  begin n = 4'd7; z = 4'd7; end
    OP_EXTB, OP_DVLQ: if (IS020) begin n = 4'd0; z = 4'd0; end
    OP_MULLL: if (IS020) begin n = 4'd8; z = 4'd8; end
    OP_BF:    if (IS020) begin n = 4'd9; z = 4'd9; end
    OP_CHK2:  if (IS020) begin n = 4'd14; z = 4'd10; end
    OP_DIVZ:  if (!IS010 && i8) begin n = 4'd0; z = 4'd1; end else if (!IS010) begin n = 4'd10; z = 4'd11; end
    default: ;
    endcase
    if (cm && !l) begin n = 4'd2; z = 4'd2; end
    nzsel = {n, z};
endfunction
function automatic logic fsel16(input logic [3:0] i, input logic [15:0] t);
    fsel16 = t[i];
endfunction
logic [7:0]  ft_x;
logic [15:0] ft_n, ft_z, ft_v, ft_c;
logic        mn_c, mz_c;
assign mn_c = cx[10] ? mul_lp[63] : mul_lp[31];
assign mz_c = cx[10] ? (mul_lp[63:0] == 64'd0) : (mul_lp[31:0] == 32'd0);
// a term is present only on the CPUs whose decode above can select its index (the others see a constant 0, so the term
// register and its logic fold away): chk010 (N 5) IS010; mn / bfn / mz / bfz / c2z / mlv / c2c (N 8 9, Z 8 9 10, V 9,
// C 8) IS020
// (checkpoint 5: the SR and held-flag terms are sr / hold_xvc themselves - sr changes only at e0, hold_xvc never between
// an FH_CM word's e3 and its e0 - instead of copies registered at e3)
assign ft_x = {hold_xvc[2], q_sho, q_sbc, q_abc, q_adc16, q_adc, q_cin, sr[4]};
// N / Z terms (KEEP rule): all of them are a few LUT levels from the e2 registers (and sr, unchanged until e0), so the
// selected N and Z are registered at e3 directly (q_nf / q_zf) instead of the terms and their indices (cp5)
// 68020 (2026-11-16, WinUAE): N 11 DIVU overflow (dividend < 0 or N), 12 DIVS overflow (|quotient| bit 7 unless found at
// the start), 13 DIV.L overflow (dlo_n), 14 CHK2 (c2_nq); Z 12 DIVS overflow (|quotient| low byte 0, same condition),
// 13 DIV.L overflow (dlo_z); V 11 CHK (q_chkv), 12 CHK2 (q_c2v); C 10 CHK (q_chkc)
assign ft_n = {1'd0, IS020 & c2_nq, IS020 & dlo_n, IS020 & !dv_ov & dv_q[7], IS020 & (xb_q[31] | sr[3]),
               xb_q[31], IS020 & bf_n, IS020 & mn_c, xa_q[31], xa_q[15], IS010 & (chk_dn | (!chk_t & sr[3])), chk_dn,
               xb_q[7], sr[3], 2'b10};
assign ft_z = {2'd0, IS020 & dlo_z, IS020 & !dv_ov & (dv_q[7:0] == 8'd0),
               xb_q[31:16] == 16'd0, IS020 & c2_zq, IS020 & bf_z, IS020 & mz_c, sr[2] & (xa_q[31:16] == 16'd0),
               xa_q[15:0] == 16'd0, chk_dz, xb_q[7:0] == 8'd0, 1'b0, sr[2], 2'b10};    // (3: a_bitz, at q_zf)
assign ft_v = {3'd0, IS020 & q_c2v, IS020 & q_chkv, hold_xvc[1], IS020 & q_mlv, q_shv, sr[1] | q_shv, q_sbv, q_abv, q_adv16, q_adv, sr[1], 2'b10};
assign ft_c = {5'd0, IS020 & q_chkc, hold_xvc[0], IS020 & q_c2c, q_shfic, q_sho, q_sbc, q_abc, q_adc16, q_adc, sr[0], 1'b0};
assign ccr_q = {ft_x[q_xi], q_nf, q_zf, fsel16(q_vi, ft_v), fsel16(q_ci, ft_c)};

logic nowrite;               // latched at e2 with the op: no result write-back
logic nowrite_d;
assign nowrite_d = (aop_d == OP_CMP) || (aop_d == OP_TST) || (aop_d == OP_CMPA) || (aop_d == OP_CHK) ||
                   (aop_d == OP_DIVO) || (aop_d == OP_DIVZ) || ((aop_d == OP_BIT) && (ir[7:6] == 2'd0)) ||
                   (IS020 && aop_d == OP_DVLO);

// ------------------------------------------------------------------------------------------------ sequential

// register writes: address-unit result at e3 (straight from the adder), ALU result at e0 (from RES; a byte / word
// write merges into the old value read on copy BW in phases 2-3); an AU write wins over an ALU write to the same entry
logic [3:0]  w_alu_ix, w_au_ix;
logic        ctlw_usp;
assign ctlw_usp = (u_xe == XE_CTLW) && cx[11] && (IS020 ? (cx[2:0] == 3'd0 || cx[2:0] == 3'd3 || cx[2:0] == 3'd4) : !cx[0]);
logic [4:0]  w_alu_p, w_au_p;
logic        w_alu_r, w_alu_full, w_au_r, w_alu_go;
always_comb begin
    w_alu_r = 1'b1; w_alu_full = 1'b0; w_alu_ix = 4'd0;
    case (u_xd)
    XD_DX:   w_alu_ix = ix_dx;
    XD_DY:   w_alu_ix = ix_dy;
    XD_AX:   begin w_alu_ix = ix_ax;  w_alu_full = 1'b1; end
    XD_AY:   begin w_alu_ix = ix_ay;  w_alu_full = 1'b1; end
    XD_MREG: begin w_alu_ix = ix_mreg; w_alu_full = 1'b1; end
    XD_RXE:  begin w_alu_ix = ix_rxe; w_alu_full = 1'b1; end
    XD_RYE:  if (UM_XD[XD_RYE]) begin w_alu_ix = ix_rye; w_alu_full = 1'b1; end else w_alu_r = 1'b0;
    XD_OSP:  w_alu_full = 1'b1;
    default: w_alu_r = 1'b0;
    endcase
    // 68010: register named by the extension word (MOVEC / MOVES), MOVEC to USP (the inactive stack pointer)
    if (u_xe == XE_RCD) begin w_alu_r = 1'b1; w_alu_ix = cx[15:12]; w_alu_full = cx[15]; end
    if (IS020 && u_xe == XE_RCH) begin w_alu_r = 1'b1; w_alu_ix = {1'b0, cx[2:0]}; w_alu_full = 1'b0; end
    if (IS020 && u_xe == XE_RCL) begin w_alu_r = 1'b1; w_alu_ix = {1'b0, cx[14:12]}; w_alu_full = 1'b0; end
    if (ctlw_usp) begin w_alu_r = 1'b1; w_alu_full = 1'b1; end
    if (nowrite || aop == OP_NOP) w_alu_r = 1'b0;
    w_alu_p = (u_xd == XD_OSP) ? p_osp : ctlw_usp ? p_ctl : phys(w_alu_ix, sr[13], msp);
    w_au_r = 1'b1; w_au_ix = 4'd0;
    case (u_ad)
    AD_ATPI: begin w_au_ix = ix_ay; w_au_r = ir[5:3] == 3'd3; end
    AD_AY:   w_au_ix = exg_dd ? ix_dy : ix_ay;      // EXG Dx,Dy: the address unit writes Dy (both registers in one word)
    AD_AX:   w_au_ix = ix_ax;
    AD_SP:   w_au_ix = 4'd15;
    default: w_au_r = 1'b0;
    endcase
    w_au_p = phys(w_au_ix, sr[13], msp);
    // same entry: equal logical indices (the inactive stack pointer, XD_OSP, is never the AU's A7)
    w_alu_go = w_alu_r && !(w_au_r && (w_au_ix == w_alu_ix) && (u_xd != XD_OSP) && !ctlw_usp);
end

function automatic logic [31:0] merge(input logic [31:0] old, input logic [31:0] v, input logic [1:0] s);
    case (s)
    2'd0:    merge = {old[31:8], v[7:0]};
    2'd1:    merge = {old[31:16], v[15:0]};
    2'd3:    merge = {v[31:16], old[15:0]};
    default: merge = v;
    endcase
endfunction

// flags of the micro-instruction: X V C (and N Z of the KEEP ops) latched at e3, N Z of the others from RES now
logic [15:0] sr_n;
logic  [4:0] ccr_f;
logic        f_n, f_z;
always_comb begin
    case (nsz_q)
    2'd0:    begin f_n = res[7];  f_z = res[7:0] == 8'd0; end
    2'd1:    begin f_n = res[15]; f_z = res[15:0] == 16'd0; end
    default: begin f_n = res[31]; f_z = res == 32'd0; end
    endcase
    case (nzm_q)
    2'd0:    ccr_f = {ccr_q[4], f_n, f_z, ccr_q[1:0]};
    2'd1:    ccr_f = {ccr_q[4], f_n, sr[2] & f_z, ccr_q[1:0]};
    default: ccr_f = ccr_q;
    endcase
end
// divider helpers: |dividend|, |divisor| (DIVS), one restoring step
logic [31:0] dv_ud;
logic [15:0] dv_ur;
logic [16:0] dv_t, dv_tsub;
assign dv_ud   = (ir[8] && xb_q[31]) ? -xb_q : xb_q;
assign dv_ur   = (ir[8] && xa_q[15]) ? -xa_q[15:0] : xa_q[15:0];
assign dv_t    = {dv_r, dv_q[15]};
assign dv_tsub = dv_t - {1'b0, dv_d};
logic [31:0] au_sum;
assign au_sum = aua_q + aub_q;
always_comb begin
    sr_n = sr;
    if (u_fl && !c_nofl && aop != OP_NOP) sr_n[4:0] = ccr_f;
    if (!nowrite && aop != OP_NOP) begin
        if (u_xd == XD_SR)  sr_n = res[15:0] & SR_MASK;
        if (u_xd == XD_CCR) sr_n[4:0] = res[4:0];
    end
    if (u_ms == MS_EXCENT) begin sr_n[13] = 1'b1; sr_n[15] = 1'b0; if (IS020) sr_n[14] = 1'b0; end
    if (IS020 && u_m2 == M2_CLRM) sr_n[12] = 1'b0;                     // 68020 interrupt: M cleared (throwaway frame)
    if (u_ms == MS_SETIPL) sr_n[10:8] = ilvl;
    if (IS010 && u_x1 == X1_SRF) sr_n = f8sr & SR_MASK;
end

`ifdef M68KSV_TESTLOAD
logic tl;
assign tl = tl_en;
`else
logic tl;
assign tl = 1'b0;
`endif

// register file copies and their common write port; the write controls are registered one phase ahead
logic  [4:0] wau_p_q, walu_p_q;
logic        wau_r_q, walu_go_q, walu_full_q;
logic  [1:0] walu_sz_q;
logic        rf_we;
logic  [4:0] rf_wa, ra_xn, ra_a, ra_bw;
logic [31:0] rf_wd;
logic        d_reg;           // write data comes from a register (copy BW serves D, not B)
assign d_reg = (UM_DW[DW_EAVL] && u_dw == DW_EAVL) || (UM_DW[DW_EAVH] && u_dw == DW_EAVH) || (u_dw == DW_EAV1) ||
               (u_dw == DW_MRL) || (u_dw == DW_MRH) || (UM_DW[DW_AYL] && u_dw == DW_AYL) || (UM_DW[DW_AYH] && u_dw == DW_AYH) || (IS010 && ((u_dw == DW_RC1) || (u_dw == DW_RCL))) ||
               (IS020 && ((u_d2 == D2_RUH) || (u_d2 == D2_RUL)));
logic [3:0] ix_pdx;               // port D register (68020: the CAS update register cx[8:6])
assign ix_pdx = (IS020 && (u_d2 == D2_RUH || u_d2 == D2_RUL)) ? {1'b0, cx[8:6]} : ix_pd;
assign ra_xn = (u_ab == AB_XN) ? phys(ixw[15:12], sr[13], msp) : (u_xa == XA_OSP) ? p_osp : (IS010 && u_xa == XA_CTL) ? p_ctl :
               phys(ix_px, sr[13], msp);
assign ra_a  = (u_aa == AA_SSP) ? (msp ? 5'd17 : 5'd16) : phys(ix_pa, sr[13], msp);   // SSP: exception entry before S is set
// at e0 copy A is addressed for the next micro-instruction (bus address needed at e1)
logic [F_AA_W-1:0] uq_aa;
logic [3:0]  uq_ba, ix_pa_nx;
logic [15:0] ir_nx;
logic  [4:0] ra_a_nx;
assign uq_aa = uq[F_AA_LSB +: F_AA_W];
assign uq_ba = uq[F_BA_LSB +: F_BA_W];
assign ir_nx = fin_q ? ((ISLM && lmc_q) ? lw0 : irn) : ir;     // 68010 loop word: the looped opcode
always_comb begin
    case (uq_aa)
    AA_AX:         ix_pa_nx = {1'b1, ir_nx[11:9]};
    AA_FBX:        ix_pa_nx = {1'b1, IS020 ? ir_nx[11:9] : ir_nx[2:0]};
    AA_SP, AA_SSP: ix_pa_nx = 4'd15;
    AA_AY:         ix_pa_nx = {1'b1, ir_nx[2:0]};
    default:       ix_pa_nx = (uq_ba == BA_AX) ? {1'b1, ir_nx[11:9]} : (uq_ba == BA_SP) ? 4'd15 : {1'b1, ir_nx[2:0]};
    endcase
end
assign ra_a_nx = (uq_aa == AA_SSP) ? (msp_n ? 5'd17 : 5'd16) : phys(ix_pa_nx, sr_n[13], msp_n);
// phases 2-3: the merge source, the destination register (a byte / word write, or a low-word write with field lh)
assign ra_bw = ph[1] ? phys(w_alu_ix, sr[13], msp) : d_reg ? phys(ix_pdx, sr[13], msp) : phys(ix_pb, sr[13], msp);
`ifdef M68KSV_TESTLOAD
logic  [4:0] tl_k;            // test load: entries written one per clock while tl_en is held
logic [31:0] tl_v;
always_comb begin
    case (tl_k)
    5'd15:   tl_v = tl_usp;
    5'd16:   tl_v = tl_ssp;
    default: tl_v = tl_r[tl_k[3:0]];
    endcase
end
assign rf_we = tl ? (tl_k <= 5'd16) : ((e3 && wau_r_q) || (e0 && walu_go_q));
assign rf_wa = tl ? tl_k : e3 ? wau_p_q : walu_p_q;
assign rf_wd = tl ? tl_v : e3 ? au_sum : (walu_full_q ? res : merge(rd_bw, res, walu_sz_q));
always_ff @(posedge clk) tl_k <= tl ? tl_k + 5'd1 : 5'd0;
`else
assign rf_we = (e3 && wau_r_q) || (e0 && walu_go_q);
assign rf_wa = e3 ? wau_p_q : walu_p_q;
assign rf_wd = e3 ? au_sum : (walu_full_q ? res : merge(rd_bw, res, walu_sz_q));
`endif
m68ksv_rf rf_xn  (.clk(clk), .we(rf_we), .wa(rf_wa), .wd(rf_wd), .ra(ra_xn),  .rd(rd_xn));
m68ksv_rf rf_a   (.clk(clk), .we(rf_we), .wa(rf_wa), .wd(rf_wd), .ra(e0 ? ra_a_nx : ra_a), .rd(rd_a));
always_ff @(posedge clk) begin
    if (e0) begin
        fwd_hit <= rf_we && (rf_wa == ra_a_nx);
        fwd_v   <= rf_wd;
    end
end
m68ksv_rf rf_bw  (.clk(clk), .we(rf_we), .wa(rf_wa), .wd(rf_wd), .ra(ra_bw),  .rd(rd_bw));
m68ksv_rf rf_dbg (.clk(clk), .we(rf_we), .wa(rf_wa), .wd(rf_wd), .ra(dbg_ra), .rd(dbg_rd));

// IRC writes (all in one place; priority as listed, last wins): RTE frame word IIB (68010), opcode prefetch (a ghost
// cycle's word from ghost_d), IACK without BERR, the late IACK of a spurious interrupt, loop word (68010: DBcc opcode)
logic        irc_ld_fx, irc_ld_rd, irc_ld_pf, irc_ld_ia, irc_ld_late, irc_ld_lw, irc_we;
logic [15:0] irc_d;
assign irc_ld_fx   = IS010 && b_dv && f8ld && (bo_fx == FX_LIIB);
assign irc_ld_rd   = !(IS010 && b_dv && f8ld) && b_dv && !(IS010 && b_berr && bo_op != BUS_IACK);
assign irc_ld_pf   = irc_ld_rd && (bo_op == BUS_NPE || bo_op == BUS_NPF);
assign irc_ld_ia   = irc_ld_rd && (bo_op == BUS_IACK) && !bo_bkpt && !b_berr;
assign irc_ld_late = e0w && iack_late;
assign irc_ld_lw   = ISLM && e0 && fin_q && lmc_q;
assign irc_we      = irc_ld_fx || irc_ld_pf || irc_ld_ia || irc_ld_late || irc_ld_lw;
assign irc_d       = b_dv ? ((ISLM && ghost && irc_ld_pf) ? ghost_d : b_din) :        // (e3: no e0 / e0w write)
                     (ISLM && fin_q && lmc_q && !(irc_ld_late && !e0)) ? lw1 : b_din;
// IRN / IR / FPC / AT / FA / DT / IM writes, likewise (each cause in the order of priority it has always had, last
// wins). The data selects use only early phase information (e2, b_dv = e3 - the phases exclude each other) and the
// word's fields; e0 (late: it waits for the micro-ROM's bus request) only gates the write enables
logic        f8_ld;            // 68010 RTE: this read's word goes to a frame register
logic        lw_c;             // 68010 loop word FIN: the looped instruction's state restored (at e0)
logic        irn_ld_f8, ir_ld_f8, fpc_ld_pf, sw_c, at_au, at_res, fa_ld_berr, fa_ld_ae, irn_we, ir_we, fpc_we;
logic  [1:0] at_ld_f8, fa_ld_f8, at_we, fa_we;
logic [15:0] irn_d, ir_d;
logic [31:0] fpc_d, at_d, fa_d;
assign f8_ld       = IS010 && b_dv && f8ld;
assign lw_c        = ISLM && fin_q && lmc_q;
assign irn_ld_f8   = f8_ld && (bo_fx == FX_LIR || bo_fx == FX_LIRN);
assign irn_we      = irn_ld_f8 || (e0 && ((uq_bus == BUS_NPF) || lw_c));
assign irn_d       = irn_ld_f8 ? b_din : lw_c ? lw0 : irc;
assign ir_ld_f8    = f8_ld && (bo_fx == FX_LIR);
assign ir_we       = ir_ld_f8 || (e0 && ((u_ms == MS_IRCIR) || fin_q));
assign ir_d        = ir_ld_f8 ? b_din : fin_q ? ((ISLM && lmc_q) ? lw0 : irn) : irc;
assign fpc_ld_pf   = e2 && bact && (bo_op == BUS_NPE || bo_op == BUS_NPF) && !ae;
assign sw_c        = IS010 && (u_x1 == X1_SWDONE) && ssw[13];
assign fpc_we      = fpc_ld_pf || (e0 && ((UM_AD[AD_FPC] && u_ad == AD_FPC) || sw_c || lw_c));
// one adder for the three FPC sums (cp5): ba_q + 2 after an opcode fetch (e2), the 68010 loop word's lbase + 4 (24 bits,
// zero-extended) and the software-completed fetch's FA + 2 (both at e0); the selects keep the old priority
logic [31:0] fpc_aa, fpc_sum;
assign fpc_aa      = (fpc_ld_pf || !IS010) ? ba_q : lw_c ? {8'd0, lbase} : fa;
assign fpc_sum     = fpc_aa + ((!fpc_ld_pf && lw_c) ? 32'd4 : 32'd2);
// (68000 family: the opcode fetch is the only FPC load - no AD_FPC word in its ROM, no loop / software completion)
assign fpc_d       = (fpc_ld_pf || (!IS010 && !UM_AD[AD_FPC])) ? fpc_sum : lw_c ? {8'd0, fpc_sum[23:0]} : sw_c ? fpc_sum : aur;
assign at_ld_f8    = {f8_ld && (bo_fx == FX_LATH), f8_ld && (bo_fx == FX_LATL)};
assign at_au       = (u_ad == AD_AT) || (u_ad == AD_ATPI);
assign at_res      = !nowrite && (aop != OP_NOP) && (u_xd == XD_AT) && !at_au;
assign at_we       = at_ld_f8 | {2{e0 && (at_au || at_res)}};
assign at_d        = f8_ld ? {b_din, b_din} : at_res ? res : aur;
assign fa_ld_berr  = e2 && berr_now;
assign fa_ld_ae    = e2 && bact && ae;
assign fa_ld_f8    = {f8_ld && (bo_fx == FX_LFAH), f8_ld && (bo_fx == FX_LFAL)};
assign fa_we       = fa_ld_f8 | {2{fa_ld_berr || fa_ld_ae}};
// (a bus error is seen in the cycle's second micro-word, which never starts a cycle - M68KSV_SIMCHECK below - so ba_q
// still holds the cycle's address: no copy of it; cp5)
assign fa_d        = f8_ld ? {b_din, b_din} : ba_q;
// DT, per byte: shift left 8 (MS_DTSHL8) > RES merged by size (XD_DT) > read data (ld_*: the bus at e3 by bo_bd / byte,
// IACK vector byte, or 68010 SWDONE at e0: DIB by bd_f / SSW.BY when SSW.DF, DIB bits 7-0 when SSW.RM)
logic        dt_rdv, dt_bus, dt_iack, dt_sw, dt_res, dt_shl, dl_hi, dl_shb, dl_b;
logic  [3:0] dt_we, dt_wmask, dt_wres, dt_we0;
logic [31:0] dt_d, dt_ldv;
assign dt_rdv   = b_dv && !f8_ld && !(IS010 && b_berr && bo_op != BUS_IACK);
assign dt_bus   = dt_rdv && (bo_op != BUS_NPE) && (bo_op != BUS_NPF) && (bo_op != BUS_IACK) && !(IS020 && bo_xp);
assign dt_iack  = dt_rdv && (bo_op == BUS_IACK) && !bo_bkpt;
assign dt_sw    = IS010 && (u_x1 == X1_SWDONE);
assign dt_res   = !nowrite && (aop != OP_NOP) && (u_xd == XD_DT);
assign dt_shl   = u_ms == MS_DTSHL8;
assign dl_hi    = (ld_bd == BD_HI) || ((ld_bd == BD_L1) && (c_sz == 2'd2));
assign dl_shb   = ld_bd == BD_SHB;
assign dl_b     = !dl_hi && !dl_shb && ld_byte;
assign dt_wmask = {dl_hi || dl_shb, dl_hi || dl_shb, !dl_hi && !dl_b, !dl_hi};
assign dt_wres  = (xsz == 2'd0) ? 4'b0001 : (xsz == 2'd1) ? 4'b0011 : (xsz == 2'd3) ? 4'b1100 : 4'b1111;
assign dt_we0   = dt_shl ? 4'b1111 : dt_res ? dt_wres :
                  ((dt_sw && ssw[12]) ? dt_wmask : 4'b0000) | {3'b000, dt_sw && ssw[11]};
assign dt_we    = (dt_bus ? dt_wmask : 4'b0000) | {3'b000, dt_iack} | (e0 ? dt_we0 : 4'b0000);
assign dt_ldv   = {dl_shb ? dt[23:16] : ld_d[15:8], dl_shb ? dt[15:8] : ld_d[7:0], dl_shb ? dt[7:0] : ld_d[15:8], ld_d[7:0]};
assign dt_d     = b_dv ? dt_ldv : dt_shl ? {dt[23:0], 8'd0} : dt_res ? res : dt_ldv;
// IM, per byte: RES merged by size (XD_IM, the same byte enables as DT) / RES low word -> high word (XD_IMH) > 68010
// slot A from DT (fx MSLA, layout IM); all at e0
logic        im_xd, im_xdh, im_sl;
logic  [3:0] im_we;
logic [31:0] im_d;
assign im_xd   = !nowrite && (aop != OP_NOP) && (u_xd == XD_IM);
assign im_xdh  = !nowrite && (aop != OP_NOP) && (u_xd == XD_IMH);
assign im_sl   = IS010 && (u_fx == FX_MSLA) && !lay_f[1];
assign im_we   = !e0 ? 4'b0000 : im_xd ? dt_wres : {im_xdh || im_sl, im_xdh || im_sl, im_sl, im_sl};
assign im_d    = im_xd ? res : im_xdh ? {res[15:0], dt[15:0]} : dt;
// 68010 resume micro-address: at a fault (not the re-run itself; TAS: its final prefetch) or from the RTE frame
logic        ua_res_bf, ua_res_af, ua_res_li, ua_res_we;
logic [10:0] ua_res_d;
assign ua_res_bf = IS010 && e2 && berr_now && !bo_rr;
assign ua_res_af = IS010 && e2 && bact && ae && !bo_rr;
assign ua_res_li = f8_ld && (bo_fx == FX_LI1);
assign ua_res_we = ua_res_bf || ua_res_af || ua_res_li;
assign ua_res_d  = ua_res_li ? b_din[10:0] : (ua_res_bf && !ua_res_af && bo_op == BUS_TAS) ? U10_TASM_NPF : upc_next;
// next micro-address loaded at e2 (an address error / bus error overrides upc_next); ua_n / ua_ce: the same load as seen
// by the RES = 1 control store (reset and test load included), so its micro ROM read tracks ua_r exactly
logic [10:0] ua_e2;
assign ua_e2 = ae ? (g0 ? UA_HALTA : UA_EXC0A) : berr_now ? ((IS020 && bo_cps) ? U20_EXC_LF : g0 ? UA_HALT : UA_EXC0) : upc_next;
assign ua_ce = rst || tl || e2;
assign ua_n  = rst ? UA_RESET : tl ? UA_TLFIN : ua_e2;

always_ff @(posedge clk) begin
    if (rst) begin
        ua_r <= UA_RESET;
        uw <= '0;
        upc <= UA_RESET;
        sr <= {2'b00, 1'b1, 2'b00, 3'b111, 3'b000, sr[4:0]};    // reset: S = 1, T = 0, I = 7; the CCR is not reset
        vec <= 8'd0;
        g0 <= 1'b1; ae_q <= 1'b0; ae <= 1'b0;     // a fault before the first instruction halts
        bwait <= 1'b0; late <= 1'b0; mc2 <= 1'b0; iq_early <= 2'd0;
        in_exc <= 1'b1;
        rsto_r <= 1'b0; halt_r <= 1'b0; stop_r <= 1'b0;
        trace_pend <= 1'b0;
        vbr <= 32'd0; sfc <= 3'd0; dfc <= 3'd0; cx <= 16'd0; f8cap <= 1'b0; f8cap2 <= 1'b0;   // 68010: VBR = 0 at reset
        cacr <= 2'd0; c_clr <= 1'b1; c_ce <= 1'b0;                                           // 68020: cache off, cleared
        lm <= 1'b0; lm_db <= 1'b0; lm_cap <= 1'b0; ghost <= 1'b0; lm_keep <= 1'b0;
        int_lvl <= 3'd7; inl_ovr <= 1'b0; iack_late <= 1'b0;
        bact <= 1'b0;
        mask <= 16'd0; m_idx <= 4'd0; cnt <= 7'd0;
        b_fc <= 3'd0;
        c_sz <= 2'd1; c_aluop <= 6'd0; c_ca <= 3'd0; c_nofl <= 1'b0; c_cont <= 11'd0; c_body <= 11'd0;
        dv_done <= 1'b0; dv_ov <= 1'b0; dv_z <= 1'b0;
        aop <= OP_NOP; wau_r_q <= 1'b0; walu_go_q <= 1'b0; fin_q <= 1'b0; nowrite <= 1'b0; hold_ld <= 1'b0;
    end else if (tl) begin
`ifdef M68KSV_TESTLOAD
        sr    <= tl_sr & SR_MASK;
        fpc   <= tl_pc + 32'd4;
        pc68  <= tl_pc + 32'd2;       // as after a jump to tl_pc (the final prefetch loads PC with its address)
        ppc   <= tl_pc;
        irn   <= tl_ir;
        irc   <= tl_irc;
        ir    <= tl_ir;
        ua_r  <= UA_TLFIN;
        uw    <= uq;
        upc   <= UA_TLFIN;
        bact  <= 1'b0;
        g0    <= 1'b0;
        trace_pend <= 1'b0;
        dv_done <= 1'b0;
        lm <= 1'b0; lm_db <= 1'b0; lm_cap <= 1'b0; ghost <= 1'b0; lm_keep <= 1'b0;
        // TLFIN is a FIN word: its dispatch must happen whichever phase the test load ends in
        aop <= OP_NOP; wau_r_q <= 1'b0; walu_go_q <= 1'b0; fin_q <= 1'b1; irq_q <= 1'b0; nowrite <= 1'b0;
`endif
    end else begin
        if (IS020) begin c_clr <= 1'b0; c_ce <= 1'b0; end      // cache clear pulses (set by MOVEC to CACR below)

        // ---------------- e1: operands, bus address, next micro-address
        if (e1) begin
            dws_q    <= dws_d;
            dwx_q    <= dwx_d;
            dwh_q    <= dwh_d;
            dw_we_q  <= bact || (u_dw != DW_NONE);                      // no bus cycle: TAS write data
            dw_dup_q <= !bact || bo_byte || (bo_op == BUS_TAS);
            fin_q  <= fin_t;
            cond_q <= cond;
            irq_q  <= (u_ms == MS_STOPW) ? irq_pend : irq_npf;
            if (fin_t && u_ms == MS_STOPW && irq_pend) begin int_lvl <= ipl; inl_ovr <= 1'b0; end
            if (UM_SQ[SQ_CALL] && u_sq == SQ_CALL) uret <= upc + 11'd1;     // (68020 ROM only)
            if (bact) begin
                ba_q <= ba_e1;
                ae   <= ae_e1;
            end else
                ae   <= 1'b0;
            if (ISLM) lmc_q <= u_x1 == X1_LMC;
        end

        // ---------------- e2: operands (register-file data is valid now), bus address check, write data
        if (e2) begin
            // the interrupt decision is latched on the T3 (= e2) of the micro-word that starts the final prefetch
            // (the 68000's IRC -> IR word); a FIN later in the instruction uses that sample
            if (npf_now && iq_early != 2'd2) irq_npf <= irq_pend;
            // 68010 loop mode: ghost cycle (see lw_in above), held for the whole cycle (BIU and the read data at its end);
            // the lm / lm_db updates of this e2 are at the end of this block
            if (ISLM && bact) begin
                ghost   <= ghost_c;
                ghost_d <= lwd[2] ? 16'hfffc : lwd[1] ? lw1 : lw0;
            end
            // a faulting micro-instruction still completes; a bus error is known in the cycle's second micro-cycle
            // (68020: a bus error on a coprocessor-interface cycle is the F-line exception: no coprocessor)
            ua_r  <= ua_e2;
            pc68 <= pc68_e2;
            if (berr_now) begin
                aepc_f <= 1'b0; aeir_n <= 1'b0;
                // (FA: fa_we below)
                // stacked IR, its access-word bits and I/N (68000 inExcept01): when the cycle's second micro-word ends
                // the instruction (FIN), the next opcode has moved to IR / IRD and I/N says whether it traps (fx68k)
                finfo <= {fin_q ? irn[15:5] : ir[15:5], s_finfo[4], s_bn | (fin_q ? in_exc_nx : in_exc), s_finfo[2:0]};
                aeir  <= fin_q ? irn : ir;
                if (!IS010) vec <= 8'd2;
                if (IS010) begin
                    // 68010 format-8 state: resume point (unless this is the re-run itself), SSW, output buffer
                    if (!bo_rr) begin
                        // (resume address: ua_res_we below)
                        fin_f   <= fin_q && (bo_op != BUS_TAS);
                        bd_f    <= bo_bd;
                        lay_f   <= bo_ly;
                        trace_f <= trace_pend;
                        f8cap   <= 1'b1;
                        lm_f    <= {lm_db, lm};
                        lm_keep <= lm && !lm_cap;
                    end
                    lm <= 1'b0; lm_db <= 1'b0; lm_cap <= 1'b0;
                    ssw   <= {3'b000, bo_op == BUS_NPE || bo_op == BUS_NPF, bo_op == BUS_RD, bo_op == BUS_TAS,
                              bo_byte && !ba_q[0], bo_byte, bo_op != BUS_WR, 5'd0, fc_v};
                    dob   <= b_dout;
                    dib   <= 16'd0;
                    g0ae  <= 1'b0;
                end
            end
            aop   <= aop_d;
            xsz_q <= xsz;
            cc_irq <= cc_ir;
            alu_cin_q <= (u_fh == FH_HD) ? hold_x0 : sr[4];
            rsrc_q  <= (alu_rsel(aop_d) == 4'd3) ? 2'd3 : (xsel_d >= 4'd11) ? 2'd2 : (xsel_d != 4'd0) ? 2'd1 : 2'd0;
            xsel_q  <= xsel_d;
            fhlo_q <= (u_fh == FH_LO) && (xsz == 2'd2);
            fhcm_q <= u_fh == FH_CM;
            fhhd_q <= u_fh == FH_HD;
            fhl_q  <= xsz == 2'd2;
            {q_ni, q_zi} <= nzsel(aop_d, u_fh == FH_CM, xsz == 2'd2, ir[8]);
            ad_sub_q  <= (aop_d == OP_SUB) || (aop_d == OP_CMP) || (aop_d == OP_SUBX) || (aop_d == OP_NEG) ||
                         (aop_d == OP_NEGX) || (aop_d == OP_SUBA) || (aop_d == OP_CMPA);
            ad_usex_q <= (aop_d == OP_ADDX) || (aop_d == OP_SUBX) || (aop_d == OP_NEGX);
            ad_neg_q  <= (aop_d == OP_NEG) || (aop_d == OP_NEGX);
            // adder y operand sign extension and flag size (the ALU's former ad_addr / ad_cmpa decode, from xsz)
            ad_ysw_q  <= ((aop_d == OP_ADDA) || (aop_d == OP_SUBA) || (aop_d == OP_CMPA)) && (xsz == 2'd1);
            ad_ysb_q  <= IS010 && ((aop_d == OP_ADDA) || (aop_d == OP_SUBA) || (aop_d == OP_CMPA)) && (xsz == 2'd0);
            ad_fsz_q  <= (aop_d == OP_CMPA) ? 3'b100 : (xsz == 2'd0) ? 3'b001 : (xsz == 2'd1) ? 3'b010 : 3'b100;
            bcd_neg_q <= aop_d == OP_NBCD;
            rsel_q    <= alu_rsel(aop_d);
            rsub_q    <= (aop_d == OP_SBCD) || (aop_d == OP_NBCD) || (aop_d == OP_TAS);
            divr_q    <= aop_d == OP_DIVR;
            nowrite   <= nowrite_d || (ISLM && u_x1 == X1_LMC && cond_q);   // loop word leaving: Dn unchanged
            xa_q  <= xa_v;
            xb_q  <= xb_v;
            aua_q <= au_a;
            aub_q <= au_b;
            wau_p_q <= w_au_p;
            wau_r_q <= w_au_r && (IS010 || !ae || u_lk == 2'd2 || (late && u_lk == 2'd1 && c_sz != 2'd2));
            if (dw_we_q) begin b_dout_r <= dw_v; b_dup_r <= dw_dup_q; end   // byte duplication: b_dout below
            if (bact) begin
                // (FPC <- ba_q + 2 after an opcode fetch: fpc_we below)
                // the access information for a bus error found at the end of this cycle (its PC is pc68 then)
                s_finfo <= {(u_ai || bo_op == BUS_NPF) ? irn[15:5] : ir[15:5], bo_op != BUS_WR, u_bn | in_exc, fc_v};
                s_bn    <= u_bn;
                if (ae) begin
                    ae_q  <= 1'b1;
                    // the 68000's PC register as the faulting word leaves it; after a bus wait (field pl) the word
                    // after it has run its PC load during the wait (fx68k): fpc
                    aepc_f <= late && u_pl; aeir_n <= u_ai;
`ifdef M68KSV_TESTLOAD
                    tl_aeupc <= upc;
                    tl_aefpc <= fpc;
`endif
                    // (FA <- ba_q: fa_we below)
                    finfo <= {u_ai ? irn[15:5] : ir[15:5], bo_op != BUS_WR, u_bn | (u_ai ? in_exc_nx : in_exc), fc_v};
                    aeir  <= u_ai ? irn : ir;
                    if (!IS010) vec <= 8'd3;
                    if (IS020) ae_jmp <= ir[15:6] == 10'b0100111011;   // JMP (frame PC: M2_AEPC)
                    if (IS010) begin
                        if (!bo_rr) begin
                            // (resume address: ua_res_we below)
                            fin_f   <= 1'b0;
                            bd_f    <= bo_bd;
                            lay_f   <= bo_ly;
                            trace_f <= trace_pend;
                            f8cap   <= 1'b1;
                            // (lm_f / lm_keep: at the end, below)
                        end
                        lm <= 1'b0; lm_db <= 1'b0; lm_cap <= 1'b0;
                        ssw   <= {3'b000, bo_op == BUS_NPE || bo_op == BUS_NPF, bo_op == BUS_RD, bo_op == BUS_TAS,
                                  bo_byte && !ba_q[0], bo_byte, bo_op != BUS_WR, 5'd0, fc_v};
                        dob   <= b_dout;
                        dib   <= 16'd0;
                        g0ae  <= 1'b1;
                    end
                end
            end
        end

        // ---------------- e3: ALU / AU results, read data
        if (e3) begin
            if (u_aa != AA_ZERO || u_ab != AB_ZERO) aur <= au_sum;
            // 68010: AUR as the faulting word leaves it (format-8 frame)
            // AUR as the faulting word leaves it: taken from AUR in the next clock (aur changes only at e3; the generator
            // checks that the RTE word restoring AUR, fx MAUR, never ends a faulting bus cycle)
            if (IS010 && f8cap) begin f8cap2 <= 1'b1; f8cap <= 1'b0; end
            if (IS010 && u_fx == FX_MAUR) aur <= {8'd0, aur_f};
            if (aop != OP_NOP) res <= xres;
            // long op in two steps (68000 16-bit ALU): the low word's flags now, the long op's later (FH_CM)
            // flag terms and term indices (ccr_q, hold_xvc: see "flags" above)
            q_adc <= a_adc; q_adv <= a_adv; q_adc16 <= a_adc16; q_adv16 <= a_adv16; q_abc <= a_abc; q_abv <= a_abv;
            q_sbc <= a_sbc; q_sbv <= a_sbv; q_sho <= a_sho; q_shv <= a_shv;
            q_cin <= alu_cin_q;
            q_shfic <= (shtype[1:0] == 2'b10) & alu_cin_q;
            q_mlv <= !cx[10] & mul_lv;
            q_c2c <= c2_cq;
            q_c2v <= c2_vq;
            q_chkv <= chk_v20;
            q_chkc <= chk_c20;
            q_nf <= fsel16(q_ni, ft_n);
            q_zf <= (q_zi == 4'd3) ? a_bitz : fsel16(q_zi, ft_z);     // (the bit test enters last)
            q_xi <= fx_i; q_vi <= fv_i; q_ci <= fc_i;
            q_hx <= fhx_i; q_hv <= fhv_i; q_hc <= fhc_i;
            if (fhlo_q) begin
                nzm_q <= xnzm;
                nsz_q <= 2'd1;
                hold_nzm <= xnzm;
                hold_x0  <= sr[4];
            end else if (fhcm_q) begin
                nzm_q <= fhl_q ? hold_nzm : 2'd2;
                nsz_q <= 2'd2;
            end else begin
                nzm_q <= xnzm;
                nsz_q <= xnsz;
                if (fhhd_q) hold_nzm <= xnzm;
            end
            hold_ld <= fhlo_q || (!fhcm_q && fhhd_q);
            walu_p_q    <= w_alu_p;
            walu_go_q   <= w_alu_go && (IS010 || !ae_q);
            // field lh: a long result (or any An result) is merged into the low word only / the high word only (3)
            walu_full_q <= w_alu_full && (u_lh == 2'd0);
            walu_sz_q   <= (u_lh == 2'd2) ? 2'd3 : (u_lh == 2'd1 && (xsz == 2'd2 || w_alu_full)) ? 2'd1 : xsz;
            if (aop == OP_CHK) begin aux <= chk_t; auxn <= chk_dn; end
            if (IS020 && aop == OP_CHK2) aux2 <= c2_cq;
        end
        if (IS010 && f8cap2) begin aur_f <= aur[23:0]; f8cap2 <= 1'b0; end
        // the long op's X V C, one clock after its e3 (from the registered flag terms)
        if (hold_ld) begin hold_xvc <= {ft_x[q_hx], fsel16(q_hv, ft_v), fsel16(q_hc, ft_c)}; hold_ld <= 1'b0; end
        if (IS020 && b_dv && bo_xp) begin if (bo_bd == BD_HI) xt[31:16] <= b_din; else xt[15:0] <= b_din; end
        if (IS010 && b_dv && bo_fx == FX_LSR) f8sr <= b_din;           // RTE: SR kept for a format-8 return
        if (IS010 && b_dv && f8ld) begin
            case (bo_fx)
            FX_LSSW: ssw <= b_din;
            FX_LSSW20: if (IS020) ssw[15] <= !(b_din[8] || b_din[12] || b_din[13]);   // DF / RB / RC cleared: completed
            FX_LFAH, FX_LFAL: ;             // FA: fa_we below
            FX_LDOB: dob <= b_din;
            FX_LDIB: dib <= b_din;
            FX_LIIB: ;                     // IRC: irc_we / irc_d below
            FX_LI0:  {fin_f, stage_f, ver_f, lay_f, bd_f, trace_f, lm_f, hold_xvc} <= b_din;
            FX_LI1:  begin hold_nzm <= b_din[15:14]; hold_x0 <= b_din[13]; end      // resume address: ua_res_we
            FX_LIR, FX_LIRN, FX_LATH, FX_LATL: ;   // IR / IRN / AT: ir_we, irn_we, at_we below
            FX_LAURH: aur_f[23:16] <= b_din[7:0];
            FX_LAURL: aur_f[15:0] <= b_din;
            default: ;
            endcase
        end else if (b_dv && !(IS010 && b_berr && bo_op != BUS_IACK)) begin    // 68010: a faulted read changes nothing
            case (bo_op)
            BUS_NPE, BUS_NPF: ;            // IRC: irc_we / irc_d below
            // the whole word goes to IRC (68000 itlx5); a cycle ended by BERR (spurious) takes the bus one clock
            // later, as fx68k (the data bus is undefined there on a real system)
            BUS_IACK:         if (!bo_bkpt && b_berr) iack_late <= 1'b1;   // IRC: irc_we; DT bits 7-0: dt_we
            default: ;                              // read data -> DT: dt_we below
            endcase
        end

        if (e0w && iack_late) iack_late <= 1'b0;                        // IRC: irc_we / irc_d below
        // FC of a cycle that waits for the bus goes out at the e0 slot all the same
        if (e0w && !e0 && uq_bus != BUS_NONE) b_fc <= fc_nx;
        // a micro-instruction whose cycle had to wait for the bus (arbitration / HALT): with field lk its An write is
        // kept on an address error (fx68k: the cycle's second micro-word reaches T3 while the cycle waits)
        if (e0) begin late <= bwait; bwait <= 1'b0; mc2 <= bact; end
        else if (e0w) bwait <= 1'b1;
        // the sample word waits for the bus: fx68k runs its T1 (level latch) on the first held e0 slot and its T3
        // (decision) one slot later, whether or not the bus is free by then
        if (e0w && uq[F_IQ_LSB]) begin
            if (!e0 && iq_early == 2'd0) begin int_lvl <= ipl; inl_ovr <= 1'b0; iq_early <= 2'd1; end
            else if (iq_early == 2'd1) begin irq_npf <= irq_pend; iq_early <= 2'd2; end
        end
        if (e3 && u_iq) iq_early <= 2'd0;
        // RESET output: changes on the e0 slot even when the next micro-instruction waits for the bus (fx68k T1)
        if (e0w && u_ms == MS_RSTO1) rsto_r <= 1'b1;
        if (e0w && u_ms == MS_RSTO0) rsto_r <= 1'b0;

        // ---------------- e0: write back, start the next micro-instruction
        if (e0) begin
            uw  <= uq;
            upc <= ua_r;
            case (uq_pu)
            PU_T1FPC: pc68 <= fpc;
            PU_T1PCX: pc68 <= pcx;
            PU_T1AUR: pc68 <= aur;
            default: ;
            endcase
            bact <= (uq_bus != BUS_NONE);
            if (uq_bus != BUS_NONE) b_fc <= fc_nx;
            if (uq_bus != BUS_NONE) begin
                bo_bkpt <= IS010 && (uq_ba == BA_BKPT);   // no data taken
                bo_cps  <= IS020 && (uq_ba == BA_CPS);    // 68020 coprocessor interface cycle
                bo_fx   <= uq_fx;
                bo_ly   <= uq_ly;
                bo_rr   <= uq_rr;
                bo_op <= uq_bus;
                bo_byte <= bq_byte;
                bo_bd <= (uq_rr && uq_bus == BUS_RD) ? bd_f : uq[F_BD_LSB +: F_BD_W];   // 68010 re-run: saved destination
                bo_xp <= IS020 && (uq[F_M2_LSB +: F_M2_W] == M2_XP);
            end
            // (IRN <- IRC when the next word is the final prefetch: irn_we below)
            if (uq[F_IQ_LSB] && iq_early == 2'd0) begin int_lvl <= ipl; inl_ovr <= 1'b0; end  // the e0 starting the sample word
            // the 68000's level latch (fx68k inl) is also loaded after the IACK's IRC -> IR (itlx6); only the pending
            // logic sees that copy - the acknowledged level (IACK, vector, mask) stays in int_lvl
            if (uq[F_MS_LSB +: F_MS_W] == MS_VINT) begin inl_v <= ipl; inl_ovr <= 1'b1; end

            sr <= sr_n;
            ae_q <= 1'b0;
            case (u_ad)
            AD_AT, AD_ATPI, AD_FPC: ;       // AT / FPC <- AUR: at_we, fpc_we below
            AD_PCX: pcx <= aur;
            default: ;
            endcase
            // 68010 format 8: slot moves from DT, sequencer state from the decoded IR, misc
            if (IS010) begin
                case (u_fx)
                FX_MSLA: if (lay_f[1]) begin srt <= dt[31:16]; vec <= dt[7:0]; end      // else IM <- DT: im_we below
                FX_MSLB: if (lay_f[0]) begin mask <= dt[31:16]; m_idx <= m_ldt; cnt <= dt[6:0]; end else res <= dt;
                FX_RSTR: begin
                    c_cont  <= stage_f ? q_bodyx : q_cont;
                    c_body  <= q_bodyx;
                    c_sz    <= q_sz;
                    c_aluop <= q_aluop;
                    c_ca    <= q_ca;
                    c_nofl  <= q_nofl;
                end
                default: ;
                endcase
                case (u_x1)
                X1_VG0: vec <= g0ae ? 8'd3 : 8'd2;
                X1_SRF: begin
                    trace_pend <= trace_f;
                    // loop mode as at the fault (the loop words are not fetched again); the DBcc counter test is
                    // re-established by one normal (internal-fetch) DBcc. The loop registers are taken as they are
                    // when no loop was entered since the fault, else rebuilt from the frame (IR, IRC / IRN, PC) -
                    // not possible after a fault on the looped instruction's last word (IR already the DBcc): then
                    // the loop is fetched again
                    if (ISLM && lm_f[0] && (lm_keep || !fin_f)) begin
                        lm      <= 1'b1;
                        lm_db   <= lm_f[1];
                        lm_dyzv <= 1'b0;
                        if (!lm_keep) begin
                            lbase <= fpc[23:0] - (lm_f[1] ? 24'd6 : 24'd4);
                            lw0   <= ir;
                            lw1   <= lm_f[1] ? irn : irc;
                            lmd   <= lp_ir;
                        end
                    end
                end
                X1_LMCAND: lm_cand <= irc == 16'hfffc;
                X1_LMDZ: if (ISLM && lm_cand && res[15:0] != 16'hffff && lp_irn[2] && !sr[15]) begin
                    lm      <= 1'b1;
                    lm_db   <= 1'b0;
                    lm_cap  <= 1'b1;
                    lm_keep <= 1'b0;
                    lbase   <= at[23:0];
                    lw0     <= irn;
                    lw1     <= ir;
                    lmd     <= lp_irn[1:0];
                    lm_dyz  <= res[15:0] == 16'd0;
                    lm_dyzv <= !lm_wdy(irn, ir[2:0]);
                end
                X1_LMC: if (!cond_q) lm_dyz <= res[15:0] == 16'd0;
                X1_LMOFF: begin lm <= 1'b0; lm_db <= 1'b0; lm_cand <= 1'b0; end
                X1_SWDONE: begin                      // handler completed the cycle: its data from DIB / IIB
                    // (FPC <- FA + 2 when SSW.IF: fpc_we below)
                    // (DIB -> DT as the read would have loaded it, RM: DIB bits 7-0 -> DT bits 7-0: dt_we below)
                end
                default: ;
                endcase
            end
            // 68010 MOVEC to SFC / DFC / VBR (USP through the register file)
            if (IS010 && u_xe == XE_CTLW && !nowrite && aop != OP_NOP && !ctlw_usp) begin
                if (IS020 && cx[1]) begin                                                   // 68020 CAAR / CACR
                    if (cx[11]) caar <= res;
                    else begin cacr <= res[1:0]; c_clr <= res[3]; c_ce <= res[2]; end      // C / CE: one-clock pulses
                end
                else if (cx[11]) vbr <= res; else if (cx[0]) dfc <= res[2:0]; else sfc <= res[2:0];
            end
            if (!nowrite && aop != OP_NOP) begin
                case (u_xd)
                XD_DT:  ;                   // DT <- RES (merged by size): dt_we below
                XD_AT:  ;                   // AT <- RES (unless the AU writes it): at_we below
                XD_IM, XD_IMH: ;            // IM <- RES (merged by size) / RES low word -> IM high word: im_we below
                XD_PCX: if (u_ad != AD_PCX) pcx <= res;
                default: ;
                endcase
            end

            // misc
            case (u_ms)
            MS_LDMASK:  begin mask <= irc; m_idx <= m_ld; end
            MS_MNEXT:   begin mask <= m_rest; m_idx <= m_nx; end
            MS_LDCNTSH: cnt <= ir[5] ? {1'b0, xa_q[5:0]} : {3'd0, ir[11:9] == 3'd0, ir[11:9]};
            MS_CNTDEC:  cnt <= cnt - 7'd1;
            MS_LDCNTRST: cnt <= 7'd60;
            MS_LDCNTMUL: cnt <= IS020 ? cnt_mul_r : cnt_mul_c;
            MS_LDAEPC:   if (UM_MS[MS_LDAEPC]) pcx <= aepc_f ? fpc : pc68;     // 68000 family only (68010 / 68020: pc68 folds away)
            MS_IRCIR:    ;                          // interrupt: IR <- IRC after the IACK (68000 itlx6): ir_we below
            // idle micro-cycles after the 16 steps (DIV routine): DIVU 14 + ext, DIVS 37 + zeros + sign term
            MS_LDCNTDIV: cnt <= IS020 ? cnt_div_r : cnt_div_c;
            MS_EXCENT:  srt <= sr;
            MS_RSTO1, MS_RSTO0: ;                  // on the e0 slot (below)
            MS_VILL:    vec <= 8'd4;
            MS_VPRIV:   vec <= 8'd8;
            MS_VLA:     vec <= 8'd10;
            MS_VLF:     vec <= 8'd11;
            MS_VTRAP:   vec <= {4'd2, ir[3:0]};
            MS_VCHK:    vec <= 8'd6;
            MS_VTRAPV:  vec <= 8'd7;
            MS_VDIV0:   vec <= 8'd5;
            MS_VTRACE:  vec <= 8'd9;
            MS_VFMT:    if (IS010) vec <= 8'd14;
            MS_VCPV:    if (IS020) vec <= 8'd13;
            MS_LDCX:    if (IS010) cx <= irc;
            MS_VRST1:   vec <= 8'd1;
            MS_VINT:    vec <= b_iack_av ? {5'd3, ilvl} : b_iack_sp ? 8'd24 : dt[7:0];
            MS_DTSHL8:  ;                           // DT << 8: dt_we below
            MS_HALT:    halt_r <= 1'b1;
            MS_SETIPL:  ;
            MS_DINIT: begin
                dv_z  <= xa_q[15:0] == 16'd0;
                dv_ov <= dv_ud[31:16] >= dv_ur;
                dv_r  <= dv_ud[31:16];
                dv_q  <= dv_ud[15:0];
                dv_d  <= dv_ur;
                dv_sq <= ir[8] & (xb_q[31] ^ xa_q[15]);
                dv_sr <= ir[8] & xb_q[31];
                dv_s_r <= ir[8];
                dv_dsn <= ir[8] & xa_q[15];
                dv_ext <= 5'd0;
                dv_done <= 1'b0;
                cnt <= 7'd16;
            end
            MS_DSTEP: begin
                if (dv_t >= {1'b0, dv_d}) begin
                    dv_r <= dv_tsub[15:0];
                    dv_q <= {dv_q[14:0], 1'b1};
                end else begin
                    dv_r <= dv_t[15:0];
                    dv_q <= {dv_q[14:0], 1'b0};
                end
                cnt <= cnt - 7'd1;
                if (cnt == 7'd1) dv_done <= 1'b1;
                if (cnt != 7'd1 && !dv_r[15]) dv_ext <= dv_ext + ((dv_t >= {1'b0, dv_d}) ? 5'd1 : 5'd2);
            end
            default: ;
            endcase
            stop_r <= (u_ms == MS_STOPW);
            // 68020 misc (field m2)
            if (IS020) case (u_m2)
            M2_FLOW: if (sr[14]) trace_pend <= 1'b1;            // T0: a taken Bcc / DBcc
            // address-error frame of a JMP to an odd address (2026-11-16): stacked PC = the JMP's address + 2, as WinUAE's
            // 68020 JMP handlers leave it (gencpu.cpp i_JMP: m68k_incpci(2) before exception3_read_prefetch_only)
            M2_AEPC: if (g0ae && ae_jmp) pcx <= ppc + 32'd2;
            M2_LDXW: xw <= irc;
            M2_LDCX2: cx2 <= irc;                               // CAS2: second extension word
            M2_SWCX: begin cx <= cx2; cx2 <= cx; end
            // RTE: longs after the first 8 bytes of the frame (format 2: 1, 9: 3, A: 6, B: 21)
            M2_LDCNTF: cnt <= (dt[15:12] == 4'h2) ? 7'd1 : (dt[15:12] == 4'h9) ? 7'd3 : (dt[15:12] == 4'ha) ? 7'd6 :
                              (dt[15:12] == 4'hb) ? 7'd21 : 7'd0;
            M2_DVLINIT: begin                                   // divisor (xa) and Dq (xb)
                dl_d  <= (cx[11] && xa_q[31]) ? -xa_q : xa_q;
                dl_z  <= xa_q == 32'd0;
                dl_q  <= xb_q;
                dl_sq <= cx[11] && xa_q[31];                    // (divisor sign; the quotient sign follows in DVLHI)
            end
            M2_DVLHI: begin                                     // dividend high (Dr in xb, or Dq's extension)
                dl_r  <= dl_md[63:32];
                dl_q  <= dl_md[31:0];
                dl_sq <= dl_sq ^ (cx[11] && dl_nd[63]);
                dl_sr <= cx[11] && dl_nd[63];
                dl_ov <= dl_md[63:32] >= dl_d;
                cnt   <= 7'd32;
                dlo_s641 <= cx[11] && cx[10];
                dlo_qz1  <= dl_q == 32'd0;
                dlo_q311 <= dl_q[31];
                dlo_rz1  <= xb_q == 32'd0;
                dlo_r311 <= xb_q[31];
                dlo_hc1  <= dl_sq && xb_q[31];
                dlo_ss1  <= dlo_sum[32];
                dlo_so6  <= {|dlo_sum[31:27], |dlo_sum[26:22], |dlo_sum[21:16], |dlo_sum[15:11], |dlo_sum[10:5], |dlo_sum[4:0]};
            end
            M2_BFINIT: begin                                    // offset (xa: Dn) and width (xb: Dn), byte address
                bf_off <= cx[11] ? xa_q : {27'd0, cx[10:6]};
                bf_w   <= (cx[5] ? (xb_q[4:0] == 5'd0) : (cx[4:0] == 5'd0)) ? 6'd32 : {1'b0, cx[5] ? xb_q[4:0] : cx[4:0]};
                bf_ea  <= at + (cx[11] ? {{3{xa_q[31]}}, xa_q[31:3]} : {30'd0, cx[10:9]});
            end
            M2_DVLSTEP: begin
                if (!dl_ts[32]) begin dl_r <= dl_ts[31:0]; dl_q <= {dl_q[30:0], 1'b1}; end
                else begin dl_r <= dl_t[31:0]; dl_q <= {dl_q[30:0], 1'b0}; end
                cnt <= cnt - 7'd1;
            end
            default: ;
            endcase
            // 68020: address of the instruction being dispatched (format-2 frames; not at an exception dispatch, so a
            // trace frame gets the traced instruction's address)
            if (IS020 && fin_q && !in_exc_nx) ppc <= fpc - 32'd4;

            // sequencing state
            if (u_sq == SQ_CONT) c_cont <= c_body;
            if (fin_q) begin
                // (IR <- IRN: ir_we below)
                c_cont  <= q_cont;
                c_body  <= q_bodyx;
                c_sz    <= q_sz;
                c_aluop <= q_aluop;
                c_ca    <= q_ca;
                c_nofl  <= q_nofl;
                if (ISLM) begin
                    lm_db <= 1'b0;
                    // the dispatch after the entry check: keep the looped instruction's decode
                    if (lm_cap) begin
                        lm_cap  <= 1'b0;
                        lq_first <= q_first; lq_exc <= q_exc; lq_cont <= q_cont; lq_bodyx <= q_bodyx; lq_sz <= q_sz;
                        lq_aluop <= q_aluop; lq_ca <= q_ca; lq_nofl <= q_nofl;
                    end
                    // loop word: the looped instruction with the state its normal fetch would leave (IR / IRN = it,
                    // IRC = the DBcc opcode, fetch address = the displacement word)
                    if (lmc_q) begin
                        // (IR / IRN <- lw0, IRC <- lw1, FPC <- the displacement word: ir_we, irn_we, irc_we, fpc_we below)
                        c_cont <= lq_cont; c_body <= lq_bodyx; c_sz <= lq_sz; c_aluop <= lq_aluop; c_ca <= lq_ca;
                        c_nofl <= lq_nofl;
                    end
                    if (in_exc_nx) begin lm <= 1'b0; lm_cap <= 1'b0; end      // interrupt / trace / illegal: leave
                end
                g0      <= 1'b0;
                trace_pend <= sr_n[15] || (IS020 && sr_n[14] && q_flow && !in_exc_nx);   // T1; 68020 T0 (flow)
                // access word I/N (68000 inExcept01): set when this instruction boundary dispatches to a group 1 /
                // illegal / privilege exception, cleared by a normal dispatch
                in_exc  <= in_exc_nx;
            end
            // group-0 state ends in the refill after the vector fetch, after the first prefetch (fx68k: its group-0
            // latch clears there), so a fault on the final refill prefetch is a bus / address error, not a double fault
            if (ua_r == UA_VECJMP_G0) g0 <= 1'b0;
            if (IS010 && u_fx == FX_G0ON) g0 <= 1'b1;        // RTE format 8 after the accessibility read
            if (IS010 && u_fx == FX_G0OFF) g0 <= 1'b0;
            if (upc == UA_EXC0 || ua_r == UA_EXC0 || ua_r == UA_EXC0A) g0 <= 1'b1;
            // group 0 / 1 exceptions cancel a pending trace (the instruction did not complete); TRAP / TRAPV / CHK /
            // zero divide keep it: the trace is taken after their exception processing
            if (u_ms == MS_VILL || u_ms == MS_VPRIV || u_ms == MS_VLA || u_ms == MS_VLF || u_ms == MS_VTRACE ||
                upc == UA_EXC0 || upc == UA_INT) trace_pend <= 1'b0;
        end

        // 68010 loop mode, e2 of the cycle's first micro-cycle (written last, nearest the registers: e2 excludes the
        // other phases, and a bus / address error in the same e2 - above - has priority)
        if (ISLM && e2 && bact && !ae && !berr_now) begin
            if (ghost_c && lwd[2]) lm_db <= 1'b1;            // the displacement word: FIN goes to the loop word
            if (lm_rf) begin lm <= 1'b0; lm_db <= 1'b0; end  // any real opcode fetch ends loop mode
        end
        // address error (e2): loop-mode state as this cycle's update leaves it, into the frame state
        if (ISLM && e2 && bact && ae && !bo_rr) begin lm_f <= {lm_db_post, lm_post}; lm_keep <= lm_post && !lm_cap; end
        if (irc_we) irc <= irc_d;
        if (irn_we) irn <= irn_d;
        if (im_we[3]) im[31:24] <= im_d[31:24];
        if (im_we[2]) im[23:16] <= im_d[23:16];
        if (im_we[1]) im[15:8]  <= im_d[15:8];
        if (im_we[0]) im[7:0]   <= im_d[7:0];
        if (ua_res_we) ua_res <= ua_res_d;
        if (dt_we[3]) dt[31:24] <= dt_d[31:24];
        if (dt_we[2]) dt[23:16] <= dt_d[23:16];
        if (dt_we[1]) dt[15:8]  <= dt_d[15:8];
        if (dt_we[0]) dt[7:0]   <= dt_d[7:0];
        if (ir_we)  ir  <= ir_d;
        if (fpc_we) fpc <= fpc_d;
        if (at_we[1]) at[31:16] <= at_d[31:16];
        if (at_we[0]) at[15:0]  <= at_d[15:0];
        if (fa_we[1]) fa[31:16] <= fa_d[31:16];
        if (fa_we[0]) fa[15:0]  <= fa_d[15:0];
    end
end

`ifdef M68KSV_SIMCHECK
// simulation check: the decode chain needs five clocks after IRN changes; the FIN micro-instruction's e2 must not come
// earlier (stops the simulation if the microcode / phase scheduling ever breaks that)
logic [3:0]  irn_age;
logic [15:0] irn_prev;
always_ff @(posedge clk) begin
    irn_prev <= irn;
    if (irn != irn_prev) irn_age <= 4'd1;
    else if (irn_age != 4'd15) irn_age <= irn_age + 4'd1;
    if (e2 && fin_q && !tl && !rst && irn_age < 4'd5) begin
        $display("m68ksv SIMCHECK: dispatch %0d clocks after IRN changed (upc %0d)", irn_age, upc);
        $stop;
    end
    // the second micro-word of a bus cycle never starts one (ba_q holds the cycle's address for a bus error: fa_d)
    if (e0 && !tl && !rst && bact && uq_bus != BUS_NONE) begin
        $display("m68ksv SIMCHECK: bus cycle started in the second micro-word of one (upc %0d)", upc);
        $stop;
    end
end
`endif

assign b_addr  = ba_q;
assign b_dout  = {b_dup_r ? b_dout_r[7:0] : b_dout_r[15:8], b_dout_r[7:0]};   // a byte on both halves
assign b_abort = ae;
assign b_ghost    = ghost;
assign b_ghost_s2 = ghost_c;
assign bq_go   = e0 && !tl && (uq_bus != BUS_NONE);
assign bq_want = !tl && (uq_bus != BUS_NONE);
assign bq_op   = uq_bus;
assign bq_byte = (((uq_bus == BUS_RD) || (uq_bus == BUS_WR) || (uq_bus == BUS_TAS)) &&
                 ((uq_bs == BS_BYTE) || (IS010 && uq_bs == BS_SSW && ssw[9]) ||
                  ((uq_bs == BS_OPSZ) && ((fin_q ? ((ISLM && lmc_q) ? lq_sz : q_sz) : c_sz) == 2'd0))));
assign bq_lw   = IS020 && (uq_bus == BUS_RD) && (uq[F_BD_LSB +: F_BD_W] == BD_HI) && !uq_rr;
// CAS / CAS2 lock: set at the e0 of the first operand read (m2 RMCON), cleared at the e0 of the final prefetch (RMCOFF),
// at a group-0 fault and at reset
logic rmc_lk;
always_ff @(posedge clk) begin
    if (rst || !IS020) rmc_lk <= 1'b0;
    else if (e0 && uq[F_M2_LSB +: F_M2_W] == M2_RMCON) rmc_lk <= 1'b1;
    else if ((e0 && uq[F_M2_LSB +: F_M2_W] == M2_RMCOFF) || (e2 && (ae || berr_now))) rmc_lk <= 1'b0;
end
assign bq_lock = rmc_lk;
assign bq_rmc  = IS020 && (rmc_lk || (uq[F_M2_LSB +: F_M2_W] == M2_RMCON)) && !(uq[F_M2_LSB +: F_M2_W] == M2_RMCOFF);
assign rsto    = rsto_r;
assign halted  = halt_r;
assign stopped = stop_r;

assign dbg_fin = e0 && fin_q && !tl && (upc != UA_TLFIN);
assign dbg_vbr = IS010 ? vbr : 32'd0;
assign cc_cacr  = IS020 ? cacr : 2'd0;
assign cc_clr   = IS020 && c_clr;
assign cc_ce    = IS020 && c_ce;
assign cc_idx   = IS020 ? caar[7:2] : 6'd0;
assign dbg_cacr = IS020 ? cacr : 2'd0;
assign dbg_caar = IS020 ? caar : 32'd0;
assign dbg_sfc = IS010 ? sfc : 3'd0;
assign dbg_dfc = IS010 ? dfc : 3'd0;
assign dbg_pc  = fpc - 32'd4;
assign dbg_upc = upc;
assign dbg_sr  = sr;
assign dbg_ir  = ir;
assign dbg_irc = irc;

endmodule
