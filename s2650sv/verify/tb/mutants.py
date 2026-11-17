#!/usr/bin/env python3
"""Write mutants of rtl/s2650sv.sv to mut/ (exact substring replacements)."""
import os, sys
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../rtl/s2650sv.sv')).read()
M = {
    'm1_com_signed_fixed': ("(alu_a[7] & alu_b[7] & ~vt[7])))", "(alu_a[7] & alu_b[7] & vt[7])))"),
    'm2_rel_off_by_one':   ("assign rel_v  = iar_p1 + ", "assign rel_v  = iar + "),
    'm3_ene_bit':          ("assign ene  = ri[2];", "assign ene  = ri[3];"),
    'm4_str_r0_quirk_fixed': ("                            if (ru != 2'b00)\n                                dw_c = r0;",
                              "                            if (ru != 2'b00)\n                                dw_c = (ru != 2'b11 && ri[1:0] == 2'b00) ? inc_v : r0;"),
    'm5_intack_early':     ("        intack  <= st[S_INT];", "        intack  <= st_c[S_INT];"),
    'm6_dar_idc':          ("dar_r = psl[5] ? dar_t", "dar_r = ~psl[5] ? dar_t"),
    'm7_ras_read_sp':      ("assign ras_ra = psu_sp - 3'd1;", "assign ras_ra = psu_sp;"),
    'm8_mio_on_wait':      ("        mio_c     = 1'b1;", "        mio_c     = go | ~st[S_IO];"),
    'm9_halt_ret_plus1':   ("                    if (irq & ~psu_ii) begin\n                        st_c = '0; st_c[S_INT] = 1'b1;\n                    end\n                    req_c = 1'b0;",
                            "                    if (irq & ~psu_ii) begin\n                        st_c = '0; st_c[S_INT] = 1'b1;\n                        ias = sel9(I_M1);\n                    end\n                    req_c = 1'b0;"),
    'm10_idc_true_carry':  ("alu_p[5] = vt[3:0] < alu_a[3:0];", "alu_p[5] = (alu_a[3:0] + alu_b[3:0] + psl[0] & psl[3]) > 5'd15;"),
}
os.makedirs('mut', exist_ok=True)
for k, (a, b) in M.items():
    assert src.count(a) == 1, k
    open('mut/%s.sv' % k, 'w').write(src.replace(a, b))
print(' '.join(M))
