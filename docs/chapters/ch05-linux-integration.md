# Chapter 5 — Linux Kernel Integration

## Overview

This chapter describes how Linux integrates the CE Suite. It is intentionally
framed at two levels that must be kept separate:

1. **Architectural level.** CME instructions take ECID numbers as operands.
   The hardware lookup path is `EC[e].ecs_ptr` (Chapter 0, §0.x). Linux
   has no privileged knowledge of the internal CE hardware tables; it interacts
   via CSRs and ECID-operand instructions.

2. **Linux convention level.** Linux represents an ECS as `struct
   execution_context`, allocated in kernel memory. The kernel writes the
   address of that struct into `EC[e].ecs_ptr` after ECID allocation. The ECID
   number itself is cached in the struct for scheduler use. Pointer idioms —
   "load `task->ecid` into a register, then issue `ec.ob`" — are Linux
   conventions, not architectural rules. The CME instruction receives an
   ECID number; how the kernel obtained that number is the kernel's business.

This separation is load-bearing. A future OS (Windows, Zephyr, a type-1
hypervisor) may represent ECS differently. The architecture accommodates all
of them because the architectural contract is "ECID number in a register,"
not "pointer to a specific struct layout."

---

## 5.1 The Linux Execution Context Struct

Linux defines one struct to represent the CE-relevant state of a schedulable
unit — thread, process, vCPU, interrupt handler, or enclave:

```c
struct execution_context {
    u16   ecid;            /* CE-assigned ECID for this context, on this hart */
    u8    delegation_level;/* delegation level L, cached from EC[e] */
    u8    flags;           /* CE-related flags (realtime, secure, etc.) */
    u32   os_flags;        /* OS scheduling flags */
    void *stack_ptr;       /* kernel stack */
    void *entry_point;     /* initial PC */
    /* ... OS bookkeeping, accounting, cgroup pointers ... */
};
```

The field layout above is a **Linux convention**, not an architectural
requirement. Hardware never indexes into this struct directly. The CE hardware
reaches it only through `EC[e].ecs_ptr`, which the kernel sets after calling
`ec.ir` to allocate the ECID.

> **Note on offset 0.** Charter §3.2 mandates that `ecs_ptr` sits at offset 0
> of the `EC[e]` hardware entry, so that a single load from
> `cme_ec_table_base + e * stride` yields the ECS pointer. That constraint
> applies to the hardware `EC[e]` struct, not to the Linux `struct
> execution_context`.

### 5.1.1 ECID lifecycle from Linux's perspective

```
1. Kernel calls ec.ir to allocate a new ECID slot.
   ec.ir rd, rs1   // rd = new ECID number; rs1 = 0 (leaf child) or 1 (delegating child)
   
2. Kernel allocates struct execution_context in kernel memory.

3. Kernel writes EC[new_ecid].ecs_ptr = &execution_context.
   (This is a CSR or memory write to the EC table, not a CME instruction operand.)

4. Kernel caches new_ecid in execution_context->ecid.

5. On context switch, kernel loads execution_context->ecid and passes it
   as the ECID operand to CME instructions.

6. On context teardown, kernel calls ec.oe to destroy the ECID and
   reclaim resources. EC[e]'s generation counter is incremented;
   any stale (ecid, generation) references held elsewhere are detectable.
```

---

## 5.2 The Linux Idiom for CME Instructions

CME instructions take **ECID numbers**, not pointers. The canonical Linux
context-switch sequence is:

```asm
    # Outgoing context: ec.ib uses current_ecid CSR implicitly.
    # No ECID operand; rd = bank slot index (x0 discards; always succeeds or traps).
    ec.ib  x0, FULL_MASK         # save current context to its bank

    # Load incoming ECID from the task struct (Linux convention):
    lhu    a1, ECID_OFFSET(next_task)   # a1 = next_task->ecid

    # ec.ob takes rd, then ECID, then mask (charter §6.6).
    ec.ob  x0, a1, FULL_MASK    # restore next context from its bank
```

The `lhu` instruction is a Linux-software step that retrieves the ECID from
the incoming task's `execution_context` struct. The `ec.ob` instruction itself
is purely architectural: `rd` (`x0`) discards the success/error result,
`rs1` (`a1`) holds the 16-bit ECID number, and `rs2` is the register mask.
The two are distinct operations at distinct levels of abstraction.

### 5.2.1 DMA spill and fill

When no free bank is available for the incoming task, Linux falls back to the
DMA path:

```asm
    # Spill outgoing context from bank to ECS in RAM.
    # The hardware derives the ECS address from EC[current_ecid].ecs_ptr.
    mv     a0, current_ecid_reg        # or read from current_ecid CSR
    ec.im  x0, a0, FULL_MASK          # bank → ECS DMA

    # Fill incoming context from ECS to a newly assigned bank.
    lhu    a1, ECID_OFFSET(next_task)
    ec.om  x0, a1, FULL_MASK          # ECS → bank DMA
```

The ECS address (`EC[e].ecs_ptr`) is architectural; the instruction derives it
from the ECID operand. The kernel does not supply the pointer as an instruction
operand.

---

## 5.3 Cache Residency via CPE

Linux can use CPE to guarantee that frequently-accessed kernel data structures
— including hot parts of `struct execution_context` for runnable tasks — remain
in partitioned L1 or L2-private cache ways.

```asm
    # Assign cache partition to an ECID (rd discarded, rs1 = ECID, rs2 = descriptor).
    cp.ir  x0, rs1, rs2    # allocate cache partition for ECID rs1
```

The CPE instruction `cp.ir` follows the same ECID-operand convention as CME:
`rs1` holds the ECID number, not a pointer to a task struct. The partition
assignment is recorded in `EC[e]` and enforced by the L1/L2 controllers. See
Chapter 7 for the full CPE instruction reference.

---

## 5.4 Interaction with Other CE Components

Linux exposes CE capabilities via a unified per-task context that covers all
four extensions:

| Extension | What Linux configures | When |
|---|---|---|
| **CME** | ECID allocation, bank assignment, delegation depth | Task creation and teardown |
| **CPE** | Cache partition assignment per ECID | Scheduling policy change or vCPU pin |
| **MSE** | Memory bandwidth/latency Contract binding | Cgroup or RT-class assignment |
| **QoS** | I/O bandwidth/latency Contract binding | Device cgroup or enclave setup |

All of these are driven by the ECID: the kernel sets up the ECID first, then
binds CPE partitions, MSE Contracts, and QoS Contracts to it. Tearing down an
ECID via `ec.oe` cascades: all bound Contracts dissolve and return their
resources to the parent Contract; all assigned banks are freed.

### 5.4.1 MSE Contract binding

Linux's real-time scheduling classes (SCHED_DEADLINE, SCHED_FIFO) map onto MSE
Contracts. The kernel allocates a Contract representing a bandwidth/latency
budget and binds it to the task's ECID at task-creation time:

```
ms.ir  rd, rs1, rs2   # assign MSE Contract to ECID rs1; rs2 = descriptor; rd = 0 or error
ms.it  rd, rs1, rs2   # delegate sub-Contract to child ECID in rs2; rs1 = parent ECID; rd = 0 or error
```

When the task is destroyed, `ec.oe` dissolves its MSE Contract automatically.
If the task is demoted (e.g., moved from SCHED_DEADLINE to SCHED_OTHER), the
kernel explicitly revokes the Contract with `ms.ot` before the ECID continues
running without it.

### 5.4.2 Delegation to guests (KVM/bhyve)

When Linux runs a guest VM, the hypervisor kernel:

1. Allocates a child ECID for each vCPU at delegation level L+1.
2. Delegates a subset of its own MSE, QoS, and CPE Contracts to those child ECIDs.
3. Sets `EC[child].parent_ecid = hypervisor_ecid`.
4. On VM teardown, calls `ec.oe hypervisor_ecid` — or individually `ec.oe
   vcpu_ecid` per vCPU — which recursively reclaims all delegated resources.

The guest OS is unaware of the host-level ECID numbers. From its perspective,
it owns its own ECID namespace starting at the delegation level it was given.
(Charter §4.1: "A child Group is delegated to a child ECID and appears to the
child as that child's Group 0.")

---

## 5.5 Non-Linux Operating Systems

The architectural contract is ECID number in a register. Any OS can integrate
CE without adopting the Linux `struct execution_context` layout. The only
invariant is:

1. The OS allocates an ECID for each scheduled unit and caches the ECID number
   somewhere accessible to the scheduler.
2. Before issuing `ec.ob` for an incoming context, the scheduler loads the
   ECID number into a general-purpose register.
3. After allocating a new ECID via `ec.ir`, the OS writes `EC[new_ecid].ecs_ptr`
   to point to its own per-task state structure (whatever shape that takes).

Examples:

| OS | Likely ECS representation |
|---|---|
| **Windows** | `ETHREAD`/`EPROCESS` or a dedicated CE extension struct |
| **Zephyr** | `struct k_thread` with a CE sidecar struct |
| **FreeRTOS** | `TCB_t` extended with CE fields |
| **KVM (hypervisor mode)** | `struct kvm_vcpu` with `ecid` and Contract IDs |
| **Bare-metal firmware** | Static per-hart table of ECID→task mappings |

The architecture makes no demands on any of these shapes. The only coupling is
`EC[e].ecs_ptr`, which each OS sets once after `ec.ir` and then maintains as
its own business.

---

## 5.6 Disable and Ignore

Linux must handle three CE availability modes gracefully:

1. **CE disabled by firmware.** All CE CSRs read zero; all CE instructions trap
   as illegal. Linux detects this at boot via the ISA feature string and falls
   back to conventional context-switch code. No CE-specific paths are entered.
2. **CE enabled, Linux ignores it.** A CE-unaware Linux kernel runs on a
   CE-capable hart without using any CE instructions. The hardware imposes no
   penalty. This is the forward-compatibility guarantee that allows CE to be
   added to hardware before kernel support lands.
3. **CE enabled, Linux uses it.** The boot-time ECID handed from M-mode
   firmware to the kernel seeds the root of the delegation tree. The kernel
   allocates child ECIDs for each hart's initial task and from there proceeds
   normally.

Linux should expose these three states via a kernel config option
(`CONFIG_RISCV_CE`) and a boot parameter (`riscv_ce=off`) for isolation
during debugging.

---

[Next: Chapter 6 — CME Usage Examples](ch06-cme-usage-examples.md)
