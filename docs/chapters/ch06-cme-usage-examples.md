# Chapter 6: CME Usage Examples

## 1. Overview

This chapter illustrates real-world usage patterns of the Context Management Extension (CME) in a modern OS kernel. These examples include switching threads, delegating context to interrupts, managing secure enclaves, virtual machine nesting, and real-time guarantees. Each example shows how CME enables ultra-fast transitions, isolation, and delegation using minimal instructions.

All examples assume that:

* The kernel maintains an `execution_context` structure per logical entity (thread, interrupt, etc.)
* Context banks and groups are properly allocated and delegated in advance
* The CME instruction set uses the `{ec}.{i,o}{b,m,s,g,t,v}` format, where:

  * `i` means "into" and `o` means "out of"
  * The letter after denotes the target (bank, memory, stream, group, tenant, vault)
  * For example, `ec.ib` = "execution context into bank", `ec.om` = "execution context out of memory"
* A new `ECID` (Execution Context ID) model is in place, where each hart maintains a local `ECID` that is a combination of the hart ID and a hart-local context ID (see Chapter 1 for design rationale)

---

## 2. Basic Thread Context Switch

### Scenario

Two threads (`T1`, `T2`) are scheduled on the same hart. Thread `T1` is currently running and `T2` is about to be restored.

### Code

```c
// Save current context
ec.ib current_ec, FULL_MASK

// Restore next context
ec.ob next_ec, FULL_MASK
```

### Notes

* `current_ec` and `next_ec` are pointers to their respective `execution_context` structs.
* Minimal latency, no extra memory or branch logic needed.
* `ECID` is updated implicitly by hardware during context switch.

---

## 3. Interrupt Delegation and Reentry

### Scenario

A hardware interrupt fires. CME delegates execution to an interrupt context bank preallocated for this purpose. After the handler, original context is restored.

### Setup (One-Time)

```c
// Allocate interrupt bank group
ec.ig rd, x0 // x0 = 0: create new group using a free bank, rd gets group ID, or 0 if no free banks
ec.ig rd, t1 // t1 = 5: put another free bank in group 5, rd gets number of free banks left
// Assign group to interrupt controller
ec.it rd, INT_CTRL_ID
```

### On Interrupt

```c
// Save interrupted context
ec.ib current_ec, FULL_MASK

// Load interrupt handler context
ec.ob interrupt_ec, FULL_MASK
```

### On Return from Interrupt

```c
// Save interrupt handler context (optional)
ec.ib interrupt_ec, FULL_MASK

// Restore previous context
ec.ob current_ec, FULL_MASK
```

---

## 4. Secure Enclave Launch

### Scenario

A secure process is spun up in an isolated vault context.

### Code

```c
// Save current user context
ec.ib user_ec, FULL_MASK

// Unseal secure bank (loaded previously)
ec.ov secure_ec, FULL_MASK
```

### On Exit

```c
// Seal secure context
ec.iv secure_ec, FULL_MASK

// Restore user context
ec.ob user_ec, FULL_MASK
```

### Notes

* `ec.iv`/`ec.ov` provide hardware-backed sealing for trusted computing.
* Secure banks are protected from even the hypervisor.
* `ECID` of the secure context is separate and hardware-enforced.

---

## 5. Nested Virtual Machine (VM) Launch

### Scenario

A host launches a guest VM (L1), which in turn launches a nested guest (L2).

### Code (L0 -> L1)

```c
// Save host context
ec.ib host_ec, FULL_MASK

// Restore L1 guest context
ec.ob l1_guest_ec, FULL_MASK
```

### Code (L1 -> L2)

```c
// Save L1 guest context
ec.ib l1_guest_ec, FULL_MASK

// Restore L2 nested context
ec.ob l2_guest_ec, FULL_MASK
```

### Code (L2 -> L1)

```c
ec.ib l2_guest_ec, FULL_MASK

ec.ob l1_guest_ec, FULL_MASK
```

### Code (L1 -> L0)

```c
ec.ib l1_guest_ec, FULL_MASK

ec.ob host_ec, FULL_MASK
```

### Notes

* CME automatically manages delegated bank visibility.
* Guests only see their banks as numbered 0..K-1
* `ECID` ensures proper binding of CE resources across nested levels.

---

## 6. Realtime Audio DSP in a VM

### Scenario

A realtime audio engine runs inside a guest VM. Context switching must meet hard realtime deadlines (e.g., every 1ms buffer).

### Strategy

* Use CME + CPE + MSE to ensure:

  * Context always fits in bank (CME)
  * Execution context struct pinned in L1 (CPE)
  * Audio memory access gets priority (MSE)

### Code

```c
// Save non-DSP VM task
ec.ib task_ec, FULL_MASK

// Load DSP audio handler
ec.ob dsp_ec, FULL_MASK
```

---

## 7. Nested Secure Enclave Inside VM

### Scenario

A secure enclave runs within a guest VM.

### Code (Guest to Secure Enclave)

```c
ec.ib guest_ec, FULL_MASK

ec.ob secure_vm_ec, FULL_MASK
```

### Code (Return)

```c
ec.ib secure_vm_ec, FULL_MASK

ec.ob guest_ec, FULL_MASK
```

### Notes

* `secure_vm_ec` can be sealed/unsealed using `ec.iv`/`ec.ov`.
* CME hardware ensures VM cannot access unauthorized banks.
* `ECID` separation between guest and secure enclave prevents leakage.

---

## 8. Placeholder: Diagram – CME Save/Restore Flow

**Description**: A flowchart showing execution switching between thread, interrupt, VM, and secure enclave contexts using `ec.ib`/`ec.ob`, highlighting `ECID` transitions.

---

Next chapter: **CPE – Cache Partitioning Extension**

---

