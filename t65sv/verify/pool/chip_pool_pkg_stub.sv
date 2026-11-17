// Stand-in for the fleet's chip_pool_pkg (only the two T65 types), for compile/lint checks.
package chip_pool_pkg;
  typedef struct packed { logic res_n; logic enable; logic rdy; logic irq_n; logic nmi_n; logic [7:0] di; } t65_i_t;
  typedef struct packed { logic [15:0] a; logic [7:0] dout; logic rw; } t65_o_t;
endpackage
