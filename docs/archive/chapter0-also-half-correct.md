---

## **Draft: CE Suite—Foundational Structures and Semantics (v0.5)**

---

### **1. Overview**

This foundational chapter defines the core structures of the Context Extensions (CE) suite:

* **Execution Context Identifiers (ECIDs)**
* **Groups** (resource ownership and delegation for per-hart state)
* **Contracts** (resource scheduling and sharing for global resources)
* **Unified Context Structures (UCS/ECS)**
* **Contract Hierarchies** and **Tenant ECs**

These concepts enable rigorous, scalable resource isolation, delegation, scheduling, and dynamic allocation across all CE extensions (CME, MSE, CPE, QoS).

---

### **2. Axiomatic Foundations**

#### **2.1 ECID Axioms**

1. **Hart-locality:** Each ECID is unique per hart. The global identifier is (hart\_id, ECID).
2. **Atomicity:** Only one ECID is active per hart at any moment.
3. **Persistence:** ECID 0 is persistent per hart and owns essential resources.
4. **Hierarchy:** ECIDs form a strict delegation tree rooted at ECID 0.

#### **2.2 Group Axioms (Context Banks)**

1. **Bank→Group Mapping:** Every context bank points upward to a group (its owner).
2. **Group→Parent Mapping:** Non-empty groups (except group zero) point upward, forming a tree rooted at group zero.
3. **Zero Group:** Always points to itself; universal root and emptiness sentinel.
4. **Empty Groups:** Any group (except zero) pointing to itself is empty and reclaimable.
5. **Bank Allocation:** New groups require at least one available bank; no empty groups.
6. **Non-Delegation of Essential Banks:** Parent groups must retain at least one bank.
7. **Limited Hardware Banks:** Finite hardware banks per hart (e.g., ≤64 non-VMT, 2–4 VMT).
8. **Metadata Reversal:** Bank metadata points upward for efficient reclamation.
9. **Group Deletion:** Automatic hardware cleanup when empty.
10. **Unique Ownership:** Banks have single-group ownership.
11. **Delegation Constraint:** Only parent groups can delegate banks.

#### **2.3 Contract Axioms (Global Resource Scheduling)**

1. **Contract as Resource Slice:** Each contract directly represents a slice of a global resource (memory, bandwidth, etc.) with defined latency, bandwidth, and policy attributes.
2. **Membership:** Each contract holds a set of ECIDs; every ECID is a member of at most one contract per resource class.
3. **Contract Hierarchy:** Contracts can be split/delegated; each child contract is a strict subset of the parent, and the sum of all children never exceeds the parent’s allocation.
4. **Delegation Authority:** Only the owner (parent contract) can split or delegate a contract, atomically and kernel-driven.
5. **Immediate Arbitration:** All binding or splitting requires hardware arbitration (e.g., MMU for MSE), which must be chip-global, atomic, and fast; if constraints are exceeded, operation fails without side effects.
6. **Releasing and Dissolving:** When a contract is released (explicitly or by releasing all members), its resources return to the parent, and the contract is dissolved.
7. **Auditing and Kernel Visibility:** Each privilege level (kernel, hypervisor, guest) can enumerate all contracts under its control and audit membership, parameters, and assignments.
8. **Hierarchy and Limits:** Contracts form a strict tree, max depth four (matching virt levels: kernel, hypervisor, guest, sub-guest/process).
9. **No Cycles:** Contract hierarchies are acyclic; no multiple parents.
10. **Efficient Metadata:** Contract metadata is flat or shallow; hardware lookups are O(1) or O(log N). Contract IDs are small (e.g., 8 bits).
11. **Resource Class:** Each contract is tagged with its resource class (e.g., memory, I/O, both) and policy parameters.
12. **Software Overflow:** If hardware contract slots are exhausted, software-managed contracts can overflow into slower paths.
13. **Unique Ownership:** Contracts are not shared between multiple parents.

---

### **3. Lifecycle and Interactions**

#### **3.1 ECID Lifecycle**

* **Creation:** Kernel assigns ECIDs; starts at ECID 0 at boot.
* **Delegation:** ECIDs created as child tenants, following strict delegation rules.
* **Migration:** OS-driven, explicit reassignment.
* **Revocation:** Recursive resource reclamation to parent ECIDs.

#### **3.2 Group Lifecycle (Context Banks)**

* **Creation:** Parent ECID creates groups by delegating context banks.
* **Delegation:** Hierarchical and hardware-enforced.
* **Revocation:** Automatic when empty; resources recursively returned to parent.

#### **3.3 Contract Lifecycle (Global Resources)**

* **Creation:** Kernel/hypervisor creates a contract by splitting a parent’s allocation (e.g., “reserve 10% of DRAM bandwidth”).
* **Membership Assignment:** ECIDs are assigned as members of contracts.
* **Splitting:** Contracts can be split into child contracts, each with a defined resource slice and member set.
* **Teardown:** When all members are removed and/or contract is dissolved, resources are atomically returned to the parent contract.

##### **Build-up Example:**

1. **Create contract:** Kernel/hypervisor splits a parent contract, creating a new contract with specified resource attributes.
2. **Assign ECIDs:** One or more ECIDs are assigned as members of the contract.
3. **Split further if needed:** Child contracts may be created for sub-guests, processes, or tenants.

##### **Teardown Example:**

1. **Remove ECIDs:** Kernel removes ECIDs from the contract.
2. **Dissolve contract:** When no ECIDs remain, contract is dissolved and resources are reclaimed by the parent.

---

### **4. Numbering Schemes and Metadata**

#### **4.1 ECID Fields (Per Hart, Hardware Tracked)**

* **ECID number:** 8 bits (unique per hart)
* **Parent ECID:** 8 bits (for delegation/revocation tree)
* **Contract IDs:** 8 bits per resource class (0x00 = best effort, i.e., no dedicated contract)
* **ECS pointer:** 32/64 bits (physical pointer to execution context structure in RAM)

**Implementation Note:**
All ECID metadata is hart-local. ECIDs reference contract IDs for global resources, but do **not** point to groups/banks/contracts directly; instead, banks and contracts reference up to the owning ECID.

#### **4.2 Group IDs (for Context Banks)**

* **Group IDs:** Hardware-internal, not visible to software.
* **Metadata:** Parent group pointer, owner ECID, delegated resource lists.

#### **4.3 Contract IDs and Metadata**

* **Contract IDs:** 8 bits (max 256 contracts per resource class).
* **Metadata:** Resource slice (latency, bandwidth, etc.), member ECID set, parent contract, resource class/type, policy flags.

---

### **5. Physical vs. Logical Representation**

* **Groups:** Tree structure for ownership/delegation of per-hart state (context banks); physically implemented with child-to-parent pointers.
* **Contracts:** Tree structure for global resource allocation; each contract directly manages its member ECIDs.

**Design Rationale:**

* Maximizes hardware lookup efficiency (O(1)), avoids duplication, and enables clear delegation/enforcement logic.
* All assignment and delegation is kernel-driven, with hardware enforcing atomicity and isolation.

---

### **6. OS Fundamentals and CE Integration**

* **Processes/Threads:** Each is a set of ECIDs (per thread or vCPU).
* **Kernel/Hypervisor:** Control plane assigning ECIDs, managing contracts, and owning all root resources at boot.
* **Resource Assignment:** On context switch, active ECID’s contract assignments are loaded into hardware for each resource class, determining scheduling, arbitration, and enforcement.
* **Dynamic Adaptation:** Kernel can atomically reassign ECIDs to different contracts (e.g., upgrading a process from best effort to real-time contract) as policy or workload changes.

---

### **7. Unified Context Structures (UCS/ECS)**

* **ECS (Execution Context Structure):** DMA-friendly, memory-mapped state block for save/restore of architectural state. ECS includes an explicit header (ECID, flags, version, etc.) and all needed GPRs, FPRs, vector state, PC, CSRs, SATP, etc.
* **UCS (Unified Context Structure):** Optional kernel-level abstraction, pointing to the ECS for all hardware context; may include extra fields for scheduling, accounting, VM info, etc.
* **Design Note:**
  The ECS header is placed at offset 0, making use of the RISC-V x0 register “dead slot.”
  Hardware and kernel use the ECS pointer for rapid save/restore and migration.

---

### **8. Diagrams and Tables**

#### **8.1 ECID Structure**

```
[ECID (8 bits)] + [Contract IDs (per resource class, 8 bits each)] + [ECS pointer (32/64 bits)]
```

#### **8.2 Contract Membership Example**

```
[Contract: 40% DRAM BW, Latency=Low]
+---------------------------------------------------+
| Contract ID: 12                                   |
| Resource: Memory (DRAM)                           |
| Slice: 40% total bandwidth                        |
| Members: ECID 2, ECID 7, ECID 11, ECID 22         |
+---------------------------------------------------+
```

#### **8.3 Efficiency Table**

| **Total ECIDs** | **Banks** | **Contracts** | **Concurrent** | **Oversubscription** |
| --------------- | --------- | ------------- | -------------- | -------------------- |
| 2000            | 32        | 16            | 32             | 62.5:1               |
| 8               | 4         | 2             | 4              | 2:1                  |
| 1               | 1         | 1             | 1              | 1:1 (static)         |

#### **8.4 Contracts vs. Groups**

| **Property** | **Group**                | **Contract**                          |
| ------------ | ------------------------ | ------------------------------------- |
| Structure    | Tree (exclusive)         | Tree (resource allocation/scheduling) |
| Purpose      | Ownership/delegation     | Scheduling/resource sharing           |
| Membership   | Single owner             | Set of ECIDs (may be 1 or many)       |
| Dynamics     | Rigid                    | Dynamic (kernel-driven)               |
| Isolation    | Strict hardware boundary | Policy-based resource guarantees      |

---

### **9. Open Points and Research Directions**

* **Diagram clarity:** Add hardware diagrams for group and contract mapping.
* **Optimal sizing:** Best practices for contract sizing, splitting, and performance.
* **Software overflow:** Efficient support for software-managed contracts when hardware limit is reached.
* **Multi-resource contracts:** Best way to support contracts covering multiple resource classes.
* **NUMA/Topology awareness:** Contract assignment in systems with non-uniform memory access.
* **Audit/debug hooks:** Further kernel/hardware mechanisms for observability and debugging.

---

### **10. Historical Note: Why Pools Were Removed**

Early CE suite drafts used "pools" as an explicit grouping layer between ECIDs and contracts.
It was later realized that:

* **Pools always pointed to a single contract, making them redundant.**
* **All contract membership logic is simpler and more efficient when tracked by the contract itself.**
* **Merging pools into contracts results in no loss of generality or flexibility, while improving clarity, auditability, and hardware-software interface design.**

As a result, all pooling concepts were removed, and **contract** is now the sole entity for global resource allocation, scheduling, and ECID grouping in the CE suite.

---

## **End of Foundational Chapter (v0.5)**

---


