
---

# Chapter 0 — Fundamental Structure

## 0.1 Scope

This chapter defines the core objects and relationships in the CE Suite. Its
definitions are normative: all instruction semantics, delegation rules, and OS
integration details in later chapters reference this chapter.

The CE Suite charter (`docs/charter/project_instructions.md`) is the
authoritative source for architectural decisions. When a detail here conflicts
with the charter, the charter wins. When a later chapter conflicts with this
chapter, this chapter wins.

---

## 0.2 Execution Context Identifier (ECID)

An **Execution Context Identifier (ECID)** is a 16-bit, hart-local,
hardware-managed token denoting one Execution Context (EC) currently bound to
a hart. The EC may be a thread, process, vCPU, interrupt handler, secure
enclave, or any other schedulable unit.

**Width.** ECID numbers are 16 bits, giving 65,536 ECIDs per hart on RV32 and
RV64 alike. The 16-bit number is treated as an opaque integer by hardware; the
`prefix || index` decomposition used by the kernel's radix-tree allocator is a
software convention.

**Hart-local.** An ECID has meaning only on the hart that issued it. The
system-wide identity of a running EC is the tuple `(hart_id, ECID)`, but no
hardware mechanism uses that tuple as a key.

**Opaque to user code.** A process cannot read or write its own ECID. The OS
may know it; the EC running as that ECID cannot. Opacity is the mechanism that
makes the ECID an unforgeable capability.

**Privileged creation only.** Only M-mode firmware, S-mode kernel, or HS-mode
hypervisor may create or destroy ECIDs. User mode may not.

**No migration across harts.** When the scheduler moves an EC from one hart to
another, the kernel unbinds the source ECID and allocates a fresh ECID on the
destination hart, reusing the same in-memory ECS. Migration is rebinding, not
literal ECID transfer.

**Generation counters.** Each `EC[e]` slot holds a generation counter
incremented on every slot reuse. A software reference to a
`(hart_id, ECID, generation)` triple is stale when the counter in `EC[e]` no
longer matches. This prevents ABA hazards when a slot is freed and reallocated.

**ECID allocation — radix tree.** ECIDs are allocated by the kernel from a
radix tree organized as `prefix || index`. Each subtree is owned by one tenant
or privileged context; allocations within a prefix require no global
coordination. Privileged actors may set per-prefix quotas on resourced ECIDs
(those holding Banks or Contracts). Destroying an ECID destroys its entire
subtree and reclaims all resources. The radix tree is a kernel data structure;
the architectural view is the `EC[e]` array (§0.3). Algorithms are in
Appendix A.

**CE disable and ignore.** Firmware may disable CE entirely; when disabled, all
CE CSRs read as zero and all CE instructions trap as illegal. Even when CE is
enabled, any privilege level may choose to ignore it and run a conventional
kernel or userspace. This opt-in property applies uniformly to all five
extensions: CME, CPE, MSE, QoS, and the ECID substrate.

---

## 0.3 The EC[e] Array

Each hart has a conceptual array `EC[0..E_max]` indexed by ECID number. The
architectural structure of each entry is:

```c
struct EC_entry {
    void     *ecs_ptr;        /* canonical ECS pointer — always at offset 0 */
    uint8_t   generation;     /* incremented on every slot reuse             */
    uint8_t   delegation_L;   /* delegation level, 0 ≤ L ≤ D                */
    uint16_t  parent_ecid;    /* ECID of the parent in the delegation tree   */
    /* implementation-defined: cached bank/contract refs, flags, etc.        */
};
```

`ecs_ptr` **must** be at offset 0. The most common hardware operation —
fetching the ECS pointer for a given ECID — is therefore a single load:

```text
entry_addr(e) = cme_ec_table_base + e × stride
ecs_ptr(e)    = *entry_addr(e)              // offset 0
```

`cme_ec_table_base` is a per-hart CSR. `stride` is implementation-defined but
fixed per hart.

**SRAM-vs-RAM residency.** `EC[e]` is conceptually RAM-resident. Implementations
are expected to keep SRAM copies of the entries for currently active ECIDs. The
fast-path instructions (`ec.ib`, `ec.ob`) touch only SRAM-resident entries; the
DMA-path instructions (`ec.im`, `ec.om`) may walk the RAM-resident table.

---

## 0.4 Execution Context Structure (ECS)

The **Execution Context Structure (ECS)** is a RAM-resident data structure
reachable via `EC[e].ecs_ptr`. It holds:

1. ECS metadata: privilege level, scheduling flags, and similar OS bookkeeping.
2. Saved register state for contexts not currently resident in a Bank, or for
   slow-path spills.
3. Pointers to Banks and Contract descriptors owned by this EC.
4. OS/hypervisor-private fields.

The ECS layout is a kernel software convention, not an architectural mandate.
CME instructions take ECID numbers as operands and locate the ECS indirectly
via `EC[e].ecs_ptr`. Chapter 5 describes the Linux kernel representation.

A fast-path context switch (`ec.ib` → `ec.ob`) does not touch the ECS at all.
ECS is accessed only on the DMA path (`ec.im`, `ec.om`), during migration, and
for OS-level bookkeeping.

---

## 0.5 Group

Every ECID `e` has exactly one **Group**. The Group's identifier equals the
ECID number: **GroupID = ECID = `e`**.

The Group is the ECID's inventory of resources — the Banks, Contracts, and
child ECIDs that belong to it.

**Up-pointers (the reversal trick).** Groups do not maintain explicit downward
membership lists. Instead, each Bank and Contract carries an **up-pointer** to
the Group that owns it. Ownership is checked at the resource:

```text
owns(current_ecid, bank) ≡ bank.group_id == current_ecid    // one load, one compare
```

This makes hardware ownership enforcement O(1), regardless of how many
resources a Group holds.

**Child renaming.** When an ECID delegates resources to a child ECID, the child
receives its own Group. From the child's perspective, its Group appears as
Group 0. The child cannot observe parent-level GroupIDs. This is the same
isolation that Linux namespaces apply to PIDs in containers: each delegation
level renumbers its world to start at zero.

---

## 0.6 Banks

A **Bank** is a hardware register-state container owned by exactly one Group.
Banks are never shared between ECIDs simultaneously. A Bank stores the GroupID
of its owning Group (equivalently, the ECID number of its owner). Implementations
may additionally cache delegation level, dirty flags, or other state in
implementation-defined fields.

### Non-VMT banks

Non-VMT banks hold GPRs, FPRs, selected CSRs, SATP, and cache partition
configuration (CP).

**RV64 non-VMT bank — 1 KB:**

| Field | Size |
|---|---|
| Group ID and reserved (in x0 slot) | 8 B |
| GPRs x1–x31 | 248 B |
| FPRs f0–f31 | 256 B |
| Cache partition config (CP) | 8 B |
| SATP | 8 B |
| CSRs and reserved | 496 B |
| **Total** | **1024 B** |

**RV32 non-VMT bank — 512 B:**

| Field | Size |
|---|---|
| Group ID and reserved (in x0 slot) | 4 B |
| GPRs x1–x31 | 124 B |
| FPRs f0–f31 | 128 B |
| Cache partition config (CP) | 4 B |
| SATP | 4 B |
| CSRs and reserved | 248 B |
| **Total** | **512 B** |

The Group ID occupies the slot where x0 would otherwise appear. x0 is
architecturally always zero and carries no register state; reusing its slot for
the Group ID wastes nothing.

### VMT banks

VMT banks hold vector, matrix, and tensor register files. Their size scales
with the implementation's vector width: for 256-bit vector registers a VMT bank
is approximately 1 KB; each doubling of the vector width doubles the bank size.
VMT banks are allocated and managed separately from non-VMT banks.

---

## 0.7 Contracts

A **Contract** is a slice of a global, multiplexed resource:

- **MSE Contracts** — memory bandwidth and latency guarantees.
- **QoS Contracts** — I/O and NoC bandwidth and latency guarantees.
- **CPE Contracts** — cache ways or a fraction of cache capacity.

Four invariants govern all Contracts:

1. **Single ownership.** A Contract has exactly one owning Group at any moment.
   Ownership can be transferred but not duplicated.
2. **Hierarchical splitting.** A privileged actor may split a Contract into
   child Contracts. Each child is a strict subset of its parent; the sum of all
   children's allocations never exceeds the parent's.
3. **Atomic admission.** Splitting or binding a Contract requires chip-global
   arbitration that succeeds or fails atomically. On failure, no state changes.
4. **Dissolution.** When the owning Group is destroyed, the Contract dissolves
   and its resources return to the parent Contract. Contract trees are bounded
   by the same delegation depth D as ECID trees.

---

## 0.8 Delegation

Every ECID has a **delegation level** `L`, stored in `EC[e].delegation_L`. The
implementation exposes a read-only cap `D` via a CSR, where **D ≤ 3**:

- **`L < D`**: this ECID may create child ECIDs and delegate Banks and
  Contracts to them.
- **`L = D`**: this ECID may bind resources for its own use but may not
  delegate further.

Root ECIDs (created by firmware or the kernel) have `L = 0`. Each delegation
step increments `L` by 1 in the child. The cap D ≤ 3 matches the realistic
depth of nested virtualization:

```
L0 — host kernel
L1 — hypervisor
L2 — nested hypervisor
L3 — guest
```

Implementations may expose a smaller cap (D = 0, 1, 2, or 3); D > 3 is not
permitted.

**Parent/child relationship.** Every non-root ECID has a parent ECID stored in
`EC[e].parent_ecid`. Only the parent or a privileged ancestor may revoke or
destroy a child.

**Forced destruction.** Destroying an ECID and its entire subtree must always
succeed. The instruction `ec.oe` (§0.9) revokes all Contracts, frees all Banks,
marks the radix-tree subtree as free, and increments the generation counter for
every freed `EC[e]` slot. A destroyed EC cannot stall its own reclamation.

---

## 0.9 CME Instruction Operand Conventions

All CME instructions follow the naming scheme `ec.{i,o}{target}` where `i` =
into (save/create/assign) and `o` = out of (restore/destroy/revoke). Target
letters name the target or kind and are drawn from `{b, m, s, g, t, v, e, r}`
(charter §6.1).

**ECID-first operands.** Any instruction that targets a context other than the
currently running one takes an ECID number as its primary operand — never a raw
pointer, never a bank ID:

```text
ec.ob rd, rs1, rs2 # rd = result, rs1 = target ECID number, rs2 = register mask
ec.om rd, rs1, rs2 # rd = result, rs1 = target ECID number, rs2 = mask
ec.oe rs1          # rs1 = target ECID to destroy (no rd — always succeeds)
```

Instructions operating on the current context consult `current_ecid`
implicitly and omit the ECID operand:

```text
ec.ib rs1          # save current context; rs1 = mask (no rd — always succeeds or traps)
```

**Error handling.** Every CE Suite instruction that can return a failure code
writes 0 (success) or a non-zero error code in `rd`. Callers pass `x0` to
discard the result. Status CSRs (`cme_status`, etc.) are updated for
diagnostic use but are not the primary error channel. Two exceptions carry no
`rd`: `ec.ib` (always succeeds or traps) and `ec.oe` (always succeeds).
Any instruction referencing an unallocated slot, a stale generation, or a
privilege violation must raise a defined trap or return a documented failure
code in `rd`. Silent ignore is prohibited.

**Instruction summary:**

| Instruction | Description |
|---|---|
| `ec.ib` | Save current context to Bank (fast path) |
| `ec.ob` | Restore target ECID's context from Bank (fast path) |
| `ec.im` | Spill Bank to ECS in RAM (DMA path) |
| `ec.om` | Fill Bank from ECS in RAM (DMA path) |
| `ec.ig` | Assign a free Bank to an ECID's Group |
| `ec.og` | Release a Bank from an ECID's Group |
| `ec.it` | Delegate resources to a child ECID |
| `ec.ot` | Revoke all resources from a child ECID |
| `ec.ir` | Allocate a new child ECID |
| `ec.oe` | Forced destroy of ECID and subtree (always succeeds) |
| `ec.iv` | Seal Bank under hardware encryption |
| `ec.ov` | Unseal Bank for a secure enclave |

Full instruction definitions are in Chapter 2.

---

## 0.10 Context Restore Mask

The register mask passed as `rs1` to `ec.ib` and as `rs2` to `ec.ob`, `ec.im`, and `ec.om`
is a 64-bit value selecting which register groups participate in the operation:

| Bits | Register group | Notes |
|---|---|---|
| 0 | GPR | Integer registers |
| 1 | FPR | Floating-point registers |
| 2 | VEC | Vector registers (RVV) |
| 3 | MAT | Matrix/tensor (future) |
| 4 | PC | Program counter |
| 5 | CSR | Control/status registers |
| 6 | SATP | Address translation register |
| 7 | — | Reserved |
| 8–31 | — | Reserved for GPR subsets |
| 32–47 | — | Reserved for FPR subsets |
| 48–51 | — | CP and other CSR subsets |
| 52–59 | — | VMT register subsets |
| 60–63 | — | Reserved |

If bit 4 (PC) is set in an `ec.ob` mask, execution jumps to the restored
program counter immediately on commit of the instruction.

Bits not assigned above are reserved and must be zero.
