# Execution Context Model (CME)

## Overview

The Context Management Extension (CME) defines a hardware-accelerated model for execution context switching, delegation, migration, and isolation. It introduces the concept of *context banks*, *bank groups*, *execution contexts* (ECs), and *execution context identifiers* (ECIDs), providing efficient and secure support for multitasking, virtualization, secure enclaves, real-time threads, and interrupt handling.

## Core Concepts

* **Context Bank**: A hardware-backed register file slice (non-vector or vector) that can store the full or partial state of an execution context.
* **Bank Group**: A collection of banks, dynamically allocated and delegated to an EC.
* **Execution Context (EC)**: Any schedulable or executable unit in the system, including:

  * OS process or thread
  * Virtual machine thread (vCPU)
  * Containerized task
  * Secure enclave
  * IRQ handler (hardware or virtualized)
* **Execution Context Identifier (ECID)**: A compact identifier used by the hardware to track and associate context-related metadata (banks, cache partitions, QoS channels, memory slots, etc.) with the currently active EC on a hart.

## The ECID Model

Each hart maintains a hardware register holding the **current ECID**. This ECID is local to the hart and, when combined with the hart ID (and SMT thread ID if applicable), forms a globally unique identifier for the active execution context.

In software, this ECID is stored as part of the *Execution Context Structure* (ECS). The ECS contains the ECID, hart/thread ID, and other metadata required by the OS. The first kilobyte of the ECS is structured to be readable and writable by hardware using the `ec.im` and `ec.om` instructions, enabling efficient DMA-based context swapping.

This design avoids requiring the OS to globally allocate and track ECIDs. Instead, ECIDs are scoped per hart, dramatically reducing complexity and avoiding cross-hart synchronization.

All CE-related resource bindings (bank IDs, group IDs, cache partitions, QoS channels, memory scheduling slots) are implicitly or explicitly associated with the **current ECID**. The hardware consults internal tables to determine resource access permissions, isolation boundaries, and priority scheduling behaviors based on the ECID.

## Context Bank Types

* **Non-vector banks** (NV): \~1024 bytes per bank (includes GPR, FPR, PC, CSR, SATP)
* **Vector banks** (VEC): 4 KiB per bank (for a 1024-bit vector register file with 32 vectors)

Note: The vector bank size is implementation-dependent. Future extensions (matrices, tensors) may share or extend vector bits. *VMT* (Vector/Matrix/Tensor) banks are expected to be fewer in number than non-VMT banks due to size constraints.

Each hart may be provisioned with a configurable number of NV and VEC banks, depending on the system profile.

## Bank Group and Visibility Model

* ECs may only access banks delegated to their root group, which is always group zero from the EC's point of view.
* Guest ECs cannot observe physical bank or group IDs.
* Group and bank mappings are enforced in hardware. Bank-to-group relationships are stored *in the bank itself*. Groups remember their parent group (group-in-group membership), while banks remember the group they belong to (bank-in-group membership). This avoids circular references and allows efficient hardware enforcement. Groups *contain the number of their parent group*, although only known to the hardware, not to the OS. If a group contains its own group number it means it is empty, and it is thus free to be assigned a bank to. This reversal in hardware (groups remember parent group and banks remember their own group membership) of the apparent semantics (groups seem to contain banks and groups), makes the system failsafe, O(1), and predictable.
* Adding banks to groups is a privileged operation. Only the OS or hypervisor may perform it.
* A group is created by assigning at least one bank into it. This occurs from the current EC's root group (group zero), and thus the new group is logically a child of the root group. This child group is logically nested, but always starts non-empty and is physically disjoint.
* The first bank (EC-local bank 0) always remains with the EC and may never be assigned to a group.
* Only free banks from the EC's group zero may be assigned to a group. Once assigned, a bank is no longer considered free in the EC's view, although the EC cannot directly query which banks are free. A CSR gives the total number of free banks.
* A group cannot be reused if it still contains banks. It must be empty before it can be reallocated.
* Removing the last bank from a group automatically dissolves that group.
* Dissolving a group automatically dissolves any child groups delegated from it, recursively.
* Groups *can contain other groups* as members, and banks as well. However, this is implemented with strict asymmetry: the group remembers its parent (for group-in-group membership), and the bank remembers its group (for bank-in-group membership). Empty groups may never be members of any group. This structure ensures robust enforcement of delegation semantics and avoids cycles, leaks, or inconsistencies.
* Delegation forms a tree rooted in each execution context's group zero. Groups created by an EC always become child groups of the EC's root group, but only the bank knows its group assignment and the group knows its parent—both tracked in hardware. Execution contexts are unaware of actual group IDs beyond their delegated group zero and any child groups they create.
* When a group is delegated to a tenant (e.g., VM or secure enclave), it is given as the tenant's group zero. The guest EC sees the delegated banks as banks 0..K-1, and the group ID as 0.
* Guests cannot observe the host group ID, bank ID, or group hierarchy.
* Delegation is rigid by design: destroying a group typically means destroying the VM or secure enclave to which it was delegated. It is the OS or hypervisor’s responsibility to tear down that VM context. Group revocation may raise exceptions, but often implies full termination.
* VM migration across harts or systems requires coordinated group teardown and rebuild. Groups must be dissolved and reestablished during such transitions.

These constraints are enforced to prevent hardware lockups, race conditions, delegation loops, or visibility leaks. Groups are ephemeral abstractions that exist only as long as they hold one or more banks.

Groups form a hierarchy (tree), with parent-child delegation handled by instructions like `ec.ig`, `ec.it`, and `ec.ot`.

This strict design supports hard real-time guarantees, even in complex systems with nested virtual machines or distributed hypervisors. While it introduces some rigidity in group management, it ensures deterministic execution and secure resource isolation—benefits highly valuable in latency-sensitive domains like high-frequency trading, embedded control, and secure computing.

## Group Hierarchy

* Groups are hierarchical, with up to 4 levels of nesting. This is a generous limit, as nesting VMs deeper than three levels relative to L0 has little practical use. The 4 levels allow an L1 hypervisor to run an L2 hypervisor that runs an L3 VM, all using context banks. This means a cloud provider can rent (virtual) hypervisor clusters to tenants, who may then explore nested virtualization within their (virtual) cluster. This is likely the maximum depth anyone will realistically require, and bounding it at 4 ensures architectural simplicity and safety.
* Each group stores its *parent group ID* (hidden from guest ECs).
* An EC executing `ec.ig` (create group) receives a software-visible group ID in `rd`, used to represent that group in OS/VM data structures.
* Bank-level ownership is tracked in hardware; software cannot override or forge access.

## CME Group Delegation

Delegation is performed explicitly:

* `ec.ig`: Create a new group (returns group ID in `rd`)
* `ec.it`: Assign group to a tenant EC (e.g., VM or thread)
* `ec.ot`: Revoke group (forced migration or interrupt)

Groups are returned to the parent upon revocation.

## Context Save/Restore Operations

* `ec.ib` (in-bank): Save current context to a bank (partial/full, mask-controlled)
* `ec.ob` (out-bank): Restore context from bank (mask-controlled, optional PC jump)
* `ec.im`: Save bank to memory (DMA path)
* `ec.om`: Restore bank from memory (DMA path)

## Secure Enclave Support

* `ec.iv`: Seal bank contents into secure vault (e.g., AES-GCM encryption)
* `ec.ov`: Unseal bank back into usable state (secure mode only)

## Masked Context Operations

Operations accept a **register mask** (and possibly an *extended mask* for CSRs) to define which parts of the context to operate on:

| Bit | Register Group | Description                                                   |
| --- | -------------- | ------------------------------------------------------------- |
| 0   | GPR            | Integer registers                                             |
| 1   | FPR            | Floating-point registers                                      |
| 2   | VEC            | Vector registers                                              |
| 3   | MAT            | Future matrix/tensor registers                                |
| 4   | PC             | Program counter                                               |
| 5   | CSR            | Control/status registers (see note below for granularity)     |
| 6   | SATP           | Supervisor address space register (triggers TLB reload/flush) |
| 7   | Reserved       | Reserved for future use                                       |

**CSR granularity:**

* The `CSR` bit is an aggregate; advanced OSes may use an *extended mask field* for fine-grained CSR selection. This is implementation- and ABI-dependent.
* Typical use: save all “critical” CSRs, or just those required for privilege level, timer, and interrupt state.

**SATP and TLBs:**

* The `SATP` bit saves/restores the supervisor address translation register.
* When SATP is restored, hardware is required to reload/flush the TLB as necessary for the new address space context (standard RISC-V behavior).
* No need to explicitly mask TLBs in context banks; they’re indirect.

**The mask:**

* The mask for context operations is always under OS/hypervisor control.
* It is not saved/restored as part of the context, but passed with each save/restore instruction.

## Placeholder: Diagram – CME Context Delegation and Group Isolation

*Description*: This diagram should illustrate the hardware-enforced bank isolation model. It shows multiple execution contexts with their delegated banks, group hierarchy, and the hardware mapping table. Include:

* ECs with bank views (0…N)
* Hardware group-bank association
* Parent group relationships

## Placeholder: Diagram – CME Instruction Flow

*Description*: Show instruction flow for saving, restoring, delegating, revoking, and sealing banks. Arrows should indicate which CSRs or hardware tables are updated.

## Notes

* Context banks are never shared between ECs simultaneously.
* Delegated banks form a secure memory boundary.
* Bank preloading allows instant activation of new VMs or threads.

---

Next chapter: **CME Instruction Set Reference**

# CME Instruction Set Reference

## Overview

This chapter describes the complete instruction set for the Context Management Extension (CME), including all supported context, group, ECID, migration, and sealing operations. It includes syntax, operand types, cycle estimates, and side effects. All CME instructions are privileged unless noted otherwise.

---

## 1. Context Bank Operations

### `ec.ib` — Save current execution context into context bank

* **Type**: System, user/privileged (configurable)
* **Syntax**: `ec.ib rd, rs1`

  * `rd`: Destination register for bank ID
  * `rs1`: Mask specifying which register groups to save
* **Side Effects**:

  * Overwrites bank contents
  * Updates CSRs: `cme_status`, `cme_last_bank`, `cme_reg_mask`
* **Guaranteed Cycles**:

  * 1 cycle (banked), up to 3 if selective masking

### `ec.ob` — Restore execution context from bank

* **Type**: System, user/privileged (configurable)
* **Syntax**: `ec.ob rd, rs1`

  * `rd`: Bank ID to restore from
  * `rs1`: Mask (which register groups to restore)
* **Side Effects**:

  * Restores registers (selective if masked)
  * May jump if PC bit is set in mask

---

## 2. DMA (Memory) Spill/Fill Operations

### `ec.im` — Save bank contents to memory

* **Type**: System, privileged
* **Syntax**: `ec.im rs1, rs2, imm`

  * `rs1`: Bank ID
  * `rs2`: Memory pointer
  * `imm`: Mask
* **Side Effects**:

  * Bank → memory transfer
  * Bank can be freed afterward
* **Cycles**: Depends on size and DMA bus width (≤ 128 cycles typical)

### `ec.om` — Load context from memory into bank

* **Type**: System, privileged
* **Syntax**: `ec.om rd, rs1, imm`

  * `rd`: Destination bank
  * `rs1`: Memory pointer
  * `imm`: Mask
* **Side Effects**:

  * Memory → bank transfer
  * May fault if no bank available

---

## 3. Group Management

### `ec.ig` — Create or extend group

* **Syntax**: `ec.ig rd, rs1`

  * `rd`: Returns new group ID (as seen from current context)
  * `rs1`:

    * `0` (x0): Create a new group using the first free EC-local bank from group 0
    * `<existing group ID>`: Add the next free EC-local bank from group 0 to the given group
* **Side Effects**:

  * Moves the selected EC-local bank to the group
  * Returns group ID in `rd`
  * Updates group/bank mapping
  * If no free banks, returns error code in `rd`

### `ec.og` — Remove bank from group

* **Syntax**: `ec.og rd, rs1`

  * `rd`: Returns the number of banks left in the group after removal
  * `rs1`: Group ID (from EC-local perspective)
* **Side Effects**:

  * Removes the *last-added* EC-local bank from the group and returns it to group 0
  * If `rd` is 0, the group is now disbanded (no members remain)
  * Hardware updates mapping and invalidates group if empty

**Group membership and visibility:**

* When an EC puts one of its banks into a group, it knows exactly which EC-local bank was moved, as *only EC-local group 0* banks may be added.
* The OS is responsible for tracking which EC-local bank numbers have been assigned to each group (local bookkeeping).
* Hardware maintains only the bank→group mapping; groups do not keep member lists.

**Warning:**

* OS/hypervisor developers: Do not remove banks from groups actively in use by tenants! This may disrupt VMs, processes, or enclaves using that group. To safely evict tenants, use `ec.ot` (revoke group) or `ec.or` (revoke ECID).

### `ec.it` — Assign group to tenant (ECID)

* **Syntax**: `ec.it rs1, rs2`

  * `rs1`: Group ID
  * `rs2`: Tenant ECID
* **Side Effects**:

  * Transfers group to tenant, updates group visibility and group/bank mappings

### `ec.ot` — Revoke group from tenant (ECID)

* **Syntax**: `ec.ot rs1`

  * `rs1`: Group ID
* **Side Effects**:

  * Recursively revokes group and all banks/subgroups from tenant
  * Triggers forced cleanup and group removal

---

## 4. ECID Lifecycle Operations

### `ec.ir` — Allocate/request new ECID (prefix delegation)

* **Syntax**: `ec.ir rd, rs1, rs2`

  * `rd`: New ECID (or 0 if none available)
  * `rs1`: Pointer to ECS in RAM
  * `rs2`: Prefix length (relative to parent ECID)
* **Semantics**:

  * Allocates child ECID; subdelegation possible if prefix >1; hardware enforces limits

### `ec.or` — Revoke/destroy ECID

* **Syntax**: `ec.or rs1`

  * `rs1`: ECID to revoke (must be child/prefix of caller)
* **Semantics**:

  * Recursively reclaims all contracts, groups, banks, subordinate ECIDs/resources

---

## 5. Secure Enclave / Vault Ops

### `ec.iv` — Seal context (encrypt/lock)

* **Syntax**: `ec.iv rs1, rs2`

  * `rs1`: Bank ID
  * `rs2`: Mask
* **Side Effects**:

  * Encrypts contents, accessible only in secure mode

### `ec.ov` — Unseal context

* **Syntax**: `ec.ov rd, rs1`

  * `rd`: Destination bank
  * `rs1`: Mask
* **Side Effects**:

  * Decrypts/unlocks for secure enclave

---

## 6. Register Mask Encoding

| Bit | Register Group | Description              |
| --- | -------------- | ------------------------ |
| 0   | GPR            | Integer registers        |
| 1   | FPR            | Floating-point registers |
| 2   | VEC            | Vector registers (RVV)   |
| 3   | MAT            | Matrix/tensor (future)   |
| 4   | PC             | Program counter          |
| 5   | CSR            | Control/status registers |
| 6   | SATP           | Address translation      |
| 7   | Reserved       |                          |

---

## 7. CSRs

| CSR Name         | Purpose                      |
| ---------------- | ---------------------------- |
| cme\_bank\_count | Number of banks (readonly)   |
| cme\_next\_free  | Next available bank          |
| cme\_status      | Last operation status/error  |
| cme\_reg\_mask   | Mask used in last operation  |
| cme\_group\_map  | Group and ECID mapping table |
| cme\_dma\_addr   | DMA pointer                  |
| cme\_seal\_key   | Vault encryption key         |

---

## 8. Instruction Timing Summary

| Instruction | Cycles (banked) | DMA Path | Secure Path |
| ----------- | --------------- | -------- | ----------- |
| ec.ib/ob    | 1–3             | –        | –           |
| ec.im/om    | –               | 10–128   | –           |
| ec.ig/og    | 1–4             | –        | –           |
| ec.it/ot    | 1–4 (recursive) | –        | –           |
| ec.iv/ov    | –               | –        | 8–16        |
| ec.ir/or    | 1–8 (log tree)  | –        | –           |

---

## 9. Instruction Encoding Sketch

* **Opcode**: 8 bits (e.g., `1101_xxxx`)
* **Function**: 4 bits (operation category)
* **Operands**: rd, rs1, rs2
* **Mask/Imm**: 8 bits
* **Address**: 32–64 bits

---

## 10. Instruction Orthogonality and Relationships

CME’s hierarchical resource management results in **overlapping but orthogonal** effects for group and ECID instructions:

* **`ec.ig`**: Adds EC-local banks to a group (creates group if new). Only EC-local group 0 banks can be added; group is created by first addition. Cannot add banks to tenant-owned groups.
* **`ec.og`**: Removes the *last-added* EC-local bank from a group, returns to group 0. If group is emptied, group is disbanded. Cannot remove banks from tenant-owned groups (unless forcibly revoked).
* **`ec.it`**: Assigns group to a tenant (new ECID).
* **`ec.ot`**: Revokes group from tenant (recursively removes all banks/subgroups; group may be deleted if emptied).
* **`ec.ir`**: Allocates new ECID with prefix; allows delegation and hierarchical contracts.
* **`ec.or`**: Revokes/destroys ECID and all subordinate resources (includes groups, banks, subordinate ECIDs).
* **`ec.iv/ov`**: Secure enclave/vault seal/unseal.

**Best practice:**

* Use `ec.ig`/`ec.og` for resource setup and teardown in cooperative (non-tenant) code.
* Use `ec.it`/`ec.ot` for tenant management (VMs, enclaves).
* Use `ec.or` for full forced cleanup (zombies, hostile or failed guests).

---

## 11. Error and Exception Handling

* All illegal or privilege-violating operations trap to the OS/hypervisor.
* Forced destruction (`ec.or`) always succeeds for the parent; OS must handle cleanup.
* Error codes returned in rd or status CSRs.

---

## 12. Placeholder: Diagrams

* **Instruction Flow Diagram:**
  ECID creation/delegation, forced destruction, group and resource mapping.
* **Radix Tree Example:**
  Visual of ECID prefixes, delegation, and recursive cleanup.

---

[Next: Hardware Microarchitecture Overview](Chapter3-Bank_Group_and_Delegation_Semantics.md)


# Chapter 3: Bank Group and Delegation Semantics

## Overview

This chapter specifies the semantics and rules for context bank grouping, group creation, hierarchical delegation, and enforcement in the Context Management Extension (CME). It covers:

* Group creation and bank assignment
* Bank-to-group and group-to-parent relationships
* Delegation and revocation to tenants (VMs, secure enclaves, interrupt handlers)
* Hardware visibility and security model
* Edge cases and rigidity by design

---

## 1. Bank Groups and Ownership Model

* **Bank groups** are the units of delegation.
  Each group is identified by a *group ID* (6 bits per context hierarchy).
* **Banks** themselves remember which group they belong to (hardware field), not vice versa.
* A group also stores the *parent group ID* (hidden from guests).
* **Only banks in EC-local group 0** (the root group as seen by a given execution context) can be added to new groups.
* The *first bank* in an EC (EC-local bank 0) is always retained in group 0 and cannot be moved.

---

## 2. Group Creation and Bank Addition/Removal

* `ec.ig` (Create or extend group):

  * `ec.ig rd, x0` creates a new group, moving the first free EC-local group 0 bank to it, and returns the new group ID in `rd`.
  * `ec.ig rd, <existing group ID>` moves the next free EC-local group 0 bank to the group.
  * **Cannot add banks to tenant-owned groups.**

* `ec.og` (Remove bank from group):

  * `ec.og rd, <group ID>` removes the *last-added* EC-local bank from the group and returns it to group 0. Returns number of banks left in `rd`; if zero, group is now dissolved.
  * **Cannot remove banks from tenant-owned groups unless forcibly revoked.**

* **A group is always non-empty; removing the last bank automatically dissolves it and updates the group mapping tree.**

* OS must track which EC-local bank numbers are in which groups. Hardware tracks only bank→group mapping.

---

## 3. Delegation and Revocation

* `ec.it` (Assign group to tenant/child ECID):

  * Transfers a group (and all its banks/subgroups) to a child context (VM, enclave, etc.)
  * After delegation, the guest sees the group as group 0, and the banks as 0..K-1.
  * Host EC loses direct access to the delegated group and cannot add/remove banks.

* `ec.ot` (Revoke group):

  * Recursively revokes group from tenant and returns all banks/subgroups to the parent group (or dissolves if emptied).
  * Can be used for normal shutdown or forced eviction.

* **Delegation and revocation are hardware-enforced.**

* Guests cannot see real group or bank IDs, or their place in the host’s group tree.

---

## 4. Group and Bank Visibility Rules

* **From the guest’s perspective:**

  * Only sees its own group (group 0) and its banks (numbered 0..K-1).
  * No knowledge of parent, sibling, or other host groups.
  * Cannot infer group hierarchy or hardware mappings.
* **From the hardware/host perspective:**

  * Each bank is tagged with its true group ID.
  * Each group records its parent (used for recursive revocation).
  * Groups and banks are mapped in secure hardware tables; software cannot override or forge membership.

---

## 5. Security, Exceptions, and Rigidity

* All group and bank membership changes are hardware-privileged.
* All attempts to access, delegate, or modify groups/banks outside one’s delegated set are trapped.
* Guests cannot read or alter host-level mapping tables (such as `cme_group_map`).
* **Rigidity is by design:**

  * Delegation is not fluid; reclaiming resources always succeeds (no lockups or races).
  * VM migration or group movement requires explicit teardown and rebuild.
  * Groups must be empty before being reused.

---

## 6. Example Use Cases

* OS creates a new group for a secure enclave by moving a free bank from group 0, delegates it.
* Enclave sees its banks as 0..3 (if given four banks) and group as 0; host sees the real group ID.
* On enclave shutdown, `ec.ot` is used to revoke the group, returning all banks to the parent (host EC).
* Bank/group mapping is strictly enforced; tenants can never “see” or “grab” banks/groups beyond what’s delegated.

---

## Placeholder: Diagram – Group Tree and Bank Mapping

*Description*: Tree diagram showing nested groups, bank-to-group assignments, delegation to tenants, and the hardware translation logic between guest-visible and physical IDs.

---

[Next: Hardware Microarchitecture Overview](../hardware-microarchitecture-overview.md)

# Chapter 4: Hardware Microarchitecture Overview

## Overview

This chapter describes the underlying microarchitectural components required to implement the Context Management Extension (CME), including context banks, switching logic, privilege isolation, and CSR integration.

## 1. Context Bank Storage Units

Each hart is equipped with:

* **N non-vector banks** (e.g., 8 banks)
* **M vector banks** (e.g., 2 banks)

### 1.1 Non-Vector Bank Contents

Each bank contains:

* 32 × 64-bit GPRs = 256 B
* 32 × 64-bit FPRs = 256 B
* CSR snapshot (estimated) = 256 B
* PC + SATP + misc = \~32 B
* **Total** ≈ 1 KB per non-vector bank

### 1.2 Vector Bank Contents

Each vector bank contains:

* 1024-bit wide RVV registers (v0–v31)
* Each v-register = 1024 bits = 128 B
* 32 registers × 128 B = 4096 B = 4 KB per vector bank

## 2. Register Switch Logic

Each register type (GPR, FPR, PC, CSR, VEC) has an associated multiplexer/demuxer:

* Connects live CPU registers to context bank memory
* Switches between banks in **1 clock cycle**
* Masked switches (partial context save/restore) allowed

Hardware fences ensure consistency when switching context.

## 3. Bank Allocation Engine

* Maintains bitmaps of free/used banks per hart
* Enforces group ownership (checks group map before grant)
* Tracks `cme_next_free` and `cme_bank_count`
* Allocates only from visible groups

## 4. Group Tracking Logic

Each hart maintains:

* `cme_group_map`: hardware-only CAM (Content Addressable Memory) for group→bank mapping
* `cme_group_parent`: hardware-only table mapping group→parent
* `cme_bank_tags`: one per bank, storing group ID and dirty/lock flags

Hardware ensures guest contexts only see remapped IDs (0..K).

## 5. DMA Spill/Fill Engine

* Performs bank save/load to/from RAM
* Works in background via DMA
* Triggered by `ec.im` / `ec.om`
* DMA controller must:

  * Handle fixed-size transfers (1K or 4K)
  * Support bank tagging to prevent reuse during DMA
  * Raise interrupts on fault/complete

## 6. Secure Vault Engine (Optional)

* Encrypts context banks during seal (`ec.iv`) and decrypts on unseal (`ec.ov`)
* Uses hardware AES or other crypto unit
* Enforces lock bit on sealed banks
* Secure CSRs: `cme_seal_key`

## 7. Fast Context Switching Path

Context switch logic:

1. Execute `ec.ib` (save):

   * Mux live regs into bank
   * Store mask
   * Update CSRs
2. Execute `ec.ob` (restore):

   * Mux bank into live regs
   * Jump to PC (if PC bit is set)

Both complete in 1–3 cycles.

## 8. Slow Path (DMA or Vault)

If no free banks:

* Use `ec.im` to spill current context
* Free a bank and allocate to new context
* Restore new context from memory (`ec.om`)

If secure isolation is needed:

* Seal banks before DMA migration

## 9. Bank and Group Limitations

* Non-vector banks per hart: configurable (typical 8)
* Vector banks per hart: configurable (typical 2)
* Groups: 6-bit ID space (64 total), hierarchical
* Max active nested groups: 4 levels (parent, child, etc.)

## Placeholder: Diagram – CME Microarchitecture

*Description*: Show context banks, register muxes, DMA engine, group tables, bank tags, and CSR links.

---

Next: Additional chapters (e.g., Linux Kernel Integration, CE Ecosystem Design, Real-Time Applications) depending on user priorities.

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

# Scratchpad – CE Design Issues and Resolutions

## ✅ Resolved Issues

### ECID Mental Model (Q1, Q2)

**ECID** (Execution Context ID) is a *hardware-managed identity token* per hart that:

* Is **invisible to software** (not writable or readable directly)
* Is loaded on `ec.ob`, and implicitly cleared on `ec.ib`
* Serves as a **contract name** to lookup all CE-related rights

**Mapped Resources via ECID (O(1) lookup):**

| Resource           | Bound By       |
| ------------------ | -------------- |
| Context bank       | CME            |
| Group ID           | CME            |
| Cache partition    | CPE            |
| QoS channels       | QOS            |
| Memory contract    | MSE            |
| ECS address (meta) | Kernel mapping |

> ECID acts as an unforgeable identity token that defines what rights are granted to the currently executing code.
> The process does not know its ECID, nor can it change it. It's managed entirely in the hart.

**Security:** A process or VM cannot:

* Forge ECIDs to gain access to other contexts
* Access memory, cache, or bandwidth not defined in its ECID-bound contract
* Jump across privilege boundaries (e.g., from guest to host) because ECID-to-bank-group mappings are enforced in hardware and delegation paths

**Lifecycle:**

* ECID is **created and loaded** via `ec.ob` (restore context)
* ECID is **unloaded** via `ec.ib` (save context)
* ECID can be **migrated** only by kernel actions when migrating an execution context between harts

---

### ✅ ECID Reuse After Destruction

**Problem:** Can an ECID be reused after its context exits?

**Resolution:** Yes, but only if:

* All resources bound to that ECID are revoked
* The ECS is cleared or reinitialized
* A **generation counter** is associated with the ECID slot in memory, to prevent stale access (ABA problems)

> Internally, the kernel may use a tuple like `{hartID, ECID, generation}` (EECIDG) to identify contexts. Hardware only needs `{hartID, ECID}`.

**Status:** ✅ Reuse is safe if tracked correctly. Hardware unaware of reuse.

---

### ✅ Zombie Process ECID Reclamation

**Problem:** What if an ECID belongs to a zombie process?

**Resolution:** The kernel can issue `ec.od` (execution context: destroy), which:

* Revokes all contracts
* Flushes context to memory (optional)
* Marks ECID slot as reusable
* Removes ECID from ownership trees

> Guarantees forward progress — zombies cannot block resources indefinitely.

**Status:** ✅ Resolution defined. `ec.od` to be added to CME set.

---

### ✅ ECID Migration Between Harts

**Problem:** What happens when a thread moves to another hart?

**Resolution:** Do **not** migrate the ECID. Instead:

* Kernel **unbinds** ECID from the source hart
* Allocates a new ECID on the destination hart
* Reuses the same ECS
* Updates kernel mapping

> This "rebind" strategy avoids cross-hart ECID tracking and simplifies implementation. Real-time contexts should not migrate anyway.

**Status:** ✅ Option 2 chosen. Clean, simple, and kernel-manageable.

---

## 🧩 Emerging Model for ECID Ownership and Delegation

* Each execution context has a **parent** (except the L0 kernel or SBI).
* **Parents create child ECIDs**, bind them to resource contracts, and may destroy them at any time.
* Delegation of banks, cache partitions, bandwidth, and memory follows CE suite rules.
* **ECID destruction must always succeed**, even if the process is 'zombie-like' or blocked.
* Only privileged software (e.g., kernel or hypervisor) may create/destroy ECIDs.

**Proposed ECID Hierarchy:**

* ECIDs are arranged in a **tree structure**, with parent nodes able to delegate or revoke child ECIDs.
* ECID groups might use **binary prefixes** to represent subtree ownership, making delegation efficient and trackable.
* Kernel maintains a mapping table from ECIDs to their metadata (in memory), not in hart SRAM.

**EECID (Extended ECID):**

* Pair of {hart ID, ECID}, unique across system
* Stored in the `execution_context_struct` (ECS)

**Optimized ECID Representation:**

* Vast majority of ECIDs have no bound resources—just ECS pointer for `ec.im`/`ec.om`
* Explicit tracking is only needed for ECIDs that have CE suite resources assigned (banks, groups, partitions, etc.)
* Use **binary prefix grouping**: Each node (privileged context) owns a prefix space

  * Unused ECIDs live in a **consecutive allocation list**
  * No fragmentation: always maintain a pointer to the next free slot
  * One-hole allowance allows efficient reuse
* **Space-efficient**: Avoids pre-allocating large SRAM; leverages memory for most structures

---

### ECID Allocation and Limits

* How many ECIDs can there be per hart? (**Resolved:** With a radix tree or sparse RAM-resident structure, there is *no hard architectural limit*; ECID space can scale to thousands or millions per hart, as only active ECIDs consume resources. No large SRAM pre-allocation required.)
* Can we reclaim/evict ECID slots safely? (**Resolved:** Yes; with a radix tree or similar RAM-based structure, ECID slots are explicitly tracked and can be reclaimed immediately on context destruction or via forced-revocation instructions like `ec.od`. No fragmentation: the allocator always knows the next free slot or manages a one-hole invariant. Generation counters avoid ABA issues.)
* Where are ECID lists kept? Likely in memory, not hart-local.
* Can we limit ECID allocations per prefix owner to avoid exhaustion? (**Resolved:** Yes. Prefix ownership and ECID allocation are enforced in the radix tree model. Since only "resourced" ECIDs consume scarce hardware resources—and most ECIDs are unresourced—the kernel can set a per-prefix (per-tenant) quota or hard limit for contract ECIDs. This is tracked at the node (prefix) level. Ordinary (unresourced) ECIDs are limited only by RAM, and resource exhaustion is impossible unless a tenant/VM actually requests more hardware contracts than allowed. This quota model is both efficient and safe.)

### ECID and Virtual Machines

* Can a VM jump into its host context by guessing an ECID?

  * No, because ECID bank access is enforced and VMs only see banks/groups delegated to them.
  * However, delegation and revocation rules are now airtight, as the radix tree model enforces strict prefix ownership and resource mapping. Parent contexts can enumerate and forcibly revoke all subordinate ECIDs in their prefix, preventing privilege escalation, leaks, or orphaned resources. No context can access or guess ECIDs outside its delegated subtree.

### Other

* Zombie processes and blocked ECIDs — can they stall resource reclamation? (**Resolved:** No. Zombie processes may persist in the OS process table, but as soon as the kernel or parent issues `ec.od` (or equivalent forced destruction), all associated resources are immediately reclaimed. The ECID slot is freed and all contracts/banks/groups are revoked. Zombie or blocked status does not block resource reclamation or lead to resource leaks.)

### ✅ Lowest-Level Actor Allowed to Create an ECID

**Resolution:**
The lowest-level actor allowed to create an ECID is always the currently privileged owner of a hart—normally the OS kernel (in M-mode or S-mode) or hypervisor (H-mode), depending on the system’s privilege structure.

* **SBI (Supervisor Binary Interface):** While the SBI can provide services to S-mode, it is not itself a resource manager. The SBI should not create ECIDs except possibly at system boot for initial handoff.
* **M-mode Firmware/Secure Monitor:** May create the *initial* ECID for the first kernel or hypervisor during boot, then delegates all further ECID management.
* **User mode:** Never allowed.
* **Normal runtime:** Only the kernel, hypervisor, or a delegated secure monitor can create or destroy ECIDs.

**Principle:**
*ECID creation must always be privileged, auditable, and strictly delegated. Normal user processes or guests cannot create ECIDs except via explicit kernel or hypervisor delegation.*

###


✅ ECID Data Structure and Allocation Model

**Requirements:**

* O(1) allocation and lookup for most ops; O(log N) for mass revocation/ownership traversal.
* Binary prefix ownership for tenants/VMs/privileged contexts; scalable to thousands or millions.
* Efficient handling of “lightweight” (no hardware resources) vs. “contract” ECIDs.
* Space-efficient; spillover into RAM for scalability.

---

#### **Radix Tree–Backed ECID Table**

* **Key:** ECID (e.g., 16 or 32 bits; composed of prefix + index)
* **Node type:** Each node represents a prefix owned by a tenant/context.
* **Leaf:** Points to an ECID entry or subtree.

**Sample structure:**

```c
struct ecid_entry {
    uint32_t ecid;              // {prefix, index}
    uint8_t  generation;        // For reuse safety
    uint8_t  valid;             // Allocated flag
    uint8_t  resourced;         // Has contract
    uint32_t parent_prefix;     // Ownership check
    uint64_t eecs_ptr;          // ECS pointer
    // Resource fields (unions/structs as needed):
    uint16_t context_bank;
    uint16_t group_id;
    uint16_t cache_partition;
    uint16_t qos_channel;
    uint16_t mem_contract;
    // ...future resource fields
};
```

* **Radix tree mapping:**

  * Root node owned by kernel or L0 hypervisor.
  * Prefix delegation creates new subtrees/nodes; tenants/VMs get ownership of an entire subtree of ECIDs.
  * Allocation within a prefix is O(1) or O(log N) as needed; deallocation fills “holes.”
  * Only ECIDs with resources or actively running need entries in the tree—sparse by default.

**Advantages:**

* **Unlimited tenants/VMs/privileged contexts** (no hard-coded prefix bit limit).
* **Fast forced revocation**: Parent can enumerate or destroy all ECIDs in a prefix/subtree efficiently.
* **No pre-allocation or wasted space**—nodes only exist when needed.
* **Dynamic growth**: New tenants/VMs just create new subtrees on demand.

---

**For comparison:**

| Feature      | Flat prefix array | Radix tree model    |
| ------------ | ----------------- | ------------------- |
| Tenant limit | Fixed (e.g., 16)  | Dynamic (unlimited) |
| Delegation   | O(N) scan         | O(log N) walk       |
| Reclamation  | O(N)              | O(log N)            |
| Space usage  | Dense, wasteful   | Sparse, efficient   |
| Scalability  | Poor              | Excellent           |

---

**Integration:**

* Kernel keeps the radix tree in RAM per hart.
* Only currently loaded ECIDs live in SRAM for CE fast-path (context switch, contract lookup).
* On destruction or migration, ECID entry is cleaned up, and parent’s subtree is updated.

---

