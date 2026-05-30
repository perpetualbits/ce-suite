<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite — Future Directions

**Purpose:** Rescue good ideas from chat history and scratchpads before they evaporate.
Nothing here is normative. Items are classified by disposition so authors know how to
treat them when they come back up.

Dispositions:
- **Normative candidate** — strong enough to become a spec section; needs design work, not just agreement.
- **Future extension** — out of scope for CE v1 but natural follow-on.
- **Research note** — requires simulation, measurement, or formal proof before any decision.
- **Rejected-deferred** — discussed and set aside with a reason; don't re-open without new evidence.
- **Needs threat model** — security or isolation claim that can't be evaluated without a formal model.
- **Needs simulation** — timing, bandwidth, or capacity claim that needs hardware modeling.
- **Needs Linux feasibility check** — OS integration consequence not yet traced through the kernel.

---

## 1. Capability Profiles (Normative candidate)

**Idea:** Define named implementation profiles (e.g., "Minimal RT", "Full Virtualization",
"Embedded") that specify which CE extensions and which delegation depths are required or
optional. A profile is a compact capability declaration that firmware advertises via a CSR
or device-tree property.

**Why it matters:** Currently, OS and hypervisor code must probe each extension individually.
Profiles would let firmware say "this hart supports Full Virtualization" and let software skip
the probe loop. Profiles also give certification bodies a stable target.

**Open questions:** Who governs the profile namespace? How do profiles compose (can a hart
implement "Minimal RT + Vault" as a profile)? How does a profile interact with partial
implementations (all extensions present but D=1 instead of D=3)?

---

## 2. CLIC Integration (Normative candidate)

**Idea:** When RISC-V CLIC (Core-Local Interrupt Controller) is present, interrupt preemption
should respect ECID boundaries. Specifically: a high-priority interrupt handler that runs as
a separate EC (its own ECID, its own Bank) should be able to preempt a lower-priority task
without invalidating the lower-priority task's cache partition, MSE Contract, or Bank state.

**Why it matters:** For hard real-time, the interrupt latency guarantee is only meaningful
if the interrupt handler has its own CE resources. Without this, the interrupt handler and
the preempted task share a cache partition, which breaks the isolation guarantee.

**Open questions:** Does the interrupt ECID need its own Bank, or is the preemption
save/restore fast enough without a Bank? How does CLIC's preemption state stack interact
with the CE delegation tree? Is the interrupt ECID a sibling or child of the preempted ECID?

---

## 3. Vector-in-Flight State (Future extension)

**Idea:** When a long-latency vector operation (e.g., a 256-element scatter-gather) is in
flight and a context switch occurs, the architectural state includes partially-committed
vector results. The current VMT bank captures the vector register file, but not in-flight
pipeline state.

**Why it matters:** A correct implementation must either drain in-flight vector ops before
`ec.ib`, or include the in-flight state in the Bank. Draining adds latency. Neither ch02
nor the Bank layout describes what happens.

**Disposition:** Future extension — likely needs a new Bank type or a drain-on-switch
mandatory rule. Needs simulation to quantify the latency cost of drain-vs-bank.

---

## 4. Shadow Register Sets (Research note)

**Idea:** Some embedded RISC-V implementations use shadow register banks (a second GPR
file that becomes active on interrupt entry). CE Banks overlap conceptually with shadow
register sets. There may be a unified design where a CE Bank *is* a shadow register set,
making interrupt preemption and context switch the same hardware mechanism.

**Why it matters:** Would reduce hardware area compared to maintaining two separate
mechanisms. Would also simplify the CLIC integration (item 2 above).

**Status:** Research note. Needs hardware feasibility work. The interaction with FPR and
VEC save/restore is unclear — shadow GPR sets typically don't cover FPRs.

---

## 5. Dirty / Lazy Tracking for Banks (Normative candidate)

**Idea:** The register mask passed to `ec.ib` / `ec.ob` selects which register groups to
save/restore. A complementary mechanism would let hardware track which groups are "dirty"
(written since last save) so that a full-mask `ec.ib` can skip groups that haven't changed.

**Why it matters:** Reduces context-switch overhead for contexts that only use GPRs (e.g.,
a simple interrupt handler that never touches FPRs). Equivalent to the FPR dirty-bit trick
used by Linux for FPU context switch.

**Open questions:** Does the dirty bit live in the Bank, in EC[e], or in a new CSR? What
is the granularity — per group, or per register? How does the dirty bit interact with
`ec.im` (DMA spill)?

---

## 6. Bank Exhaustion Protocol (Normative candidate)

**Idea:** When all Banks on a hart are in use and `ec.ig` or `ec.ob` needs a new Bank, the
hardware must either block (unacceptable for real-time), return an error, or trigger a
software handler that spills a Bank to RAM first. The spec currently leaves this implicit.

**Why it matters:** A real implementation needs a defined protocol. Options include:
a "Bank steal" interrupt (hardware selects a victim Bank, issues an NMI to the OS, which
spills and frees it); or a pure error path (hardware returns `CME_ERR_NO_BANK`; software
must call `ec.im` before retrying). The choice affects real-time latency guarantees.

**Disposition:** Normative candidate. Charter §8.3 defers Bank exhaustion; this is the
design work needed to resolve it.

---

## 7. Minimal Embedded Profile (Future extension)

**Idea:** A stripped-down CE profile for deeply embedded systems (RISC-V E extension,
≤8 KB SRAM): no VMT banks, no delegation (D=0), no vault, MSE and QoS optional. The
profile guarantees that CE can be implemented in a few hundred gates.

**Why it matters:** CE is designed for server-class and embedded use alike, but the
current spec implicitly assumes a relatively resource-rich implementation. An embedded
profile would let small MCU vendors adopt CE without the full hardware cost.

**Disposition:** Future extension. Does not affect v1 normative text. Should be tracked
in a future appendix once the v1 baseline is stable.

---

## 8. Nested Virtualization CSRs (Normative candidate)

**Idea:** When D=3 (four-level delegation: host kernel, hypervisor, nested hypervisor,
guest), software needs to discover the current delegation level and parent ECID without
issuing a full EC[e] table lookup. A new per-hart CSR `current_ecid_level` (RO) and
`current_ecid_parent` (RO) would expose this directly.

**Why it matters:** A nested hypervisor needs to know its own delegation level to decide
whether it can further delegate to guests. Currently this requires an EC table read.
A CSR read is much cheaper.

**Open questions:** Are these covered by existing `EC[e].delegation_L` accessibility?
If the current EC can read its own EC entry, this is already possible; the CSR is just
a cache of that information.

---

## 9. Hart Migration Automation (Normative candidate)

**Idea:** Currently, chapter 9 (§0.2 of ch00) states that ECID migration across harts
requires the kernel to unbind the source ECID and allocate a fresh one on the destination.
CPE state and MSE Contracts must be re-issued. This is expensive. A future extension
could define a hart-migration descriptor and a `ec.imig` instruction that packages all
state into a transferable form.

**Why it matters:** Live migration of vCPUs across harts is a common operation in cloud
workloads. If CE state adds O(N) re-configuration instructions to each migration, CE
becomes a performance liability for cloud hypervisors.

**Disposition:** Future extension — significant; likely needs new instruction encoding
and possibly a shared memory format for migration packets.

---

## 10. NUMA Awareness (Research note)

**Idea:** On NUMA systems, an MSE Contract allocates memory bandwidth on a specific
memory node. If a task migrates to a hart on a different NUMA node, the Contract's
bandwidth guarantee may not hold (different node, different controller). The spec is
silent on this.

**Why it matters:** For real-time workloads with NUMA hardware, the MSE Contract must
either be node-local or must express a cross-node aggregate. Neither is currently
specified.

**Disposition:** Research note. Needs hardware topology modeling. May require a
node-affinity field in MSE Contracts.

---

## 11. Compressed / Sparse Banks (Research note)

**Idea:** On register-sparse workloads (e.g., a simple interrupt handler that only uses
x1–x7 and no FPRs), the 1 KB Bank is mostly wasted space. A compressed Bank format
could encode only live registers, reducing SRAM usage significantly.

**Why it matters:** Bank SRAM is expensive. For systems with many ECIDs, the total Bank
SRAM cost could be reduced substantially with compression.

**Disposition:** Research note. Needs hardware feasibility and latency analysis. The save
path for a variable-format bank is more complex than for a fixed-format bank.

---

## 12. Speculative Preload (`ec.ob` variants) (Normative candidate)

**Idea:** Add a non-committing variant of `ec.ob` that begins filling a Bank from the
ECS in RAM speculatively, without committing to the context switch. If the switch is
later cancelled (e.g., the scheduler picks a different task), the speculative fill is
discarded. Equivalent to a prefetch for context state.

**Why it matters:** Context switch latency is dominated by the DMA fill path (`ec.om`).
If the scheduler can begin the fill while still deciding which task to run, the fill
latency can be hidden behind scheduling computation.

**Disposition:** Normative candidate. The "speculative but cancellable" semantics need
careful definition; there must be no externally visible side effect before commit.

---

## 13. Power Gating Integration (Research note)

**Idea:** When a hart enters a deep sleep state, all Banks must be preserved or spilled
to RAM. The power management firmware should issue `ec.im` for each resident Bank before
gating the hart's SRAM. On wake, `ec.om` fills Banks before the first context runs.

**Why it matters:** Without a defined protocol, firmware may gate SRAM while Banks
contain unsaved state, causing silent data loss.

**Disposition:** Research note. The protocol is straightforward in principle but needs to
be tested against real power management frameworks (ACPI CPPC, RISC-V SBI HSM).

---

## 14. Fine-Grained Security Partitioning (Needs threat model)

**Idea:** CPE partitions cache ways per ECID. An attacker who can observe cache timing
can potentially infer which ways are assigned to a target ECID by measuring access
times to cache lines in different sets. CPE partitioning reduces cross-ECID interference
but may not eliminate timing side-channels entirely.

**Why it matters:** If CPE's isolation guarantee is used for security isolation (not just
real-time isolation), the threat model must address cache timing attacks (Flush+Reload,
Prime+Probe variants that cross way boundaries).

**Disposition:** Needs threat model. The current spec claims isolation for
*real-time determinism*, not security. If security claims are made, a formal threat model
and likely an adversarial timing analysis are required.

---

## 15. Zero-Copy Pipelines Between ECIDs (Future extension)

**Idea:** A zero-copy data pipeline between two ECIDs could share a Bank (or a region
within a Bank) between producer and consumer, with hardware enforcing read/write access
roles. This extends the current Bank model, which enforces exclusive ownership.

**Why it matters:** Shared-memory IPC between enclaves or between a guest and a host
driver is a common pattern. Making this a first-class CE operation would allow
hardware-enforced zero-copy without page table manipulation.

**Disposition:** Future extension. The current EC ownership model (one Group per Bank,
up-pointer for O(1) ownership check) would need to be extended to support shared-read
or read/write role splits.

---

## 16. Linux Scheduler Integration (Needs Linux feasibility check)

**Idea:** Map SCHED_DEADLINE reservation parameters directly onto MSE Contract
bandwidth/latency classes. Specifically: when the scheduler admits a SCHED_DEADLINE
task, it calls `ms.ir` to allocate an MSE Contract matching the declared runtime and
period. If the Contract admission fails (no bandwidth available), the task admission
fails.

**Why it matters:** This closes the loop between the POSIX real-time scheduling API
and hardware-level memory bandwidth reservation. Without it, SCHED_DEADLINE guarantees
are soft (scheduler time-accounting) rather than hard (hardware-enforced).

**Disposition:** Needs Linux feasibility check. The CE admission API is synchronous
(trap to hardware); SCHED_DEADLINE admission currently happens in a spin-lock-protected
scheduler path. The interaction with priority inheritance and bandwidth reclamation
(GRUB algorithm) needs to be traced.

---

## 17. Certification Story (Future extension)

**Idea:** For safety-critical use (automotive ISO 26262, aerospace DO-178C), the CE
Suite needs a safety manual that enumerates failure modes, defines diagnostic coverage
requirements, and specifies which CE instructions are not to be used in safety-relevant
contexts.

**Why it matters:** Hardware certification bodies require a formal safety analysis.
Without it, CE cannot be used in ASIL-D or DAL-A designs regardless of technical quality.

**Disposition:** Future extension (post-v1). Requires cooperation with system integrators
and certification bodies. The spec as written is a prerequisite, not a substitute, for
the safety manual.

---

## 18. No-`rd` Instructions as Missed Opportunities (Normative candidate)

**Idea:** Instructions with no `rd` — currently `ec.ib` (always succeeds or traps) and
`ec.oe` (always succeeds) — discard the return-value slot entirely. Even when an
instruction cannot fail, the `rd` field could carry back useful information:

- `ec.ib` could return the bank ID (or slot index) into which the context was saved.
  Useful for a hypervisor that wants to know *which* bank is now occupied by a saved
  guest, without an extra CSR read.
- `ec.oe` could return a count of resources freed (banks released, Contracts dissolved,
  ECIDs reclaimed). Useful for auditing and capacity accounting without polling separate
  CSRs.
- `ec.ib` could return a generation token for the saved state — a (bank, generation)
  pair that makes the save result addressable for a later targeted restore.

**Why it matters:** In RISC-V, the `rd=x0` convention already provides the discard case
for free. Adding a meaningful return value to these instructions costs nothing in the
encoding and potentially saves software a follow-on CSR read.

**Current state:** `ec.ib` and `ec.oe` have no `rd` because they were defined as
"always-succeed" instructions where failure reporting was the only justification for
`rd`. This reasoning is sound but narrow — it excludes the success-path information case.

**Open questions:** Which bank ID namespace would `ec.ib` return? Is it hart-local? Is
it stable across context switches? What exactly does `ec.oe` count — leaf ECIDs, total
resources, or subtree depth?

**Disposition:** Normative candidate. Revisit when the Bank assignment model is fully
defined. Any change would require bumping the instruction encoding revision.

---

## 19. CPE soft-partition hints (PREFETCH_CLASS, WEIGHT)

**Status:** Future work, not part of v1. Orthogonal to F1's
CPE encoding decision.

**Source:** Surfaced during the salvage analysis of the
alternative CPE encoding proposal (Cluster E discussion,
2026-05-29). The alternative encoding itself was rejected
(see `scratchpads/cpe/2026-05-salvage-cpe.md` for the
rejection rationale and ch07 for the current encoding).
These two hint ideas are independent of the encoding
question.

**The idea:**

Current CPE (ch07) uses strict way-mask partitioning: a
partition either includes a cache way or it does not. This
is correct for hard-real-time and isolation use cases.
But many workloads sit in between — they would benefit
from biased cache behavior without strict isolation. Two
candidate hint mechanisms:

- **PREFETCH_CLASS:** software-supplied hint per ECID about
  the expected prefetch pattern (e.g. streaming, pointer-
  chasing, random). The prefetcher could use this hint to
  bias its aggressiveness, prefetch distance, or
  replacement-policy decisions for lines belonging to that
  ECID. The hint is advisory — hardware may ignore it
  entirely without affecting correctness.

- **WEIGHT:** software-supplied weighting (e.g. 1–16) for
  soft partition pressure. When the cache is over-
  subscribed and the replacement policy has to choose a
  victim, weights bias the selection toward less-weighted
  ECIDs first. This is softer than way-mask partitioning
  (no guarantees) but useful for QoS-like behavior in
  workloads that cannot afford the area cost of full
  partitioning.

**Why future-only:**

Both hints are non-essential for the v1 use cases CE Suite
targets (RT/safety-critical isolation, virtualization
isolation, fairness with hard guarantees). They would
complement those use cases for general-purpose workloads
where strict isolation is wasteful. v1 should ship without
them; a v2 extension can revisit if implementer demand
materializes.

**Implementation sketch:**

Most likely a new CSR (e.g., `cpe_hint`) carrying per-ECID
hint values, with bits assigned to PREFETCH_CLASS and
WEIGHT fields. Probing via `cpe_caps` (an additional
capability bit). No new instructions required; the existing
`cp.ir`/`cp.it` pattern is unaffected.

Reserved-bit policy: existing `cpe_caps` reserved bits in
ch07 §7.7 must accommodate this addition without breaking
prior implementations.

---

*End of Future Directions.*
