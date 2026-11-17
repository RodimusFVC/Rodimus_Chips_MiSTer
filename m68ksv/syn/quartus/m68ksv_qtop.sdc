# m68ksv timing test: one core clock, 96 MHz = 10.417 ns.
# The CPU runs on clock enables (cen_p / cen_n) generated inside the design, so every path is a single-cycle path.
create_clock -name clk -period 10.417 [get_ports clk]
derive_clock_uncertainty
set_false_path -from [get_ports {reset_pin dtack_pin ipl_pin[*] vpa_pin berr_pin}]
set_false_path -to [get_ports {bus_sig[*] fc_out[*] halt_out}]
