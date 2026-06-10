# 32-Bit Single-Cycle RISC-V Processor — RTL to Physical Design Using Open-Source EDA Tools

> **Full RTL-to-GDS flow** on a structurally modelled RV32I single-cycle core, targeting the **ASAP7 7 nm PDK** using Yosys, OpenROAD, and OpenSTA — zero commercial tools.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
  - [Datapath Modules](#datapath-modules)
  - [Supported Instructions](#supported-instructions)
- [Repository Structure](#repository-structure)
- [Physical Design Flow](#physical-design-flow)
  - [1. Synthesis (Yosys)](#1-synthesis-yosys)
  - [2. Floorplanning](#2-floorplanning)
  - [3. Power Distribution Network](#3-power-distribution-network)
  - [4. Placement](#4-placement)
  - [5. Clock Tree Synthesis](#5-clock-tree-synthesis)
  - [6. Routing](#6-routing)
  - [7. Static Timing Analysis (OpenSTA)](#7-static-timing-analysis-opensta)
- [Timing Constraints (SDC)](#timing-constraints-sdc)
- [Key Results](#key-results)
- [Tools & PDK](#tools--pdk)
- [How to Reproduce](#how-to-reproduce)
- [Author](#author)

---

## Project Overview

This project implements a **32-bit single-cycle RISC-V (RV32I subset) processor** in structural Verilog and carries it through a complete **Physical Design (PD) flow** using only open-source EDA tools. The design targets the **ASAP7 predictive 7 nm PDK**, making it a practical end-to-end reference for RTL-to-GDS using the open-source stack.

Every module in the RTL is written to match a schematic-level datapath — no behavioural shortcuts — so the netlist faithfully reflects the hardware intent before and after synthesis.

---

## Architecture

The processor is a textbook single-cycle implementation: every instruction completes in one clock cycle. The datapath is fully structural, with each functional block implemented as an independent Verilog module wired together in `Top_Module`.
<img width="512" height="372" alt="image" src="https://github.com/user-attachments/assets/8205225e-2568-483e-a209-97f64ee0a680" />


### Datapath Modules

| # | Module | Function |
|---|--------|----------|
| 1 | `PC` | 32-bit program counter, synchronous reset to 0 |
| 2 | `Adder` | Pure combinational 32-bit adder (used for PC+4 and branch target) |
| 3 | `Instruction_Memory` | ROM — case-addressed on `Address[9:2]`, returns 32-bit instruction |
| 4 | `Control_Unit` | Decodes 7-bit opcode into `Branch`, `MemRead`, `MemtoReg`, `ALUOp[1:0]`, `MemWrite`, `ALUSrc`, `RegWrite` |
| 5 | `Register_File` | 32×32 register file; `x0` hardwired to 0; synchronous write, combinational read |
| 6 | `Immediate_Generator` | Sign-extends I-type, S-type, and B-type immediates to 32 bits |
| 7 | `Shift_Left_1` | Logical left-shift by 1 (×2 for branch offset) |
| 8 | `MUX_2to1` | Parameterised 2-to-1 MUX (reused for ALUSrc, MemtoReg, PCSrc) |
| 9 | `ALU_Control` | Maps `ALUOp[1:0]` + `funct3`/`funct7` to 4-bit ALU control word |
| 10 | `ALU` | Executes AND, OR, ADD, SUB, SLT based on 4-bit control |
| 11 | `Data_Memory` | Synchronous RAM; black-boxed post-synthesis for SRAM macro insertion |
| 12 | `Top_Module` | Structural wiring of all modules; exports `PC_out`, `ALU_out`, `WriteBack_out` |

### Supported Instructions

| Format | Instructions |
|--------|-------------|
| R-type | `add`, `sub`, `and`, `or`, `slt` |
| I-type | `addi`, `lw` |
| S-type | `sw` |
| B-type | `beq` |

The instruction memory ships with a five-instruction smoke-test sequence:

```asm
addi x2, x0, 5      # x2 = 5
addi x3, x0, 10     # x3 = 10
add  x3, x2, x3     # x3 = 15
sw   x6, 0(x3)      # mem[15] = x6
lw   x6, 0(x3)      # x6 = mem[15]
```

---

## Repository Structure

```
.
├── risc.v              # Full structural RTL — all 12 modules + Top_Module
├── risc.sdc            # SDC timing constraints for ASAP7 7 nm target
├── floorplan.tcl       # OpenROAD floorplan and PDN TCL script
├── lef/                # ASAP7 technology and cell LEF files
├── lib/                # Liberty (.lib) files for synthesis and STA
├── netlist/            # Synthesised gate-level netlist(s)
├── reports/            # Timing, area, and DRC reports from each PD stage
└── logs/               # Tool logs from Yosys, OpenROAD, OpenSTA runs
```

---

## Physical Design Flow

### 1. Synthesis (Yosys)

The RTL is synthesised with **Yosys** using the ASAP7 standard cell library. `Data_Memory` is marked as a black box so it maps to an SRAM macro rather than flip-flop arrays.

Key synthesis steps:
- `read_verilog risc.v` — parse all 12 modules
- `synth -top Top_Module` — technology-independent elaboration and optimisation
- `dfflibmap -liberty <asap7.lib>` — map flip-flops to target library cells
- `abc -liberty <asap7.lib>` — combinational logic mapping and optimisation
- `write_verilog netlist/risc_synth.v` — export gate-level netlist

### 2. Floorplanning

Floorplanning is driven by `floorplan.tcl` inside **OpenROAD**. The script sets the die area, core utilisation, and aspect ratio, then places I/O pins.

```tcl
# Example excerpt — see floorplan.tcl for the full script
initialize_floorplan -utilization 40 -aspect_ratio 1.0 \
                     -core_space 10 -site asap7sc7p5t
```

A 40 % utilisation target leaves adequate routing headroom for a single-cycle design whose critical path passes through multiple combinational stages.

### 3. Power Distribution Network

The PDN is also defined in `floorplan.tcl`. Horizontal and vertical stripes on metal layers M4/M5 connect to VDD/VSS rails on M1, ensuring adequate IR drop margin across the core.

### 4. Placement

Global and detailed placement are run inside OpenROAD:

```tcl
global_placement -density 0.40
detailed_placement
```

Placement legality is verified with `check_placement` before proceeding to CTS.

### 5. Clock Tree Synthesis

CTS is performed with OpenROAD's `TritonCTS`. The `core_clk` net is balanced across all sequential elements. Post-CTS hold slack is checked and buffer insertion is used to repair any hold violations introduced by clock skew.

### 6. Routing

Global routing (`fastroute`) followed by detailed routing (`TritonRoute`) completes the physical implementation. The router observes ASAP7 design rules for minimum spacing, width, and via enclosure.

### 7. Static Timing Analysis (OpenSTA)

Post-route STA is run with **OpenSTA**, reading the gate-level netlist, the ASAP7 `.lib`, and `risc.sdc`. Timing reports for setup and hold are generated for the `core_clk` domain.

```bash
sta -f run_sta.tcl   # reads netlist + sdc, reports WNS/TNS
```

---

## Timing Constraints (SDC)

The constraints in `risc.sdc` target the ASAP7 7 nm node at a **500 MHz clock (2 ns period)**.

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Clock period | 2000 ps | 500 MHz target |
| Setup uncertainty | 40 ps | ~2 % of period (pre-CTS skew budget) |
| Hold uncertainty | 20 ps | 1 % of period |
| Clock transition | 30 ps | < 5 % of period; realistic for ASAP7 buffers |
| Input delay | 800 ps (40 %) | External logic budget before data arrives |
| Output delay | 800 ps (40 %) | Downstream capture margin |
| Driving cell | `INVx4_ASAP7_75t_R` | Medium-strength RVT inverter |
| Output load | 5 fF | Models ~3–4 gate inputs at 7 nm |
| Max transition | 100 ps | 5 % of period |
| Max capacitance | 500 fF | ~100–200 µm wire at 7 nm |
| Max fanout | 20 | Avoids transition degradation on decode signals |
| OCV derating (early) | 0.90 | Hold pessimism |
| OCV derating (late) | 1.10 | Setup pessimism |
| False path | `reset` port | Async reset — no setup/hold relationship to `clk` |

---

## Key Results

| Metric | Value |
|--------|-------|
| Target technology | ASAP7 7 nm (predictive PDK) |
| Clock frequency | 500 MHz |
| RTL modules | 12 (structural) |
| RTL lines | 352 |
| Instruction support | R / I / S / B types (RV32I subset) |
| Synthesis tool | Yosys (open-source) |
| PD tool | OpenROAD (open-source) |
| STA tool | OpenSTA (open-source) |
| Data_Memory | Black-boxed (SRAM macro) |

> Detailed area, power, and timing numbers are available in the `reports/` directory.

<img width="569" height="569" alt="image" src="https://github.com/user-attachments/assets/bfb7314d-5d7e-4833-9ece-66a14574eebf" />
<img width="672" height="301" alt="image" src="https://github.com/user-attachments/assets/cf006601-14c2-45cd-bb0d-4b240f530b65" />

---

## Tools & PDK

| Tool / PDK | Version / Notes |
|------------|----------------|
| **Yosys** | Logic synthesis |
| **OpenROAD** | Floorplan, placement, CTS, routing |
| **OpenSTA** | Static timing analysis |
| **TritonCTS** | Clock tree synthesis (part of OpenROAD) |
| **TritonRoute** | Detailed router (part of OpenROAD) |
| **ASAP7 PDK** | Arizona State University predictive 7 nm process; `asap7sc7p5t` standard cell library |
| **Verilog** | Structural RTL; Verilator-lint-clean (`UNUSED`, `UNDRIVEN`, `DECLFILENAME` suppressed intentionally) |

---

## How to Reproduce

### Prerequisites

```bash
# Install Yosys
sudo apt install yosys

# Install OpenROAD (includes OpenSTA, TritonCTS, TritonRoute)
# Follow: https://github.com/The-OpenROAD-Project/OpenROAD
```

### Run Synthesis

```bash
yosys -p "
  read_verilog risc.v
  synth -top Top_Module
  dfflibmap -liberty lib/<asap7_lib>.lib
  abc -liberty lib/<asap7_lib>.lib
  write_verilog netlist/risc_synth.v
"
```

### Run Physical Design

```bash
openroad floorplan.tcl
```

### Run STA

```bash
opensta -f run_sta.tcl
# Reads netlist/risc_synth.v + risc.sdc + ASAP7 liberty
```

---

## Author

**Janamanchi Rathna Koushal**
B.Tech ECE (VLSI Design Specialisation) — SR University, Warangal
CGPA: 9.564 | Samsung Fellowship Grade II (IISc / Synopsys ISWDP Cohort 6)

- GitHub: [@RathnakoushalJanamanchi](https://github.com/RathnakoushalJanamanchi)
- LinkedIn: [rathna-koushal-janamanchi](https://linkedin.com/in/rathna-koushal-janamanchi)

---

*This project is part of a broader RTL-to-GDS learning portfolio covering OpenLane, Sky130A, ASAP7, and industry-standard Physical Design methodologies.*
