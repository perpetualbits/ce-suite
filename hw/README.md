<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Hardware (RTL, simulation, FPGA)

**Status: not yet populated.**

This tree is the placeholder for the eventual hardware implementation
of the CE Suite, intended for synthesis on the author's PA200T-StarLite
Artix-7 board (see `docs/archive/fpga-board-spec.md` for board details).

## Planned layout

```
hw/
├── rtl/      # SystemVerilog or Chisel sources
├── tb/       # testbenches
├── sim/      # simulation outputs (gitignored)
└── board/    # FPGA-specific files (constraints, IP cores, vendor projects)
```

## Before any RTL work begins

1. The specification chapters must be coherent enough to implement against.
   At minimum: the charter must be at a version the author is willing to
   freeze for the duration of the implementation, and Chapter 0 + Chapter 2
   (CME instruction set) must be aligned with that charter.
2. A decision must be made between **SystemVerilog** and **Chisel**.
   Chisel produces faster iteration for small projects; SystemVerilog
   has wider tooling support. The board's vendor toolchain (Xilinx Vivado)
   accepts both.
3. The first RTL target should be the **CME core** alone: `EC[e]` table,
   the staging banks (S/R), the copy engine, the wide bus, and `ec.ib`/
   `ec.ob`/`ec.im`/`ec.om`. CPE, MSE, and QoS come later.
4. The reference Python simulator in `tools/cme-sim.py` is the
   functional baseline. RTL must produce the same observable behavior.

## Claude Code

This subtree is where Claude Code will most likely be useful. When you're
ready to start, point Claude Code at this directory and at the relevant
spec chapters; do not give it the whole repository at once.
