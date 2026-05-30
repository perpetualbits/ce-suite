<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite hw/ — Work Items

**Purpose:** Tracks every task in the CE Suite FPGA implementation from
toolchain setup through board bring-up. Items are ordered by dependency;
nothing in a later phase should be started until the items it depends on
are resolved.

**Relationship to spec:** The CE Suite specification (`docs/chapters/`) and
the Sail formal model (`sail/`) are the normative references. This
implementation is derivative. When RTL behaviour disagrees with the Sail
model or the spec, the Sail model wins (or, where Sail is silent, the spec
wins).

**Scope decisions:**
- Target board: PA200T-StarLite (Xilinx Artix-7 XC7A200T-2FBG484I). See
  `docs/archive/fpga-board-spec.md` for capability details.
- Language decision (Chisel vs SystemVerilog) is deferred to H4.
- CPE/MSE/QoS are in scope but CME is the first target; later phases add
  the remaining extensions.
- The hypercube chiplet vision (Cluster H.2 in the salvage discussion) is
  explicitly out of scope and archived separately.
- Sail Phase 12 (S26 onward) must be complete before Phase 1 begins.

---

## ⚑ Current priority — OPTIONAL; gated on Sail Phase 12

**This work is OPTIONAL.** The CE Suite specification, formal model (Sail),
and submission to RISC-V International do not require any RTL implementation.
RTL exists only to demonstrate implementability and to provide a reference for
adopters.

**Gating:** This work plan should not begin until Sail Phase 12 (S26 onward —
CPE/MSE/QoS execute functions and litmus tests) is complete. Two reasons:

1. The Sail model is the authoritative formal reference. RTL correctness is
   judged against Sail, not against prose. Until Sail is complete, the RTL
   has nothing to verify against beyond the prose specification.
2. RTL work is enormously time-consuming. Starting before the spec and formal
   model are settled risks rework cascading through the implementation when
   architectural details shift.

The architect may choose to defer this work indefinitely. RISC-V
International may pick up the spec via a Task Group, in which case RTL work
likely lands with a member organization rather than the architect. If the
architect chooses to proceed, this file is the plan.

---

## Phase 0 — Preconditions

Must hold before any RTL is written.

### H1 · Charter version frozen for the implementation cycle

**What:** Architect records the charter version frozen for the implementation
(e.g. "v0.NN frozen for hw implementation 2026-MM-DD") and commits to not
changing it except for show-stopping bugs. Without a frozen spec, RTL work
cannot be brought to closure.

**Status:** ☐

---

### H2 · Chapters reviewed for implementability

**What:** ch00, ch03, ch07, ch09, ch11 reviewed against the frozen charter
for implementability. Any ambiguities or gaps surfaced as work items (D-series
or F-series in `docs/work-items.md`) and resolved before RTL begins.

**Spec ref:** ch00 §0.2–§0.10, ch03 §3.1–§3.7

**Depends on:** H1

**Status:** ☐

---

### H3 · Sail Phase 12 complete

**What:** Sail Phase 12 (S26–S38) is complete: CPE/MSE/QoS execute functions,
litmus tests, upstream integration review, and submission prep. The Sail model
is the RTL reference; until it is final, RTL implements a moving target.

**Depends on:** Sail S26–S38

**Status:** ☐

---

## Phase 1 — Toolchain and language selection

### H4 · Decide Chisel vs SystemVerilog

**What:** Architect's call. Chisel: faster iteration, smaller community,
generates Verilog. SystemVerilog: wider tooling, more conservative, direct to
Vivado. Both work with Vivado. Document the decision and its rationale in
`hw/README.md` or a new `hw/docs/design-decisions.md`.

**Depends on:** H1 (spec frozen before committing to a language)

**Status:** ☐

---

### H5 · Install and verify the Vivado toolchain end-to-end

**What:** Install Vivado on the architect's workstation. Build a hello-world
bitstream for the PA200T-StarLite (blink LEDs) to confirm the toolchain is
functional from synthesis through board programming. This is Tier 1 of the
learning stack.

**Depends on:** H4

**Status:** ☐

---

### H6 · Establish source-control conventions for hw/

**What:** Decide which generated artifacts are gitignored (likely: Vivado
`.jou`/`.str`, `.bit`/`.bin`/`.elf`, simulation outputs) and which are
tracked (RTL sources, constraint files, testbenches, documentation). Commit
a `.gitignore` for `hw/`.

**Depends on:** H4, H5

**Status:** ☐

---

## Phase 2 — Baseline RISC-V core

### H7 · Select a baseline RV64IMA core

**What:** Choose a baseline RV64IMA core. Candidates (approximate order of
complexity): VexRiscv-OoO, Rocket Chip, Boom, CVA6 (Ariane). The choice
depends on H4 (language) and on what features the core already provides
(privilege levels, MMU, vector if relevant). Document the choice and its
rationale.

**Depends on:** H4

**Status:** ☐

---

### H8 · Bring the baseline core up on the Artix-7

**What:** Synthesize and implement the baseline core. Boot a minimal program
from BRAM. Verify timing closure at a conservative clock (e.g. 50–100 MHz
initially). This is Tier 2 of the learning stack.

**Depends on:** H5, H7

**Status:** ☐

---

### H9 · Add UART output and confirm hello world

**What:** Add a UART peripheral. Confirm "hello world" reaches a host terminal.
This is the first end-to-end verification that the toolchain, board, and core
are all functional.

**Depends on:** H8

**Status:** ☐

---

## Phase 3 — CME core integration

### H10 · Implement the EC array (EC[e] table)

**What:** Implement the EC[e] table per ch00 §0.2–§0.3. Map to BRAM. Size
for a small ECID width initially (e.g. 8-bit ECIDs, 256-entry table). The
`ecs_ptr` field must be at offset 0 per the architectural requirement.

**Spec ref:** ch00 §0.2–§0.3, ch03 §3.3

**Depends on:** H8

**Status:** ☐

---

### H11 · Implement the staging banks (S/R)

**What:** Implement the staging banks per ch04. Decide how many bank pairs
to instantiate (small for initial bring-up; the spec permits any number).
Banks are BRAM-resident; the one-hot enable scheme and S/R staging
mechanism are worked out in `scratchpads/cme/2026-05-salvage-cme.md`.

**Spec ref:** ch04, ch00 §0.6

**Depends on:** H10

**Status:** ☐

---

### H12 · Implement the copy engine

**What:** Implement the wide-bus copy engine: the state machine that moves
register groups between live architectural state and a staging bank. This
is the microarchitectural core of the fast-path context switch.

**Spec ref:** ch04 §4.4–§4.6

**Depends on:** H11

**Status:** ☐

---

### H13 · Implement `ec.ib` and `ec.ob` execute logic

**What:** Decode the restore mask, drive the copy engine, update EC[e] state
as required. This is the primary fast-path context-switch pair. Verify against
the `tools/cme-sim.py` reference simulator.

**Spec ref:** ch03 §3.1

**Depends on:** H12

**Status:** ☐

---

### H14 · Implement `ec.im` and `ec.om` (DMA path)

**What:** Implement the DMA path to/from ECS in RAM. `ec.im` spills a bank to
the ECID's ECS pointer in DDR3; `ec.om` fills a bank from ECS. Requires a
memory controller path sufficient for synchronous reads/writes.

**Spec ref:** ch03 §3.2, ch17 §17.3

**Depends on:** H13

**Status:** ☐

---

### H15 · Implement the SATP/TLB invalidation rule (D6)

**What:** When `ec.ob` restores SATP (mask bit 6) and the value differs from
the current SATP, invalidate the TLB. The baseline core's TLB-flush mechanism
is the integration point. The rule is normative per charter §6.8 (D6
resolution, v0.19).

**Spec ref:** charter §6.8, ch03 §3.1 "TLB Invalidation on SATP Restore"

**Depends on:** H13

**Status:** ☐

---

### H16 · Implement the remaining CME instructions

**What:** Implement: `ec.ig` (assign bank), `ec.og` (release bank), `ec.it`
(delegate bank to child), `ec.ot` (revoke resources), `ec.ir` (allocate child
ECID), `ec.oe` (forced destroy). `ec.iv`/`ec.ov` may be decode-only stubs
(encryption algorithm is implementation-defined).

**Spec ref:** ch03 §3.3–§3.6

**Depends on:** H10, H13

**Status:** ☐

---

### H17 · Implement the CME CSRs

**What:** Add all CME CSRs defined in ch13: `current_ecid` (0xFC0),
`cme_ec_table_base` (0x7C0), `cme_del_cap` (0xFC1), `cme_bank_count`
(0xFC2), `cme_status` (0xFC3), `cme_reg_mask` (0xFC4), `cme_seal_key`
(0x7C3), `ce_ctrl` (0x7D0), `cme_priv_ctl` (0x7CF), `current_ecid_level`
(0xFD1), `current_ecid_parent` (0xFD2).

**Spec ref:** ch13 §3, ch14 §14.2–§14.5

**Depends on:** H10, H16

**Status:** ☐

---

## Phase 4 — CPE / MSE / QoS additions

### H18 · CPE: cache partitioning

**What:** Implement per-ECID cache-way partition masks for L1 D-cache, L1
I-cache, and L2 (if present). Requires modifying the baseline core's cache
subsystem. Substantial work; scope depends on the chosen baseline core.

**Spec ref:** ch07

**Depends on:** H17

**Status:** ☐

---

### H19 · MSE: memory scheduling

**What:** Implement the memory arbiter and MSE contract enforcement.
Requires modifying or replacing the baseline core's memory controller path
to support per-ECID bandwidth and latency classes.

**Spec ref:** ch09

**Depends on:** H17

**Status:** ☐

---

### H20 · QoS: I/O quality of service

**What:** Implement QoS contract enforcement at the NoC, DMA, and peripheral
interfaces. Scope depends heavily on what the baseline core's peripheral
subsystem looks like.

**Spec ref:** ch11

**Depends on:** H17

**Status:** ☐

---

## Phase 5 — Verification

### H21 · Cosimulation harness

**What:** Build a harness that drives RTL and `tools/cme-sim.py` from the
same instruction stream and verifies architectural-state equivalence at each
step. This is the primary RTL correctness check.

**Depends on:** H13 (at minimum; extend for H14–H20 as each lands)

**Status:** ☐

---

### H22 · Run Sail litmus tests against RTL

**What:** Run the litmus tests produced in Sail Phase 10 (S35–S36) against
the RTL. Each test that passes Sail must pass RTL. Any divergence is a bug
in the RTL (or, rarely, a new Sail gap to file).

**Depends on:** H21, Sail S35–S36

**Status:** ☐

---

### H23 · Integration test suite

**What:** Run a small set of integration tests: boot a minimal kernel, switch
contexts with `ec.ib`/`ec.ob`, exercise CPE/MSE/QoS contracts. End-to-end
demonstration that the CE Suite works as an integrated system.

**Depends on:** H18, H19, H20, H22

**Status:** ☐

---

## Phase 6 — Board bring-up and demonstration

### H24 · Stable bitstream for the PA200T-StarLite

**What:** Produce a stable bitstream for the PA200T-StarLite. Document the
timing closure achieved, the resource usage (LUTs, FFs, BRAMs, DSPs), and
any board-specific constraints.

**Depends on:** H23

**Status:** ☐

---

### H25 · Demonstration application (optional)

**What:** Optionally: write a demonstration application that exercises the
CE Suite's value proposition (e.g. a bounded-WCET context-switch
microbenchmark) and publish the result. This is informative evidence for
the RISC-V ratification process.

**Depends on:** H24

**Status:** ☐

---

## Status conventions

  ☐ — open, not yet started
  ◐ — in progress
  ✓ — done

Update status fields as work proceeds. Mark blocking dependencies explicitly
when an item cannot proceed until another is done.

---

## Priority order

| # | Item | Phase | Depends on |
|---|------|-------|------------|
| 1 | **H1** — Charter frozen | 0 | — |
| 2 | **H2** — Chapters reviewed | 0 | H1 |
| 3 | **H3** — Sail Phase 12 complete | 0 | Sail S26–S38 |
| 4 | **H4** — Language decision | 1 | H1 |
| 5 | **H5** — Vivado toolchain | 1 | H4 |
| 6 | **H6** — Source-control conventions | 1 | H4, H5 |
| 7 | **H7** — Baseline core selection | 2 | H4 |
| 8 | **H8** — Core bring-up on Artix-7 | 2 | H5, H7 |
| 9 | **H9** — UART / hello world | 2 | H8 |
| 10 | **H10** — EC array | 3 | H8 |
| 11 | **H11** — Staging banks | 3 | H10 |
| 12 | **H12** — Copy engine | 3 | H11 |
| 13 | **H13** — ec.ib / ec.ob | 3 | H12 |
| 14 | **H14** — ec.im / ec.om | 3 | H13 |
| 15 | **H15** — SATP/TLB invalidation | 3 | H13 |
| 16 | **H16** — Remaining CME instructions | 3 | H10, H13 |
| 17 | **H17** — CME CSRs | 3 | H10, H16 |
| 18 | **H18** — CPE | 4 | H17 |
| 19 | **H19** — MSE | 4 | H17 |
| 20 | **H20** — QoS | 4 | H17 |
| 21 | **H21** — Cosimulation harness | 5 | H13 |
| 22 | **H22** — Sail litmus tests | 5 | H21, Sail S35–S36 |
| 23 | **H23** — Integration tests | 5 | H18–H20, H22 |
| 24 | **H24** — Stable bitstream | 6 | H23 |
| 25 | **H25** — Demonstration app | 6 | H24 |

---

## When work begins

Before starting Phase 1, create `hw/CLAUDE.md` as the sub-project bootstrap
file (pattern: same as `sail/CLAUDE.md`). The bootstrap should reference this
work-items file as the authoritative plan.

---

*End of hw/ Work Items.*
