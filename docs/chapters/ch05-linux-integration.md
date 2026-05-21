# Chapter 5: Linux Kernel Integration

## 1. Overview

This chapter outlines how the Linux kernel (and other OSes) can integrate the Context Management Extension (CME) and related CE stack components (CPE, QoS, MBW). While Linux is the primary case, this model generalizes to Windows, BSD, Android, HarmonyOS, RTOS, and macOS.

The CE suite aims to unify scheduling, isolation, and delegation for all execution contexts: threads, processes, virtual machines (VMs), interrupts, secure enclaves, etc.

## 2. Unified Execution Context Structure

The kernel should adopt a **unified `execution_context` structure** that generalizes:

* Threads and processes
* Interrupt contexts
* VM vCPUs
* Containers
* Secure enclaves

This `execution_context` struct must be:

* **Contiguous in memory** (DMA-friendly)
* **64B-aligned** (or cache-line aligned)
* **Used in all scheduler and trap/interrupt handlers**
* **Pinned in L1 cache** via CPE (Cache Partitioning Extension), for low-latency deterministic access

### 2.1 Proposed Struct Layout (Simplified)

```c
struct execution_context {
    u16 context_bank_id;      // Context bank used by this EC (MUST be first field)
    u16 group_id;             // CME logical group ID (opaque to guest)
    u32 flags;                // Realtime, preempt, secure, etc.
    void *stack_ptr;          // Kernel stack for EC
    void *entry_point;        // Initial PC
    void *dma_addr;           // Memory spill/fill buffer
    u8   privilege_level;     // User, kernel, guest, secure
    u8   resource_profile;    // Memory, cache, QoS levels
    ... // scheduler fields, accounting, etc.
};
```

### Rationale:

* Placing `context_bank_id` first allows passing the pointer directly as `rs1` to CME instructions.
* CME ops (e.g., `ec.ib`, `ec.ob`) can dereference this address for the bank ID.
* Makes save/restore **one instruction** each, no prework.
* With cache partitioning (via CPE), this struct can remain L1-resident, avoiding unpredictable latency.

## 3. CME Instruction Encoding and Convention

### Uniform Encoding Convention

To maintain consistent naming across the CE suite:

* CME now **only supports** pointer-based bank access.
* The instruction format follows:

  ```
  ec.ib rs1, mask   // Save context to bank at *(rs1)
  ec.ob rs1, mask   // Restore context from bank at *(rs1)
  ```
* `rs1` = pointer to `execution_context`
* `mask` = register or immediate (GPR/FPR/VEC/PC/CSR)
* `rd` is unused (bank number not returned)

All future instructions across the CE suite (CME, CPE, QoS, MBW) follow this naming pattern:

```text
  {ec, cp, qs, ms}.{i,o}{b,m,s,g,t,v}
```

## 4. Efficiency Gains

| Step            | Without Struct Pointer | With CME Struct-Based Default |
| --------------- | ---------------------- | ----------------------------- |
| Save context    | Load + `ec.ib`         | Single `ec.ib`                |
| Restore context | Load + `ec.ob`         | Single `ec.ob`                |
| DMA migration   | Explicit via `ec.im`   | Still explicit, same flow     |

## 5. Cache Residency and Partitioning

The `execution_context` struct can be guaranteed to reside in L1 cache using:

* **CPE (Cache Partitioning Extension)** to assign cache slices
* Set via:

  ```
  cp.ig rs1, rs2 // allocate cache slice to execution context
  ```
* Ensures access latency for CME instructions remains deterministic

## 6. Kernel Scheduler Considerations

* Scheduler uses `execution_context *` as the fundamental unit
* EC-to-hart binding tracked via per-hart `current_ec`
* Context switch example:

```c
    ec.ib current_ec, FULL_MASK
    ec.ob next_ec, FULL_MASK
```

* Optional: Fallback paths for DMA spilling if no bank available

## 7. Interaction with Other CE Components

* Execution context fields are honored across CE:

  * `resource_profile` selects settings for CPE, QoS, MBW
  * CPE enforces L1/L2 residency and isolation
  * QoS assigns DMA and I/O bandwidth
  * MBW manages DRAM latency/bandwidth arbitration

### 7.1 Memory Scheduling Ideas (MBW)

Two models are proposed:

**A. Hart-Initiated Memory Access Hinting**

* Prefetch engine looks ahead into instruction stream
* Predicts pending loads/stores
* MBW arbitration favors higher-priority groups

**B. OS-Aware Memory Access Throttling**

* Kernel tracks memory ops per hart
* Group priority policies drive bus arbitration
* Works like QoS on a NIC scheduler

Further refinement and simulations needed.

## 8. Non-Linux Guests

The struct layout and pointer-passed CME instructions can be adapted by:

* Windows
* BSDs (FreeBSD/NetBSD)
* RTOS (Zephyr, FreeRTOS)
* Hypervisors (KVM, bhyve, Xen)
* Android/HarmonyOS
* Apple OS (hypothetical future RISC-V port)

## Placeholder: Diagram – Execution Context Struct in Cache

*Description*: Show struct pinned in L1, CME pointer dereference, cache slice allocation via CPE.

---

Next chapter: **CME Usage Examples** – real-world patterns of delegation, nested contexts, and isolation.

