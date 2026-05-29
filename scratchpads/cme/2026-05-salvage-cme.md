<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Salvaged CME hardware and microarchitecture ideas

**Status:** Scratchpad — non-normative. Salvage material under
review.
**Source:** Distilled from 27 ChatGPT design-discussion chats
conducted between July 2025 and May 2026, summarized in a
review session on 2026-05-29.
**Cluster discussion:** A, B, C
**Disposition policy:** Items here exit the scratchpad via one
of three routes — promoted to a `docs/work-items.md` entry,
archived to `docs/future-directions.md`, or rejected with a
one-line note. See `scratchpads/README.md` for the lifecycle.

---

================================================================================
Salvaged CME ideas
================================================================================

Here is a structured overview of all the hardware implementation ideas that were discussed for register banks across the three chats.

---

## Register Bank Hardware Implementation — Structured Overview

The discussions covered three distinct chats: **"Hardware context banks design"**, **"One-hot register switching"**, and **"Register bank distribution"**. The chats progressed from "is this feasible?" to circuit-level specifics to microarchitecture layout.

---

### 1. The Problem Statement

The core concern you raised: if you want to save all bits from the live register file (GPR, FPR, PC, SATP, CSRs ≈ 1 KB / 8192 bits) into one of 64 banks in a single clock cycle, does that require a full 6-bit mux per bit? That would be a 64:1 mux on every single bit — 8192 of them — which is obviously catastrophic in area and transistor count.

The answer is: no, and here is why not, plus what you do instead.

---

### 2. Idea A: SRAM Banks with One-Hot Enable + Wide Shared Bus

**The main recommended approach.**

Instead of per-bit muxing, you treat each bank as a small SRAM array. Selection is done by asserting a single one-hot write-enable wordline on the target bank. All banks share the same wide bitlines (driven from the live register file), but only the selected bank's wordline is asserted. The others see the data arrive but never latch it.

Key circuit elements:
- A **6-to-64 one-hot decoder** — only about 100–200 transistors. This is the only "mux" logic per bank selection.
- A **wide shared bus** (e.g., several 256-bit segments, one per register group) running from the live register file to all banks.
- **Pass-gates (transmission gates)** on each bank entry: they are off unless the one-hot select for that bank is asserted.
- **Save path** (ec.ib): bus drives data, selected bank's wordline opens, SRAM latches in 1 cycle.
- **Restore path** (ec.ob): selected bank reads out to sense amps, a small local mux per bus segment (not per bit!) routes back to the live register file.

Timing: the critical path is only: bank_id register → 6:64 decoder → pass-gate enable → bitline settle → latch. No deep logic trees on the data path.

Scalability: competitive up to ~128 banks at GHz clocks before wire capacitance and driver sizing become the limiting factor. For 64 banks it is very comfortable.

Partitioning the bus for parallelism: rather than one single 8192-bit bus, you partition into groups:
- Bus A: GPR slice(s)
- Bus B: FPR slice(s)
- Bus C: PC/SATP/CSR slice(s)
- Bus D and beyond: vector slices

These buses can all fire in parallel on the same cycle. If each SRAM subarray is sized so one bank row = one group's width (256–512 bits per row), you save GPR+FPR+CSR in 1–2 cycles by firing a few adjacent wordlines concurrently. This is an SRAM organization problem, not a mux problem.

Mask gating: the group mask bits from the CME instruction (ec.ib / ec.ob) can disable whole bus segments and their wordlines for register groups that are not being switched. This saves power nearly linearly with how much of the context is masked out.

---

### 3. Idea B: S/R Staging Registers (Your Own Idea — Validated as Solid)

You proposed an intermediate S (save) buffer and R (restore) buffer to break the hard problem into two simpler ones. This was validated as correct and used extensively in real hardware:

- **Live → S**: trivial 1:1 wiring, true 1-cycle copy, no muxing needed.
- **S → B[i]**: a small copy engine (DMA-like) walks SRAM rows from S to the selected bank over ~8–16 short cycles, off the critical path.
- **B[i] → R**: symmetric.
- **R → Live**: trivial 1:1 wiring, 1-cycle restore.

Real-world precedents cited: ARM Cortex-M banked shadow registers (1-cycle interrupt swap), SPARC register windows (pointer rotation), IBM z/Architecture shadow register sets, x86 microcode shadow register files.

The S/R approach simplifies timing closure dramatically because the long SRAM transfer is now decoupled from the pipeline. It also naturally supports dirty/used bits: on save, skip subsets that haven't been touched since last restore. The cost is ~1–8 KB of flops/SRAM for S and R, plus a tiny copy engine — well worth it.

For VMT (vector/matrix/tensor) banks at 4 KB each, staging via S/R is essentially mandatory because the transfer time scales with size. The VMT-ready bit idea: let the hart resume on GPR/FPR after 1–2 cycles of restore, and block only the first vector instruction until the VMT transfer completes. This gives the illusion of a fast full restore even for large contexts.

---

### 4. Idea C: One-Hot Bitline Direct Connection (Your Invention)

You proposed connecting each register bit directly to a one-hot line that runs to the corresponding bit position in each bank, so a given bit position is wired in parallel to all 64 banks, with a pass-gate at each bank that opens when that bank's select line is asserted.

This was validated as workable and competitive. The key realization: you still need the global one-hot select lines (64 of them, one per bank), but the decoder generating them is small (6:64, ~100–200 transistors). Each bit position then has 64 pass-gate connections — small transistors, laid out as a regular row structure alongside the register cells. The "mux" is implemented electrically (only one pass-gate open at a time) rather than logically (no per-bit logic tree).

The area cost is dominated by the pass-gates and the wiring for 64 select lines that must reach every bit cell. For 64 banks at GHz clocks, this is fine. The select lines are best implemented in top metal layers (M8+) with an H-tree distribution to minimize skew.

This is essentially a content-addressable memory (CAM)-adjacent structure, using the bank ID as the address and the one-hot decoded enables as the wordlines. The comparison to SRAM wordlines is exact — this is how SRAMs already work internally.

---

### 5. Idea D: Multiple Full Register Sets (Pointer Swap)

Instead of banks in SRAM with mux/demux, you instantiate N full live register files and switch between them by flipping a pointer. This is exactly the SPARC register window model and ARM's banked mode registers.

**Advantages:** no copy at all on switch; ec.ib/ec.ob become pointer updates. Truly 1-cycle, zero data movement.

**Disadvantages:** area scales linearly with N. For N=4 (like S, R, and two live contexts) this is fine. For N=64 it is entirely impractical — you would have 64× the register file area sitting idle on every hart. This approach caps at a handful of contexts and is the right choice only for S and R.

CME's S and R staging registers are essentially this idea applied at small N, which is why they work well.

---

### 6. Idea E: Distributed Banks / Unit-Local Storage

**The most architecturally ambitious idea, from the "Register bank distribution" chat.**

Instead of a monolithic context bank block near the register file, you distribute slices of each bank physically adjacent to the execution unit that owns them:

- Integer cluster gets a local bank SRAM slice for GPR and selected CSRs.
- FP cluster gets its own slice for FPR and FP CSRs.
- Vector lanes each get per-lane bank SRAM (this is already the natural shape of RVV implementations).

A context switch then updates the "which bank slice is currently selected" pointer for each cluster simultaneously in 1 cycle, with a fence rule for correctness.

**Benefits on wiring and power:**
- Shorter wires: most register reads stay inside a small physical neighborhood, reducing wire capacitance C and therefore dynamic power P ∝ C·V²·f.
- No global crossbar: instead of routing any register to any unit, you keep wide buses inside each cluster and use narrower inter-cluster links.
- Port count reduction: central register files need many read/write ports simultaneously. Distributed banking lets you split the RF into cluster-local pieces with far fewer ports per piece, which is a major area and power win.
- Less L1 cache pollution: vector scratch traffic stays in the vector-local store and doesn't evict normal data from the shared L1.

The bank conceptually becomes a set of slices (int-slice, fp-slice, vec-slices-per-lane), all tagged with the same (GroupID, BankID) ownership metadata. ec.ob/ec.ib switch all slice selectors for all clusters simultaneously.

---

### 7. Idea F: VULM / IULM — Vector and Interrupt Unit-Local Memory

This grew out of the distributed banks discussion. Rather than "banks next to the unit," you define two named unit-local memory instances:

**VULM (Vector Unit-Local Memory):** a managed scratchpad adjacent to the vector lanes. Physically K slots (K much smaller than the number of runnable ECIDs). Each slot is tagged by ECID. On context switch, if the incoming ECID's slot is already resident (hit), switch in 1 cycle. On miss, evict a victim (spilling dirty lines asynchronously to the ECID's backing VLS image in memory), retag the slot, and start a fill (async). Best-effort ECIDs share K slots with LRU eviction; real-time ECIDs get pinned (locked) slots.

Slot state machine per slot: IDLE → WARMING → RESIDENT_PARTIAL → RESIDENT, with EVICTING overlapping. Spill and fill run as independent DMA-like channels, per line (64B or 128B), with valid and dirty bits per line.

Policy for best-effort tasks: bypass-on-miss (vector loads/stores hit directly against backing memory if the line isn't warm yet, and the line is pulled in concurrently). Policy for real-time: stall-on-miss (block the first vector instruction until the slot is warm). This gives RT tasks deterministic latency and BE tasks transparency.

**IULM (Interrupt Unit-Local Memory):** a smaller, typically fully pinned store next to the interrupt controller. Holds hot interrupt dispatch metadata: pending bitmaps, priority queues, ISR entry vectors, per-source metadata, pre-parsed MSI packets. Keeps interrupt entry at zero-drama — no cache miss, no eviction surprise. If partitioned by Group, guests and VMs have their own interrupt metadata slice and never contend on each other's interrupt bookkeeping.

-Here are the two write-ups for your CME salvage section.

---

## Write-up 1: C/S/R Shadow Staging Register Design

The key microarchitectural insight for making CME's "1-cycle context switch" claim physically real is the introduction of two staging register sets — S (Save) and R (Restore) — that sit between the live architectural register file (C, Current) and the context bank SRAM array (B[j]).

**The three layers are:**

- **C** — the live, active architectural register file connected to the pipeline
- **S** — a shadow copy of the same width as C, used as the save staging buffer
- **R** — a second shadow copy of the same width, used as the restore preload buffer
- **B[j]** — the context bank SRAM array, slow and wide, off the critical path

**Save sequence (ec.ib, switching away from current context):**

Step 1 (1 cycle, on critical path): C → S. All live registers are captured into S in a single cycle via a wide, trivial mux — no arbitration, no memory access, no latency. This is what makes the switch "1 cycle" from the pipeline's point of view.

Step 2 (10+ cycles, off critical path): S → B[j]. The contents of S are transferred to the target bank in SRAM. This takes multiple cycles but happens in the background; the pipeline can begin executing the new context before this finishes.

**Restore sequence (ec.ob, switching into a context):**

Step 1 (10+ cycles, off critical path, ideally preloaded): B[j] → R. The target bank's contents are read from SRAM into R. If the scheduler knows the next context in advance, this can be preloaded before the switch instruction is even issued.

Step 2 (1 cycle, on critical path): R → C. The preloaded R is written into the live register file in one cycle.

**Why this matters for CME hardware design:** Without S/R staging, a direct C↔B[j] connection would require either a very slow switch (waiting for SRAM), or a massive N:1 mux tree routing every register bit to every bank simultaneously. Neither is acceptable. S/R staging decouples the timing-critical pipeline interaction (always 1 cycle) from the bulk data movement (many cycles, hidden in the background). The S and R sets are each the same physical size as the register file — no more, no less.

**Speculative preload** of R is a natural optimization: the OS or hardware scheduler can prefetch the next context's bank into R before ec.ob is issued, effectively hiding the entire SRAM latency on the restore path. This is purely microarchitectural and requires no ISA change.

**Dirty tracking** is a complementary optimization: per-register-group dirty bits mean that unchanged registers (e.g. FPRs that a purely integer thread never touched) don't need to be written to B[j] during the S→B[j] transfer, reducing the transfer time and SRAM write energy.

---

## Write-up 2: S/R Staging — Silicon Precedents and Area Numbers

The S/R staging approach is not novel to CME — it is the standard industry method for fast context switching across multiple generations of high-performance processors. This validates the design as well-understood, implementable with existing EDA flows, and predictable in area and timing.

**ARM Cortex-M (banked registers for interrupt modes):** ARM's FIQ exception mode has 7 banked shadow registers (r8–r14 plus SPSR). On FIQ entry, these become visible in 1 cycle — no data movement, just a mode-bit selects which physical register is presented to the pipeline. For general interrupts, key state (PC, SP, LR, PSR) is hardware-pushed to the stack in the background. The area cost of the banked register set is described as negligible — a few hundred bytes of flip-flops per core. The limitation is that only a small subset of state is banked; CME generalises this to the full architectural state.

**SPARC register windows:** SPARC implements 8 to 32 overlapping "windows" of 24 GPRs each, selected by a circular window pointer (CWP). A context switch within the window set costs exactly 1 cycle — only the pointer changes, no data moves. When all windows are exhausted, the oldest is spilled to memory ("window overflow trap"), and lazy refill happens on demand. Physical storage for windows is approximately 8–15% of core area. The downside is that SPARC windows are optimised for call/return depth, not arbitrary context switching across unrelated tasks. CME's approach is more general.

**IBM z/Architecture:** zSeries processors use dedicated floating shadow register sets for fast exception entry, interrupt handling, and transactional memory. The key registers are duplicated per privilege level; on exception, the hardware switches which physical set is visible in 1 cycle. Bulk context serialisation to memory happens asynchronously. The critical-path logic is pointer and mux only.

**x86 (Intel/AMD):** Shadow register sets are used internally for microcode exception and interrupt handling, including MXCSR, control registers, and portions of the integer file. Lazy FPU/SSE state switching (FPU state is not saved until the new context actually executes a floating-point instruction) reduces unnecessary saves. The shadow sets are a small fraction of the register file area, which itself is a small fraction of core area.

**Area numbers (from the Context Bank Schematic chat analysis):**

Using Apple M1 as a concrete reference point: core area ≈ 5 mm²; full GPR/FPR register file ≈ 0.25 mm²; 128 KB L1 cache ≈ 2 mm². Generalised across modern processes, a full architectural register file (GPR + FPR) occupies roughly 0.2–0.4 mm² per core.

For CME, S and R together are two extra register files: 0.25–0.5 mm² total. The context bank SRAM for 1,024 banks (a large configuration) adds approximately 0.8 mm². Total CME overhead at the Apple M1 process node is therefore approximately 1–2% of core area. At FPGA scale, this translates to a modest increase in BRAM usage and flip-flop count — well within the Artix-7's budget for even a 4-hart configuration.

**The key lesson from industry precedent:** no production chipmaker uses a deep N:1 mux tree to connect live registers directly to a large bank array. Every implementation that achieves 1-cycle context switching uses some form of staging buffer — exactly the S/R structure in CME. This is not a workaround; it is the correct solution and is standard practice.--

### 8. Area and Transistor Numbers (Option A config, 16/12 nm)

From the CE Sizing calculator produced in the Hardware context banks design chat:

| Config | SRAM | Transistors | Area (arrays) | Total CE area |
|---|---|---|---|---|
| 64×1 KB NV + 4×4 KB VMT + 10 KB S/R | 90 KB | ~5.1 M | ~0.036 mm² | ~0.046 mm² |

As a percentage of the host core:

| Core baseline | Area % | Transistor % | SRAM % |
|---|---|---|---|
| Small in-order (0.7 mm², 18 M Tx, 80 KB SRAM) | 6.6% | 28% | 112% |
| Mid in-order (1.5 mm², 30 M Tx, 128 KB SRAM) | 3.1% | 17% | 70% |
| Small OoO (3.0 mm², 60 M Tx, 192 KB SRAM) | 1.5% | 8.5% | 47% |

Area is comfortably single-digit for any OoO core. Transistors can be notable on very small in-order cores but acceptable for the workloads CME targets. The SRAM percentage is large relative to tiny cores but shrinks quickly as you add caches.

---

### 9. Which Ideas Are Salvageable for the hw/ Directory

The ideas that translate cleanly into RTL starting points are:

**High priority:** SRAM banks + one-hot enable + wide grouped buses (Idea A) — this is the standard professional approach and has clear RTL structure. Pair it with S/R staging (Idea B) for timing relief. Together these are the "default profile" for the CME hardware.

**Worth formalizing:** the one-hot bitline pass-gate approach (Idea C) — it's novel, competitive, and makes a good argument in the extension proposal that the switching mechanism is extremely light in logic depth.

**Architectural direction:** distributed bank slices (Idea E) — this is the right long-term direction for multi-cluster OoO cores, and the VULM/IULM concept (Idea F) is the cleanest version of it for the vector and interrupt domains specifically.

**Not for RTL yet:** multiple full register sets (Idea D) — only appropriate for S and R (2 full-width sets), not for the general bank store.
