# Existing verified image1 clock-domain constraints; restored after interface generation.
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

# Additional engineering margin after image1 hardware corruption report.
set_clock_uncertainty -setup -from [get_clocks {csi_rxc_i}] -to [get_clocks {csi_rxc_i}] 0.800
set_clock_uncertainty -hold -from [get_clocks {csi_rxc_i}] -to [get_clocks {csi_rxc_i}] 0.600
set_clock_uncertainty -setup -from [get_clocks {clk_pixel_2x}] -to [get_clocks {clk_pixel_2x}] 0.250
