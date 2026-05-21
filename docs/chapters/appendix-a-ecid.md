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

