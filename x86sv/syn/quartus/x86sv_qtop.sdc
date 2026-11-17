# x86sv timing test: one core clock. 80 MHz = 12.500 ns; for 96 MHz use -period 10.417.
# The CPU runs on a clock enable (ce = clk / 4) generated inside the design, so every path is a single-cycle path.
create_clock -name clk -period 12.500 [get_ports clk]
derive_clock_uncertainty
set_false_path -from [get_ports {reset_pin ready_pin intr_pin nmi_pin test_n_pin}]
set_false_path -to [get_ports {port_out[*] bus_sig[*] lock_out qs_out[*]}]
