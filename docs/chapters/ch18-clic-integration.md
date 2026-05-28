# Chapter 18 — CLIC Interrupt Integration

**Status:** Normative.

This chapter specifies how to integrate the CE Suite with the RISC-V Core-Local Interrupt
Controller (CLIC). The CE Suite model already supports assigning interrupt handlers their
own ECIDs, Banks, and cache partitions — an ISR is just another EC. What is missing from
other chapters is the normative description of how to configure this: how to pre-allocate
the ISR ECID at boot, how to write the interrupt vector entry so that interrupt delivery
triggers a bank swap, and how to ensure the ISR's CPE partition is separate from the
preempted task's partition.

No new instructions, CSRs, or hardware mechanisms are required. The integration is
accomplished entirely through existing CE Suite instructions issued in the ISR prologue
and epilogue. CLIC itself has no CE-specific hardware hooks; the bank swap is a software
operation.

---

## 18.1 The problem: shared CE resources under preemption

An interrupt fires asynchronously, preempting whatever EC is currently running on the hart.
Without CE configuration, the ISR begins execution with:

- The preempted task's Bank loaded — containing the task's live register state.
- The preempted task's CPE cache partition active.
- The preempted task's MSE and QoS Contracts in force.

The ISR is borrowing the preempted task's CE resources. This creates two problems.

**Register state corruption.** The ISR writes to GPRs and FPRs that are loaded from
the preempted task's Bank. When the preempted task resumes, it expects those registers
to contain the values they held when it was preempted. A software prologue/epilogue that
saves and restores registers to the stack recovers correctness but adds hundreds of cycles
of latency — exactly what CE banks are designed to eliminate.

**Isolation failure.** The ISR's cache accesses evict lines from the preempted task's
CPE partition. After the ISR returns, the preempted task's working set is partially evicted;
its cache-miss rate on resumption is unpredictable, making WCET analysis invalid. The
preempted task's MSE Contract, sized for the task's peak bandwidth, is now shared with
the ISR's accesses.

Both problems are unacceptable in a hard real-time system. The CE Suite eliminates them
by giving the ISR its own Bank and its own CPE partition, and by swapping to those
resources atomically on interrupt entry.

---

## 18.2 The interrupt-EC pattern

The solution assigns a dedicated ECID to each ISR vector — or to each interrupt priority
level, if multiple vectors share a priority — at boot time. This ECID holds:

- **At least one NV Bank.** The bank swap on interrupt entry and exit is a fast-path
  operation (1–9 cycles each direction, §18.7).
- **A dedicated CPE cache partition.** Separate from the task pool, so the ISR's cache
  activity neither evicts task lines nor is bounded by the task's partition (§18.5).
- **Optionally, an MSE Contract.** For systems where the ISR's DRAM access latency must
  be bounded independently of the preempted task (§18.6).

The ECID is permanent: it is allocated once at boot and released only when the interrupt
vector is deregistered. It is not created or destroyed per interrupt invocation.

On each invocation the ISR prologue and epilogue perform the CE resource swap:

```
Interrupt fires
  prologue: ec.ib (save preempted task's Bank)
            ec.ob (restore ISR's Bank)
ISR body executes — with its own Bank, CPE partition, and Contracts
ISR returns
  epilogue: ec.ib (save ISR's Bank)
            ec.ob (restore preempted task's Bank)
```

From the preempted task's perspective, its Bank, CPE partition, and Contracts are intact
on resumption. From the ISR's perspective, its register state at entry is whatever was
last saved to its Bank (zero-initialized on first invocation).

---

## 18.3 Boot-time allocation

Before enabling any CLIC interrupt vector that requires CE isolation, the platform
allocates a dedicated ECID for it. The allocation is performed by M-mode firmware or
the S-mode kernel, depending on which privilege level manages the interrupt vector table.

```asm
    # ── Allocate a leaf ECID for the ISR vector ──────────────────────────────
    # rs1 = 0 → leaf child: delegation_L = D (cannot delegate further).
    ec.ir  a0, x0                       # a0 = new isr_ecid number
    sh     a0, isr_ecid_slot(s0)        # store in per-hart, per-vector table

    # ── Assign a dedicated CPE cache partition ────────────────────────────────
    # t0 = CPE partition descriptor for this ISR vector (platform-configured).
    cp.ir  x0, a0, t0                   # x0: result discarded (check if errors matter)

    # ── Optionally assign an MSE Contract ─────────────────────────────────────
    # t1 = MSE Contract descriptor (bandwidth/latency class for this ISR).
    ms.ir  x0, a0, t1

    # ── Initialize the ISR Bank with zero register state ─────────────────────
    # Prerequisite: EC[isr_ecid].ecs_ptr must point to a zero-initialized ECS
    # in kernel memory before this step (platform-specific write to the EC table).
    #
    # ec.om performs ECS → Bank DMA, assigning isr_ecid a Bank containing
    # the zero state from its ECS.
    ec.om  x0, a0, FULL_MASK            # isr_ecid now has a Bank with zero state
```

The `ec.om` call initializes the ISR Bank to zero. On the first interrupt invocation the
ISR therefore enters with a clean register file rather than stale hardware state.

Each ISR ECID is recorded in a per-hart, per-vector table. The ISR prologue reads the
ECID from this table during interrupt delivery.

---

## 18.4 Interrupt entry and exit

The ISR prologue must:

1. Preserve the preempted ECID before the bank swap overwrites the GPRs.
2. Save the preempted task's Bank.
3. Restore the ISR's Bank.

The preempted ECID is the current value of the `current_ecid` CSR (Chapter 13). It must
be saved in a location that survives `ec.ob` — specifically, a location that is not a
GPR, because `ec.ob` overwrites all GPRs with the ISR's saved state. In M-mode trap
handlers, `mscratch` is the natural choice: it is an M-mode CSR and is not part of any
Bank (Banks store user/S-mode register state; M-mode CSRs are outside the Bank).

### 18.4.1 M-mode ISR prologue and epilogue

```asm
# ─── ISR prologue ────────────────────────────────────────────────────────────
isr_entry:
    # 1. Save the preempted ECID in mscratch before the GPR bank swap.
    csrr   t0, current_ecid              # t0 = preempted task's ECID
    csrw   mscratch, t0                  # mscratch survives ec.ob (M-mode CSR)

    # 2. Load the ISR ECID for this vector from the per-hart, per-vector table.
    #    Must happen before ec.ob, which will overwrite a0 with ISR Bank state.
    lhu    a0, isr_ecid_slot(s0)         # a0 = isr_ecid (recorded at boot)

    # 3. Save the preempted task's Bank.
    #    ec.ib operates on current_ecid implicitly; GPRs are unchanged by ec.ib.
    ec.ib  x0, FULL_MASK                 # x0: discard bank slot index

    # 4. Restore the ISR's Bank.
    #    After this instruction, GPRs/FPRs contain the ISR's saved state.
    ec.ob  x0, a0, FULL_MASK             # x0: discard result; a0 = isr_ecid

# ─── ISR body ────────────────────────────────────────────────────────────────
    # The ISR executes here. current_ecid is now isr_ecid. The CPE partition
    # enforced by the L1/L2 controllers is the ISR's partition, not the task's.
    ...

# ─── ISR epilogue ────────────────────────────────────────────────────────────
isr_exit:
    # 5. Save the ISR's Bank (preserves ISR state for the next invocation).
    ec.ib  x0, FULL_MASK                 # x0: discard bank slot index

    # 6. Load the preempted ECID from mscratch.
    csrr   a0, mscratch                  # a0 = preempted ECID (saved in step 1)

    # 7. Restore the preempted task's Bank.
    #    After this, GPRs/FPRs are restored to the preempted task's state.
    ec.ob  x0, a0, FULL_MASK             # x0: discard result

    # 8. Return from interrupt.
    mret
```

**`ec.ib` does not modify GPRs.** `ec.ib` snapshots the current register state into the
Bank; it does not alter the registers themselves. After step 3, `a0` still holds `isr_ecid`
and remains valid for step 4. After step 5, the ISR's GPRs are unchanged and available for
step 6.

**Loading `isr_ecid_slot` before step 3.** The load of `s0`-relative `isr_ecid_slot` in
step 2 must complete before `ec.ob` in step 4 overwrites `s0` with the ISR's saved state.
Placing the load at step 2 (before `ec.ib`) satisfies this ordering. Alternatively, the ISR
ECID can be held in a fixed M-mode CSR or per-hart memory at a fixed physical address that
does not require `s0` as a base.

### 18.4.2 Dirty-save optimization

If the ISR is known never to touch FPRs or vector registers, the dirty-save mode of `ec.ib`
(Chapter 3 §3.1, `rs1 = x0`) reduces the save to the GPR group only:

```asm
    ec.ib  x0, x0       # dirty-save mode: save only register groups written
                         # since the last ec.ib or ec.ob; typically 1–3 cycles
```

This is the direct analogue of the FPU lazy-save pattern used in conventional kernels.
`FULL_MASK` remains correct for correctness; dirty-save mode is an implementor's
optimization that trades a minor correctness assumption (ISR does not write FPRs) for
lower entry/exit overhead.

---

## 18.5 CPE cache-partition isolation

Assigning the ISR a dedicated CPE cache partition (`cp.ir` at boot, §18.3) ensures that
the ISR's cache footprint is strictly bounded to its own ways in L1 and L2-private caches.

When `ec.ob x0, a0, FULL_MASK` in the prologue completes, `current_ecid` is updated to
`isr_ecid`. The L1 and L2-private cache controllers enforce the partition recorded for
`isr_ecid`. The preempted task's cache partition is no longer active; the ISR cannot
cause evictions in the task's ways.

On the epilogue `ec.ob`, `current_ecid` reverts to the preempted ECID and the task's
CPE partition is restored. The task's hot lines — undisturbed during the ISR — are
available at full cache speed on resumption.

**Why this matters for WCET.** Without CPE isolation, the ISR's memory access pattern
is part of the preempted task's WCET analysis: the task's cache misses after returning
from the ISR are bounded not only by the task's own accesses but also by what the ISR
evicted. With CPE isolation, the two WCET analyses are fully independent.

**Partition sizing.** The ISR's CPE partition should be sized for the ISR's own working
set. An interrupt handler that accesses a few hundred bytes of code and data may need
only one or two cache ways; an ISR running a small control loop with a kilobyte footprint
needs a proportionally larger partition. These sizes are determined at system design time
and are not architectural constraints.

---

## 18.6 MSE memory reservation (optional)

For systems where the ISR must make bounded-latency DRAM accesses independently of the
preempted task's DRAM activity, an MSE Contract is assigned to the ISR ECID at boot
(`ms.ir`, §18.3).

After the prologue's `ec.ob`, the MSE arbitrator enforces the ISR's Contract, not the
preempted task's. The ISR's DRAM access latency is bounded by its own Contract class,
regardless of what the preempted task was doing or what other harts are doing.

This is particularly relevant for ISRs that service DMA completion or network packet
arrival and must copy data from a device buffer to a kernel ring buffer within a
deadline. If the copy's DRAM latency is unbounded, the ISR's execution time is
unbounded, which breaks the CLIC preemption model's latency guarantee.

When an MSE Contract is not needed — for ISRs that execute entirely from cache — the
`ms.ir` step in §18.3 is omitted. The ISR inherits no MSE Contract from the preempted
task after `ec.ob`; it runs without a Contract, which means its DRAM accesses are
best-effort. This is the correct default for cache-resident interrupt handlers.

---

## 18.7 Nested interrupts

CLIC supports preemptable interrupt delivery: a higher-priority interrupt can preempt a
lower-priority ISR. The prologue/epilogue in §18.4.1 handles nesting correctly without
modification.

When a higher-priority interrupt fires while a lower-priority ISR is executing:

1. The prologue saves the preempted ECID in `mscratch`. At this point, the preempted
   ECID is the lower-priority ISR's ECID — not a task ECID.
2. The bank swap in steps 3–4 saves the lower-priority ISR's Bank and loads the
   higher-priority ISR's Bank.
3. The higher-priority ISR executes with its own dedicated ECID, Bank, and partition.
4. The epilogue restores the lower-priority ISR's Bank and ECID from `mscratch`, and
   the lower-priority ISR resumes.

The only requirement is that each interrupt priority level has its own ECID and Bank.
The number of ISR ECIDs needed is bounded by the system's CLIC priority level count,
which is a platform constant, not by the CE delegation depth D.

ISR ECIDs at different priority levels may all be children of the same parent ECID (the
S-mode kernel ECID or an M-mode root ECID), each as a leaf at delegation level D. The
delegation tree does not need to reflect the interrupt priority hierarchy.

---

## 18.8 Bank provisioning

For the prologue bank swap to succeed on the fast path, both the preempted task's Bank
and the ISR's Bank must be resident in on-chip SRAM at the moment the interrupt fires.
Chapter 4 §4.3 describes the SRAM-vs-RAM residency model.

The ISR's Bank is always resident: it is filled at boot (§18.3) and saved by the
epilogue on every exit, keeping it in SRAM.

The preempted task's Bank should be resident if the system has enough NV Bank slots to
hold all concurrently active ECIDs. System designers must provision sufficient NV banks
(readable from `cme_bank_count`, Chapter 13 §3.2) to cover:

- All runnable task ECIDs that may be in hardware at the moment an interrupt fires.
- All ISR ECIDs at all priority levels that may nest simultaneously.

If the preempted task's Bank is not resident, `ec.ob` for the task in the epilogue
returns `CME_ERR_NO_BANK` and the software must follow the Bank Exhaustion Recovery
protocol in Chapter 3 §3.1 and Chapter 15 §15.4 before resuming the task.

---

## 18.9 Timing

The CE portion of interrupt entry and exit overhead, on the fast path (both Banks in
SRAM):

| Operation | Cycles (fast path) |
|---|---|
| `ec.ib` — save preempted task's Bank | 1–9 |
| `ec.ob` — restore ISR's Bank | 1–9 |
| **Total prologue CE overhead** | **2–18** |
| `ec.ib` — save ISR's Bank | 1–9 |
| `ec.ob` — restore preempted task's Bank | 1–9 |
| **Total epilogue CE overhead** | **2–18** |

With dirty-save mode (`ec.ib x0, x0`) and a GPR-only ISR, each `ec.ib` drops to 1–3
cycles, reducing total per-direction overhead to 2–12 cycles.

Compare to conventional software save/restore: saving and restoring 32 GPRs and 32 FPRs
requires at minimum 128 load/store instructions, 128 cycles of issue bandwidth, plus
cache-miss penalties if the stack is cold. With CE, the entire save/restore fits within
the bank SRAM and is independent of the data-cache state.

The CPE bank swap (the L1/L2 controller switching from the task partition to the ISR
partition) happens as a side effect of `ec.ob` updating `current_ecid`. No additional
cycles are required beyond the `ec.ob` latency above.

> **Informative note.** The timing ranges above are from Chapter 4 §4.5–§4.6 and
> apply to the non-VMT bank path. ISRs that use vector register files incur the VMT
> bank timing (Chapter 4 §4.6).

---

## 18.10 Other operating environments

The pattern in §18.4.1 is written for M-mode trap handlers. The same pattern applies
at other privilege levels, with the privilege-appropriate scratch register and return
instruction:

| Environment | Privilege level | Scratch for preempted ECID | Return instruction |
|---|---|---|---|
| Bare-metal firmware | M-mode | `mscratch` | `mret` |
| RTOS (CLIC delegated to S-mode) | S-mode | `sscratch` | `sret` |
| Linux IRQ handler | S-mode | per-cpu kernel variable (pre-prologue store) | `sret` |
| KVM guest VM | VS-mode | `vsscratch` | `sret` (VS) |

The ISR ECID is allocated at the privilege level that owns the interrupt vector table.
M-mode firmware allocates ISR ECIDs for M-mode vectors; the S-mode kernel allocates ISR
ECIDs for S-mode delegated interrupts. Allocation and CPE/MSE assignment follow §18.3
at the appropriate privilege level.

For Linux, the IRQ handler subsystem would wrap each registered interrupt handler in a
CE-aware trampoline that performs steps 1–4 on entry and steps 5–8 on exit. The ISR
ECID for each IRQ line would be allocated once by the CE-aware IRQ subsystem when the
interrupt is first requested (`request_irq`), and released when the interrupt is freed
(`free_irq`). This is a software convention, not an architectural requirement.

---

## 18.11 Relationship to other chapters

**Chapter 3 (CME Instruction Set Reference)** defines `ec.ib` (§3.1), `ec.ob` (§3.1),
`ec.om` (§3.2), `ec.ir` (§3.5), and `ec.oe` (§3.6). The dirty-save mode for `ec.ib`
is specified in §3.1. The Bank Exhaustion Recovery protocol referenced in §18.8
is in §3.1 and §3.3.

**Chapter 4 (Hardware Microarchitecture)** specifies the SRAM-vs-RAM residency model
(§4.3), NV and VMT bank timing tables (§4.5–§4.6), and the power-gating protocol
(§4.14). The fast-path cycle counts in §18.9 come from §4.5–§4.6.

**Chapter 7 (CPE Instruction Set Reference)** defines `cp.ir` — the cache partition
assignment instruction used in §18.3.

**Chapter 9 (MSE)** defines `ms.ir` — the MSE Contract assignment instruction used in
§18.3.

**Chapter 13 (CSR Reference)** defines `current_ecid` (§3.1) and `cme_bank_count`
(§3.2), the CSR used to determine available NV bank slots for §18.8.

**Chapter 14 (Privilege Model)** specifies which privilege levels may issue CE
instructions and how interrupt delegation interacts with CE (§14.8).

**Chapter 15 (Trap and Exception Table)** defines `CME_ERR_NO_BANK` (§15.3) and the
Bank Exhaustion Recovery cross-reference (§15.4).

---

[Next: Appendix A — ECID Radix Tree Algorithms](appendix-a-ecid.md)

---

*End of Chapter 18.*
