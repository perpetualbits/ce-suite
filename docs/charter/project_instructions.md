<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite — Project Instructions and Axiom Charter

**Version:** 0.23
**Status:** Normative for the CE Suite specification.
**Scope:** All CE Suite chapters, appendices, and supporting documents.

---

## 0. How to use this document

This charter, together with **Chapter 0 — Fundamental Structure**, is the normative
spine of the CE Suite. Every other chapter is derivative and must be made consistent
with it.

If a chapter conflicts with this charter or with Chapter 0, the chapter is wrong
and must be refactored. Decisions about the model are made *here* first, then
propagated to Chapter 0 if they affect structure, and then to derivative chapters.

This document is the **comb**: when a chapter (or a future writing session) drifts,
read this first, then Chapter 0, then refactor the drifting chapter.

A companion document, **Working Notes for Authors**, holds workflow rules and
warnings about common drift patterns. Workflow guidance does not belong here.

---

## 1. What the CE Suite is

The **Context Extensions (CE) suite** is a set of five coordinated RISC-V
extensions that together deliver hardware-guaranteed determinism for shared
SoCs — without sacrificing throughput on average-case workloads.

The five extensions are:

1. **CME — Context Management Extension.** Hardware-resident context banks
   per hart; sub-10-cycle save/restore via staging banks and a copy engine;
   delegation and revocation of banks to child execution contexts.
2. **CPE — Cache Partitioning Extension.** Per-hart partitioning of L1 and
   L2-private caches per ECID. (L3 is out of scope for v1.)
3. **MSE — Memory Scheduling Extension.** Deterministic DRAM arbitration
   with alternating best-effort and contract time slots, per-EC bandwidth and
   latency classes, and per-group caps.
4. **QoS — I/O Quality-of-Service Extension.** The same arbitration philosophy
   as MSE, applied to the NoC, DMA, and peripheral interconnect.
5. **The ECID and Group/Contract substrate.** The identity and ownership layer
   that all four extensions hang off. Not a separately-numbered extension; it
   is the shared foundation defined in Chapter 0.

The target outcome: provable Worst-Case Execution Time, certifiability for
ASIL D / FDA Class III / DO-178C, 1–2 cycle context switches, and bounded
memory- and I/O-access latency, at an estimated 5–15% transistor overhead
per core (stratified by deployment class in Appendix C §C.4).

---

## 2. Glossary (normative)

These terms have exactly these meanings throughout the spec. Authors must not
introduce synonyms or redefine them.

| Term | Definition |
|---|---|
| **EC** | *Execution Context.* Any schedulable unit: thread, process, vCPU, container task, interrupt handler, secure enclave. The unit the OS scheduler dispatches. |
| **ECID** | *Execution Context Identifier.* A hart-local, hardware-managed identity token denoting one EC currently bound to that hart. Opaque to software running as that EC. |
| **`current_ecid`** | The ECID of the EC currently executing on a hart. Held in a CSR. |
| **`EC[e]`** | The architectural per-hart ECID entry indexed by ECID number `e`. See §3.2. |
| **ECS** | *Execution Context Structure.* A memory-resident structure describing the saved/saveable state of one EC. Reachable via `EC[e].ecs_ptr`. |
| **Group** | An ECID's inventory of resources (banks, contracts, child ECIDs). Every ECID has exactly one Group; GroupID = ECID number. |
| **Bank** | A hardware register-state container (non-VMT or VMT) owned by exactly one Group. |
| **Contract** | A slice of a global, multiplexed resource (memory bandwidth/latency for MSE, I/O bandwidth/latency for QoS) bound to an ECID's Group. |
| **Delegation level (L)** | An ECID's depth in the delegation tree, 0 ≤ L ≤ D. `L < D` permits delegation; `L = D` does not. |
| **Generation counter** | A small counter per `EC[e]` slot, incremented on every reuse of the slot, used to detect stale references (ABA safety). |
| **Hart** | Standard RISC-V hardware thread. CE state is per-hart. |
| **Privileged actor** | M-mode firmware, S-mode kernel, or HS-mode hypervisor. The only actors permitted to create or destroy ECIDs. |

### 2.1 Retired terms

The following terms appeared in earlier drafts and are **retired**. They must
not appear in current specification text. If you encounter them in a draft,
refactor.

- **Pool** — Subsumed into *Contract*. Earlier drafts placed a Pool layer
  between ECIDs and Contracts; this layer was redundant because every Pool
  was always bound to exactly one Contract. Contracts now hold their member
  ECIDs directly.
- **EECID / EECIDG** — Earlier names for "ECID + hart_id" or
  "ECID + hart_id + generation" tuples. Replaced by saying "ECID" (hart-local)
  and explicitly naming `hart_id` and the generation counter when needed.
- **CPE pool, CME pool** — Pooling was rejected for per-hart resources.
  Bank and cache-partition assignment is always explicit and kernel-driven.
- **Resource-attached flag** — Replaced by the presence or absence of a
  Contract binding in `EC[e]`.
- **`ec.or`** — Renamed to `ec.od` (v0.7), then to `ec.oe` (v0.8, see §6.5).
  The original mnemonic is retired to avoid visual collision with boolean
  operations.
- **`ec.od`** — Renamed to `ec.oe` (see §6.5, v0.8). The trailing letter
  `d`=destroy was the one exception to the rule that trailing letters name
  target objects or kinds; `e`=existence restores full consistency.

---

## 3. ECID identity and the EC array

> *"I am my ECID number in hardware, and I become useful via a pointer to
> my structures in memory."*

### 3.1 ECID properties

1. **Hart-local.** ECIDs are unique per hart at a given moment. The
   system-wide identity of a running EC is the tuple `(hart_id, ECID)`.
   No hardware mechanism ever uses a global ECID namespace.
2. **Opaque to software running as that EC.** A process cannot read or write
   its own ECID. The OS may know it, but a CE-managed EC cannot forge or
   change its own identity.
3. **Privileged creation only.** Only the kernel, hypervisor, or secure
   firmware may create or destroy ECIDs. User mode never. When CE is
   enabled at boot, M-mode firmware creates the first ECID and hands it
   to the kernel; thereafter the kernel (and any delegated hypervisor)
   owns ECID creation. CE may also be disabled or ignored; see §3.7.
4. **No migration of ECIDs across harts.** When an EC moves between harts,
   the kernel unbinds the source-hart ECID and allocates a fresh ECID on
   the destination hart, reusing the same ECS. Migration is therefore
   "rebinding," never literal ECID movement.
5. **Reuse requires generation-counter increment.** When an ECID slot is
   freed and later reallocated, its generation counter must be incremented.
   Any reference held by software to a `(hart_id, ECID, generation)` triple
   becomes stale and must be detected as such.

### 3.2 The `EC[e]` array

Each hart has a conceptual array `EC[0..E_max]` indexed by ECID number.
`EC[e]` is the canonical descriptor of ECID `e` on that hart. At minimum:

```c
struct EC_entry {
    void    *ecs_ptr;        // canonical pointer to ECS in RAM (offset 0)
    uint8_t  generation;     // incremented on slot reuse
    uint8_t  delegation_L;   // delegation level, 0..D
    uint16_t parent_ecid;    // parent in the delegation tree
    // implementation-defined: cached bank/contract refs, flags, etc.
};
```

The `ecs_ptr` field **must** be at offset 0. This makes the architectural
indexing trivial and lets the most common access — fetching the ECS
pointer for a given ECID — be a single load.

Implementations may add fields, cache, mirror, or split this entry across
SRAM and RAM. The **architectural model** is "array indexed by ECID, ECS
pointer at offset 0."

### 3.3 The `cme_ec_table_base` CSR

Each hart has a CSR `cme_ec_table_base` and an implementation-defined fixed
`stride`. Architecturally:

```text
entry_addr(e) = cme_ec_table_base + e * stride
ecs_ptr(e)    = *(entry_addr(e))           // because ecs_ptr is at offset 0
```

### 3.4 SRAM-vs-RAM residency

`EC[e]` is **conceptually** RAM-resident. Implementations are expected to
keep a small number of active entries in SRAM (typically the entries for
ECIDs currently runnable on that hart) and fall back to the RAM-resident
table otherwise. CME's fast path (`ec.ib`, `ec.ob`) touches only SRAM-resident
state; the DMA path (`ec.im`, `ec.om`) may walk the RAM-resident table.

### 3.5 ECID allocation: radix tree

ECID numbers are allocated by the privileged actor that owns the parent
ECID, using a **radix tree** keyed by ECID number (treated as
`prefix || index`). Each tree node represents an ECID prefix owned by a
tenant or privileged context.

- **Prefix ownership.** A tenant owns an entire subtree of the radix
  tree; allocations within a prefix are local and do not require global
  coordination.
- **Quotas per prefix.** Privileged actors may set per-prefix quotas on
  "resourced" ECIDs (those holding Contracts or Banks) to prevent
  exhaustion. Unresourced ECIDs are limited only by RAM.
- **Forced revocation.** Destroying an ECID destroys every descendant in
  its subtree. The tree walk is O(log N) on average.

The radix tree is a kernel data structure in RAM. The `EC[e]` array is
the architectural view; the radix tree is the kernel's allocation backing
store. The two are not in conflict — `EC[e]` indexes into entries that
the radix tree also references.

### 3.6 ECID width

ECID numbers are **16 bits** at the architectural level (allowing 65,536
ECIDs per hart, of which only the resourced ones consume SRAM). RV32 and
RV64 implementations share this width.

The 16-bit width is partitioned as `prefix || index` by software
convention; hardware treats it as an opaque integer.

#### Relationship to OS process identifiers

ECIDs and OS-level identifiers (PIDs, TIDs, task IDs) are different
concepts with no required 1:1 mapping. An OS-level identifier (PID,
22 bits on default Linux configurations, sometimes more) names a
long-lived OS abstraction — a process or thread tracked in the kernel's
task table, possibly suspended, possibly a zombie, possibly checkpointed
to disk.

An ECID, by contrast, names a context **currently bound to a specific
hart**. Most OS-level tasks at most moments are *not* hart-bound — they
are runnable but not running, or blocked on I/O. A task acquires an
ECID at the moment it is dispatched to a hart and releases it when
switched out.

The OS therefore multiplexes many PIDs through a small number of ECIDs,
the same way it multiplexes many PIDs through a small number of harts.
16 bits per hart × N harts provides ample headroom: on a 256-hart server,
that is 16 million simultaneously-hart-bound contexts, well past anything
modern operating systems run concurrently.

### 3.7 Disable and ignore semantics

CE is opt-in at every level.

1. **Firmware disable.** M-mode firmware controls CE availability
   through the `ce_ctrl` CSR (address 0x7D0, M-mode RW). Each of the
   four extensions has an independent enable bit:

   | Bit | Field | Description |
   |-----|-------|-------------|
   | 0 | `CME_EN` | 1 = CME enabled |
   | 1 | `CPE_EN` | 1 = CPE enabled |
   | 2 | `MSE_EN` | 1 = MSE enabled |
   | 3 | `QOS_EN` | 1 = QoS enabled |
   | XLEN−1:4 | — | WIRI |

   Reset value: 0x0 (all extensions disabled). Firmware explicitly
   enables whichever extensions are required. When a bit is 0, all
   instructions for that extension trap as illegal and all CSRs for
   that extension read as 0. If hardware for an extension is absent,
   the corresponding bit is RO 0 — software cannot enable what is not
   implemented. Extensions may be enabled and disabled independently;
   there is no required ordering.

2. **Privileged ignore.** Even when CE is enabled in firmware, any
   privilege level may choose to ignore it. An OS or hypervisor may
   run an entirely conventional kernel and userspace without using
   any CE instructions or features. The hardware imposes no
   obligation to use CE.
3. **Boot when enabled.** When CE is enabled at boot, M-mode firmware
   creates the first ECID and hands it to the kernel. The kernel
   either uses it (and may delegate further) or, per (2), may ignore
   it. Either is conforming behavior.

This disable/ignore property applies uniformly across all five
extensions: CME, CPE, MSE, QoS, and the ECID substrate.

---

## 4. Groups, Banks, Contracts

Full byte-level layouts are in Chapter 0. This section fixes the
**relationships** that all chapters must respect.

### 4.1 Group is inventory

1. Every ECID `e` has exactly **one** Group, with **GroupID = ECID = e**.
   The Group is the ECID's inventory of resources.
2. Resources (Banks, Contracts, child ECIDs) carry **up-pointers** into
   their Group. Groups do not maintain explicit downward member lists.
   This is the "reversal trick" that makes hardware enforcement O(1):
   any resource knows its owner; ownership is checked at the resource, not
   walked from the Group.
3. A child Group is delegated to a child ECID and appears to the child
   as that child's Group 0.

### 4.2 Banks

1. A Bank is a hardware register-state container, either non-VMT or VMT.
2. Non-VMT banks are 1 KB on RV64, 512 B on RV32, holding GPRs, FPRs,
   selected CSRs, SATP, and CP. Exact layout in Chapter 0.
3. VMT banks hold vector/matrix/tensor register files. Size scales with
   the implementation's vector width.
4. A Bank stores its owning Group ID (= owning ECID). Implementations may
   additionally cache delegation level and dirty/lock flags.
5. Banks are never shared between ECIDs simultaneously.

### 4.3 Contracts

#### §4.3.0 — Contract: object model

**Definition.** A Contract is a privileged-actor-created binding of a slice of a
global multiplexed resource to one owning ECID's Group, tracked by hardware for
the duration of the binding.

**Identity.** A Contract is identified by the tuple `(owning_ECID, resource_class)`,
where `resource_class` is one of:

- `MSE` — DRAM bandwidth and latency.
- `QoS(domain_id)` — I/O fabric bandwidth and latency, per domain.
- `CPE` — private cache way allocation.

There is no separately allocated Contract ID. Contracts are addressed solely via
their owning ECID and resource class. An ECID may simultaneously own at most one
MSE Contract, at most one CPE Contract, and one QoS Contract per `domain_id`.

**State.** A Contract's state occupies two locations:

- **Parameters** — the resource-class-specific fields (`bw_class`, `lat_class`,
  `l1_way_mask`, `l2_way_mask`, etc.) are stored in the owning ECID's Bank, in
  the CP field defined by Chapter 0 §0.6. They are loaded atomically into
  per-hart hardware registers by `ec.ob` on context switch.
- **Admission-control state** — running sums, group caps, and the existence
  record of the binding live in implementation-defined per-controller or per-hart
  SRAM, keyed by ECID. The exact placement is not architectural; the
  architectural requirement is that admission decisions are atomic and chip-global
  (§4.3.3).

**Lifecycle.** A Contract is created by a privileged actor executing one of
`ms.ir`, `qs.ir`, `cp.ir` (assignment from the privileged actor's own resources)
or `ms.it`, `qs.it`, `cp.it` (delegation from a parent Contract). The Contract
exists from the successful completion of that instruction until the matching
`*.or`/`*.ot` or the forced destruction of its owning ECID via `ec.oe`. Failed
creation leaves no Contract behind (§4.3.3).

**Creation parameters vs. Contract object.** The `rs2` operand of `*.ir` and
`*.it` instructions carries the *creation parameters* for a new Contract. The
Contract itself is the binding that results from successful execution; it is not
the parameters. The per-extension chapters specify the parameter encoding (§6.1
names the instructions; Chapter 7 §7.4, Chapter 9 §9.4, Chapter 11 §11.5 specify
the parameters).

**What this section does not specify.** No Contract ID namespace (ECID + class
suffices). No unified `Contract_descriptor` struct shape (the three resource
classes have legitimately different storage needs; forcing uniformity would
constrain implementations without benefit). No specific hardware layout for
admission-control SRAM (implementation choice).

#### §4.3.1 — Single ownership

A Contract has exactly one owning ECID's Group at any moment.

#### §4.3.2 — Hierarchical splitting

A privileged actor may split a Contract into child Contracts. Each child is a
strict subset of its parent; the sum of all children's allocations must never
exceed the parent's.

#### §4.3.3 — Atomic admission

Splitting or binding a Contract requires chip-global hardware arbitration that
succeeds or fails atomically. On failure, no state is changed.

#### §4.3.4 — Dissolution

When a Contract's last member ECID releases it, or the owning Group is destroyed,
the Contract dissolves and its resources return to the parent Contract.

#### §4.3.5 — Delegation depth

Contract trees are bounded by the same D as ECID delegation (see §5).

#### §4.3.6 — Per-extension delegation instructions

Contract delegation and revocation are handled by the extension that owns the
Contract type, not by `ec.it`. Specifically: `ms.it`/`ms.ot` for MSE Contracts,
`qs.it`/`qs.ot` for QoS Contracts, and `cp.it`/`cp.ot` for CPE Contracts. The
CME instruction `ec.it` handles **Bank delegation only** — one Bank per call,
implementation-chosen from the parent's Group. CPE's subset is therefore `{r, t}`
(resource assign/revoke + delegation). Full `cp.it`/`cp.ot` semantics are in
Chapter 7.

### 4.4 Banks vs ECS

- **Banks** hold fast-path register state. CME's 1–9 cycle save/restore
  touches Banks and `current_ecid` only.
- **ECS** holds metadata, slow-path saved state, and references (bank IDs,
  contract descriptors, OS bookkeeping). The DMA path (`ec.im`, `ec.om`)
  reads/writes ECS.

A context switch between two ECIDs whose state is already in Banks does
not touch ECS at all.

### 4.5 MSE Telescoping and Arbitration Policy

This section fixes the normative rules for MSE Contract precision, delegation
telescoping, pre-flattening, multi-tier slot arbitration, dithered slot scheduling,
and the group bandwidth cap. These rules are MSE-specific. The Contract axioms in
§4.3 (ownership, splitting, atomic admission, dissolution, delegation depth, and
per-extension delegation instructions) apply to all three Contract types; the rules
here refine those axioms for MSE.

#### §4.5.0 — Software transparency at any delegation level

**Principle: software runs unchanged at any delegation level.**

This is the foundational principle of CE Suite delegation. An operating system,
hypervisor, application, or workload is unaware of its level in the delegation
tree by default. The MSE bandwidth-class fields it reads from CSRs, the descriptor
values it writes via `ms.ir` and `ms.it`, and the resources it observes via
`mse_bw_cap`, `mse_bw_sum`, and `mse_absolute_bw` all use the same 0–255 scale
regardless of whether the software is running at L0, L1, L2, or L3.

Each level operates on a 0–255 view of *its own slice*. The fact that the slice
is itself a fraction of a parent's slice is invisible to software at this level.
Hardware translates between levels transparently: stored values for arbitration
are computed in absolute global form (per §4.5.3 pre-flattening), but the
software-facing CSRs and descriptor fields always present the local view
appropriate to the running EC's delegation level.

This parallels the analogous property of CME: an L1 hypervisor, running with
delegated banks, sees its world as if it had Group 0 — the parent's delegation
tree above it is invisible. The telescoping mechanism extends this property to
MSE bandwidth allocation.

Software that needs to know its level for diagnostic purposes can query
`current_ecid_level` (Chapter 13 §3.x). No level-aware behavior is required for
any standard OS, hypervisor, application, or workload. The same kernel image
runs unchanged whether installed at L0 (bare metal), L1 (under a host
hypervisor), L2 (in a nested VM), or L3 (deeply nested).

Why this matters: without this property, software would need to be aware of its
installation depth to interpret bandwidth-class values correctly. Every OS
distribution would need to ship variants for different host environments, or have
configuration steps that propagate parent-context information. By design, CE Suite
makes this unnecessary. This is the central architectural property that makes
CE Suite practically deployable in real multi-tenant environments.

#### §4.5.1 — Contract precision and the 0–255 absolute scale

An MSE Contract carries two fields that the memory controller evaluates each
arbitration cycle:

- `bw_class`: the Contract holder's guaranteed bandwidth as an integer count of
  CN slots per arbitration window.
- `lat_class`: the priority for tie-breaking within a CN slot.
  Lower value = higher priority.

Both fields have a maximum architectural width of 8 bits per field. Implementations
may decode fewer bits and advertise the decoded width via the `mse_caps` CSR
(specified in Chapter 13). The minimum supported decoded width is 4 bits per field
for meaningful MSE support.

When a Contract is telescoped at delegation (§4.5.2), the hardware maintains two
representations of `bw_class`:

- **Stored (hardware-internal):** a pre-flattened absolute value on the 0–255 scale
  representing fraction of total system bandwidth. Hardware computes this value once
  at delegation time; subsequent arbitration reads it in O(1) (§4.5.3).
- **Software view (local):** the value returned by `mse_absolute_bw` and used in
  `ms.ir`/`ms.it` descriptor fields is on the running EC's local 0–255 scale,
  representing fraction of *its own slice*. Hardware converts between stored and
  local values at read time. Software at any delegation level uses the same 0–255
  range, consistent with §4.5.0.

**Worked example.** Suppose the system has 256-slot windows and
`mse_slot_ratio.CN_FRAC = 192` (75% CN, 25% BE). A root Contract at L=0 holds
`bw_class = 64` (on the 0–255 scale), guaranteed 64 CN slots per window (64/192 ≈
33% of available CN time; 64/256 = 25% of total window time). At L=0, local view
equals the pre-flattened storage value — no conversion needed.

The L=0 operator delegates 50% of this Contract to an L=1 hypervisor by calling
`ms.it` with `child_bw_class = 128` (= 50% on the 0–255 local scale). Hardware
computes the pre-flattened storage value as `floor(64 × 128 / 256) = 32` (exact
here). The L=1 hypervisor reads `mse_absolute_bw` and receives `bw_class = 128`
(= `floor(32 × 256 / 64)`): 50% on its own local scale. The hypervisor is
guaranteed 32 CN slots per window = 12.5% of total window time, though it need
not track this global figure.

#### §4.5.2 — Telescoping at delegation

When a Contract is delegated from a parent ECID to a child ECID via `ms.it`, the
parent specifies the child's bandwidth share as `child_bw_class` on the parent's
local 0–255 scale — a value where 256 represents 100% of the parent's own slice,
128 represents 50%, and so on. The child's local precision (1–8 bits) may also be
specified.

The hardware computes the child's pre-flattened storage value as the parent's
pre-flattened value times the child's local fraction, **rounded down**:
`child_stored = floor(parent_stored × child_bw_class / 256)`. When the child reads
`mse_absolute_bw`, hardware converts back to local view:
`child_local = floor(child_stored × 256 / parent_stored)`. Round-down at delegation
may cause the returned local value to differ from the original `child_bw_class` by
a small amount; lost capacity flows to over-budget or BE traffic (§4.5.4).

A child may further delegate to a grandchild using this same mechanism, applying its
own stored value as the new parent. Implementations support delegation depth up to
D (§5.1).

**Worked example.** L=0 holds a root Contract with `bw_class = 128` (global
pre-flattened: 128; local: 128 — same at the root). Each level delegates 50% of
its slice to the next level.

| Level | `child_bw_class` passed | Stored global            | Local readback                    |
|-------|------------------------|--------------------------|-----------------------------------|
| L=0   | (root)                 | 128                      | 128                               |
| L=1   | 128 (50% of L=0)       | `floor(128×128/256) = 64`| `floor(64×256/128) = 128`         |
| L=2   | 128 (50% of L=1)       | `floor(64×128/256) = 32` | `floor(32×256/64) = 128`          |
| L=3   | 128 (50% of L=2)       | `floor(32×128/256) = 16` | `floor(16×256/32) = 128`          |

The stored global values (128, 64, 32, 16) are the hardware-internal pre-flattened
representation, halving at each level as each child holds 50% of its parent's
absolute bandwidth. The local readback values are 128 at every level — the same
value regardless of delegation depth. A kernel or hypervisor that reads
`mse_absolute_bw = 128` and interprets it as "I hold 50% of my allocation" is
correct at L=0, L=1, L=2, or L=3. Software runs unchanged.

#### §4.5.3 — Pre-flattening and reconfiguration completion

The hardware maintains the pre-flattened bandwidth value in the leaf Contract.
Arbitration reads this value in O(1).

When a parent Contract is reconfigured (its bandwidth value changes via a privileged
operation), all descendant Contracts in its subtree are recomputed. Hardware retains
the local fraction specified at delegation time (`child_bw_class` from `ms.it`) and
derives the new stored global value as `floor(new_parent_stored × child_bw_class /
256)`. The recomputation must complete before the next arbitration cycle that
involves any affected Contract holder. Implementations may briefly stall arbitration
on affected harts during recomputation; non-affected harts continue unaffected.

The `mse_absolute_bw` CSR (Chapter 13) returns the running EC's bandwidth in
**local view**: hardware converts the stored pre-flattened global value to the local
0–255 scale using `floor(stored_global × 256 / parent_stored_global)`. Software at
any delegation level reads the same scale — fraction of its own slice — consistent
with §4.5.0.

**Worked example.** The root (L=0) holds stored global = 192. It has delegated to an
L=1 hypervisor: stored global = 96, local readback = `floor(96 × 256 / 192) = 128`
(50% of L=0's slice). The hypervisor has three child Contracts:

| Child | `child_bw_class` | Stored global | Local readback (`floor(× 256 / 96)`) |
|-------|-----------------|---------------|--------------------------------------|
| L=2-A | 128 (50%)       | 48            | `floor(48 × 256 / 96) = 128`         |
| L=2-B | 64 (25%)        | 24            | `floor(24 × 256 / 96) = 64`          |
| L=2-C | 32 (12.5%)      | 12            | `floor(12 × 256 / 96) = 32`          |

Each L=2 EC reads `mse_absolute_bw` and sees its fraction of the hypervisor's
slice, unaware of L=0's global allocation.

The root now reduces L=1's allocation: L=1 stored global changes from 96 to 64.
Hardware recomputes each child's stored global from the retained local fraction:

| Child | Local fraction | New stored global           | New local readback (`floor(× 256 / 64)`) |
|-------|---------------|-----------------------------|-----------------------------------------|
| L=2-A | 128/256 = 50% | `floor(64 × 128 / 256) = 32` | `floor(32 × 256 / 64) = 128`           |
| L=2-B | 64/256 = 25%  | `floor(64 × 64 / 256) = 16`  | `floor(16 × 256 / 64) = 64`            |
| L=2-C | 32/256 = 12.5%| `floor(64 × 32 / 256) = 8`   | `floor(8 × 256 / 64) = 32`             |

The L=2 local readback values are identical before and after the reconfiguration.
From each L=2 EC's perspective, its bandwidth class is the same fraction of its
parent's slice — the reconfiguration at L=1 is invisible in the local view. All
descendants of the recomputed Contracts are similarly updated. The next arbitration
involving any affected hart uses the new stored values.

#### §4.5.4 — Multi-tier slot arbitration

Within a CN slot, the memory controller selects the winning Contract holder by this
priority order:

1. **First tier — Contract holders within their budget.** Among Contract holders who
   have not yet consumed their `bw_class` slots in the current window, the holder
   with the lowest `lat_class` wins. Ties broken by round-robin across harts (each
   hart's most-recent grant time is tracked; the least-recently-served wins).

2. **Second tier — Contract holders over budget.** If no first-tier holder requests
   memory in this slot, Contract holders who have consumed their budget but still
   want memory compete by `lat_class`. Ties resolved as in tier 1.

3. **Third tier — Best-effort fallthrough.** If no Contract holder of any tier
   requests memory in this CN slot, the slot becomes available for best-effort
   traffic. Best-effort harts compete by a fair scheme (round-robin or equivalent).

A best-effort slot (the alternation pattern from `mse_slot_ratio`) is always
available to best-effort traffic independently of the CN slot policy.

**Worked example.** Window = 256 slots. `CN_FRAC = 128` (50/50 split). Slot pattern
dithered (§4.5.5) so CN and BE slots interleave. Active Contracts: EC-A
(`bw_class = 8`, `lat_class = 1`), EC-B (`bw_class = 4`, `lat_class = 3`), EC-C
(`bw_class = 16`, `lat_class = 5`). 50% of slots are BE = 128 slots/window; the
other 128 are CN.

In CN slots 1–8: EC-A wants memory, is within budget, `lat_class = 1` wins all 8
slots. EC-A is now at budget. In CN slots 9–12: EC-B wants memory, is within budget,
`lat_class = 3` wins all 4. EC-B is now at budget. In CN slots 13–28: EC-C wants
memory, is within budget, `lat_class = 5` wins all 16. EC-C is now at budget.

In CN slots 29–128: no Contract holder is within budget. EC-A continues to request
memory (over-budget); it wins by `lat_class`. EC-A consumes the rest of the CN slots
that window via the over-budget tier. If EC-A also has no demand, the slot falls
through to BE.

#### §4.5.5 — Dithered slot scheduling with bounded gap

The slot pattern within a window must satisfy `mse_slot_ratio.CN_FRAC` over the
window's slot count. In addition, the maximum gap between consecutive CN slots is
bounded by ⌈256 / CN_FRAC⌉ slots, and the maximum gap between consecutive BE slots
is similarly bounded.

This guarantees that a Contract holder waiting for its next CN slot waits at most one
bounded gap, regardless of `CN_FRAC` value. Best-effort traffic similarly has bounded
wait for its next BE slot.

Implementations satisfy this property by any mechanism. The spec specifies the
guarantee (bounded gap), not the mechanism.

**Worked example.** With `CN_FRAC = 192` (75% CN, 25% BE), the maximum gap between
consecutive CN slots is ⌈256/192⌉ = 2. The pattern CCCBCCCBCCCB... satisfies this:
every 4 slots contains exactly 3 CN and 1 BE, and the longest gap between two CN
slots is 1 (one BE slot between them). A Contract holder waiting for the next CN
slot waits at most 1 slot period.

By contrast, a naïve contiguous-block scheduler might place all 192 CN slots first
followed by 64 BE slots, creating a 64-slot worst-case wait — 64 times worse.
Dithering preserves the worst-case latency guarantee that the rest of MSE relies on:
the (K+1) × slot_size_ns bound for CN latency under interrupt nesting (Chapter 9
§9.3).

#### §4.5.6 — Cap rule on pre-flattened values

The group bandwidth cap (§4.3.2) is enforced on the pre-flattened absolute values.
The sum of all children's pre-flattened `bw_class` values must not exceed the
parent's pre-flattened `bw_class`.

Because telescoping uses round-down (§4.5.2), a parent that delegates all of its
bandwidth to children loses a small amount of total capacity to rounding. This is
intentional: the round-down guarantees no child can exceed what the parent promised,
even by 1/256 of total bandwidth. The lost capacity is not wasted — §4.5.4 routes
it to over-budget or BE traffic.

**Worked example.** Parent at pre-flattened 76. Three children at 38, 19, 12 (sum
= 69). 76 − 69 = 7 units of parent capacity unaccounted for; this becomes available
for over-budget overflow to any descendant who wants more, or to BE if no descendant
wants it.

---

## 5. Delegation

### 5.1 Delegation level L and the cap D

1. Every ECID has a delegation level `L`, `0 ≤ L ≤ D`, stored in `EC[e]`.
2. The architectural maximum is **D ≤ 3**, giving up to four levels
   (0, 1, 2, 3). This matches the four virtualization levels intended
   to be supported simultaneously: L0 host kernel, L1 hypervisor, L2
   nested hypervisor, L3 guest.
3. Implementations may expose a smaller cap (D = 0, 1, 2, or 3) via a
   read-only CSR. A microcontroller-class implementation may pick D = 1;
   a server-class implementation will typically pick D = 3. D > 3 is
   not permitted.
4. `L < D` permits creating child ECIDs and delegating Banks and Contracts.
5. `L = D` permits binding resources for self-use but not further delegation.

### 5.2 Parent/child relationship

1. Every ECID except the root has exactly one parent ECID, stored in
   `EC[e].parent_ecid`.
2. Only the parent (or a privileged ancestor) may revoke a child ECID's
   resources or destroy the child.
3. Destroying an ECID destroys all of its descendants and reclaims all
   their resources, recursively, in O(log N) walks of the radix tree.

### 5.3 Forced destruction

Forced destruction of an ECID (and its subtree) must always succeed, even
if the target is a zombie, blocked, or hostile. See §6.5 for the
instruction (`ec.oe`).

### 5.4 Self-Preservation Invariant

1. A non-leaf EC must retain enough of each resource type to remain
   operational. No EC may delegate all of any one resource type to its
   children.
2. The invariant applies uniformly to CME Banks, MSE Contracts, CPE Contracts,
   and QoS Contracts, and at every delegation level including `L = 0`. The root
   EC is not exempt.
3. **Rationale.** An EC with zero Banks is un-runnable: its register state has
   nowhere to load from on context restore. An EC with zero MSE, CPE, or QoS
   Contract is not un-runnable but degraded — it competes as best-effort and
   may fail to make forward progress or to meet WCET bounds. A hypervisor at
   `L = 1`, like any non-leaf EC, must retain its own resources to continue
   making allocation decisions for its children.
4. **CME enforcement is architectural.** The CME Bank case is enforced
   structurally by the bank-0-unnamed rule (§6.9): an EC cannot delegate its
   last non-VMT Bank, because that Bank is not nameable as a delegation target.
   No runtime check and no error code are involved; the operation is
   inexpressible.
5. **MSE, CPE, and QoS carry no architectural floor.** The architecture places
   no minimum-retention floor on MSE Contracts, CPE Contracts, or QoS
   Contracts. Software at each level is responsible for retaining sufficient
   bandwidth, cache, and I/O resources for its own operation. The asymmetry
   with CME Banks is intentional: zero Banks is categorical failure, whereas
   zero bandwidth, cache, or I/O is a recoverable degraded state.
6. **Scope is self-preservation only.** The invariant prevents an EC from
   un-resourcing itself. It does not prevent a parent from leaving a child with
   zero resources through cooperative revocation (`ec.ot`); that is a separate,
   intentional capability with its own semantics (§5.2, §5.3).

---

## 6. CME instruction principles

Full instruction definitions are in Chapter 3. This section fixes the
**global rules** that all CME (and by extension, CPE, MSE, QoS) instructions
must obey.

### 6.1 Naming convention

All CE Suite instructions follow:

```text
<ext>.<dir><target>
```

- `<ext>` ∈ `{ec, cp, ms, qs}` — names the extension:
  `ec` = CME, `cp` = CPE, `ms` = MSE, `qs` = QoS.
- `<dir>` ∈ `{i, o}` — direction: `i` = "into" (save/seal/create/assign-in),
  `o` = "out of" (restore/unseal/destroy/revoke).
- `<target>` — a single letter drawn from the pool below, naming the target
  or kind. **Each extension uses only the subset applicable to it**; the
  full cross-product is not valid.

| Letter | Target / kind |
|--------|---------------|
| `b`    | bank |
| `m`    | memory (ECS in RAM) |
| `s`    | stream / staging bank |
| `g`    | group |
| `t`    | tenant |
| `v`    | vault (sealed bank) |
| `e`    | existence |
| `r`    | resource / region |

Per-extension subsets (authoritative):

| Extension | Subset | Notes |
|-----------|--------|-------|
| CME (`ec`) | `b, m, g, t, r, e, v` | `s` removed — staging banks are hardware-internal to `ec.ib`/`ec.ob`; no software instruction targets them |
| CPE (`cp`) | `r, t` | `r`=resource assign/revoke; `t`=tenant delegation (D3) |
| MSE (`ms`) | `r, t` | `r`=resource assign/revoke; `t`=tenant delegation |
| QoS (`qs`) | `r, t` | `r`=resource assign/revoke; `t`=tenant delegation |

CPE, MSE, and QoS instruction details are in their respective chapters.

Authors must not invent mnemonics outside this scheme. New letters or
new extension prefixes require a charter change (with a version bump and
changelog entry) before they may appear in any chapter.

### 6.2 ECID-first operands

1. Any CME instruction that targets a context **other than the current
   one** uses an **ECID number** as the operand. Never a C pointer, never
   a bank ID.
2. Instructions operating on the current ECID may omit the ECID operand
   and consult `current_ecid` implicitly.
3. Example:

   ```text
   ec.ob rd, rs1, rs2 # rd = result, rs1 = target ECID, rs2 = restore mask
   ec.om rd, rs1, rs2 # rd = result, rs1 = target ECID, rs2 = mask
   ec.oe rd, rs1      # rd = ECIDs freed, rs1 = target ECID to destroy
   ```

This is a **change** from earlier draft chapters (notably Ch2 and Ch5),
which used pointer-based or bank-ID-based operands. Those drafts are
obsolete; refactor on contact.

### 6.3 Metadata lookup pattern

When an instruction needs metadata about an ECID `e`:

```text
ec_entry  = EC[e]                            # via cme_ec_table_base + stride * e
generation_check(ec_entry, expected_gen)     # if applicable
ecs_ptr   = ec_entry.ecs_ptr                 # offset 0
group     = e                                # GroupID = ECID
# further indirections via ECS or Group metadata
```

### 6.4 OS conventions are non-architectural

OSes will define their own per-EC structures, e.g.:

```c
struct execution_context {
    uint32_t ecid;
    /* ... OS-managed fields ... */
};
```

These structures are **kernel software conventions**. CME instructions
never take their addresses as architectural operands. Pointer-based
idioms (e.g., "load `ctx->ecid` into rs1, then issue `ec.ob`") are
described in Chapter 5 as Linux conventions, not as architectural
semantics.

### 6.5 Required forced-destroy instruction: `ec.oe`

The CME instruction set **must include** `ec.oe` (Execution Context:
out of existence):

```text
ec.oe rd, rs1     # rd = ECIDs freed, rs1 = ECID to destroy
```

Semantics:

1. Revokes all Contracts held by the target ECID and its descendants.
2. Frees all Banks owned by the target and descendants, returning them
   to the parent's Group.
3. Marks the radix-tree subtree as free.
4. Increments the generation counter for each freed `EC[e]` slot.
5. **Always succeeds.** Forward progress is guaranteed; zombies cannot
   stall reclamation.
6. **`rd` returns the total count of ECIDs freed**, including the target
   itself. Each ECID in the destroyed subtree is counted exactly once.
   Callers that do not need the count write to `x0`.

`ec.oe` is privileged. The mnemonic replaces `ec.od` (v0.7) and the
earlier `ec.or` (pre-hiatus); both are retired (see §2.1). The trailing
letter `e`=existence: the instruction takes an ECID *out of existence*,
recursively destroying the target EC and its entire delegation subtree.
This is consistent with the trailing-letter rule: `e` names the target
kind (existence), not the operation.

### 6.6 Errors and traps

#### Primary error channel: `rd`

Every CE Suite instruction that can return a failure code without
trapping writes its result in `rd`:

- **0** — success (operation completed normally).
- **Non-zero** — error code (documented per instruction).

Callers who do not need the result write to `x0` (the RISC-V discard
register). All instructions that can fail take `rd` as their first
operand; the status CSRs (`cme_status`, `mse_status`, `qos_status`,
`cpe_status`) are updated in parallel for diagnostic use but are **not**
the primary error channel.

#### Success-path `rd` for `ec.ib`, `ec.oe`, and `ec.it`

Three CME instructions return success-path information in `rd` rather than
an error code, because they cannot produce a soft failure:

- **`ec.ib rd, rs1`** — saves the running context; either succeeds or
  raises a trap. `rd` returns the bank slot index (0-based within the
  owning Group) of the bank written. Callers that do not need the index
  write to `x0`.
- **`ec.oe rd, rs1`** — forced destroy; always succeeds (§6.5). `rd`
  returns the total count of ECIDs freed, including the target itself.
  Callers that do not need the count write to `x0`.
- **`ec.it`** — delegates Banks to a child tenant (§6.9); either succeeds or
  raises a trap. `rd` returns the count of non-VMT Banks remaining in the
  parent's Group after the operation. Callers that do not need the count write
  to `x0`. The full operand list and enumerated trap causes are in Chapter 3
  (§3.4).

These instructions do not return an error code in `rd`; they raise a trap
on any error path. The `rd = x0` discard convention applies.

#### Trap path

If an instruction references an ECID for which `EC[e]` is invalid
(slot unallocated, or generation mismatch), or the caller violates
delegation rules or Group ownership, the implementation **must** either
raise a defined trap or return a documented failure code in `rd` as
above. Silent ignore is prohibited.

### 6.7 QoS domain selector operand (D4)

`qs.or` and `qs.ot` revoke QoS Contracts from an ECID. Because an ECID can
hold Contracts on multiple QoS domains simultaneously, these instructions
need a domain selector. The selector is passed in `rs2`:

```text
qs.or rd, rs1, rs2   # rs2 = domain_id (0 = revoke all domains)
qs.ot rd, rs1, rs2   # rs2 = domain_id (0 = revoke all domains)
```

`rd` is a write-only destination register in RISC-V and cannot be read by
hardware. Any encoding that reads from `rd` is architecturally illegal and
must not appear in the spec.

### 6.8 TLB behavior on context restore

When `ec.ob` restores a context whose mask includes bit 6 (SATP),
and the restored SATP value differs from the SATP value in effect
immediately before the `ec.ob`, the hardware shall behave as if an
appropriate `sfence.vma` had been executed atomically with the SATP
restore, before any subsequent instruction observes the new
translation. The exact scope of the implied `sfence.vma` (all
ASIDs, the new ASID only, or other) is an open item under §8;
until it is settled, implementations satisfy this rule by using
any scope that is correct for the standard `csrw satp` followed by
`sfence.vma x0, x0` pattern in the same situation.

Implementations are *permitted* to skip the invalidation when the
restored SATP value equals the SATP value in effect immediately
before the `ec.ob` — including but not limited to detection via
direct comparison, ASID tagging, or other equivalent means — but
are not *required* to detect this case. A conformant implementation
that always invalidates is correct; a conformant implementation
that uses any valid optimization to skip invalidation when safe is
also correct.

The H-extension analogues for `vsatp` (via `hfence.vvma`) and
`hgatp` (via `hfence.gvma`) are an open item under §8 and are
specified in ch19 (interop with ratified extensions) once
resolved.

This rule resolves D6 in `docs/work-items.md`. The full
specification of `ec.ob`'s TLB behavior, including any cycle-cost
qualifications, is in ch03 once propagated.

### 6.9 Bank-0-unnamed delegation and `ec.it` operand semantics

1. **Local Bank numbering.** Each EC sees its non-VMT Banks numbered
   `0 .. K-1` in its own local view, where `K` is the count of non-VMT Banks
   the EC holds. This local-view numbering is the CME analog of the local-view
   property established for MSE telescoping (§4.5.0): software at any delegation
   level observes the same numbering scheme regardless of depth.
2. **Bank 0 is structurally retained.** Local Bank 0 — the EC's first non-VMT
   Bank — is not nameable as a delegation target. An EC therefore cannot
   delegate its last non-VMT Bank; the attempt is architecturally inexpressible
   rather than refused at runtime. This is the enforcement mechanism for the
   CME case of the Self-Preservation Invariant (§5.4), and it holds at every
   level including `L = 0`.
3. **`ec.it` operand semantics.** `ec.it` (delegate Banks to a child tenant)
   takes `rs1` as the **count** of non-VMT Banks to delegate in the call, not a
   Bank specifier. Hardware delegates the highest-numbered local non-VMT
   Bank(s) from the parent's Group, never local Bank 0. On success, `rd`
   returns the count of non-VMT Banks remaining in the parent's Group after the
   operation.
4. **`rs1 = 0` is a no-op.** Zero Banks are delegated and `rd` returns the
   parent's non-VMT Bank count unchanged.
5. **VMT Banks are exempt.** VMT Banks (holding vector/matrix/tensor state)
   carry no retention requirement and may be delegated in full. An EC that has
   delegated all VMT Banks remains runnable for non-vector code on its retained
   non-VMT Bank 0.
6. **Error handling is by trap, not by error code.** Because `rd` carries a
   success-path value (Banks remaining), `ec.it` does not return an error code
   in `rd`. Delegation-rule violations — for example `L = D` (§5.1), an invalid
   or stale child ECID, or a Group-ownership violation — raise a trap. `ec.it`
   thus belongs to the success-path-`rd` family alongside `ec.ib` and `ec.oe`
   (§6.6): it either succeeds, with `rd` = Banks remaining, or it traps. The
   high-frequency self-preservation error ("delegate my last Bank") is not a
   trap case at all; it is inexpressible (point 2). The enumerated trap causes
   are specified in Chapter 3 (§3.4).
7. **Breaking change.** This repurposing of `rs1` from a Bank specifier to a
   count is a breaking change to `ec.it`'s operand semantics; chapters and
   models using the earlier Bank-specifier encoding are obsolete on this point
   and refactor on contact (cf. §6.2). The complete `ec.it` instruction
   definition — full operand list including the child-tenant target and
   encoding — is specified in Chapter 3 (§3.4) and propagated in a separate
   session.

---

## 7. Document alignment rules

### 7.1 Conflict resolution

1. If a chapter conflicts with this charter or Chapter 0, the chapter
   is wrong; refactor the chapter.
2. Do not amend axioms casually. Changes to the model are made here and
   in Chapter 0 first, with a version bump and a changelog entry.

### 7.2 ECID language requirement

Any mechanism described in the spec must be expressible in terms of:

- ECIDs and `current_ecid`
- `EC[e]` entries
- Groups, Banks, Contracts
- ECS reached via `EC[e].ecs_ptr`

Mechanisms that fundamentally depend on raw pointers, PIDs, or thread
IDs without an ECID mapping are incomplete and not architectural.

### 7.3 Chapter-by-chapter alignment

- **Chapter 1 (Execution Context Model).** Lead with the ECID and `EC[e]`
  model. The old "context bank-centric" framing is obsolete.
- **Chapter 2 (Bank/Group/Delegation Semantics).** Tie all delegation
  to the ECID radix tree (§3.5). Drop the separate 6-bit group ID
  numbering; GroupID = ECID throughout.
- **Chapter 3 (Instruction Set Reference).** Operands are ECID numbers
  and masks (per §6.2). Include `ec.oe`. Retire `ec.or` and `ec.od`. The
  instruction mask encoding follows Chapter 0 §0.9.
- **Chapter 4 (Hardware Microarchitecture Overview).** Use the REVISED
  version (S/R staging banks, copy engine, VMT-ready flag). Add the
  SRAM-vs-RAM residency story for `EC[e]` (§3.4) and the radix-tree
  lookup path.
- **Chapter 5 (Linux Kernel Integration).** Frame as: "Given the ECID
  model, Linux represents ECS as `struct execution_context`, whose
  address is stored in `EC[e].ecs_ptr`." Pointer idioms are Linux
  conventions, not architectural rules.
- **Chapter 6 (CME Usage Examples).** Examples name ECIDs explicitly
  (current_ecid, interrupt_ecid, vm_ecid, enclave_ecid) and show
  how `ec.*` instructions manipulate them.
- **Chapter 7 (CPE Instruction Set Reference).** Already mostly ECID-
  framed; verify the rs1 ECID field is 16 bits (per §3.6) and update
  mnemonics to `cp.*` per §6.1.
- **Future chapters on MSE and QoS** (not yet drafted). Must use the
  Contract model from §4.3; must not reintroduce Pools. Instruction
  mnemonics use `ms.*` and `qs.*` per §6.1.
- **Appendix A (ECID).** Convert from a resolved-issues scratchpad
  into a real appendix with the radix-tree data structure (C struct)
  and the allocation, delegation, and forced-destruction algorithms.

### 7.4 Versioning

This charter has a version number on the first line. Every substantive
change increments it and adds a changelog entry at the bottom. Chapter 0
is versioned in lockstep with this charter — if Chapter 0's model
changes, this charter changes, and vice versa.

---

## 8. Open items deferred to later versions

These items are acknowledged but not resolved in v0.12. They do not block
the rest of the spec.

1. **NUMA-aware Contract assignment.** Multi-socket / NUMA semantics for
   MSE Contracts are not yet specified.
2. **Multi-resource Contracts.** Whether a single Contract can span
   multiple resource classes (e.g., memory + I/O) is open.
3. **Software-overflow Contracts.** When hardware Contract slots are
   exhausted, `ms.ir`/`ms.it`/`qs.ir`/`qs.it`/`cp.ir` return their
   respective system-full error codes. The slow-path response (deny, queue,
   or other strategy) is implementation-defined for v1.0 and not mandated
   by this specification. Richer slow-path semantics are deferred to a later
   version.
4. **Cross-hart ECS sharing for migration.** Migration currently rebinds
   ECIDs (§3.1.4); whether ECS objects can be referenced by `EC[e]` on
   multiple harts simultaneously during the handover window is open.
5. **UCS (Unified Context Structure).** Closed as out of architectural
   scope for v1.0. UCS is a kernel implementation pattern — a software
   abstraction over ECS for unified scheduling — not an architectural
   mandate. The spec does not define it; implementers may define their own
   kernel-side structures. A UCS appendix may be added in a future version
   as informative guidance, but it is not required for ratification.
6. **Secure Vault key management.** Instruction-level vault semantics are
   normative in v1.0 (ch03 §3.6): sealed-bank state, `ec.iv`/`ec.ov`
   behaviour, `ec.ob` refusal of sealed banks, and spill/fill of sealed
   ciphertext. The encryption algorithm is implementation-defined. Key
   derivation, attestation, rotation, and cross-hart portability of sealed
   banks remain deferred to a future revision.
7. **D6.1 — Exact scope of the auto-invalidation on `ec.ob`.** Per §6.8
   (TLB behavior on context restore), `ec.ob` with bit 6 (SATP) set
   automatically performs a TLB invalidation when the restored SATP differs.
   The exact scope of that invalidation is not yet specified. Candidates:

   - **Scope 1.** As if `sfence.vma x0, x0` — invalidate all ASIDs,
     all virtual addresses. Always correct; pessimistic when ASIDs
     are in use.
   - **Scope 2.** As if `sfence.vma x0, ASID(new_SATP)` — invalidate
     all virtual addresses for the new ASID. Correct when ASIDs are
     used; degrades to Scope 1 when ASIDs are not used.
   - **Scope 3.** Implementation-defined, with the minimum guarantee
     that no stale translation from the previous address space is
     observable.

   This decision requires implementer-level review and is deferred to
   TG-stage refinement. The §6.8 wording ("as if an appropriate
   sfence.vma had been executed") is loose enough that resolving
   D6.1 does not require another charter revision unless the rule
   itself changes.
8. **D6.2 — H-extension analogues of the SATP/TLB rule.** `ec.ob` may
   also restore `vsatp` and `hgatp` (via the bit 6 aggregate, or via
   dedicated mask bits in a future extension of §0.10). When this happens,
   the analogous TLB invalidation rule applies, using `hfence.vvma` for
   `vsatp` and `hfence.gvma` for `hgatp`. The exact mapping — including
   whether the bit-6 aggregate covers all three or whether
   `vsatp`/`hgatp` require separate treatment — is an open item.
   Resolution depends on D6.1 (base scope decision), the §0.10 mask
   granularity, and the H-extension interaction language in ch19 §19.2.1.
9. **D6.3 — Charter §1 "1–2 cycle" claim qualification.** The charter §1
   introduction characterizes CE Suite as providing 1–2 cycle context
   switches. Under §6.8, cross-address-space `ec.ob` incurs an
   auto-invalidation whose cost is not 1–2 cycles; the TLB refill cost on
   first access to the new address space adds further latency. The general
   claim is therefore true for `ec.ob`'s instruction-commit latency but
   workload-dependent for end-to-end switching cost. Three resolution
   candidates:

   - Leave §1 alone (risk: a casual reader is misled).
   - Add a parenthetical qualification to §1 (honest, slightly verbose).
   - Move the precise claim from §1 into ch04 (microarchitecture) and
     replace §1's claim with a more abstract characterization.

   A related parked insight in
   `scratchpads/general/2026-05-rt-subset-determinism.md` proposes that
   the strong "1–2 cycle" claim is defensible for a defined RT-subset of
   ECs (same-SATP, CPE-reserved, MSE/QoS-contracted, permanently-resident
   bank). The eventual D6.3 resolution should decide whether to absorb
   that framing into the §1 qualification, develop it as its own work
   item, or defer further.

10. **D7.1 — Priority inversion and bandwidth donation.** The multi-tier slot
    arbitration adopted in v0.21 (§4.5.4) routes over-budget Contract bandwidth
    and unused BE slots to waiting ECs, addressing the common case where idle
    bandwidth flows usefully. A separate formal priority-inversion or bandwidth-
    donation mechanism — e.g., priority inheritance across hart boundaries, or
    explicit donation of a Contract slice by one EC to another — remains an open
    question for ratification-stage refinement with real implementer input.
    D-pools (the salvage-analysis mechanism that served a similar purpose) are
    explicitly dropped as an architectural concept and are not revived by this
    item.

---

## Changelog

- **v0.23 (this version).** Self-Preservation Invariant added as a normative
  principle.

  Establishes that a non-leaf EC must retain enough of each resource type to
  remain operational; no EC may delegate all of any one resource type to its
  children. Added as §5.4 (cross-cutting principle) with the CME enforcement
  mechanism in §6.9.

  - **§5.4.** Applies to CME Banks and MSE/CPE/QoS Contracts, at all levels
    including `L = 0`. CME is enforced architecturally via bank-0-unnamed;
    MSE/CPE/QoS carry no architectural floor and are software's responsibility.
    Scope is self-preservation only; cooperative revocation of a child is
    unaffected.

  - **§6.9.** Bank-0-unnamed local numbering: each EC's first non-VMT Bank
    (local Bank 0) is not nameable for delegation, making delegation of an EC's
    last non-VMT Bank inexpressible. `ec.it` is redesigned so `rs1` is the count
    of Banks to delegate (highest-numbered local non-VMT Banks chosen by
    hardware), `rd` returns Banks remaining, and `rs1 = 0` is a no-op. VMT Banks
    are exempt. Delegation-rule violations (`L = D`, invalid child, ownership)
    trap rather than returning an error code; `ec.it` joins the
    success-path-`rd` family in §6.6. This is a breaking change to `ec.it`'s
    operand encoding.

  - **§6.6.** `ec.it` added to the success-path-`rd` instruction list alongside
    `ec.ib` and `ec.oe`.

  Propagation to ch00 (§0.6 Banks), ch02 (§2.4 delegation note; §2.6 gains an
  eighth invariant), ch03 (§3.4 `ec.it` rewrite), ch07/ch09/ch11
  (software-responsibility notes for CPE/MSE/QoS), and the unified Sail redo
  follows in subsequent commits. `docs/work-items.md` gains a Cluster
  Self-Preservation entry.

- **v0.22.** Local-view semantics for telescoping (cluster D
  revision).

  The v0.21 commit (6c46f5a) described §4.5's MSE telescoping in *global view*
  terms: software at every delegation level would see CSR values representing
  fraction of total system bandwidth. This was inconsistent with the architect's
  design intent that software runs unchanged at any delegation level — the same
  property CME's group-zero-from-any-level already embodies.

  v0.22 introduces §4.5.0 stating this principle prominently, and revises
  §4.5.1, §4.5.2, §4.5.3 to clarify that:

  - Hardware stores pre-flattened absolute values internally (for O(1)
    arbitration). This is unchanged from v0.21.

  - Software-facing CSR readback (`mse_absolute_bw`) returns a value on the
    running EC's *local* 0–255 scale, representing fraction of *its own slice*.
    The conversion from stored global to readback local is
    `floor(stored_global × 256 / parent_stored_global)`, performed at read time
    by hardware.

  - Descriptor fields (`bw_class` in `ms.ir`, `child_bw_class` in `ms.it`) are
    on the *parent's local scale*. Software at any level uses the same 0–255
    range regardless of depth.

  - Telescoping (§4.5.2) operates within this framework: the parent grants the
    child a slice expressed on the parent's local 0–255 scale; hardware translates
    this to a global pre-flattened value for arbitration using
    `floor(parent_stored × child_bw_class / 256)`.

  - Reconfiguration (§4.5.3) preserves local fractional views: hardware retains
    the `child_bw_class` from the original `ms.it` call and recomputes stored
    global values when a parent's allocation changes. Local readback values are
    approximately preserved through reconfiguration (exactly preserved when the
    fraction is representable without rounding).

  The hardware mechanics (multi-tier arbitration §4.5.4, dithering §4.5.5, cap
  rule §4.5.6, round-down rounding) are unchanged from v0.21.

  Propagation to ch00 (architectural philosophy), ch09 (MSE chapter), ch10
  (usage examples), ch13 (CSR semantics), Sail-A (one-line patch in
  `read_CSR(0xFD3)`) follows in subsequent commits.

- **v0.21.** Cluster D resolution: MSE telescoping with
  per-delegation precision, multi-tier slot arbitration, and dithered slot
  scheduling become normative. All content placed in new §4.5 (MSE Telescoping
  and Arbitration Policy) using Approach A (§5 already exists for Delegation).
  - **Telescoping (§4.5.1, §4.5.2).** Contract delegation may reduce precision at
    each step. Pre-flattened absolute bandwidth is computed on a 0–255 scale and
    stored in the leaf Contract for O(1) arbitration. Recursive delegation to depth
    D is supported. Round-down rounding preserves the "child receives at most
    parent's promise" guarantee.
  - **Field widths (§4.5.1).** `bw_class` and `lat_class` are 8 bits architectural
    maximum, implementation-defined decoded width (minimum 4 bits). Discoverable via
    `mse_caps` (specified in Chapter 13).
  - **Pre-flattening (§4.5.3).** Hardware pre-computes absolute bandwidth at
    delegation; arbitration is O(1). Reconfiguration completes recomputation before
    the next affected arbitration cycle. A pre-flattened bandwidth readback CSR
    (`mse_absolute_bw` or similar; final name and address in Chapter 13) is
    mentioned for software readability of the running EC's effective bandwidth.
  - **Multi-tier slot arbitration (§4.5.4).** Within CN slots: within-budget
    Contract holders by `lat_class` → over-budget Contract holders by `lat_class`
    → BE fallthrough. Round-robin tie-break on `lat_class`. The multi-tier rule
    guarantees bandwidth is never wasted while preserving Contract minimums.
  - **Dithered slot scheduling (§4.5.5).** Slot pattern must satisfy `CN_FRAC`
    over each window and bound the maximum gap between consecutive CN slots to
    ⌈256/CN_FRAC⌉. Implementation mechanism unspecified. Preserves the
    (K+1) × slot_size_ns worst-case CN latency under interrupt nesting.
  - **Cap rule reformulation (§4.5.6).** Group bandwidth cap is enforced on
    pre-flattened absolute values. Round-down rounding creates small unused
    capacity which flows via over-budget overflow or BE fallthrough.
  - **§8 update:** added item 10 (D7.1 — priority inversion handling and formal
    bandwidth donation as a separate mechanism beyond slot-overflow); pending
    ratification-stage refinement with implementer input.
  - **Dropped:** D-pools (the salvage analysis's collective bandwidth-sharing
    mechanism). The slot-overflow policy in §4.5.4 subsumes the pool concept's
    main value. No §8 entry for D-pools.
  - Propagation to ch09 (significant rewrite of §9.3 and §9.4), ch10 (new
    examples), ch13 (new `mse_absolute_bw` CSR and possibly `mse_caps`
    additions), and Sail MSE phase follows in subsequent commits.

- **v0.20.** §1 area-overhead claim refined: the "5–15%"
  per-core range is retained as the digestible summary, with an inline
  cross-reference to Appendix C §C.4 for stratification by deployment class
  (CE-MinimalRT, CE-RT, CE-Full) and against specific public baselines
  (SiFive U84, Cortex-A55, P670-class). The v2 sizing calculator
  (`tools/ce-sizing-calculator.py`, commit 891361c) is the authoritative
  source for these figures. No normative semantic change; this is a
  precision refinement to the headline pitch.

- **v0.19.** Resolved D6 (TLB behavior on context restore). §6.8
  added: `ec.ob` with bit 6 (SATP) set in the mask now has normative TLB
  semantics — when the restored SATP differs from the current SATP, hardware
  performs an `sfence.vma`-equivalent invalidation atomically with the restore;
  the optimization of skipping the invalidation when SATP is unchanged is
  permitted but not required. Three sub-decisions deliberately parked as new §8
  open items: D6.1 (exact scope), D6.2 (H-extension analogues for
  `vsatp`/`hgatp`), D6.3 (§1 wording on cross-address-space cost, with
  reference to the parked RT-subset insight in
  `scratchpads/general/2026-05-rt-subset-determinism.md`). Propagation to ch03,
  ch00 §0.10, ch17, ch19, and the Sail S5/S6 SATP stubs is pending separate
  sessions per project-management-guide §4.2.

- **v0.18.** §8.3 and §8.5 addressed for v1.0. §8.3:
  software-overflow Contract slow-path is implementation-defined; error
  codes are already specified; richer semantics deferred. §8.5: UCS closed
  as out of architectural scope for v1.0 — kernel implementation pattern,
  not an architectural mandate. Propagated to: ch09 §9.12 and ch11 §11.13
  (slow-path notes updated to reflect implementation-defined status).

- **v0.17.** Option B vault resolution: `ec.iv`/`ec.ov`
  instruction-level semantics are now normative. Defines sealed-bank state
  (hardware tracks sealed/unsealed per bank), `ec.iv` encrypt-and-seal using
  `cme_seal_key`, `ec.ov` decrypt-and-authenticate returning
  `CME_ERR_NOT_SEALED` on failure, `ec.ob` refusal of sealed banks
  (`CME_ERR_ALREADY_SEALED`), and spill/fill preservation of sealed ciphertext.
  Encryption algorithm remains implementation-defined. Key derivation,
  attestation, rotation, and cross-hart portability remain deferred (§8.6
  updated). Propagated to: ch03 §3.6 (full normative vault section replaces
  shell-only block); ch13 §3.9 (spec-status paragraph updated); ch15 §15.5.1
  (shell qualifiers removed; ec.ob sealed-bank row added).

- **v0.16.** §8.7 resolved: `ce_ctrl` CSR (0x7D0, M-mode RW)
  defined as the CE-disable mechanism. Four independent per-extension enable
  bits — `CME_EN` (bit 0), `CPE_EN` (bit 1), `MSE_EN` (bit 2), `QOS_EN`
  (bit 3) — reset to 0 (all disabled); firmware explicitly enables. If
  hardware for an extension is absent the corresponding bit is RO 0.
  Extensions may be enabled independently with no required ordering. §3.7
  updated with the normative CSR definition; §8.7 removed from open items.
  Propagated to: ch13 §1.1 (CE-disable CSR deferred note replaced with
  normative `ce_ctrl` entry and address-table addition); ch00 §0.2 (disable
  section updated to name `ce_ctrl`); ch16 (CE-disabled behavior note updated).

- **v0.15.** D5 resolved: §4.3.0 — Contract: object model added as
  a new normative subsection at the start of §4.3. The subsection establishes the
  Contract identity tuple `(owning_ECID, resource_class)`, the two-location state
  model (parameters in Bank CP field; admission-control state in per-controller
  SRAM), the lifecycle from `*.ir`/`*.it` to `*.or`/`*.ot`/`ec.oe`, and the
  distinction between creation parameters and the Contract object itself.
  Explicitly out of scope: no Contract ID namespace, no unified descriptor struct,
  no encoding changes. Existing items 2–7 of §4.3 formalized as §4.3.1–§4.3.6;
  changelog references updated from "§4.3 item 7" to "§4.3.6". Propagated to
  ch00 §0.7.0 (new subsection restating the model with a concrete example),
  ch07 §7.4 (single-sentence cross-reference), ch09 §9.4.1 (single-sentence
  cross-reference), ch11 §11.5.1 (single-sentence cross-reference).
- **v0.14.** E8 resolved: `ec.ib` and `ec.oe` both gain `rd`
  operands returning success-path information. `ec.ib rd, rs1` returns the bank
  slot index (0-based within the owning Group) of the bank written. `ec.oe rd, rs1`
  returns the total count of ECIDs freed, including the target. Callers write to
  `x0` to discard. §6.5 syntax updated (new item 6); §6.6 "Exceptions (no rd)"
  replaced by "Success-path rd for ec.ib and ec.oe"; §6.2 example updated.
  Unblocks E8 ch03 propagation session.
- **v0.13.** Structural renumbering: ch02 ↔ ch03 swapped so that
  Bank/Group/Delegation Semantics precedes the CME Instruction Set Reference;
  CPE/MSE/QoS usage examples and ISRs renumbered (ch08 = CPE examples, ch09 = MSE ISR,
  ch10 = MSE examples, ch11 = QoS ISR). §7.3 updated; all cross-references propagated.
- **v0.12.** B: CME subset corrected to `{b,m,g,t,r,e,v}` —
  `s` removed (staging banks are hardware-internal; no software instructions);
  `g`, `t`, `r` confirmed (already defined in ch03). Per-extension subset table
  added to §6.1. D4 resolved: `qs.or`/`qs.ot` domain selector passed in `rs2`
  (0 = all domains); reading from `rd` prohibited (§6.7 added).
- **v0.11.** D3 resolved — CPE Contracts are delegatable; `cp.it`
  and `cp.ot` are required; CPE subset is `{r, t}`; §4.3.6 updated to confirm
  this. Full instruction semantics deferred to Chapter 7 (F1). This unblocks F1.
- **v0.10.** D2 resolved — `ec.it` delegates Banks only, one per
  call; Contract delegation is extension-owned (`ms.it`, `qs.it`, `cp.it` per D3);
  stated in §4.3.6. Propagated to ch03 §4 and ch02 §3.4.
- **v0.9.** D1 resolved — unified error/status policy (§6.6):
  every CE Suite instruction that can fail writes 0 (success) or a non-zero
  error code in `rd`; `x0` discards the result. Status CSRs (`cme_status`,
  etc.) updated in parallel for diagnostics only. Two exceptions: `ec.ib`
  (always succeeds or traps; no `rd`) and `ec.oe` (always succeeds; no `rd`).
  §6.2 example updated to show `rd` on `ec.ob` and `ec.om`. Syntax changes
  propagated to ch00 and ch02.
- **v0.8.** `ec.od` → `ec.oe`: trailing letter `e`=existence
  restores full consistency of the "trailing letter names the target or kind"
  rule; `ec.od` retired (§2.1); `d`=destroy removed from letter table,
  `e`=existence added (§6.1); §6.5 updated; §8 item 1 resolved and removed.
- **v0.7.** Locked: `ecs_ptr` mandated at offset 0 (§3.2, §3.3); ECID width
  = 16 bits, with PID-vs-ECID note (§3.6); D ≤ 3 as architectural maximum,
  implementations may pick smaller (§5.1); instruction naming uses two-letter
  extension prefixes `{ec, cp, ms, qs}` (§6.1); §3.7 added covering CE
  disable and ignore semantics at firmware and per-privilege-level granularity;
  `ec.or` → `ec.od` rename confirmed, rationale parked in §8.
- **v0.6.** Strawman rewrite after the late-2025 / mid-2026 hiatus. Added
  glossary with retired terms, proposed ECID width, D value, `ec.od`,
  generation counters, chapter-by-chapter alignment, and separation of
  workflow notes into a companion document.
- **v0.5 (pre-hiatus).** The unversioned "compressed charter" —
  established the ECID-first, EC-array, ECID-not-pointer rules.

---

*End of CE Suite Project Instructions and Axiom Charter, v0.23.*
