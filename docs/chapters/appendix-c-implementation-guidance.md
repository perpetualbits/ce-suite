<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Appendix C — Implementation Guidance

**Status:** Non-normative. Informative only.
**Scope:** This appendix sketches plausible physical implementations of the
microarchitecture Chapter 4 specifies. Nothing here constrains implementers.
All design choices, area numbers, and circuit sketches are one reasonable
path; equally correct alternatives exist. When this appendix and Chapter 4
appear to conflict, Chapter 4 governs.

---

## C.1 Purpose

Chapter 4 specifies *what* the CME microarchitecture must deliver: the
staging-bank model, the wide internal bus with bank-select decoder, the
masked-transfer semantics, and the DMA slow path. It deliberately does not
specify *how* an implementation achieves those properties. That flexibility
is intentional — a microcontroller-class implementation has very different
constraints from a server-class OoO core.

This appendix addresses three audiences:

1. **Implementers** wanting a concrete starting point. The sketches here are
   derived from standard SRAM and bitline techniques and have precedents in
   production silicon; they are a reasonable default rather than a research
   problem.
2. **Reviewers** asking whether the CE Suite microarchitecture is feasible.
   The area-cost estimates and industry analogues in §C.1 and §C.3 answer
   this question directly.
3. **Architects** exploring more ambitious variants (distributed banks,
   unit-local storage). §C.5 sketches these directions as speculative
   starting points, not finished designs.

No part of this appendix is normative. An implementation that disagrees with
every sketch here but satisfies Chapter 4's observable behaviour is fully
conformant.

---

## C.2 Industry Precedents for the S/R Staging Pattern

Chapter 4 §4.4 introduces two staging banks — the S (save) staging bank and
the R (restore) staging bank — that sit between the live register file and the
Bank SRAM array. This decoupling is not novel; it is the standard industry
solution to fast hardware context switching. The following precedents establish
that the technique is well-understood, implementable with existing EDA flows,
and predictable in area and timing.

### C.2.1 ARM Cortex-M banked shadow registers

ARM's FIQ exception mode provides 7 banked shadow registers (r8–r14 plus
SPSR). On FIQ entry, these become visible in one cycle — no data movement
occurs; a mode bit selects which physical register is presented to the
pipeline. For general interrupts, the processor hardware-pushes key state (PC,
SP, LR, PSR) to the stack in the background. The banked set's area cost is
described as negligible — a few hundred bytes of flip-flops per core. The
limitation is coverage: only a small subset of architectural state is banked.
CE Suite's contribution is generalising this idea to the full architectural
state under software control via the `ec.ib` / `ec.ob` instruction pair.

### C.2.2 SPARC register windows

SPARC implements 8–32 overlapping windows of 24 GPRs each, selected by a
circular window pointer (CWP). A context switch within the window set costs
exactly one cycle — only the pointer changes; no data moves. When all windows
are exhausted, the oldest is spilled to memory via a window-overflow trap, and
lazy refill occurs on demand. Physical storage for windows is approximately
8–15 % of core area. The approach is optimised for call/return depth rather
than arbitrary context switching across unrelated ECIDs; CE Suite's model is
more general, with software-controlled bank assignment and the ECID ownership
model providing isolation.

### C.2.3 IBM z/Architecture shadow registers

IBM zSeries processors use dedicated floating shadow register sets for fast
exception entry, interrupt handling, and transactional memory. Selected
registers are duplicated per privilege level; on exception, the hardware
switches which physical set is visible to the pipeline in one cycle. Bulk
context serialisation to memory happens asynchronously. The critical-path logic
is pointer and mux only — structurally identical to the S/R model in
Chapter 4 §4.4.

### C.2.4 x86 shadow registers (Intel/AMD)

x86 processors use shadow register sets internally for microcode exception and
interrupt handling, covering MXCSR, control registers, and portions of the
integer file. Lazy FPU/SSE state switching — saving FP state only when a new
context first executes a floating-point instruction — reduces unnecessary
transfers. This is directly analogous to CE Suite's mask-gated transfers
(Chapter 4 §4.6) and the VMT-ready flag (Chapter 4 §4.7).

### C.2.5 Synthesis

The common lesson across all four precedents: no production processor that
achieves one-cycle context switching uses a deep N-way mux tree connecting live
registers directly to a large bank array. Every implementation uses some form
of staging — exactly the S staging bank and R staging bank in Chapter 4 §4.4.
This is the correct solution, not a workaround, and it is standard practice.
CE Suite's contribution is providing it as an explicitly-visible architectural
primitive with software-controlled granularity.

---

## C.3 One Plausible Physical Implementation

This section sketches one way to implement Chapter 4 §4.4's wide internal bus
and bank-select decoder using standard SRAM and bitline techniques. Other
implementations — sense-amplifier-based, flip-flop-based, or using vendor
hard-macro SRAM — are equally valid.

### C.3.1 One-hot wordline selection

The bank-select decoder (Chapter 4 §4.4) asserts a single wordline per bank
array. A 6-to-64 one-hot decoder — roughly 100–200 transistors — drives 64
wordlines. Only the selected Bank's wordline is asserted; all others remain
idle. This eliminates the need for per-bit muxing: the "selection" of a Bank
is done electrically at the SRAM wordline level, not logically in front of
each data bit.

The comparison to conventional SRAM access is exact: this is how SRAM
wordlines work internally. The Bank array is a small SRAM; the bank-select
decoder is the row decoder. No novel circuit elements are required.

### C.3.2 Pass-gate gating on inactive Banks

In this sketch, each Bank's bitlines carry shared data driven from the live
register file or from S/R. Pass-gates (transmission gates) at each Bank entry
are held off unless that Bank's one-hot select is asserted. Inactive Banks see
the data on the bitlines but never latch it.

The area cost of the pass-gates is modest: each is a small NFET/PFET pair, one
per bit position per Bank. For 64 Banks at GHz clock rates, this is comfortable
in area and timing. The one-hot select lines are best routed in upper metal
layers (M8+ in advanced nodes) with an H-tree distribution to minimise skew.

Alternative: sense-amplifier-based SRAM with a conventional dual-port interface
achieves the same effect without pass-gates, at the cost of slightly higher
area per bit but with better noise immunity. Either approach is valid under
Chapter 4's model.

### C.3.3 Register-class-grouped wide buses

Rather than a single 8192-bit bus for the full RV64 architectural state, the
wide internal bus (Chapter 4 §4.4) is usefully partitioned into per-class
segments matching Chapter 4's register groups:

- **Bus A** — GPR slice (x1–x31, 31 × XLEN bits)
- **Bus B** — FPR slice (f0–f31, 32 × FLEN bits)
- **Bus C** — PC, SATP, and selected CSRs
- **Bus D and beyond** — VMT register file slices (vector lanes, etc.)

Each bus fires independently; all buses for a single `ec.ib` or `ec.ob`
operation can fire in parallel. This matches the per-group masked transfer
model of Chapter 4 §4.6 naturally: a mask bit disabling a group simply holds
that bus segment's drivers idle, saving power linearly with the number of
inactive groups.

Bus widths can be sized per class: the GPR bus is typically 2048 bits (32
registers × 64 bits on RV64); the FPR bus is similar; the CSR bus is much
narrower. VMT buses scale with the implementation's vector width. No single bus
needs to carry the full 8192-bit context simultaneously.

### C.3.4 SRAM subarray sizing

If each Bank subarray is sized so that one row equals one group's bus width
(e.g., 256–512 bits per row), an `ec.ib` with GPR+FPR+PC requires two
adjacent wordline assertions in the GPR/FPR subarrays and one in the CSR
subarray — three assertions across separate subarrays, all firing in the same
clock cycle. The S→Bank transfer is then one or two cycles per subarray (see
Chapter 4 §4.5 Option A), with all subarrays progressing in parallel.

This is an SRAM organisation choice, not a mux problem. The implementation
complexity is in the SRAM array layout, not in the data-path logic.

---

## C.4 Area-Cost Estimates

This section provides back-of-envelope area estimates for the Option A
reference profile from Chapter 4 §4.5. These numbers are derived from the
feasibility analysis in `scratchpads/cme/2026-05-salvage-cme.md` and are
illustrative only — actual area depends heavily on process node, SRAM
compiler choices, and implementation discipline.

### C.4.1 Reference configuration

The analysis used the following configuration at 16/12 nm process:

| Component | Size | Notes |
|-----------|------|-------|
| 64 NV banks | 64 × 1 KB = 64 KB | SRAM; 1 KB per bank per Chapter 0 §0.6 |
| 4 VMT banks | 4 × 4 KB = 16 KB | SRAM; 4 KB typical for VLEN=256 |
| S staging bank + R staging bank | ~10 KB total | Flip-flops or SRAM; ~1 register file each |
| **Total** | **~90 KB** | **~5.1 M transistors** |

Estimated silicon area for the bank arrays alone at 16/12 nm: approximately
0.036 mm². Including bank-select decoder, tag storage, and dirty-bit logic:
approximately 0.046 mm².

### C.4.2 As a fraction of host core area

| Host core type | Core area | CME area fraction | Transistor fraction |
|---------------|-----------|-------------------|---------------------|
| Small in-order | ~0.7 mm² | ~6.6 % | ~28 % |
| Mid in-order | ~1.5 mm² | ~3.1 % | ~17 % |
| Small OoO | ~3.0 mm² | ~1.5 % | ~8.5 % |

The transistor fraction is notable on very small in-order cores, but those
cores are not the primary CE Suite target. For the OoO-class cores where CME
provides the highest value, the area overhead is comfortably below 2 %.

A useful comparison: a hardware double-precision FPU typically adds 5–15 % of
core area; a hardware vector unit (VLEN=256) adds 10–25 %. At 1–2 % overhead
for a full CME implementation, the CE Suite adds less area than a hardware FPU
while providing deterministic multi-context switching for all workload classes.

### C.4.3 Process node scaling

SRAM density scales roughly as (process node)² in area per bit. At 7 nm the
~90 KB configuration would occupy approximately 0.010–0.015 mm² for the
arrays, reducing the overhead fraction further. The transistor logic (decoder,
tag, dirty bits) scales similarly. At 3 nm, the CME overhead becomes negligible
relative to cache and execution unit area.

The charter §1 estimate of 5–15 % transistor overhead is therefore
conservative; the 1–2 % OoO figure above is for the SRAM arrays. The higher
figure applies to very small in-order cores, which are not the primary target.

---

## C.5 Speculative R-Preload

Chapter 4 §4.4 describes the R staging bank as the restore preload buffer for
`ec.ob`. It does not require hardware to preload R before `ec.ob` is issued —
that is the software path where `ec.ob` triggers the Bank→R transfer and then
R→Live. However, a straightforward optional optimisation applies:

**If the implementation knows or predicts the next ECID to be restored**, it
can begin the Bank→R transfer speculatively before `ec.ob` is issued. On
`ec.ob` commit, R is already warm and the R→Live step completes in one cycle.
The overall observed latency is then 1–2 cycles rather than 3–9 cycles for the
common case.

Sources of the "next ECID" hint:
- **Scheduler software hint** — the OS writes the next ECID to a hint CSR
  before executing `ec.ib` on the outgoing context.
- **Hardware prediction** — analogous to a branch predictor, hardware can
  track ECID dispatch patterns and prefetch speculatively.
- **EC[e] hot set prefetch** — the hardware prefetches the hot-set SRAM entry
  for the predicted ECID alongside the R-preload.

Nothing in Chapter 4 mandates this optimisation. Nothing forbids it. It is a
purely microarchitectural choice, invisible to software. The speculative
preload is squashed (and R invalidated) if the `ec.ob` names a different ECID
than predicted.

This optimisation is analogous to instruction-fetch prefetch or cache
prefetch: optionally hide latency that is architecturally visible only as
timing, not as correctness. High-context-switch-rate workloads (RTOS ISR
handling, hypervisor scheduling) benefit most.

---

## C.6 Distributed Bank Variations

The Bank model in Chapter 4 treats each Bank as a logically unified store.
Nothing in Chapter 4 requires this store to be physically monolithic — an
implementation may distribute Bank storage across the execution clusters that
use it. This section sketches three variations. All are more speculative than
the S/R staging model in §C.2–§C.3; further architectural work is needed
before any could be recommended for production.

### C.6.1 VULM — Vector Unit-Local Memory

In an implementation with a dedicated vector execution unit (or vector lane
array), the vector portion of a Bank — holding the VMT register file — can be
placed physically adjacent to the vector register file rather than in the
central Bank array.

Under this sketch, each "VULM slot" is a tagged buffer in the vector unit's
local SRAM. A VULM slot is associated with an ECID and can be in one of
several states: empty, warming (filling from the backing VMT image in memory),
partially warm, fully resident, or evicting. On `ec.ob`, the vector unit checks
whether the incoming ECID's VULM slot is resident:
- **Hit**: the vector unit switches its active register file pointer to the
  resident slot in one cycle, concurrent with the scalar register restore.
- **Miss**: the unit begins an asynchronous fill of the slot from memory;
  scalar execution resumes normally (the VMT-ready flag in Chapter 4 §4.7
  stalls the first vector instruction until the fill completes).

VULM reduces the wide-bus reach for the vector portion of contexts — the
vector data never travels the full distance to the central Bank array and back.
For implementations with wide vector registers (VLEN ≥ 512), the wiring and
power savings can be significant.

This is conceptually related to the VMT-ready mechanism in Chapter 4 §4.7
but operates at the SRAM level rather than at the flag level. An implementer
pursuing VULM would need to specify the number of VULM slots, the eviction
policy, and the interaction with `ec.im`/`ec.om` (the DMA path in
Chapter 4 §4.10). These are non-trivial design decisions not resolved here.

### C.6.2 IULM — Interrupt Unit-Local Memory

An interrupt controller handling frequent interrupts repeatedly saves and
restores the same small set of interrupt-handler ECIDs. Placing a small number
of Bank slots in the interrupt controller's local SRAM — an IULM — pins those
slots close to the interrupt dispatch hardware, minimising the restore latency
for interrupt entry.

An IULM sketch: the interrupt controller holds K pinned IULM slots, one per
interrupt-priority level, each tagged with the ECID of the ISR for that level.
On interrupt delivery, the controller simultaneously asserts the interrupt and
triggers the IULM→R→Live restore for the ISR's slot, so that by the time the
processor commits the context switch, R is already warm.

This is analogous to the M-mode banked register approach in ARM Cortex-M
(§C.2.1) but generalised to arbitrary ISR register state. It requires
coordination between the interrupt controller and the CME context-switch
hardware. Chapter 18 (CLIC Integration) covers the software protocol for
managing interrupt-handler ECIDs; IULM is a hardware optimisation below that
protocol layer, not a change to it.

### C.6.3 Distributed bank slices for out-of-order cores

An OoO core typically has several physical register files — one per issue port
cluster, or one per register class (integer, floating-point, vector). The Bank
array could be physically distributed to match: an integer Bank slice adjacent
to the integer physical register file, an FP Bank slice adjacent to the FP
file, and so on.

Under this sketch, an `ec.ob` operation broadcasts the bank-select signal to
all clusters simultaneously; each cluster performs its own Bank-slice→R
transfer in parallel. The observable effect is identical to the monolithic
model — Chapter 4's timing bounds and ownership semantics are unchanged — but
the physical wire lengths, port counts, and power consumption differ
favourably.

The key challenge is coherence: `ec.ig` (bank assignment) and `ec.oe` (forced
destroy) must correctly update every slice, not just the central bank record.
Bank tag and dirty-bit state must be consistent across slices. These are
solvable design problems but require careful specification of the slice
coherence protocol, which is out of scope for this appendix.

---

## C.7 What This Appendix Does Not Cover

This appendix deliberately stops short of the following:

- **Timing closure at high clock rates.** Whether the one-hot decoder and
  pass-gate scheme achieves timing closure at a given target frequency depends
  on the process node, cell library, and physical layout. Timing sign-off
  requires a complete flow; this appendix provides no guarantees.
- **Specific cell library choices.** SRAM compilers, standard-cell libraries,
  and hard macros vary by foundry and licensee. The choice of SRAM compiler
  materially affects area, power, and timing.
- **Full RTL or netlist.** The sketches here are structural descriptions, not
  Verilog or SystemVerilog. An RTL implementation would need to resolve many
  additional details.
- **Formal verification of the described implementations.** Whether any
  specific implementation satisfies Chapter 4's invariants (ownership, timing,
  masked transfer correctness) requires a formal or simulation-based
  verification effort. The Sail model (`sail/`) provides the formal reference;
  RTL must be verified against it independently.
- **FPGA-specific constraints.** Synthesis for Xilinx Artix-7 or other FPGA
  families involves LUT/BRAM mapping choices different from ASIC. The `hw/`
  sub-project covers FPGA implementation; this appendix targets ASIC
  microarchitecture.
- **CPE, MSE, and QoS implementation.** This appendix covers CME (context
  banks and staging). The other three extensions have distinct microarchitecture
  (cache-way partitioning hardware, memory arbiter, I/O QoS enforcement) that
  warrants separate treatment.

For the authoritative CE Suite specification, see Chapter 4
(Hardware Microarchitecture Overview) and the chapters for each individual
extension. This appendix is a plausibility argument and a starting point; the
spec is the source of truth.

---

[Next: Glossary](../reference/glossary.md)
