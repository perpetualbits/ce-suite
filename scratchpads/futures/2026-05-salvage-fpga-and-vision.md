<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Salvage: FPGA implementation roadmap and long-horizon visions

**Status:** Scratchpad — non-normative. Salvage material under
review.
**Source:** Distilled from 27 ChatGPT design-discussion chats
conducted between July 2025 and May 2026, summarized in a
review session on 2026-05-29.
**Cluster discussion:** H
**Disposition policy:** Items here exit the scratchpad via one
of three routes — promoted to a `docs/work-items.md` entry,
archived to `docs/future-directions.md`, or rejected with a
one-line note. See `scratchpads/README.md` for the lifecycle.

---

================================================================================
Salvaged FPGA implementation ideas
================================================================================

Here is everything the ChatGPT project chats reveal about your FPGA board and the plan to put a RISC-V + CE suite CPU on it.

---

## The Board

You have a **Xilinx Artix-7 PA200T-Starlite** with the following specs as recorded in the FPGA Board Design Feasibility chat:

- **FPGA chip:** XC7A200T-2FBG484I
- **Logic cells:** 215,360 LUTs
- **Slices:** 33,650
- **Block RAM:** 13,140 Kb total (≈1.6 MB on-chip)
- **DSP slices:** 740
- **DDR3:** 1 GB off-chip
- **QSPI flash:** 256 Mb
- **Crystal oscillator:** 200 MHz
- **Peripherals:** JTAG, UART, SD card, 1 GbE Ethernet, HDMI

---

## What You Wanted to Do

The stated goal from the opening of the FPGA chat was a five-step roadmap:

1. Get to know the FPGA and understand how to use it
2. Learn SystemVerilog
3. Take a ready RISC-V 64-bit design and deploy it
4. Expand the design with CME and test it
5. Eventually add vector (RVV) and H (Hypervisor) extensions

---

## The Feasibility Numbers

**For a minimal 64-bit RISC-V core (e.g. picoRV64):** roughly 10,000–15,000 LUTs. Adding CME logic (CSRs, context-bank datapath, group and delegation control) was estimated at a few thousand additional LUTs, putting a single core with CME at perhaps 20,000–25,000 LUTs total. The board's 215,360 LUTs gives you ~190,000 free after a single core — a very large headroom.

**For context banks:** a single context bank holding GPRs + FPRs + basic CSRs is roughly 4–8 KB of SRAM. With 1.6 MB total on-chip BRAM, the conclusion reached was that you can fit 64 banks per hart comfortably for a small number of harts. The discussion computed that 64 banks/hart × a few harts still only consumes a modest fraction of BRAM.

**For 4 harts with CME + vector + H:** this was your specific question. The answer was that the Artix-7 is more than capable, though no hard LUT number was computed for the full 4-hart + RVV configuration in the chats. The general assessment was "the board can handle it if you're patient with the toolchain builds."

**RVV VLEN:** this was touched on in the vector/RVV context but no specific VLEN number (128, 256, 512) was pinned down for the Artix-7 in the chats. What was discussed is that RVV with VLEN=128 or VLEN=256 is achievable on FPGA with an existing soft core, but full VLEN=512 or VLEN=1024 would require significantly more BRAM and DSPs. The 740 DSP slices and 1.6 MB BRAM suggest VLEN=128 is comfortable, VLEN=256 is feasible, VLEN=512 would be tight.

**Harts:** no hard limit was stated, but the implication from the LUT budget is that 2–4 harts with modest configuration (CME, without full RVV) is very practical. A single non-vector RISC-V 64-bit hart with CME likely lands around 20K–30K LUTs; four of those is 80K–120K LUTs, well within the 215K budget. Adding RVV compresses the hart count significantly depending on VLEN.

---

## How the Discussion Developed

The conversation started with board arrival excitement and broad feasibility confirmation. ChatGPT's initial role was to validate that the Artix-7 200T is capable, and it was confirmed as "more than capable." The discussion then jumped to CME-specific concerns: cache state management after 1-cycle context switches, bank exhaustion as a denial-of-service risk, zeroing banks for security, SATP/TLB handling, and timing side-channels. This shows the FPGA conversation was primarily used as a vehicle to think through CME design problems, not to plan a step-by-step FPGA implementation.

The suggested learning roadmap from the FPGA chat was:

1. Vivado setup → blink LEDs (SystemVerilog "Hello World")
2. Instantiate MIG DDR3 controller + BRAM buffer via UART
3. Integrate a baseline 64-bit RISC-V core (picoRV64 or LiteX RV64)
4. Install RISC-V GCC toolchain, write minimal firmware, boot from flash/SD
5. Add CME as CSR extensions + datapath logic, simulate with Verilator
6. On-board verification with small RTOS-like firmware testing ec.ib/ec.ob
7. Optional: Rocket or VexRiscv-Linux for Linux-capable configuration

The "Software FPGA Feasibility" chat was a brief standalone exploration asking whether a pure-software FPGA emulator is feasible (answer: yes for slow simulation, no for real-time — it was about Verilator-style simulation, not hardware).

---

## What Was Found About Feasibility

The key hardware conclusion reached was: **the board is plenty big enough for what you need in the near term.** The concerns raised were not resource-related but knowledge-related. The "Vector unit design critique" and "CE suite development" chats make this explicit — the bottleneck is not the FPGA but the gap in skills you yourself identified:

- Understanding existing RISC-V extensions (H-mode, PMP, RVV semantics)
- Chip design / RTL implementation in SystemVerilog
- Kernel coding and Linux internals
- Assembly programming
- General software development
- Technical writing for the ISA proposal

The advice given in the "Vector unit design critique" chat was to prototype key aspects on the FPGA *before* submitting to RISC-V International, precisely to uncover corner cases that AI-assisted spec work might miss.

---

## What Learning Plan / Course Material Was Developed

No formal course plan or syllabus was produced in the chats. The closest thing is the implicit roadmap from the FPGA chat above (blink → DDR3 → RISC-V core → CME → Verilator → Linux). The "RISC-V vector unit spec" chat produced a good workflow guide for managing multi-document projects with AI tools, but that's tooling, not a learning curriculum.

What was identified as the learning stack you need:

**Tier 1 (gate to anything):** SystemVerilog or VHDL basics, Vivado flow, FPGA timing/constraints. Without this, nothing synthesizes.

**Tier 2 (gate to the RISC-V core):** RISC-V privileged spec (S-mode, M-mode, CSR model, PMP), understanding an existing open-source core (picoRV64, VexRiscv, or Rocket), the RISC-V GCC toolchain and linker scripts.

**Tier 3 (gate to CME implementation):** How context banks map to SRAM arrays, one-hot enable schemes (already designed in the ChatGPT session), S/R staging registers, and how to add custom CSRs to an existing pipeline.

**Tier 4 (gate to the full CE suite on FPGA):** RVV microarchitecture, H-extension hypervisor CSRs, TLB design, cache-way partitioning hardware.

The "Vector unit design critique" chat suggests the sensible near-term goal is not full RVA23 compliance but a smaller footprint: a working RV64 core with CME demonstrating correct bank save/restore, which you can then use as evidence when engaging with the RISC-V community.

---

## The Hypercube Dream

Separately, the "Hypercube Chiplet Architecture" chat contains a much more ambitious vision: 9 chiplets (1 octagonal core + 8 compute chiplets each with 4 harts + 8 GB RAM), hypercube-connected, with a full CE suite and an adapted Linux. This is a long-term architectural vision, not an FPGA project. The relevant sizing number is that one hex-tile compute chiplet was designed for a 500 mm² die (edge length ≈13.87 mm), which is clearly silicon, not FPGA territory.

---

## Bottom Line

You have the right board. The resource budget is not the constraint. The path forward is: learn Vivado + SystemVerilog, get a working VexRiscv or picoRV64 core running on your DDR3, then start attaching the CME datapath — using the SRAM bank designs and one-hot enable schemes already worked out in the ChatGPT sessions. The RVV VLEN question is a decision you can defer: start with VLEN=128 (or even no vector) and add it once the core CME is working. That is both the most honest assessment of where things stood, and the most practical next step.
