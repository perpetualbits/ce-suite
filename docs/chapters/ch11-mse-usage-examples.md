# Chapter 11 — MSE Usage Examples

## 1. Overview

This chapter illustrates real-world usage patterns of the Memory Scheduling
Extension (MSE). Examples cover Contract assignment, latency bound calculation,
context-switch transparency, delegation to guest vCPUs, revocation, error
handling, and the combination of MSE with CPE for end-to-end bounded memory
latency.

All examples assume:

- ECIDs and banks are pre-allocated; `EC[e]` entries are initialised before the
  sequences shown.
- The `ms.*` instruction set uses the `{ms}.{i,o}{target}` format, where `i`
  means "into" (assign/delegate) and `o` means "out of" (revoke). Target
  letters: `r`=resource (Contract), `t`=tenant (delegation). The full reference
  is in Chapter 8.
- Instructions that can fail write 0 (success) or a non-zero error code in `rd`.
  `x0` is used for `rd` to discard the result where the fast path is expected
  to succeed.
- Inline `rs2` values use the encoding defined in Chapter 8 §5:
  - For `ms.ir`: bits 3:0 = `bw_class`, bits 7:4 = `lat_class`, bit `[XLEN-1]` = 0.
  - For `ms.it`: bits 15:0 = `child_ecid`, bits 19:16 = `child_bw_class`,
    bits 23:20 = `child_lat_class`, bit `[XLEN-1]` = 0.

---

## 2. Reading Latency Parameters

### Scenario

Before assigning Contracts, the kernel reads the slot size and maximum interrupt
nesting depth to determine worst-case DRAM latency bounds.

### Code

```asm
    csrr   t0, mse_slot_ns       # slot size in nanoseconds (RO)
    csrr   t1, mse_max_nesting   # max interrupt nesting depth K (RO)

    # Worst-case CN latency = (K + 1) × slot_size_ns.
    addi   t2, t1, 1             # t2 = K + 1
    mul    t2, t2, t0            # t2 = worst-case latency in nanoseconds
```

### Notes

- `mse_slot_ns` and `mse_max_nesting` are read-only and fixed per implementation.
  Read them once at boot and cache the results.
- On an implementation with K=1 and slot size=128 ns, worst-case CN latency is
  256 ns. This is the number to put in a WCET budget or deadline analysis.
- `mse_bw_sum` (RO) holds the running sum of `bw_class` across all active
  Contract holders on this hart. Read it before calling `ms.ir` to check
  remaining headroom without making a failing call.

---

## 3. Assigning a Contract to a Real-Time Task

### Scenario

A real-time audio DSP task (`rt_ecid`) is assigned an MSE Contract guaranteeing
minimum memory bandwidth and bounded latency. The ECID is not currently running.

### Code — inline descriptor

```asm
    # Build inline ms.ir descriptor:
    #   bits 3:0  = bw_class  (e.g. 4 = bandwidth class 4)
    #   bits 7:4  = lat_class (e.g. 2 = latency class 2, lower = higher priority)
    #   bit [XLEN-1] = 0 (inline form)

    li    a2, ((2 << 4) | 4)     # lat_class=2, bw_class=4 → 0x24
    ms.ir a0, rt_ecid, a2        # assign Contract; a0 = 0 on success
    bnez  a0, .mse_assign_error

    # Contract is stored in EC[rt_ecid]. It takes effect on the next
    # ec.ob that restores rt_ecid's bank.
```

### Code — assigning to the currently-running ECID

```asm
    # If rt_ecid is currently running on this hart, the Contract takes effect
    # immediately at the next CN slot boundary — no ec.ob needed.
    li    a2, ((2 << 4) | 4)
    ms.ir a0, current_ecid_val, a2
    bnez  a0, .mse_assign_error
    # Memory controller registers updated; new class active at next slot.
```

### Notes

- `bw_class` controls the guaranteed minimum bandwidth (number of CN slots per
  scheduling window). `lat_class` controls arbitration priority within CN slots:
  lower value = higher priority.
- An ECID with `bw_class=0` and `lat_class=0` is best-effort and does not
  participate in CN slot arbitration. Assigning both to zero via `ms.ir` has
  the same effect as `ms.or`.
- `ms.ir` checks two admission conditions before committing (Chapter 8 §5, §7.3):
  the group bandwidth cap and the system-wide CN budget. If either fails, `rd`
  holds the error code and no state changes.

---

## 4. Context Switch — MSE Contract Is Automatic

### Scenario

Two tasks share a hart. One holds an MSE Contract (`rt_ecid`); the other is
best-effort (`be_ecid`). The scheduler switches between them.

### Code

```asm
    # Switch from best-effort task to real-time task.
    ec.ib  FULL_MASK              # save be_ecid context (current_ecid implicit)
    ec.ob  x0, rt_ecid, FULL_MASK # restore rt_ecid; MSE Contract restored automatically
```

### Notes

- The MSE Contract parameters (`bw_class`, `lat_class`) are stored in the CP
  field of the non-VMT bank (Chapter 0 §0.6). `ec.ob` restores the entire bank,
  including CP, in one operation. The memory controller reads the new class
  values from per-hart registers, which are updated as part of `ec.ob`.
- No separate `ms.ir` is needed on every context switch. The Contract follows
  the ECID automatically.
- When `be_ecid` is restored, its absence of a Contract (both fields zero) is
  equally automatic: the memory controller reverts to best-effort arbitration
  for that ECID.

---

## 5. MSE and CPE Together — End-to-End Latency

### Scenario

A hard real-time task needs both cache isolation (CPE) and bounded DRAM latency
(MSE). Assigned once at task creation; both Contracts travel with the ECID across
context switches.

### Setup

```asm
    # Assign CPE cache partition: L1 ways 0-3, L2 ways 0-1.
    li    a2, 0x030F             # l1_way_mask=0x0F, l2_way_mask=0x03
    cp.ir x0, rt_ecid, a2

    # Assign MSE Contract: bw_class=4, lat_class=1.
    li    a2, ((1 << 4) | 4)    # lat_class=1, bw_class=4 → 0x14
    ms.ir x0, rt_ecid, a2
```

### Context switch (no additional setup needed)

```asm
    ec.ib  FULL_MASK
    ec.ob  x0, rt_ecid, FULL_MASK  # restores both CPE partition and MSE Contract
```

### Resulting latency bounds

```
    Cache hit  (data in CPE-partitioned L1/L2):  1 cycle          (CPE guarantee)
    Cache miss (uncached DRAM access):           ≤ (K+1) × slot   (MSE guarantee)
```

### Notes

- CPE and MSE are complementary: CPE eliminates evictions so the working set
  stays cache-resident; MSE bounds the latency for the accesses that do reach
  DRAM.
- Both Contracts are stored in the bank's CP field and restored atomically by
  `ec.ob`. There is no window between context switch and Contract enforcement.

---

## 6. Delegating a Contract to a Guest vCPU

### Scenario

A hypervisor (`hyp_ecid`, L=1) holds an MSE Contract with `bw_class=8`,
`lat_class=1`. It delegates portions to two vCPUs so each guest gets a
guaranteed memory bandwidth share.

### Delegate to first vCPU

```asm
    # Inline ms.it descriptor: child_ecid=vcpu0_ecid, bw_class=3, lat_class=2.
    #   bits 15:0  = vcpu0_ecid
    #   bits 19:16 = child_bw_class = 3
    #   bits 23:20 = child_lat_class = 2

    li    t0, ((2 << 20) | (3 << 16))  # child_lat_class=2, child_bw_class=3
    or    t0, t0, vcpu0_ecid            # insert child_ecid in bits 15:0
    ms.it a0, hyp_ecid, t0
    bnez  a0, .mse_delegate_error
```

### Delegate to second vCPU

```asm
    li    t0, ((2 << 20) | (3 << 16))
    or    t0, t0, vcpu1_ecid
    ms.it a0, hyp_ecid, t0
    bnez  a0, .mse_delegate_error
    # hyp_ecid has now delegated 6 of its 8 bw_class units; 2 remain.
```

### Notes

- After both delegations, `hyp_ecid`'s effective `bw_class` is reduced by 6.
  A third delegation of `bw_class=3` would fail with `MSE_ERR_CAP_EXCEEDED`.
- Setting `child_bw_class=0` and `child_lat_class=0` in the descriptor causes
  the child to inherit the parent's full class. Use this when the parent wants
  to hand off its entire Contract to one child.
- The child's delegated Contract takes effect on the next `ec.ob` that restores
  the child's bank — or immediately if the child is currently running.
- `ms.it` performs an atomic admission check: if the check fails, the parent's
  allocation is unchanged.

---

## 7. Revocation and Teardown

### Scenario A — explicit Contract revoke before task demotion

A task is demoted from real-time to best-effort (e.g., moved from SCHED_DEADLINE
to SCHED_OTHER in Linux). The kernel revokes the MSE Contract before the ECID
continues running.

```asm
    ms.or  a0, rt_ecid           # revoke Contract; a0 = 0 on success
    bnez   a0, .mse_revoke_error
    # rt_ecid is now best-effort; its bw_class released to parent headroom.
```

### Scenario B — teardown via `ec.oe` (implicit revoke)

The kernel destroys `rt_ecid` entirely. The MSE Contract dissolves automatically
as part of the destroy sequence.

```asm
    ec.oe  rt_ecid               # forced destroy; MSE Contract revoke is implicit
    # bw_class returned to parent's cap headroom automatically.
```

### Scenario C — revoking a delegated vCPU Contract

```asm
    ms.ot  a0, vcpu0_ecid        # revoke vcpu0's delegated Contract
    bnez   a0, .mse_revoke_error
    # vcpu0's bw_class=3 returned to hyp_ecid's headroom.
    # If vcpu0 had further delegated to sub-vCPUs, those are revoked first
    # (recursive, bounded by D ≤ 3; always succeeds).
```

### Notes

- `ms.ot` is the mirror of `ms.it`: it revokes a delegated child Contract and
  returns the bandwidth to the parent's cap headroom.
- `ec.oe` cascades through the delegation subtree, revoking all Contracts before
  freeing ECID slots. Explicit `ms.or` or `ms.ot` before `ec.oe` is redundant
  but harmless.

---

## 8. Error Handling

### `MSE_ERR_CAP_EXCEEDED` — group bandwidth cap

```asm
    # hyp_ecid has bw_cap=8. vcpu0 and vcpu1 each hold bw_class=3 (total 6).
    # Attempting to assign bw_class=4 to vcpu2 would exceed the cap.
    li    t0, ((1 << 20) | (4 << 16))
    or    t0, t0, vcpu2_ecid
    ms.it a0, hyp_ecid, t0
    li    t1, 3                  # MSE_ERR_CAP_EXCEEDED = 3
    beq   a0, t1, .handle_cap
    # Fix: revoke one vCPU's Contract first, or request fewer bw_class units.
```

### `MSE_ERR_SYSTEM_FULL` — global CN budget exhausted

```asm
    li    a2, ((2 << 4) | 8)     # bw_class=8, lat_class=2
    ms.ir a0, new_ecid, a2
    li    t1, 4                  # MSE_ERR_SYSTEM_FULL = 4
    beq   a0, t1, .handle_full
    # Fix: read mse_bw_sum to see how much headroom is available;
    # request a lower bw_class, or wait for another Contract to be revoked.
```

### `MSE_ERR_NOT_CHILD` — delegation to non-child ECID

```asm
    # ms.it requires child_ecid to be a child of rs1 in the delegation tree.
    li    t0, ((1 << 20) | (2 << 16))
    or    t0, t0, unrelated_ecid  # not a child of hyp_ecid
    ms.it a0, hyp_ecid, t0
    li    t1, 2                  # MSE_ERR_NOT_CHILD = 2
    beq   a0, t1, .handle_not_child
```

### Notes

- On any error, no state changes — the parent's allocation is unchanged.
- Read `mse_bw_sum` before calling `ms.ir` to pre-check global headroom without
  risking a failing call. The group cap check requires knowing `bw_cap(parent)`,
  which is stored in `EC[e]` (implementation-defined field).

---

## 9. Monitoring Contract Violations

### Scenario

The kernel enables Contract violation monitoring so it can detect when an ECID
does not receive its guaranteed CN slots in a scheduling window.

### Setup

```asm
    # Enable mse_violation interrupt for this hart.
    li    t0, 1
    csrw  mse_violation_en, t0
```

### Violation handler

```asm
    # Read and clear the violation sticky bit.
    csrr  t0, mse_violation
    li    t1, 1
    csrw  mse_violation, t1      # write 1 to clear

    # t0 encodes which ECID(s) missed their CN slot allocation.
    # Log, raise a system alert, or demote the offending Contract.
```

### Notes

- `mse_violation` is sticky: it accumulates until explicitly cleared by writing 1.
- A violation means the hardware detected that a Contract holder did not receive
  its guaranteed `bw_class` worth of CN slots in the last scheduling window
  (Chapter 8 §8). This can indicate system overload or a mis-configured slot ratio.
- The slot ratio is adjustable via `mse_slot_ratio` (bits 7:0, where 128=50%).
  The BE fraction must remain ≥ 25 % and the CN fraction ≥ 25 % (Chapter 8 §2.1).

---

## 10. Where to go next

**Chapter 8** is the normative MSE reference: slot scheme, Contract parameters,
arbitration rules, CSRs, and error codes.

**Chapter 7** covers CPE (cache partitioning), which composes with MSE for
end-to-end bounded memory latency (see §5 above).

**Chapter 12** covers QoS usage examples: how I/O and NoC bandwidth Contracts
compose with MSE for workloads that span both DRAM and peripheral interconnect.

[Next: Chapter 12 — QoS Usage Examples](ch12-qos-usage-examples.md)
