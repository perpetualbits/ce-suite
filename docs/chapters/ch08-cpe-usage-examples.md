# Chapter 8 — CPE Usage Examples

## 1. Overview

This chapter illustrates real-world usage patterns of the Cache Partitioning
Extension (CPE). Examples cover partition assignment for real-time tasks,
context-switch transparency, delegation to guest vCPUs, revocation, and
error handling.

All examples assume:

- ECIDs and banks are pre-allocated; `EC[e]` entries are initialised before the
  sequences shown.
- The `cp.*` instruction set uses the `{cp}.{i,o}{target}` format, where `i`
  means "into" (assign/delegate) and `o` means "out of" (revoke). Target
  letters: `r`=resource (partition), `t`=tenant (delegation). The full reference
  is in Chapter 7.
- Instructions that can fail write 0 (success) or a non-zero error code in `rd`.
  In examples below, `x0` is used for `rd` to discard the result where the fast
  path is expected to succeed.
- Inline descriptors are XLEN-wide values with bit `[XLEN-1]` = 0. The pointer
  form (bit `[XLEN-1]` = 1) is used in examples that need more than 8 ways per
  level; the struct fields are defined in Chapter 7 §4 and §5.
- `cpe_caps` field positions used below are **informative**, not yet normative
  (Chapter 7 §7). A production driver should read the normative layout once it
  is defined. The examples show the probing pattern; the exact shifts may change.

---

## 2. Probing Capabilities

### Scenario

Before assigning partitions, the kernel reads `cpe_caps` to discover the
maximum number of ways per level and which levels support partitioning.

### Code

```asm
    csrr   t0, cpe_caps

    # Extract max L1 ways (bits 3:0, log2 encoded).
    # e.g. t1 = 4 means up to 16 L1 ways.
    andi   t1, t0, 0xF          # t1 = log2(max_L1_ways)
    li     t2, 1
    sll    t2, t2, t1           # t2 = max_L1_ways

    # Check L1D partitioning supported (bit 9).
    srli   t3, t0, 9
    andi   t3, t3, 1            # t3 = 1 if L1D partitioning available

    # Check delegation supported (bit 11).
    srli   t4, t0, 11
    andi   t4, t4, 1            # t4 = 1 if cp.it/cp.ot available
```

### Notes

- The `cpe_caps` bit layout shown here is **informative** (Chapter 7 §7). Treat
  the field positions as illustrative until the normative encoding is defined.
- A driver should perform this probe once at boot and cache the results; do not
  read `cpe_caps` on every partition assignment.
- If a level is not supported, assigning ways to it returns `CPE_ERR_UNSUPPORTED`.

---

## 3. Assigning a Partition to a Real-Time Task

### Scenario

A real-time audio DSP task (`rt_ecid`) is assigned exclusive use of L1 ways 0–3
and L2 ways 0–1 to prevent cache eviction by other tasks on the same hart.

### Code — inline descriptor, L1 + L2

```asm
    # Build inline cp.ir descriptor for cp.ir rd, rs1, rs2:
    #   bits  7:0  = l1_way_mask  (ways 0-3 → 0x0F)
    #   bits 15:8  = l2_way_mask  (ways 0-1 → 0x03)
    #   bits 17:16 = level_sel    (0 = L1+L2)
    #   bit  18    = couple       (0 = independent)
    #   bit  19    = lock_en      (0 = replacement only)
    #   bit  [XLEN-1] = 0         (inline form)

    li    a2, 0x030F             # l1_way_mask=0x0F, l2_way_mask=0x03, level_sel=0
    cp.ir x0, rt_ecid, a2        # assign partition; rd discarded
```

### Code — L1 only, with error check

```asm
    # Assign L1 ways 0-3 only (level_sel = 1 = L1 only).
    #   bits  7:0  = 0x0F  (l1_way_mask)
    #   bits 15:8  = 0x00  (l2_way_mask unused)
    #   bits 17:16 = 0x01  (level_sel = L1 only)

    li    a2, 0x1000F            # level_sel=1 in bits 17:16, l1_way_mask=0x0F
    cp.ir a0, rt_ecid, a2        # a0 = 0 on success, error code on failure
    bnez  a0, .cpe_assign_error
```

### Notes

- Way masks are bit-per-way: bit 0 = way 0, bit 1 = way 1, etc. The inline form
  supports up to 8 ways per level. For implementations with more than 8 ways,
  use the pointer form (`CPE_Assignment_Params` struct, Chapter 7 §4).
- If any requested way is already assigned to another ECID at the same level,
  `cp.ir` returns `CPE_ERR_OVERLAP` and no state changes.
- A subsequent `cp.ir` for the same ECID replaces the prior assignment entirely
  (no partial merge); the hardware writes back and invalidates displaced lines
  before committing the new assignment.

---

## 4. Context Switch — CPE State Is Automatic

### Scenario

Two tasks share a hart. One holds a CPE partition (`rt_ecid`); the other does not
(`be_ecid`, best-effort). The scheduler switches between them.

### Code

```asm
    # Switch from best-effort task to real-time task.
    ec.ib  FULL_MASK              # save be_ecid context (current_ecid implicit)
    ec.ob  x0, rt_ecid, FULL_MASK # restore rt_ecid; CPE partition restored automatically
```

### Notes

- The CPE partition assignment is part of `rt_ecid`'s architectural state. It is
  stored in the CP field of the non-VMT bank (Chapter 0 §0.6) and restored by
  `ec.ob` as part of the normal bank restore — no separate `cp.ir` is needed on
  each context switch.
- When `be_ecid` is restored, its absence of a CPE partition assignment is equally
  automatic: the hardware reverts to unpartitioned access for that ECID.
- CPE enforcement begins immediately when `ec.ob` commits (or at the next
  instruction boundary; implementation-defined per Chapter 7 §3).

---

## 5. Delegating a Sub-Partition to a Guest vCPU

### Scenario

A hypervisor (`hyp_ecid`, L=1) holds a CPE Contract covering L1 ways 0–7. It
launches two vCPUs and delegates 4 ways to each. Neither vCPU can exceed its
allocation; neither can observe the other's partition.

### Setup — delegate to first vCPU

```asm
    # Build inline cp.it descriptor for cp.it rd, rs1, rs2:
    #   bits 15:0  = child_ecid  (vcpu0_ecid, fits in 16 bits)
    #   bits 19:16 = l1_ways     (4 ways)
    #   bits 23:20 = l2_ways     (0, L2 not delegated here)
    #   bit  [XLEN-1] = 0        (inline form)

    li    t0, (4 << 16)          # l1_ways = 4 in bits 19:16
    or    t0, t0, vcpu0_ecid     # child_ecid in bits 15:0
    cp.it a0, hyp_ecid, t0       # delegate 4 L1 ways to vcpu0
    bnez  a0, .cpe_delegate_error
```

### Setup — delegate to second vCPU

```asm
    li    t0, (4 << 16)
    or    t0, t0, vcpu1_ecid
    cp.it a0, hyp_ecid, t0       # delegate 4 L1 ways to vcpu1
    bnez  a0, .cpe_delegate_error
```

### Notes

- After both delegations, `hyp_ecid`'s effective L1 allocation is reduced by 8
  ways. If the hypervisor tries to delegate a third vCPU beyond its remaining
  capacity, `cp.it` returns `CPE_ERR_CAP_EXCEEDED`.
- `vcpu0_ecid` must be a child of `hyp_ecid` in the delegation tree
  (`EC[vcpu0_ecid].parent_ecid == hyp_ecid`). Delegating to an unrelated ECID
  returns `CPE_ERR_PERMISSION`.
- To delegate both L1 and L2 ways, set `l2_ways` (bits 23:20) in the same
  descriptor. For more than 15 ways in either direction, use the pointer form
  (`CPE_Delegation_Params` struct, Chapter 7 §5).
- The vCPU's delegated partition is enforced automatically on `ec.ob` — no
  per-switch `cp.ir` is needed for the guest (Chapter 7 §9).

---

## 6. Revocation and Teardown

### Scenario A — explicit revoke before reassignment

The kernel wants to reclaim `rt_ecid`'s partition and reassign it to a different
task before `rt_ecid` is destroyed.

```asm
    cp.or  a0, rt_ecid           # revoke all partitions; a0 = 0 on success
    bnez   a0, .cpe_revoke_error

    # Ways are now free; assign them to new_ecid.
    li     a2, 0x030F
    cp.ir  x0, new_ecid, a2
```

### Scenario B — teardown via `ec.oe` (implicit revoke)

The kernel destroys `rt_ecid` entirely. CPE Contracts in the subtree are revoked
as part of the destroy sequence; no explicit `cp.or` is needed.

```asm
    ec.oe  rt_ecid               # forced destroy; CPE revoke is implicit
    # Ways are returned to rt_ecid's parent's allocation automatically.
```

### Scenario C — revoking a delegated vCPU partition

The hypervisor reclaims its vCPU's partition before VM teardown.

```asm
    cp.ot  a0, vcpu0_ecid        # revoke vcpu0's delegated partition
    bnez   a0, .cpe_revoke_error
    # 4 ways returned to hyp_ecid's allocation; available for re-delegation.
```

### Notes

- `cp.or` and `cp.ot` both invalidate the cache lines in the revoked ways before
  returning (Chapter 7 §6, sanity rule 5). This is required for isolation: a
  subsequent task cannot read stale data from a previously assigned way.
- `ec.oe` revokes all CPE Contracts in the subtree before freeing the ECID slots.
  Explicit `cp.or` before `ec.oe` is redundant but harmless.
- If `vcpu0_ecid` itself has delegated sub-partitions to grandchildren, `cp.ot`
  revokes those first, recursively (bounded by D ≤ 3). Forward progress is
  guaranteed; a hostile child cannot stall revocation.

---

## 7. Error Handling

### `CPE_ERR_OVERLAP` — way conflict

```asm
    # ECID A already holds ways 0-3 of L1.
    # Attempting to assign ways 2-5 to ECID B overlaps ways 2-3.
    li    a2, 0x3C               # l1_way_mask = ways 2-5 (0b00111100)
    cp.ir a0, ecid_b, a2
    li    t0, 2                  # CPE_ERR_OVERLAP = 2
    beq   a0, t0, .handle_overlap
    # Handle: either revoke A's partition first, or pick non-overlapping ways.
```

### `CPE_ERR_CAP_EXCEEDED` — delegation over-commit

```asm
    # hyp_ecid holds 4 L1 ways total.
    # vcpu0 already has 2; vcpu1 already has 2; nothing left for vcpu2.
    li    t0, (2 << 16)
    or    t0, t0, vcpu2_ecid
    cp.it a0, hyp_ecid, t0
    li    t1, 3                  # CPE_ERR_CAP_EXCEEDED = 3
    beq   a0, t1, .handle_cap_exceeded
    # Handle: revoke one vCPU's delegation before re-trying, or allocate fewer ways.
```

### `CPE_ERR_COUPLE_MISMATCH` — coupling constraint

```asm
    # Assign L1 ways 0-3 (4 ways) and L2 ways 0-0 (1 way) with couple=1.
    # Coupling requires equal fractions; 4 ≠ 1 → mismatch.
    #   bits 7:0  = 0x0F (L1 ways 0-3, 4 ways)
    #   bits 15:8 = 0x01 (L2 way 0, 1 way)
    #   bit 18    = 1    (couple enabled)
    li    a2, 0x4010F            # couple=1 at bit 18, l1=0x0F, l2=0x01
    cp.ir a0, rt_ecid, a2
    li    t0, 4                  # CPE_ERR_COUPLE_MISMATCH = 4
    beq   a0, t0, .handle_couple
    # Fix: use equal way counts, e.g. l1_way_mask=0x03, l2_way_mask=0x03.
```

### Notes

- On any error, `cp.ir` and `cp.it` make no state changes (Chapter 7 §6).
- The full error code table is in Chapter 7 §8.

---

## 8. Hart Migration

### Scenario

A task (`rt_ecid`) migrates from hart A to hart B. CPE state is per-hart and
does not transfer automatically. The kernel must re-issue `cp.ir` on the
destination hart after migration.

### Code

```asm
    # --- On hart A (source) ---

    # 1. Revoke CPE partition on source hart (optional but cleans up resources).
    cp.or  x0, rt_ecid

    # 2. Spill bank state to ECS in RAM.
    ec.im  x0, rt_ecid, FULL_MASK

    # 3. Destroy source ECID; kernel allocates fresh ECID on hart B.
    ec.oe  rt_ecid

    # --- On hart B (destination) ---

    # 4. Kernel allocates new ECID (new_ecid) on hart B, sets up EC[new_ecid].
    ec.ir  new_ecid_reg, 1       # allocating a delegating child on hart B

    # 5. Fill bank from ECS (same ECS in RAM as before).
    ec.om  x0, new_ecid_reg, FULL_MASK

    # 6. Re-issue CPE partition on hart B.
    li     a2, 0x030F            # same descriptor as before
    cp.ir  x0, new_ecid_reg, a2
```

### Notes

- CPE state is per-hart (Chapter 7 §9). After migration, the kernel must call
  `cp.ir` on the destination hart before the migrated task runs.
- The ECS in RAM — including saved register state — is reused across harts. Only
  the ECID and CPE assignment are hart-local and must be re-established.
- MSE and QoS Contracts are similarly per-hart or per-controller and may require
  re-binding after migration. See Chapters 11 and 12.

---

## 9. Where to go next

**Chapter 7** is the normative CPE instruction reference: full instruction
semantics, descriptor encoding tables, hardware sanity rules, CSRs, and error
codes.

**Chapter 10** covers MSE usage examples: how to assign and delegate memory
bandwidth and latency Contracts, and how MSE and CPE compose for hard real-time
workloads.

[Next: Chapter 9 — MSE: Memory Scheduling Extension](ch09-mse-memory-scheduling.md)
