# Camera clock is a user constraint, not generated from the MIPI data lane.
create_clock -period 6 -name csi_rxc_i [get_ports {csi_rxc_i}]
# Experimental image7-only MIPI guard, not a measured board jitter value.
# Preserve frequency, DPHY taps and RTL; ask P&R for additional source-
# synchronous setup/hold margin after image7 rejected all camera frames.
set_clock_uncertainty -setup -from [get_clocks {csi_rxc_i}] -to [get_clocks {csi_rxc_i}] 0.500
set_clock_uncertainty -hold -from [get_clocks {csi_rxc_i}] -to [get_clocks {csi_rxc_i}] 0.300
# Current-design clock-domain constraints retained from the verified baseline.
set_max_delay -from [get_clocks {core_clk}] -to [get_clocks {clk_sys}] 5
set_false_path -from [get_clocks {tac_clk}] -to [get_clocks {clk_sys}]
set_false_path -from [get_clocks {twd_clk}] -to [get_clocks {clk_sys}]
set_max_delay -from [get_clocks {clk_sys}] -to [get_clocks {core_clk}] 5
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {tac_clk}]
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {twd_clk}]
set_false_path -from [get_clocks {twd_clk}] -to [get_clocks {core_clk}]
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {csi_rxc_i}]
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {clk_pixel}]
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {clk_pixel_2x}]
set_false_path -from [get_clocks {clk_pixel}] -to [get_clocks {clk_sys}]
set_false_path -from [get_clocks {clk_pixel_2x}] -to [get_clocks {clk_sys}]
set_false_path -from [get_clocks {csi_rxc_i}] -to [get_clocks {clk_sys}]
