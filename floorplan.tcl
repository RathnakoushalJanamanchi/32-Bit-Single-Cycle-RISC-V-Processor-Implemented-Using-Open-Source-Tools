# =====================================================
# RISC-V Physical Design Flow — ASAP7 4x
# =====================================================

# Step 1: Load LEF files
read_lef /home/ubuntu/riscv_pd/lef/asap7_tech_4x_201209.lef
read_lef /home/ubuntu/riscv_pd/lef/asap7sc7p5t_28_R_4x_220121a.lef
read_lef /home/ubuntu/riscv_pd/lef/data_memory.lef

# Step 2: Load Liberty files
read_liberty /home/ubuntu/riscv_pd/lib/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty /home/ubuntu/riscv_pd/lib/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty /home/ubuntu/riscv_pd/lib/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty /home/ubuntu/riscv_pd/lib/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib
read_liberty /home/ubuntu/riscv_pd/lib/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty /home/ubuntu/riscv_pd/lib/data_memory.lib

# Step 3: Load netlist and SDC
read_verilog /home/ubuntu/riscv_pd/netlist/risc_synth.v
link_design Top_Module
read_sdc /home/ubuntu/riscv_pd/risc.sdc

# Step 4: Floorplan
# Site width=0.216 Site height=1.08
# Core X = 0.216 * 60 = 12.96 (exact multiple of site width)
# Core Y = 1.08  * 12 = 12.96 (exact multiple of site height)
# Core end X = 0.216 * 820 = 177.12
# Core end Y = 1.08  * 172 = 185.76
initialize_floorplan \
  -die_area  "0 0 200 200" \
  -core_area "12.96 12.96 187.20 185.76" \
  -site      asap7sc7p5t

# Step 5: Routing tracks
make_tracks M2 -x_offset 0.108 -x_pitch 0.216 -y_offset 0.108 -y_pitch 0.216
make_tracks M3 -x_offset 0.108 -x_pitch 0.216 -y_offset 0.108 -y_pitch 0.216
make_tracks M4 -x_offset 0.108 -x_pitch 0.216 -y_offset 0.108 -y_pitch 0.216
make_tracks M5 -x_offset 0.108 -x_pitch 0.216 -y_offset 0.108 -y_pitch 0.216
make_tracks M6 -x_offset 0.108 -x_pitch 0.216 -y_offset 0.108 -y_pitch 0.216
make_tracks M7 -x_offset 0.108 -x_pitch 0.216 -y_offset 0.108 -y_pitch 0.216

# Step 6: IO pin placement
place_pins -hor_layers M4 -ver_layers M5

# Step 7: Tap and endcap cells
tapcell \
  -tapcell_master "TAPCELL_ASAP7_75t_R" \
  -endcap_master  "TAPCELL_ASAP7_75t_R" \
  -distance 14

# Step 8: Place data_mem macro
set db [ord::get_db]
set block [[$db getChip] getBlock]
set inst [$block findInst data_mem]
$inst setLocation 50000 50000
$inst setPlacementStatus FIRM

# Step 9: PDN
add_global_connection -net VDD -pin_pattern "^VDD$" -power
add_global_connection -net VSS -pin_pattern "^VSS$" -ground
set_voltage_domain -power VDD -ground VSS
define_pdn_grid -name "Core" -voltage_domains "Core"

# M1 followpins — power rails along each standard cell row
add_pdn_stripe -followpins -layer M1 -starts_with POWER

# M7 power stripes — vertical power mesh
# pitch = 1.08 * 100 = 108 um (100 rows apart)
# offset = 1.08 * 50 = 54 um (start at middle)
add_pdn_stripe \
  -layer M7 \
  -width 0.640 \
  -pitch 108.0 \
  -offset 54.0 \
  -starts_with POWER

add_pdn_connect -layers {M1 M7}
pdngen

puts "PDN DONE"


# Global placement
global_placement -density 0.65

# Resizer design
set_wire_rc -signal -resistance 1.3e-4 -capacitance 1.3e-4
set_wire_rc -clock  -resistance 1.3e-4 -capacitance 1.3e-4
repair_design -max_wire_length 100

# Detailed placement
detailed_placement

# CTS
clock_tree_synthesis \
  -root_buf "BUFx4_ASAP7_75t_R" \
  -buf_list "BUFx4_ASAP7_75t_R BUFx2_ASAP7_75t_R"

# Post-CTS repair
repair_timing -setup -hold
repair_design
detailed_placement

# Fix macro overlap
set db [ord::get_db]
set block [[$db getChip] getBlock]
set inst [$block findInst data_mem]
$inst setPlacementStatus PLACED
$inst setLocation 100000 100000
$inst setPlacementStatus FIRM
cut_rows -endcap_master TAPCELL_ASAP7_75t_R
tapcell -tapcell_master "TAPCELL_ASAP7_75t_R" -endcap_master "TAPCELL_ASAP7_75t_R" -distance 14
detailed_placement

# Filler
filler_placement "FILLER_ASAP7_75t_R FILLERxp5_ASAP7_75t_R"

# Global routing
make_tracks M1 -x_offset 0.144 -x_pitch 0.288 -y_offset 0.144 -y_pitch 0.288
set_routing_layers -signal M2-M7 -clock M4-M7
global_route \
  -guide_file /home/ubuntu/riscv_pd/netlist/route.guide \
  -congestion_iterations 30

# Fix power nets
foreach net [$block getNets] {
    set sig_type [$net getSigType]
    if {$sig_type == "POWER" || $sig_type == "GROUND"} {
        if {![$net isSpecial]} {
            $net setSpecial
            puts "Fixed net: [$net getName]"
        }
    }
}

# Save before detailed routing
write_def /home/ubuntu/riscv_pd/netlist/pre_route.def
puts "PRE-ROUTE DEF SAVED"
