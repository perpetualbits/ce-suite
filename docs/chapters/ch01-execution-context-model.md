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

