#!/usr/bin/env python3
"""Mutation controls: single-bug copies of rtl/pit8253.sv (written under OUT, never in the repo) must all be caught
by the lockstep bench. usage: python3 -B -I run_mutants.py   (OUT overridable by env PIT_OUT)"""
import os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.path.join(HERE, "..", "rtl", "pit8253.sv")
TB = os.path.join(HERE, "tb_pit8253.cpp")
OUT = os.environ.get("PIT_OUT", "/Work/Projects/verilator_local_files/Rodimus_Chips_MiSTer/pit8253") + "/mutants"

# (name, 8254?, old, new) — each `old` must occur exactly once
M = [
 ("bcd_units_borrow_le",   0, "bu = (v[3:0] < {2'b00, n});", "bu = (v[3:0] <= {2'b00, n});"),
 ("bcd_thousands_wrap",    0, "x  = {1'b0, v[15:12]} + 5'd9;", "x  = {1'b0, v[15:12]} + 5'd8;"),
 ("bcd_hundreds_wrap",     0, "hn = bt ? ((v[11:8] == 4'd0) ? 4'd9 :", "hn = bt ? ((v[11:8] == 4'd0) ? 4'd8 :"),
 ("flush_ignores_gate",    0, "n_pin = (n_ctrl[2] && !n_gate_in) ? 1'b1 : n_outp;", "n_pin = n_outp;"),
 ("gate_rise_modes",       0, "if (gate[i] && (ctrl[2] || ctrl[1])) n_rose", "if (gate[i] && ctrl[2]) n_rose"),
 ("count1_mode2",          0, "if (mode_of(n_ctrl[3:1]) == 3'd2) ldn = 16'd2;", "if (mode_of(n_ctrl[3:1]) == 3'd2) ldn = 16'd3;"),
 ("mode3_mask_read",       0, "wire [15:0] mv = (ctrl[2] && ctrl[1]) ? {val[15:1], 1'b0} : val;", "wire [15:0] mv = val;"),
 ("mode3_mask_latch",      0, "rbv = (n_ctrl[2] && n_ctrl[1]) ? {n_val[15:1], 1'b0} : n_val;", "rbv = n_val;"),
 ("midwrite_read_xor",     0, "wmsb ? ~lowcnt :", "wmsb ? lowcnt :"),
 ("mode4_zero_count",      0, "(n_val == 16'd0 || e && n_val == 16'd1)", "(e && n_val == 16'd1)"),
 ("mode2_reload_at_2",     0, "if (e && n_ph == 2'd3 && n_val == 16'd1) begin", "if (e && n_ph == 2'd3 && n_val == 16'd2) begin"),
 ("m3_high_phase_val1",    0, "if (n_ph == 2'd2 && e && (n_val == 16'd1 || n_val == 16'd2)) begin", "if (n_ph == 2'd2 && e && (n_val == 16'd2)) begin"),
 ("latch_rmsb_guard",      0, "if (rb_ct && !n_rmsb && n_lat_cnt == 2'd0)", "if (rb_ct && n_lat_cnt == 2'd0)"),
 ("reset_pin_low",         0, "outp <= 1'b1; pin <= 1'b1;", "outp <= 1'b1; pin <= 1'b0;"),
 ("mode0_msb_keeps_count", 0, "                        n_ph = 2'd0;\n                        `PIT_SETOUT(1'b0)", "                        `PIT_SETOUT(1'b0)"),
 ("status_bits_swapped",   1, "n_status = {n_outp, n_null, n_ctrl};", "n_status = {n_null, n_outp, n_ctrl};"),
 ("status_not_cleared",    1, "if (n_lat_stat)                 n_lat_stat = 1'b0;", "if (n_lat_stat)                 n_lat_stat = 1'b1;"),
 ("readback_one_counter",  1, "wire rbc     = (PIT8254 != 0) && bus_ctl && (d_e[7:6] == 2'b11) && d_e[RBB];", "wire rbc     = (PIT8254 != 0) && bus_ctl && (d_e[7:6] == 2'b11) && d_e[1];"),
 ("mode_alias_67",         0, "mode_of = c[2] ? {1'b0, c[2:1]} : c[3:1];", "mode_of = c[3:1];"),
 ("mode1_no_load_out_low", 0, "`PIT_LOAD `PIT_SETOUT(1'b0) end\n                if (n_ph == 2'd2 && e && n_val == 16'd1) begin n_ph = 2'd3;", "`PIT_LOAD end\n                if (n_ph == 2'd2 && e && n_val == 16'd1) begin n_ph = 2'd3;"),
 ("ds1_no_write_hold",     0, "wire        hold  = bw && (clk_ce[i] || pw);", "wire        hold  = 1'b0;"),
 ("ds2_gate_ignores_cnt",  0, "if ((n_ctrl[2] && n_cnt_wr) || (!n_ctrl[2] && n_ctrl[1])) n_ph = 2'd1;", "if (n_ctrl[2] || n_ctrl[1]) n_ph = 2'd1;"),
]

def build_run(m):
    name, is8254, old, new = m
    src = open(RTL).read()
    if src.count(old) != 1:
        return name, "BAD-MUTANT (pattern count %d)" % src.count(old)
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    f = os.path.join(d, "pit8253.sv")
    open(f, "w").write(src.replace(old, new))
    cmd = ["verilator", "--cc", "--exe", "--build", "-j", "1", "-O1", "-Wno-fatal", "-public-flat-rw", "--top-module", "pit8253",
           "-GPIT8254=%d" % is8254, "-CFLAGS", "-std=c++17 -O1 -I%s -DPIT8254=%d" % (HERE, is8254), "-Mdir", d + "/obj", f, TB]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        return name, "BUILD-FAIL " + r.stderr[-300:]
    r = subprocess.run([d + "/obj/Vpit8253", "all", "--seeds", "1", "--cycles", "2000000"], capture_output=True, text=True)
    first = next((l for l in r.stdout.splitlines() if l.startswith("DIVERGENCE")), "")
    return name, ("CAUGHT  " + first[:110]) if r.returncode else "SURVIVED"

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    with ThreadPoolExecutor(4) as ex:
        res = list(ex.map(build_run, M))
    bad = 0
    for n, s in res:
        print("%-24s %s" % (n, s))
        bad += not s.startswith("CAUGHT")
    print("%d mutants, %d caught, %d not caught" % (len(M), len(M) - bad, bad))
    sys.exit(1 if bad else 0)
