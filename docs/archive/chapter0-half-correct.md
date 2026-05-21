# **CE Suite: Foundational Structures and Semantics (Draft v0.4)**

---

## **1. Overview**

This foundational chapter rigorously defines the core concepts and constructs of the Context Extensions (CE) suite:

* **Execution Context Identifiers (ECIDs)**
* **Groups** (resource ownership and delegation)
* **Pools** (resource scheduling and dynamic sharing)
* **Unified Context Structures (UCS/ECS)**
* **Extended ECID (EECID)** and **Tenant ECs**

These form the fundamental framework for resource isolation, delegation, scheduling, and dynamic allocation for the CE extensions (CME, MSE, CPE, QoS).

---

## **2. Axiomatic Foundations**

### **2.1 ECID Axioms**

1. **Hart-locality:** ECIDs uniquely exist per hart. The global identifier is a tuple (hart\_id, ECID).
2. **Atomicity:** Only one ECID is active per hart at any moment.
3. **Persistence:** ECID 0 is persistent per hart and owns essential resources.
4. **Hierarchy:** ECIDs form a strict delegation tree rooted at ECID 0.

### **2.2 Group Axioms (Context Banks)**

1. **Bank→Group Mapping:** Every context bank points upward to a group (its owner).
2. **Group→Parent Group Mapping:** Non-empty groups (except group zero) point upward, forming a tree rooted at group zero.
3. **Zero Group:** Always points to itself; universal root and emptiness sentinel.
4. **Empty Groups:** Any group (except zero) pointing to itself is empty and reclaimable.
5. **Bank Allocation:** New groups require at least one available bank; no empty groups.
6. **Non-Delegation of Essential Banks:** Parent groups must retain at least one bank.
7. **Limited Hardware Banks:** Finite hardware banks (≤64 non-VMT banks per hart, 2-4 VMT banks per hart).
8. **Metadata Reversal:** Bank metadata points upward to parent groups for efficient reclamation.
9. **Group Deletion:** Automatic hardware cleanup when empty.
10. **Unique Ownership:** Banks have single-group ownership.
11. **Delegation Constraint:** Only parent groups can delegate banks.

### **2.3 Group Axioms (Contracts: MSE/QoS)**

1. **Contract→Group Mapping:** Contracts point to a group owner.
2. **Hierarchical Delegation:** Contracts form hierarchical groups; child contracts can subdivide resources.
3. **Zero Group:** Universal root group, points to itself.
4. **Empty Groups:** Reclaimable when empty.
5. **Contract Allocation:** Creation requires available contracts.
6. **Non-Delegation of Essential Resources:** Parent retains essential minimum resources.
7. **Limited Hardware Contracts:** Finite hardware-enforced contracts.
8. **Software Contracts and Overflow:** Software-managed overflow groups allowed if hardware slots exhausted.
9. **Metadata Reversal:** Contract metadata points upward for efficient reclamation.
10. **Group Deletion:** Automatic hardware-driven cleanup.
11. **Unique Ownership:** Contracts have single-group ownership.
12. **Delegation Constraint:** Delegation authority rests only with parent groups.

## 2.4 Pool and Contract Axioms (Refined)

### **Axioms**

1. **Per-Resource-Class Pools:**

   * Every ECID is a member of at most one pool per global resource class (e.g., one for MSE, one for QOS).
   * Pools are logical groupings; each pool is always bound to a contract for that resource class.
2. **Contract-Pool Binding:**

   * A contract (resource slice: latency, bandwidth, etc.) is always bound to exactly one pool.
   * A contract is only effective when bound to a pool; unbound contracts are inert.
   * Pools with only one ECID provide that ECID a dedicated contract.
3. **Splitting and Delegation:**

   * Only the owner (parent pool) may split or delegate a contract, creating a subpool with its own contract (a strict subset of the parent).
   * The sum of all child contracts must never exceed the parent’s allocation.
   * Splitting is a privileged, kernel-driven, atomic operation.
4. **Resource Arbitration and Acceptance:**

   * Binding or splitting a contract requires hardware arbitration (MMU for MSE, QOS scheduler for QOS) to check global resource constraints.
   * The outcome (accept/reject) must be immediate and chip-global; failure to bind leaves the contract unbound and resources unchanged.
5. **Releasing and Dissolving:**

   * When a contract is released (explicitly or by releasing its pool), its resources return to the parent pool and the contract is dissolved.
   * A pool with no ECIDs is dissolved and its contract dissolved as well.
6. **Auditing and Kernel Visibility:**

   * Each virt level (kernel, hypervisor, guest) can enumerate all pools and contracts under its control, including those created by its tenants.
   * Kernel can query all pool memberships and contract parameters for audit and debug.
7. **Hierarchy and Limits:**

   * Pools and contracts form a strict tree with a maximum depth of four (matching virt levels: L0 kernel, L1 hypervisor, L2 guest, L3 sub-guest/process).
   * No cycles or multiple parent pools allowed.
8. **Metadata Structure and Hardware Lookup:**

   * All pool and contract metadata structures must be flat or shallow, ensuring O(1) or O(log N) lookup in hardware for arbitration and resource scheduling.
   * Contract and pool IDs are small (e.g., 8 bits), and assignment tables are SRAM-local or rapidly accessible.

---

### **Build-up and Teardown Example**

#### **Build-up Sequence:**

1. **Create pool:** Kernel creates a new pool (must have at least one ECID as a member).
2. **Bind contract:** Kernel binds a contract (possibly split from a parent) to this pool, defining its resource slice (latency, bandwidth, etc.).
3. **Assign ECIDs:** Kernel assigns one or more ECIDs to the new pool; these ECIDs now share the pool’s contract parameters.

#### **Teardown Sequence:**

1. **Unbind contract:** When the pool is no longer needed, kernel unbinds the contract, releasing resources back to the parent pool/contract.
2. **Remove ECIDs:** Kernel removes any remaining ECIDs from the pool (reassigns them or terminates them).
3. **Dissolve pool:** If no ECIDs remain, the pool is dissolved.

---

### **Explanatory Notes**

* Pools are **never used for context banks or cache partitions**—these per-hart resources are always assigned per-ECID, kernel-driven, not pooled.
* For global resources (MSE, QOS), pools enable flexible, policy-driven sharing and strict scheduling guarantees.
* Hardware arbitration for contract binding is always chip-global and must be atomic and fast.
* All delegation, splitting, and merging forms a strict, shallow hierarchy for efficient lookup and resource tracking.
* All kernel operations on pools and contracts are privileged and auditable, with full visibility for resource management and debugging.

---

## **3. Lifecycle and Interactions**

### **3.1 ECID Lifecycle**

* **Creation:** Kernel-assigned, starts at ECID 0 at boot.
* **Delegation:** ECIDs created as child tenants following delegation rules.
* **Migration:** OS-driven, explicit resource reassignment.
* **Revocation:** Recursive resource reclamation to parent ECIDs.

### **3.2 Group Lifecycle**

* **Creation:** Parent ECID creates groups by delegating resources.
* **Delegation:** Strict, hierarchical, hardware-enforced.
* **Revocation:** Automatic when empty; recursive resource reclamation.

### **3.3 Pool Lifecycle**

* **Creation:** Explicit per resource type.
* **Membership:** Explicit ECID membership; defaults to best-effort if unspecified.
* **Assignment:** Dynamic, hardware-scheduled according to policies.

---

## **4. Numbering Schemes and Metadata**

### 4.1 ECID Numbering and Metadata

#### **Metadata in ECID (identity):**

* **ECID number:** 8 bits

  * The unique local “name” of this ECID within its hart.
  * Used as a reference by all other hardware or software structures (banks, contracts, groups, etc.).

#### **Data stored per ECID (on the hart):**

* **Parent ECID:** 8 bits

  * Used for fast delegation tree traversal and revocation.
* **Pool numbers**

  * **MSE pool**: 8 bits (memory contracts)
  * **QoS pool**: 8 bits (bandwidth/IO contracts)
  * **Each field 0x00**: signifies “best effort” pool (no dedicated contract for that resource class)
* **ECS pointer:** 32 or 64 bits

  * Physical memory address of the Execution Context Structure in RAM (for context save/restore, hardware/software bridge).

#### **What is NOT stored:**

* **hart\_id:**

  * Not part of the ECID. Hart identity is tracked via machine CSR, not per ECID.
* **Resource-attached flag:**

  * No longer needed. Pool numbers fully encode all contract/resource status.
* **Pointers to banks, groups, contracts:**

  * ECID does NOT point to these; instead, those objects point up to the ECID.

---

> **Implementation Note – Locality, Pool Membership, and Reference Patterns:**
> All ECID metadata and data fields are kept strictly local to the hart where the ECID is active. The ECID’s “name” (8 bits) is used by banks, groups, and contracts to refer to this ECID (never the reverse). Pool memberships (for CME, CPE, MSE, QoS) are referenced by 8-bit values per resource class; value 0x00 means “best effort” and also encodes lack of a dedicated contract.
> ECS pointers allow the hardware to save/restore the EC’s full context and bridge to the OS logic. The global ECID identity (hart\_id, ECID) is only used by the OS; hardware never manipulates the global tuple.

---

#### **Summary Table: ECID Hardware Fields**

| FieldWidthDescription |            |                                                |
| --------------------- | ---------- | ---------------------------------------------- |
| ECID number           | 8 bits     | Local “name”; unique per hart                  |
| Parent ECID           | 8 bits     | ECID of parent in delegation tree              |
| MSE pool              | 8 bits     | Pool for memory contracts (0x00 = best effort) |
| QoS pool              | 8 bits     | Pool for bandwidth/IO (0x00 = best effort)     |
| ECS pointer           | 32/64 bits | Physical pointer to ECS in RAM                 |

### **4.2 Group Numbering and Metadata**

* **Group IDs:** Hardware-internal, invisible to software.
* **Metadata:** parent group pointer, owner ECID, delegated resource lists.

### **4.3 Pool Numbering and Metadata**

* **Pool IDs:** 8-bit identifiers, max 256 pools per resource class.
* **Metadata:** Latency (4 bits), Bandwidth (4 bits), scheduling policy flags.

---

## **5. Physical vs. Logical Representation**

* **Groups:** Logically downward; physically implemented with child-to-parent pointers.
* **Pools:** Logically manage resource collections; physically resources point upward to pools or ECIDs.

**Rationale for Choices:**

* Hardware transistor efficiency and minimal state
* Rapid hardware lookups (O(1))
* Clear delegation enforcement logic

---

## **6. OS Fundamentals and Relationship to CE**

* **Linux processes:** Collections of ECIDs (per-thread).
* **Kernel:** Distributed control plane with ECIDs per hart; interrupt handlers as child ECIDs within pools.
* **VMs:** Analogous structure with vCPUs as ECIDs, organized similarly.

---

## **7. Unified Kernel Structures (UCS/ECS)**

* **UCS:** Global OS kernel-maintained data structure, managing EC state.
* **ECS:** DMA-friendly, memory-mapped subset of UCS; structurally matches non-VMT context banks, enabling DMA-based context switches.
* **EECID:** Not hardware-tracked; software shorthand for (hart\_id, ECID) tuples.
* **Tenants:** An EC assigned a group, capable of further delegation.

#### **ECS: Execution Context Structure Layout**

The **Execution Context Structure (ECS)** holds the full architectural state of an execution context for save/restore operations. It is stored in RAM and is referenced from the ECID.

**Header Placement and x0 Optimization:**

* The ECS does **not** save register x0 (which is always zero in RISC-V).
* The space that would have held x0 (4 bytes for RV32, 8 bytes for RV64) is instead used as the **ECS header**.
* This header provides identity, state flags, versioning, and future extensibility, and always appears at the very start of the ECS memory block.

**Proposed ECS Header Fields:**

* `ecid` (uint8\_t): The local ECID number for this execution context.
* `flags` (uint8\_t): Dirty/valid, atomicity, or other runtime state.
* `version` (uint8\_t): Structure version (for compatibility/discovery).
* `reserved`: Padding/feature bitmap (fills remaining header bytes).

**Example ECS Layout for RV64:**

| Offset Field Size Description |           |         |                                       |
| ----------------------------- | --------- | ------- | ------------------------------------- |
| 0                             | ecid      | 1 byte  | ECID number                           |
| 1                             | flags     | 1 byte  | Valid/dirty/atomic flags              |
| 2                             | version   | 1 byte  | Structure version                     |
| 3–7                           | reserved  | 5 bytes | Padding/future feature bits           |
| 8                             | x1–x31    | 248 B   | GPRs (x1–x31)                         |
| ...                           | f0–f31    | 256 B   | FPRs                                  |
| ...                           | pc        | 8 B     | Program Counter                       |
| ...                           | CSRs      | ≥40 B   | Core privileged state (inc. SATP)     |
| ...                           | VMT block | impl.   | Vector/matrix/tensor state if present |

* For **RV32**: The header is 4 bytes, and GPRs are 31 × 4 = 124 bytes.

**Vector Block:**

* If the CPU/hart supports RVV or future VMT extensions, the ECS always reserves space for the full vector block (size is hardware/implementation-specific and must be discoverable by the kernel at boot).

**ECS Discovery and Extensibility:**

* All fields, sizes, and layout are discoverable by the kernel at boot (via firmware, device tree, or CSR-based reporting).
* The ECS `version` field ensures backward and forward compatibility.
* Struct layout must be published by hardware vendors as part of CE platform documentation.

**Design Advantages:**

* No wasted space for x0; header makes efficient use of “dead” register slot.
* Hardware and OS can rapidly identify, validate, and migrate ECS blocks.
* Enables high-performance DMA/context switching and future extensibility.

---

Here’s the **revised table** with an explicit header and entries that clearly distinguish what’s *in the ECS* versus what’s simply referenced from the UCS/kernel struct.

---

---

| Field           | Interrupt | Thread/Process | vCPU  | ECS (always present) | UCS (pointer to ECS) | Notes                                                        |   |
| --------------- | --------- | -------------- | ----- | -------------------- | -------------------- | ------------------------------------------------------------ | - |
| **ECID number** | (N/A)\*   | Yes            | Yes   | Yes (in header)      | pointer              | ECS header always contains ECID; ECID points to ECS          |   |
| GPRs            | Yes       | Yes            | Yes   | Yes                  | pointer              | ECS always contains all GPRs                                 |   |
| FPRs            | Maybe     | Yes            | Yes   | Yes                  | pointer              | ECS always reserves FPRs; lazy save possible                 |   |
| VEC/VMT         | Maybe     | Yes            | Yes   | Yes                  | pointer              | ECS reserves VEC/VMT block if hart supports                  |   |
| PC              | Yes       | Yes            | Yes   | Yes                  | pointer              | ECS always contains PC                                       |   |
| CSRs            | Yes       | Yes            | Yes   | Yes                  | pointer              | ECS contains all required CSRs (incl. privilege, SATP, etc.) |   |
| SATP            | No        | Yes            | Yes   | Yes                  | pointer              | ECS always reserves SATP field                               |   |
| Privilege Mode  | Yes       | Yes            | Yes   | Yes (in CSR fields)  | pointer              | Tracked in ECS CSR fields                                    |   |
| Parent Pointer  | Maybe     | Maybe          | Maybe | No                   | Yes                  | Kernel-only linkage, not in ECS                              |   |
| VM/Guest Info   | No        | No             | Yes   | No                   | Yes                  | Only in vCPU/VM kernel structs, not in ECS                   |   |

\*Interrupts: The interrupted context’s ECID is known, but the interrupt itself doesn’t “own” an ECID.

|   |   |   |   |   |   |   |
| - | - | - | - | - | - | - |

Conclusion:

The ECS is a fundamental and universally required structure for CE-compliant systems, enabling fast and reliable hardware and OS context management.

The UCS, while conceptually appealing for OS design, is optional and primarily serves as a software-level abstraction for unifying process, thread, vCPU, and container metadata. Most kernel logic can simply reference the ECS for hardware context, with UCS providing extra linkage or accounting fields as needed.

The case for UCS is strongest in kernels or hypervisors that want to streamline all context management codepaths—but ECS remains the true cross-type anchor.

|   |   |   |   |   |   |   |
| - | - | - | - | - | - | - |

---

### **Clarifying Note:**

> **Note:**
> For all context types, the kernel’s UCS or management struct does not duplicate any hardware context fields, but simply points to the ECS in RAM. The ECS contains all architectural state needed for context switching and migration—including the ECID number in its header.
> Kernel-level fields unique to scheduling, VM, or process management are only stored in the UCS or associated kernel structs.

---

Let me know if you want this table added verbatim, or if you want further formatting or placement guidance!

---

## **8. Diagrams and Tables**

### **8.1 ECID Structure**

```
[hart_id (8 bits)] + [ECID (7 bits)] + [resource-attached flag (1 bit)]

```

### **8.2 Pool Membership Example**

```
[Bank Pool: 4 Banks]            [Worker Pool: 8 ECIDs]
+-----------+                   +-------+-------+-------+-------+-------+-------+-------+-------+
| Bank 0    |<----assign------->|ECID 0 |ECID 1 |ECID 2 |ECID 3 |ECID 4 |ECID 5 |ECID 6 |ECID 7 |
| Bank 1    |                   |       (scheduled)            |            (waiting)          |
| Bank 2    |                   |       (on CPU)               |            (in UCS)           |
| Bank 3    |                   |                               |                               |
+-----------+                   +-------+-------+-------+-------+-------+-------+-------+-------+

```

### **8.3 Efficiency Table**

| **Total ECIDsBanksConcurrentOversubscription** |    |    |              |
| ---------------------------------------------- | -- | -- | ------------ |
| 2000                                           | 32 | 32 | 62.5:1       |
| 8                                              | 4  | 4  | 2:1          |
| 1                                              | 1  | 1  | 1:1 (static) |

### **8.4 Pools vs. Groups**

| **PropertyGroupPool** |                      |                    |
| --------------------- | -------------------- | ------------------ |
| Structure             | Tree (exclusive)     | Arbitrary set      |
| Purpose               | Ownership/delegation | Scheduling/sharing |
| Membership            | Single owner         | Many ECIDs         |
| Dynamics              | Rigid                | Dynamic            |
| Isolation             | Strict               | Policy-based       |

---

## **9. Formalized Open Points and Clarifications**

* **Hardware Group 0:** Permanently owned by persistent kernel ECID per hart. Reset returns to CE-neutral.
* **Host/Guest CE Usage:** Guests require CE-aware hosts; delegation always begins at ECID 0.
* **Boot ECID Allocation:** ECID 0 at boot for predictable initialization and recovery.

| **StageOwner ECIDGroup 0 StateNotes** |         |                    |                                |
| ------------------------------------- | ------- | ------------------ | ------------------------------ |
| Reset/boot                            | 0       | All resources      | Kernel ECID, non-empty group 0 |
| After kernel boot                     | 0       | All/most resources | Kernel delegates resources     |
| After delegation                      | 0, N, … | Subset(s)          | Tenants/guests manage subsets  |
| Tear-down/cleanup                     | 0       | All resources      | Returned to root kernel ECID   |

---

## **10. Open Issues and Research Directions**

* Explicit hardware diagrams
* Optimal pool sizing strategies
* Efficient kernel interactions with ECS/UCS
* Detailed real-world feasibility analysis

---

---

## **Section X: Pools—Scope, Limits, and Practical Use in CE**

### **1. Why Pools Are a Bad Idea for Context Banks (CME)**

Context banks are a per-hart hardware resource:

* **Only one ECID can be active per bank at any moment.**
* Any handoff of a bank between ECIDs must be scheduled and tracked by the kernel, since only the kernel knows the runnable state, priorities, and deadlines for each ECID.
* **Hardware “pool rotation”**—automatically passing a bank among a set of ECIDs in a pool—cannot take into account blocking, sleeping, or other policy, and so risks starvation, priority inversion, or security flaws.
* The kernel’s own data structures already track which ECIDs are in which pools or eligible sets.
* **Conclusion:** *CME pools add complexity and risk without any benefit. All bank assignment and handoff must be handled by kernel code, via privileged CME instructions.*

---

### **2. Why Pools Are a Bad Idea for Cache Partitions (CPE)**

Cache partitions (L1/L2) are also per-hart, hardware-divided resources:

* **Each partition should be owned by a single ECID at a time** to preserve isolation and maximize cache locality.
* If a set of workers “shared” a partition as a pool, their different working sets and code paths would thrash the cache, giving none of them predictable performance.
* Any real-world kernel or scheduler will assign private partitions to contexts needing isolation, and use the “best effort” (BE) partition for the rest.
* **Conclusion:** *Pooling cache partitions only dilutes performance, introduces unpredictability, and defeats the point of cache partitioning. Partition assignment should always be explicit and per-ECID, kernel-driven.*

---

### **3. Why Pools Are Good for Global Resources (MSE, QOS)**

Memory scheduling (MSE) and I/O bandwidth/quality-of-service (QOS) are global, chip-level resources:

* These resources are inherently **multiplexed and shared**—multiple ECIDs may contend for memory or I/O at any given moment.
* **Pools** allow the kernel to group ECIDs with similar latency or bandwidth requirements and assign them shared or prioritized access to these resources.
* **Example:**

  * ECIDs in a “real-time pool” might get lower memory access latency, higher I/O throughput, or more guaranteed bandwidth than those in a “best effort” pool.
  * The kernel or system admin can reassign ECIDs between pools to adapt to workload needs.
* **Conclusion:** *Pools are essential for MSE and QOS, enabling controlled, dynamic, and policy-driven allocation of scarce, shared global resources.*

---

### **4. Step-by-Step Example: Context Switch and Pool-Based Resource Configuration**

Let’s trace what happens when the kernel switches from ECID\_A to ECID\_B on a hart:

#### **Context Switch IN (to ECID\_B):**

1. **Kernel issues ec.ob**  or ec.om to restore ECID\_B.
2. **Hart loads ECID\_B’s number** (from the context bank or ECS) as a side effect of ec.ob and ec.om.
3. **ECID\_B’s pool assignments are looked up** (from kernel-managed ECID table).

   * **MSE Pool:** 8 bits loaded into the MMU (determines memory scheduling policy for ECID\_B).
   * **QOS Pool:** 8 bits loaded into DMA/IO controller (sets I/O priorities, bandwidth limits).
   * **CPE Partition:** If ECID\_B has a private cache partition, cache controller is switched to it; else, ECID\_B uses the BE cache slice.
   * **CME (Context Bank):** Bank is directly assigned to ECID\_B as part of the context switch; no pool logic is used.
4. **Hart architectural state (registers, CSRs, etc.)** is loaded from ECS/context bank.

#### **Context Switch OUT (from ECID\_A):**

1. **Kernel issues** `ec.ib` (save to context bank) or `ec.im` (save to ECS in RAM).
2. **Hart saves all architectural state** (registers, CSRs, etc.) into the assigned context bank or ECS.
3. **ECID\_A’s bank and resource assignments** are updated in kernel data structures.

#### **Throughout:**

* **Only MSE and QOS pools are used** to influence hardware scheduling of global resources.
* **CME and CPE use per-ECID explicit assignment.** No hardware pooling or sharing at the bank/partition level.
* **All assignments, tracking, and handoffs are managed by the kernel.** Hardware just loads the relevant configuration bits for the new ECID.

---

### **Summary Table: Pools in CE**

| Resource     | Pooling Supported? | Why/Why not?                     | Assignment Mechanism    |
| ------------ | ------------------ | -------------------------------- | ----------------------- |
| CME (Banks)  | No                 | Kernel knows best; one-at-a-time | Explicit, kernel-driven |
| CPE (Cache)  | No                 | Private partitions or BE only    | Explicit, kernel-driven |
| MSE (Memory) | Yes                | Multiplexed global resource      | Pools enable sharing    |
| QOS (I/O)    | Yes                | Multiplexed global resource      | Pools enable sharing    |

---

> **In summary:**
> Pools are fundamental for chip-wide scheduling of global resources like memory and I/O, but do not belong in the control of per-context, local resources like context banks or cache partitions.
> All assignments and handoffs are kernel-driven, with hardware just loading the necessary configuration from the active ECID.

---

**Ready to copy/paste and adapt for your document! If you want further editing or placement suggestions, just let me know.**

**End of Foundational Chapter (Draft v0.4)**

---


