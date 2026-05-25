# CE Suite — Project Instructions and Axiom Charter

**Version:** 0.8
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
per core.

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

1. **Firmware disable.** The BIOS or M-mode firmware may disable CE
   entirely for the system. When CE is disabled, all CE CSRs read as
   zero (or the implementation-defined "unimplemented" pattern), all
   CE instructions trap as illegal, and the system behaves as a
   standard RISC-V system without CE. This is essential for
   testing — kernel bugs suspected of involving CE can be isolated
   by booting with CE off.
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

1. A Contract is a slice of a global, multiplexed resource — memory
   bandwidth/latency for MSE, I/O bandwidth/latency for QoS, cache ways
   or fraction for CPE.
2. **Single ownership.** A Contract has exactly one owning ECID's Group
   at any moment.
3. **Hierarchical splitting.** A privileged actor may split a Contract
   into child Contracts. Each child is a strict subset of its parent;
   the sum of all children's allocations must never exceed the parent's.
4. **Atomic admission.** Splitting or binding a Contract requires
   chip-global hardware arbitration that succeeds or fails atomically.
   On failure, no state is changed.
5. **Dissolution.** When a Contract's last member ECID releases it, or
   the owning Group is destroyed, the Contract dissolves and its
   resources return to the parent Contract.
6. **Delegation depth.** Contract trees are bounded by the same D as
   ECID delegation (see §5).

### 4.4 Banks vs ECS

- **Banks** hold fast-path register state. CME's 1–9 cycle save/restore
  touches Banks and `current_ecid` only.
- **ECS** holds metadata, slow-path saved state, and references (bank IDs,
  contract descriptors, OS bookkeeping). The DMA path (`ec.im`, `ec.om`)
  reads/writes ECS.

A context switch between two ECIDs whose state is already in Banks does
not touch ECS at all.

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
instruction (`ec.od`).

---

## 6. CME instruction principles

Full instruction definitions are in Chapter 2. This section fixes the
**global rules** that all CME (and by extension, CPE, MSE, QoS) instructions
must obey.

### 6.1 Naming convention

All CE Suite instructions follow:

```text
{ec, cp, ms, qs}.{i, o}{b, m, s, g, t, v, e, r}
```

- The two-letter prefix names the extension:
  `ec` = CME, `cp` = CPE, `ms` = MSE, `qs` = QoS.
- The middle letter is direction: `i` = "into" (save/seal/create/assign-in),
  `o` = "out of" (restore/unseal/destroy/revoke).
- The trailing letter names the target or kind: `b`=bank, `m`=memory,
  `s`=stream/staging, `g`=group, `t`=tenant, `v`=vault, `e`=existence,
  `r`=resource/region.

Authors must not invent mnemonics outside this scheme. New verbs require
a charter change (with a version bump and changelog entry) before they
may appear in any chapter.

### 6.2 ECID-first operands

1. Any CME instruction that targets a context **other than the current
   one** uses an **ECID number** as the operand. Never a C pointer, never
   a bank ID.
2. Instructions operating on the current ECID may omit the ECID operand
   and consult `current_ecid` implicitly.
3. Example:

   ```text
   ec.ob rs1, rs2     # rs1 = target ECID, rs2 = restore mask
   ec.om rs1, rs2     # rs1 = target ECID, rs2 = mask
   ec.od rs1          # rs1 = target ECID to destroy
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
ec.oe rs1     # rs1 = ECID to destroy
```

Semantics:

1. Revokes all Contracts held by the target ECID and its descendants.
2. Frees all Banks owned by the target and descendants, returning them
   to the parent's Group.
3. Marks the radix-tree subtree as free.
4. Increments the generation counter for each freed `EC[e]` slot.
5. **Always succeeds.** Forward progress is guaranteed; zombies cannot
   stall reclamation.

`ec.oe` is privileged. The mnemonic replaces `ec.od` (v0.7) and the
earlier `ec.or` (pre-hiatus); both are retired (see §2.1). The trailing
letter `e`=existence: the instruction takes an ECID *out of existence*,
recursively destroying the target EC and its entire delegation subtree.
This is consistent with the trailing-letter rule: `e` names the target
kind (existence), not the operation.

### 6.6 Errors and traps

If an instruction references an ECID for which:

- `EC[e]` is invalid (slot unallocated, or generation mismatch), or
- the caller violates delegation rules or Group ownership,

then the implementation **must** either raise a defined trap or return
a documented failure code via `rd` or a status CSR. Silent ignore is
prohibited.

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
- **Chapter 2 (Instruction Set Reference).** Operands are ECID numbers
  and masks (per §6.2). Include `ec.oe`. Retire `ec.or` and `ec.od`. The
  instruction mask encoding follows Chapter 0 §0.9.
- **Chapter 3 (Bank/Group/Delegation Semantics).** Tie all delegation
  to the ECID radix tree (§3.5). Drop the separate 6-bit group ID
  numbering; GroupID = ECID throughout.
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

These items are acknowledged but not resolved in v0.8. They do not block
the rest of the spec.

1. **NUMA-aware Contract assignment.** Multi-socket / NUMA semantics for
   MSE Contracts are not yet specified.
2. **Multi-resource Contracts.** Whether a single Contract can span
   multiple resource classes (e.g., memory + I/O) is open.
3. **Software-overflow Contracts.** When hardware Contract slots are
   exhausted, what the slow-path looks like.
4. **Cross-hart ECS sharing for migration.** Migration currently rebinds
   ECIDs (§3.1.4); whether ECS objects can be referenced by `EC[e]` on
   multiple harts simultaneously during the handover window is open.
5. **UCS (Unified Context Structure).** A kernel-side abstraction over
   ECS for unified scheduling. Currently kernel-design guidance only,
   not architectural. May be promoted to an optional appendix.
6. **Secure Vault key management.** `ec.iv`/`ec.ov` semantics for sealed
   banks are specified; key derivation, attestation, and rotation are not.
7. **CE-disable CSR naming and bit layout.** §3.7 establishes that CE
   may be disabled at firmware level, but the specific CSR(s), reset
   defaults, and per-extension granularity (can CME be enabled while
   MSE is disabled?) are not yet pinned.

---

## Changelog

- **v0.8 (this version).** `ec.od` → `ec.oe`: trailing letter `e`=existence
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

*End of CE Suite Project Instructions and Axiom Charter, v0.7.*
