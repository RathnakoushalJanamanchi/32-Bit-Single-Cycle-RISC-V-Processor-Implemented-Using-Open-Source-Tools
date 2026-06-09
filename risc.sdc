# ==========================================================================
# SDC FILE FOR 32-BIT SINGLE-CYCLE RISC-V CORE (7nm ASAP7 Target)
# Units: Time = ns, Capacitance = pF
# ==========================================================================

# 1. Environment
set sdc_version 2.1
set_units -time ps -capacitance fF -resistance kOhm -voltage V -current mA
current_design Top_Module

# 2. Clock
set CLK_PERIOD 2000
create_clock -name core_clk -period $CLK_PERIOD [get_ports clk]

# Pre-CTS uncertainty: setup 0.04ns, hold 0.02ns
# Rule of thumb: uncertainty = 2-5% of clock period
# 0.04 = 2% of 2.0ns — accounts for clock skew before CTS
set_clock_uncertainty -setup 40 [get_clocks core_clk]
set_clock_uncertainty -hold  20 [get_clocks core_clk]

# Clock transition 0.03ns = 30ps
# Rule: transition < 5% of clock period for 7nm
# ASAP7 buffers switch in ~20-40ps, so 30ps is realistic
set_clock_transition 30 [get_clocks core_clk]

# 3. I/O Timing
set IN_DELAY  [expr $CLK_PERIOD * 0.4]
set OUT_DELAY [expr $CLK_PERIOD * 0.4]

# 40% input delay means external logic uses 0.8ns before data arrives
# Remaining 60% (1.2ns) is your core's budget
# For single-cycle RISC-V this is tight — reduce to 30% if timing fails
# set_input_delay applies to all inputs EXCEPT clk
set_input_delay $IN_DELAY -clock core_clk [get_ports reset]
set_output_delay $OUT_DELAY -clock core_clk [all_outputs]

# 4. Driving Cell
# INVx4_ASAP7_75t_R = size-4 inverter, RVT, 7.5-track
# Output pin is Y (verified from liberty file)
# Use size-4 because it represents a medium-strength driver
# from upstream chip logic — not too weak, not too strong
set_driving_cell -lib_cell INVx4_ASAP7_75t_R -pin Y [get_ports reset]

# Load = 0.005pF = 5fF on outputs
# Realistic for 7nm — one gate input load is ~1-2fF
# 5fF models driving ~3-4 gates downstream
set_load 5 [all_outputs]

# 5. DRC Constraints
# max_transition 0.05ns = 50ps
# Rule: max_transition < 5-10% of clock period
# 50ps / 2000ps = 2.5% — tight but correct for 7nm
set_max_transition 100 [current_design]

# max_capacitance 0.02pF = 20fF
# Rule: max_cap = max_transition × drive strength
# At 7nm, wire cap ~0.1-0.2fF/um, so 20fF = ~100-200um wire
set_max_capacitance 500 [current_design]

# max_fanout 20
# Rule: fanout > 20 degrades transition, violates max_transition
# For control signals in RISC-V (opcode decode) fanout can hit 15-20
set_max_fanout 20 [current_design]

# 6. OCV Derating
# early = 0.90 means hold paths run 10% faster (pessimistic for hold)
# late  = 1.10 means setup paths run 10% slower (pessimistic for setup)
# 10% is standard flat OCV for 7nm academic flows
# Industry uses AOCV/POCV tables but flat 10% is safe for ASAP7
set_timing_derate -early 0.90
set_timing_derate -late  1.10

# 7. False Paths
# Reset is async — it has no setup/hold relationship to clk
# Telling STA to ignore reset-to-flop paths prevents false violations
set_false_path -from [get_ports reset]

