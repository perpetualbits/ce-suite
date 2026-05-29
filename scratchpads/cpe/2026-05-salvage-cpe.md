<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Salvaged CPE alternative encoding

**Status:** Scratchpad — non-normative. Salvage material under
review.
**Source:** Distilled from 27 ChatGPT design-discussion chats
conducted between July 2025 and May 2026, summarized in a
review session on 2026-05-29.
**Cluster discussion:** E
**Disposition policy:** Items here exit the scratchpad via one
of three routes — promoted to a `docs/work-items.md` entry,
archived to `docs/future-directions.md`, or rejected with a
one-line note. See `scratchpads/README.md` for the lifecycle.

---

================================================================================
Salvaged CPE ideas
================================================================================

Here is the complete structured overview of how CPE thinking developed, which ideas are still worth keeping, and what survives hardware reality.

---

## CPE — Development of Thought and Hardware Viability

### Phase 1: The Original Problem Statement and Scope Confusion

The first CPE discussion began with a broad question: *what should the bits in rs1 and rs2 be for a cache partition instruction?* The initial assumption was that CPE might cover all levels of cache — L1, L2, L3, even shared system caches — and should map to all known partitioning mechanisms (way masks, cache coloring, class-of-service, address region reservations).

ChatGPT responded with a very rich rs1/rs2 encoding that covered all of those modes (WAY_MASK, COLOR, COS, REGION, RESV) plus a pointer-based Cache Partition Descriptor (CPD) for complex cases. This was technically interesting but too complex.

You then tightened the scope significantly with a key clarification: **CPE is per-hart only, for private caches only, and its purpose is specifically to prevent cache evictions caused by other ECs on the same hart from affecting a hard real-time EC.** L3 (shared across harts) was explicitly declared out of scope for v1. This was the defining moment that gave CPE its identity.

---

### Phase 2: The "Is This Even Necessary?" Question

You raised a genuinely difficult question during this phase: is a private cache partition actually *better* for a hard real-time EC than just having full access to the cache but accepting context-switch misses?

The honest answer reached: **it depends on working set size and reuse distance.** If the real-time EC's working set fits in its partition, the partition eliminates interference entirely. If the working set is larger than the partition, it would have been better off with full cache access. The design correctly leaves this as a runtime decision for the OS and application programmer — CPE gives the OS the knob, not the policy.

A second question: should L1 and L2 be configured together or separately? Your instinct was that a **fixed ratio, coupled allocation** (same fraction of L1 and L2) was simpler to reason about and sanity-check in hardware. This became the COUPLE_L1L2 bit.

---

### Phase 3: The Real-World Existence Check

A critical discovery: cache partitioning is not a new idea and has real industrial precedents:

**Intel Cache Allocation Technology (CAT) / Memory Bandwidth Allocation (MBA)**: partitions L3 cache ways per class of service (COS), controlled via MSR writes. Used in cloud environments to isolate tenant workloads.

**ARM MPAM (Memory Partitioning and Monitoring)**: ARM's v8.4+ answer to Intel CAT/MBA. Partitions cache capacity and memory bandwidth by PARTID (partition ID), which is carried in the transaction stream. Already deployed in server-class ARM cores.

**Way locking**: older mechanism present in some embedded processors (MIPS, some ARM Cortex-R cores) where specific cache ways are locked and cannot be evicted. Used in automotive/safety-critical RTOS contexts.

**OS cache coloring**: a software-only technique where the OS arranges physical page allocation so different processes land on different cache sets. Much weaker than hardware partitioning — it is a hint, not a guarantee.

**RISC-V status**: as of the chat date (2025), no standard RISC-V extension for cache partitioning exists. Some implementations provide custom CSRs for way locking but nothing architecturally standard. This is explicitly a gap that CPE would fill.

---

### Phase 4: The TLB Invalidation Interaction (a CPE-Adjacent Insight)

This came out of the FPGA Board Design chat but is architecturally important for CPE. The observation: CME's 1-cycle context switch is so fast that there is no software window between save and restore to flush caches or shoot down TLBs. This creates two problems that CPE must address:

**Problem 1 — Cache warm state after switch:** When ec.ob restores a new context, the L1/L2 caches still contain data from the previous context. The new context immediately experiences cold misses. For best-effort workloads this is acceptable. For real-time it is a latency spike. CPE addresses this: if the real-time context has a reserved partition, *its lines are never evicted by anyone else*, so when it gets switched back in, its hot cache lines are still there. This is the killer use case for CPE.

**Problem 2 — TLB stale translations:** If the ec.ob restores a new SATP (different address space), the hardware TLB must be flushed or the old translations will corrupt the new context's memory accesses. The agreed solution: hardware automatically performs an sfence.vma-equivalent when ec.ob restores a new SATP value. Implementations may optimize by tracking whether SATP actually changed and skipping the flush if it didn't (ASID-based optimization).

---

### Phase 5: The Instruction Design — What Survived

The final instruction encoding design (Chapter 7 draft) settled on:

**Two instructions:** `cp.ip` (cache partition in — assign) and `cp.op` (cache partition out — revoke). This matches the ec.{i,o}b naming pattern.

**rs1 encodes:** ECID (16 bits), LEVEL_SEL (Auto/L1-only/L2-only), COUPLE_L1L2 flag, MODE (WAY_MASK or PERCENT), INLINE flag, LOCK_EN flag, INSTR_DATA_SEL (both L1I+L1D or data-only), PREFETCH_CLASS hint, QoS WEIGHT hint, OPC (ASSIGN/MODIFY/REVOKE/QUERY), VERSION.

**rs2 encodes (if INLINE=1):** either explicit way masks (separate fields for L2, L1D, L1I) or percentage values (percentage × 256, for each level). If INLINE=0, rs2 is a pointer to a CPD (Cache Partition Descriptor) struct in memory for complex configurations.

**Key validity rules (hardware enforced):** masks for different ECIDs at the same level must be disjoint; if COUPLE_L1L2=1, the allocated fraction must match across L1 and L2 within ±1 way; LOCK_EN cannot lock more ways than were assigned; ASSIGN may need to clean/evict prior lines from victim ways (BUSY_TRY_AGAIN status if this takes time); REVOKE must writeback and invalidate.

**Status reporting** via rd or a CPE status CSR: OK, UNSUPPORTED_LEVEL, INVALID_MASK, COUPLE_MISMATCH, INSUFFICIENT_WAYS, PERMISSION_DENIED, BUSY_TRY_AGAIN.

---

### What Survives Hard Hardware Reality

**Definitely viable:**

The way-mask approach (MODE=WAY_MASK) is exactly what Intel CAT and ARM MPAM do at the hardware level. Implementing per-ECID way masks in the cache replacement logic requires: a small SRAM or register array storing the way-mask per ECID (or per currently-active ECID — like an N-deep CAM indexed by ECID), and a modification to the replacement policy logic that checks the mask before evicting a candidate line. This is O(1) at eviction time. Well-understood, proven in silicon.

The COUPLE_L1L2 flag and the PERCENT mode are nice ergonomic additions that translate to way masks internally. Hardware converts percent to a valid way count before storing. No exotic mechanisms needed.

The INLINE vs. CPD-pointer split is a clean encoding: the fast path (simple way mask or percentage, fits in 64 bits) stays in-register; the complex path (multi-level, mixed modes) uses a memory-resident descriptor. This is the same pattern used in Intel's RDTSC/CAT MSR interface.

The LOCK_EN flag (locking a minimum number of ways so they cannot be evicted even under pressure) is equivalent to ARM Cortex-R's "way locking" feature, which has existed in safety-critical embedded processors for years. Implementable as a "locked" bit in each cache way's tag, checked before any eviction decision.

**Interesting but needs more work:**

The PREFETCH_CLASS and WEIGHT hints. These are soft QoS hints, not hard guarantees. They interact with the prefetcher and fill priority logic in ways that are implementation-specific. Useful to include in the spec as optional hints but not part of the mandatory compliance surface.

The QUERY operation (OPC=QUERY). This lets software ask "what is ECID X's current partition?" Very useful for the OS to audit state without walking a software table. Implementable as a read path on the ECID's cached partition entry. Straightforward.

**Needs care:**

Sharing CPE partition state across context migrations (when an ECID migrates from one hart to another). CPE is per-hart, so if the OS moves a real-time thread to a different hart, it must re-issue cp.ip on the new hart. This is mentioned in Chapter 7 as "OS must reapply CPE settings on migration." True but important — the OS must save the CPE config in its ECS and replay it on the new hart before scheduling the EC there.

The ASSIGN/REVOKE atomicity: if ASSIGN requires evicting another context's lines from the target ways, it takes variable time (BUSY_TRY_AGAIN). This is fine for non-real-time paths (only the privileged OS calls ASSIGN/REVOKE) but needs a clear spec on whether the caller blocks or polls.

**Left out of v1 correctly:**

L3 cache partitioning. L3 is shared across harts and requires a system-level arbiter (like ARM MPAM's hierarchical partitioning with PARTID carried in the bus protocol). This is a different, larger problem — it belongs in a CPE-S (shared) extension or in a QoS layer sitting above CPE. The decision to exclude it from v1 was correct and keeps CPE tractable.

Software cache coloring. This was acknowledged as a real and useful technique but explicitly not what CPE is — CPE provides *hardware enforcement*, which software coloring cannot guarantee.

---

### Summary: The Clean Core of CPE

CPE's essential value proposition, distilled: **a hard real-time EC on a hart can reserve a set of cache ways in its private L1/L2. Those ways are never evicted by any other EC. When CME switches the hard real-time EC back in, its working set is still hot.** The 1-cycle context switch of CME and the persistent partition of CPE together eliminate two of the three classical sources of real-time latency jitter: context save/restore time and cache cold-start time. The third (TLB stale translation) is handled by the automatic sfence.vma-on-SATP-change rule in CME.

All of this is implementable with known techniques (way masks, locked ways, per-ECID replacement policy bits), and has clear precedent in Intel CAT and ARM MPAM. The RISC-V gap is real — nothing standardizes this today — and CPE fills it cleanly.
