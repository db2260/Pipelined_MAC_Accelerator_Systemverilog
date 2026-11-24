# 500 MHz starting point (2.0 ns). Tighten until WNS < 0 to find Fmax.
set CLK_PERIOD 2.0
create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty 0.10 [get_clocks clk]
set_clock_transition  0.05 [get_clocks clk]

set_input_delay  [expr 0.30*$CLK_PERIOD] -clock clk [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay [expr 0.30*$CLK_PERIOD] -clock clk [all_outputs]
set_false_path -from [get_ports rst_n]          ;# async reset, synchronized upstream
set_load 0.02 [all_outputs]
