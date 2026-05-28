# Appendix A — ECID Allocation, Delegation, and Destruction

**Status:** Normative reference for kernel implementers.
**Scope:** This appendix documents the kernel-side data structures and algorithms for
ECID lifecycle management. It complements the architectural definitions in Chapter 0 §0.2–§0.3.

---

## A.1 Scope and relationship to the architectural model

The **architectural model** for ECIDs is the `EC[e]` array defined in Chapter 0 §0.3:
a per-hart array indexed by ECID number, with `ecs_ptr` at offset 0. Hardware accesses
ECIDs through this array. Hardware never traverses the kernel radix tree.

The **kernel ECID prefix tree** is a software data structure maintained per hart in
kernel RAM. It serves three purposes:

1. **Prefix ownership.** Each node tracks which privileged actor (kernel, hypervisor,
   or nested hypervisor) owns which contiguous range of ECIDs.
2. **Fast allocation.** O(1) allocation within a prefix via a free list; O(log N)
   subtree walk for prefix delegation and revocation.
3. **Quota enforcement.** Per-prefix caps on resourced ECIDs (those holding Contracts
   or Banks) prevent tenant exhaustion of scarce hardware resources.

The two views are complementary: the kernel allocates an ECID by initializing the
`EC[e]` entry on the appropriate hart and recording the allocation in its prefix tree.
Hardware reads `EC[e]` directly; the prefix tree is invisible to hardware.

**Relationship to EC migration.** ECIDs are hart-local. When the scheduler moves an EC
from one hart to another, the kernel deallocates the source ECID (returning the slot to
the source hart's prefix tree) and allocates a fresh ECID on the destination hart,
reusing the same in-memory ECS. The prefix trees on each hart are updated independently;
no cross-hart coordination is required for allocation or deallocation. Migration is
covered in Chapter 0 §0.2 and Chapter 1.

---

## A.2 Data structures

### A.2.1 The `EC[e]` entry (architectural)

Reproduced from Chapter 0 §0.3 for reference. This is the structure hardware reads:

```c
/* Per-hart; conceptually RAM-resident, SRAM-cached for active ECIDs. */
struct EC_entry {
    void     *ecs_ptr;       /* ECS pointer — always at offset 0              */
    uint8_t   generation;    /* incremented on every slot reuse               */
    uint8_t   delegation_L;  /* delegation level, 0 ≤ L ≤ D                  */
    uint16_t  parent_ecid;   /* parent ECID in the delegation tree            */
    /* Implementation-defined: cached bank/contract refs, flags, etc.         */
};
```

The kernel must write this entry before making the new ECID visible to any software.
The `generation` field must be incremented each time a slot is reused, to prevent
stale `(hart_id, ECID, generation)` references from reaching the wrong target.

### A.2.2 The kernel prefix tree node

```c
/* One node in the kernel ECID prefix tree. One tree per hart, in kernel RAM. */
struct ecid_prefix_node {
    uint16_t  ecid_base;          /* first ECID in this node's range            */
    uint16_t  ecid_limit;         /* one past the last ECID in range            */
    uint16_t  owner_ecid;         /* ECID of the actor that owns this range     */
    uint8_t   delegation_L;       /* delegation level of owner_ecid             */

    uint32_t  resourced_quota;    /* max resourced ECIDs allowed in this subtree */
    uint32_t  resourced_count;    /* current resourced ECID count in subtree    */

    struct ecid_prefix_node *parent;
    struct ecid_prefix_node *first_child;   /* head of singly-linked child list */
    struct ecid_prefix_node *next_sibling;  /* sibling list link                */

    /* Implementation-defined: free list of unallocated ECIDs in [ecid_base, ecid_limit)
       that have not been delegated to child nodes. Push and pop must be O(1).  */
};
```

**Range invariant.** Every child node's range `[child.ecid_base, child.ecid_limit)` is a
non-overlapping subset of its parent's range. The union of all child ranges never covers
the full parent range: the remainder is the parent's own free pool, managed in the
implementation-defined free list.

**Prefix alignment.** For radix-tree efficiency, `ecid_base` should be aligned to
`ecid_limit − ecid_base` and the range size should be a power of two. This makes
subtree indexing O(1) at each tree level. Implementations are not architecturally
required to enforce alignment, but unaligned ranges degrade allocation performance.

**Reverse lookup.** The destruction algorithm (§A.5.2) requires finding the prefix node
that contains a given ECID. Implementations may maintain a flat reverse-index
(`ecid → prefix_node *`) for O(1) lookup, or walk the tree for O(log N) lookup. The
choice is implementation-defined; the algorithm below uses `find_prefix_node` to
abstract over it.

---

## A.3 ECID allocation

### A.3.1 Overview

ECID allocation is always performed by the privileged actor that owns the containing
prefix — the kernel (L0), a hypervisor (L1), or a nested hypervisor (L2). User mode
may never allocate ECIDs. The maximum delegation depth is D ≤ 3.

Two operations cover the full allocation surface:

- **Single ECID allocation** (`ecid_alloc`): pops one ECID from the node's free list
  and initializes the corresponding `EC[e]` entry. O(1).
- **Prefix delegation** (`ecid_delegate_prefix`): carves a contiguous, aligned sub-range
  out of a parent node and gives it to a child privileged actor. The child may then
  allocate ECIDs within that range without coordinating with the parent. O(range size)
  to initialize the child free list.

### A.3.2 Algorithm: single ECID allocation

```
function ecid_alloc(node, delegation_L) → new_ecid | error:

    preconditions:
        node.delegation_L < D            // node's owner may create children
        delegation_L == node.delegation_L + 1  // child is exactly one level deeper

    if node.free_list is empty:
        return ECID_ERR_EXHAUSTED

    new_ecid = node.free_list.pop()      // O(1)

    EC[new_ecid].ecs_ptr      = null     // caller must set before dispatch
    EC[new_ecid].generation  += 1        // ABA guard; wraps modulo 256
    EC[new_ecid].delegation_L = delegation_L
    EC[new_ecid].parent_ecid  = node.owner_ecid

    return new_ecid
```

The caller must write a valid `ecs_ptr` into `EC[new_ecid]` before dispatching the ECID
to any hart. The entry is not visible to hardware until `ecs_ptr` is non-null.

**Resourced ECIDs.** If the newly allocated ECID will hold Contracts or Banks
(a "resourced" ECID), the caller must additionally increment `node.resourced_count`
and verify that it does not exceed `node.resourced_quota`. Unresourced ECIDs are
limited only by the free list and do not consume the quota.

### A.3.3 Algorithm: prefix delegation

Prefix delegation creates a new child prefix node owned by a specific child ECID.
The child's free list is populated with the delegated range; that range is removed
from the parent's free list.

```
function ecid_delegate_prefix(parent_node, base, limit, child_ecid, quota) → error:

    preconditions:
        base >= parent_node.ecid_base
        limit <= parent_node.ecid_limit
        base < limit
        is_power_of_two(limit - base)              // alignment
        base % (limit - base) == 0                 // alignment
        not overlaps_any_child(parent_node, base, limit)
        EC[child_ecid].delegation_L < D            // child may delegate further
        quota <= parent_node.resourced_quota - parent_node.resourced_count

    // Remove [base, limit) from the parent's free pool.
    // ECIDs in [base, limit) already allocated to specific contexts are
    // not in the free list and are not affected here.
    parent_node.free_list.remove_range(base, limit)

    // Create and link the child node.
    child_node = new ecid_prefix_node
    child_node.ecid_base       = base
    child_node.ecid_limit      = limit
    child_node.owner_ecid      = child_ecid
    child_node.delegation_L    = EC[child_ecid].delegation_L
    child_node.resourced_quota = quota
    child_node.resourced_count = 0
    child_node.parent          = parent_node
    child_node.first_child     = null
    child_node.next_sibling    = parent_node.first_child
    parent_node.first_child    = child_node

    // Populate the child's free list.
    for ecid in [base .. limit):
        child_node.free_list.push(ecid)   // O(range size) total

    return ECID_OK
```

After this call, the child ECID's software owns the range and may call `ecid_alloc`
or `ecid_delegate_prefix` on the child node without coordinating with the parent.

---

## A.4 Delegation

### A.4.1 Resource delegation

Allocating a child ECID (§A.3.2) creates the child's *identity*. Delegating *resources*
— Banks and Contracts — is a separate step performed after ECID allocation.

**Banks** are delegated to a child ECID via `ec.it`. The instruction atomically updates
the Bank's owner field from the parent ECID to the child ECID. The Bank's owner field
is maintained by hardware; software cannot forge or overwrite it directly.

**Contracts** are split from the parent's Contract via the appropriate admission
instruction (`ms.it` for MSE, `qs.it` for QoS, `cp.ir` for CPE). Each split requires
chip-global arbitration and either succeeds atomically or fails with no state change
(atomic admission invariant). The parent's remaining Contract is reduced
by the amount allocated to the child.

### A.4.2 Delegation invariants

After any delegation step, the following invariants must hold:

1. **Level monotonicity.** `EC[child].delegation_L == EC[parent].delegation_L + 1`.
2. **Parent pointer.** `EC[child].parent_ecid == parent_ecid`.
3. **Bank ownership.** Any Bank delegated to the child has `bank.group_id == child_ecid`.
4. **Contract subset.** Any Contract split to the child represents a strict subset of
   the parent's allocation; the parent's allocation is reduced accordingly so that the
   sum never exceeds the original.
5. **Quota compliance.** If the child ECID is resourced, `parent_node.resourced_count`
   has been incremented and does not exceed `parent_node.resourced_quota`.
6. **Depth cap.** `EC[child].delegation_L ≤ D`. Delegation is not permitted when
   `EC[parent].delegation_L == D`.

---

## A.5 Forced destruction

### A.5.1 Guarantee

The instruction `ec.oe rd, rs1` destroys the ECID in `rs1` and its entire
delegation subtree. It **always succeeds**. A zombie, blocked, or hostile EC cannot
stall its own destruction. The kernel need not wait for the target to be cooperatively
scheduled or to voluntarily release resources.

### A.5.2 Algorithm: destroy ECID subtree

`ec.oe rd, rs1` triggers the following sequence in the implementation:

```
function ecid_destroy(target_ecid):

    // 1. Find the target's prefix node.
    node = find_prefix_node(target_ecid)

    // 2. Recursively destroy all allocated ECIDs in child nodes (post-order).
    for each child_node in subtree(node), post-order:
        for each ecid allocated within child_node:
            ecid_destroy_single(ecid)
        // Collapse the child node; its range reverts to the parent.
        parent = child_node.parent
        parent.free_list.add_range(child_node.ecid_base, child_node.ecid_limit)
        unlink_and_free(child_node)

    // 3. Destroy the target ECID itself.
    ecid_destroy_single(target_ecid)

    // 4. If target_ecid is a prefix owner, collapse its node.
    if node != null and node.owner_ecid == target_ecid:
        parent_node = node.parent
        if parent_node != null:
            parent_node.free_list.add_range(node.ecid_base, node.ecid_limit)
        unlink_and_free(node)


function ecid_destroy_single(ecid):

    // a. Revoke all Contracts owned by ecid.
    //    Resources return to the parent Contract automatically.
    for each contract where contract.owner_ecid == ecid:
        contract.resources → dissolve to parent Contract
        contract.owner_ecid = INVALID

    // b. Free all Banks owned by ecid.
    for each bank where bank.group_id == ecid:
        bank.group_id = INVALID
        bank.state    = FREE

    // c. Invalidate the EC[e] entry on the hart.
    EC[ecid].ecs_ptr      = null
    EC[ecid].delegation_L = INVALID
    EC[ecid].parent_ecid  = INVALID
    EC[ecid].generation  += 1          // invalidates all stale (ecid, generation) refs

    // d. Return the ECID slot to the parent node's free list.
    prefix_node = find_prefix_node(ecid)
    if prefix_node != null:
        prefix_node.free_list.push(ecid)
```

**Step ordering.** Contracts must be revoked before Banks are freed, to ensure no Contract
can reference a freed Bank. The `EC[e]` entry must be invalidated before the ECID slot
is returned to the free list, so that the slot cannot be reallocated and observed in a
partially-initialized state.

**Active hart preemption.** Before step (c), the implementation must ensure the target
ECID is not currently active on any hart (`current_ecid ≠ target_ecid` on all harts).
If the target is executing on a remote hart, that hart must be interrupted and the context
switched away before `EC[e]` is written. The mechanism for cross-hart interruption is
implementation-defined.

**Subtree depth.** Because D ≤ 3, the delegation subtree has at most four levels.
Post-order destruction is therefore bounded to a shallow, fast walk in practice.

---

## A.6 Diagrams

### A.6.1 Prefix ownership tree

The diagram below shows a four-level delegation hierarchy (D = 3) with two hypervisors
and multiple guest VMs, as it would appear in the kernel prefix tree for one hart.

```
ECID space: [0x0000 .. 0xFFFF]
│
└─ L0  Kernel
       owner_ecid: 0x0001, range: 0x0000–0xFFFF, quota: unlimited
   │
   ├─ L1  Hypervisor A
   │      owner_ecid: 0x0010, range: 0x1000–0x1FFF, quota: 512 resourced
   │  │
   │  ├─ L2  Guest VM 1
   │  │      owner_ecid: 0x1010, range: 0x1000–0x10FF, quota: 64 resourced
   │  │      allocated: 0x1011, 0x1012, 0x1013  (L3 guest threads)
   │  │
   │  └─ L2  Guest VM 2
   │         owner_ecid: 0x1020, range: 0x1100–0x11FF, quota: 64 resourced
   │         allocated: 0x1101, 0x1102  (L3 guest threads)
   │
   └─ L1  Hypervisor B
          owner_ecid: 0x0020, range: 0x2000–0x2FFF, quota: 256 resourced
          │
          └─ L2  Guest VM 3
                 owner_ecid: 0x2010, range: 0x2000–0x20FF, quota: 32 resourced
                 allocated: 0x2001  (L3 single thread)
```

The owner ECIDs (0x0010, 0x1010, etc.) are ordinary ECIDs allocated from the parent's
range by the parent's software. There is no structural difference between an owner ECID
and any other allocated ECID; the `owner_ecid` field in the prefix node is a software
record, not a hardware distinction.

Calling `ec.oe 0x0010` (destroy Hypervisor A) would collapse the entire subtree rooted
at that node: ECIDs 0x1010, 0x1011, 0x1012, 0x1013, 0x1020, 0x1101, 0x1102, and 0x0010
itself would all be destroyed, their Banks freed, and their Contracts dissolved. The range
0x1000–0x1FFF would be returned to the kernel's free list.

### A.6.2 `EC[e]` array and prefix tree relationship

Hardware sees only the `EC[e]` array. The kernel prefix tree is in RAM, invisible to
hardware. The diagram shows how the two views correspond for the Guest VM 1 subtree.

```
  Kernel prefix tree (RAM)                       Hardware EC[e] array (SRAM + RAM)
  ─────────────────────────────────────────      ─────────────────────────────────────────
  node: 0x1000–0x1FFF                            EC[0x0010]: ecs_ptr=…, gen=2, L=1
    owner: 0x0010  (Hypervisor A)                EC[0x1010]: ecs_ptr=…, gen=5, L=2
    free:  [0x1030, 0x1031, …]                   EC[0x1011]: ecs_ptr=…, gen=1, L=3
    │                                            EC[0x1012]: ecs_ptr=…, gen=3, L=3
    └─ node: 0x1000–0x10FF                       EC[0x1013]: ecs_ptr=…, gen=1, L=3
         owner: 0x1010  (Guest VM 1)             EC[0x1020]: ecs_ptr=…, gen=1, L=2
         allocated: 0x1011, 0x1012, 0x1013       …
         free: [0x1014, 0x1015, …]
                    │
                    └──── EC[0x1011].ecs_ptr ──► ┌─ ECS (RAM)
                                                 │  privilege level, scheduling flags
                                                 │  saved GPRs, FPRs (if spilled)
                                                 │  bank_ids[], contract_ids[]
                                                 │  OS private fields
                                                 └─────────────────────────────────
```

**Flow for a context switch (fast path).**
The kernel issues `ec.ib` (save current context to Bank) followed by `ec.ob` with the
target ECID number. Neither instruction touches the prefix tree or the ECS — only the
Bank and `current_ecid` are updated. The prefix tree is consulted only during allocation,
delegation, or destruction.

---

## A.7 Complexity summary

| Operation | Complexity | Notes |
|---|---|---|
| Allocate single ECID in a prefix | O(1) | Free-list pop |
| Look up `EC[e]` by ECID | O(1) | `base + e × stride`; hardware direct |
| Find prefix node for an ECID | O(1) or O(log N) | Depends on reverse-index; tree depth ≤ D+1 |
| Delegate prefix to child actor | O(range size) | Initialize child free list |
| Destroy single ECID | O(C + B) | C = Contracts held, B = Banks held; both bounded by quota |
| Destroy ECID subtree (`ec.oe`) | O(S · (C̄ + B̄)) | S = subtree size; C̄, B̄ = average resources per ECID |
| Return slot to free list | O(1) | Free-list push |

**Depth bound.** Because D ≤ 3, subtree depth is at most four levels. The "log N" factor
in prefix-node lookup is therefore a small constant, not a scaling concern.

**Quota bound.** Resourced ECIDs are counted against per-prefix quotas, so the total
number of Contracts and Banks in any subtree is bounded by the quota. Destruction of
the entire subtree is therefore bounded by a constant multiple of the quota, not by the
total ECID space.

---

*End of Appendix A.*
