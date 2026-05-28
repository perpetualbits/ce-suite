# Chapter 7 — CPE Instruction Set Reference

## 7.1 Overview

The **Cache Partitioning Extension (CPE)** provides hardware mechanisms for
isolating and reserving per-hart private cache capacity (L1I, L1D, and
L2-private) for specific Execution Contexts (ECIDs). A hard real-time EC
holding a CPE Contract is guaranteed that cache lines in its assigned ways
will not be evicted by other ECs on the same hart.

CPE v1 covers **per-hart private caches only** and does not manage shared
caches (e.g., L3). L3 partitioning may be addressed by a future CPE-S
extension.

Three rules govern every CPE instruction:

1. **ECID-first operands.** `rs1` holds the ECID number — a plain 16-bit
   integer. Parameters go in `rs2`.
2. **`rd` is the primary error channel.** 0 = success; non-zero = error code.
   Pass `x0` to discard.
3. **CPE Contracts are hierarchically delegatable.** `cp.it`/`cp.ot` follow
   the same splitting semantics as MSE and QoS.

---

## 7.2 Instruction Naming

CPE uses the subset `{r, t}` from the target-letter table:

| Mnemonic | Name | Direction | Target |
|---|---|---|---|
| `cp.ir` | Cache Partition: assign (In) Resource | in | resource |
| `cp.or` | Cache Partition: revoke (Out) Resource | out | resource |
| `cp.it` | Cache Partition: delegate (In) Tenant | in | tenant |
| `cp.ot` | Cache Partition: revoke (Out) Tenant | out | tenant |

---

## 7.3 Instruction Reference

> **Memory ordering.** CPE Contract instructions operate on per-hart hardware
> registers and SRAM; they carry no implicit memory fence. Cross-hart coordination
> during EC migration requires explicit `FENCE` instructions. See Chapter 17.

### `cp.ir` — Assign a cache partition to an ECID

> `cp.ir` = cache partition into resource (`cp` = CPE, `i` = into/assign, `r` = resource)

* **Syntax**: `cp.ir rd, rs1, rs2`
  * `rd`: 0 on success; error code on failure (see §7.8).
  * `rs1`: Target ECID.
  * `rs2`: Partition descriptor — inline or pointer (see §7.4).
* **Semantics**:
  1. Validates `rs1` is an allocated ECID on this hart.
  2. Validates the partition descriptor in `rs2` (see §7.4 and §7.6).
  3. Checks that assigned ways do not overlap with ways already assigned to
     other ECIDs at the same level. If overlap: returns `CPE_ERR_OVERLAP`.
  4. Checks that the assignment is consistent with any parent Contract the
     caller holds (if `rs1` was delegated a sub-partition via `cp.it`).
  5. Applies the assignment: programs the L1/L2 way-partition controllers
     for ECID `rs1`. If a prior assignment exists for `rs1`, it is replaced.
  6. Stores the assignment parameters in `EC[rs1]` for context-switch
     restore by CME.
  7. If `rs1` is currently active on this hart, the change takes effect
     immediately (or on the next instruction boundary; implementation-defined).
* **Cycles**: 1–8 (hardware writeback and invalidation of displaced lines may
  extend latency; see §7.6 sanity rule 4).

---

### `cp.or` — Revoke all cache partitions from an ECID

> `cp.or` = cache partition out of resource (`cp` = CPE, `o` = out of/revoke, `r` = resource)

* **Syntax**: `cp.or rd, rs1`
  * `rd`: 0 on success; error code on failure.
  * `rs1`: Target ECID.
* **Semantics**:
  1. Validates `rs1`.
  2. Revokes all partition assignments for ECID `rs1` at all cache levels.
  3. Invalidates all cache lines in the revoked ways that belong to `rs1`
     (required for isolation; see §7.6 sanity rule 5).
  4. If `rs1` holds child CPE Contracts (delegated via `cp.it`), those are
     revoked first recursively (bounded by D ≤ 3). Always makes forward
     progress; cannot be stalled by a hostile child.
  5. Clears the CPE state in `EC[rs1]`.
* **Cycles**: 1–16 (invalidation latency).

---

### `cp.it` — Delegate a cache-partition sub-slice to a child ECID

> `cp.it` = cache partition into tenant (`cp` = CPE, `i` = into/delegate, `t` = tenant/child ECID)

* **Syntax**: `cp.it rd, rs1, rs2`
  * `rd`: 0 on success; error code on failure.
  * `rs1`: Parent ECID — must hold a CPE Contract (assigned via `cp.ir`).
  * `rs2`: Delegation descriptor — child ECID plus way counts (see §7.5).
* **Semantics**:
  1. Validates `rs1` holds a CPE Contract on this hart.
  2. Extracts `child_ecid`, `l1_ways`, `l2_ways` from `rs2` (see §7.5).
  3. Verifies `child_ecid` is a child of `rs1` in the delegation tree and
     satisfies `EC[child_ecid].delegation_L < D`.
  4. Checks that `l1_ways + existing_l1_sum(children of rs1) ≤ l1_ways(rs1)`
     and same for L2. If exceeded: returns `CPE_ERR_CAP_EXCEEDED`.
  5. Splits the Contract: reduces `rs1`'s effective allocation by the
     delegated amounts; assigns the delegated slice to `child_ecid`.
  6. Updates running sums for ancestor groups.
* **Cycles**: 1–8.

---

### `cp.ot` — Revoke a delegated cache partition from a child ECID

> `cp.ot` = cache partition out of tenant (`cp` = CPE, `o` = out of/revoke, `t` = tenant/child ECID)

* **Syntax**: `cp.ot rd, rs1`
  * `rd`: 0 on success; error code on failure.
  * `rs1`: Child ECID whose delegated CPE Contract is being revoked.
* **Semantics**:
  1. Validates `rs1` holds a delegated CPE Contract.
  2. If `rs1` itself has child Contracts, revokes those first (recursive,
     bounded by D ≤ 3). Always makes forward progress.
  3. Revokes `rs1`'s Contract; returns the ways to the parent's allocation.
  4. Invalidates cache lines in the revoked ways owned by `rs1`.
  5. Clears the CPE state in `EC[rs1]`.
* **Cycles**: 1–16 (invalidation latency; proportional to subtree depth).

---

## 7.4 Partition Descriptor (`rs2` for `cp.ir`)

Per Chapter 0 §0.7.0, this descriptor is the *creation parameters*
for a CPE Contract identified by `(rs1, CPE)`. The Contract exists from the
successful completion of `cp.ir` until its matching `cp.or` or `ec.oe`.

`rs2` is an XLEN-wide value that is either an inline descriptor or a pointer
to a `CPE_Assignment_Params` struct:

**Inline form (bit [XLEN-1] = 0):**

| Bits | Field | Meaning |
|---|---|---|
| 7:0 | `l1_way_mask` | L1 cache way mask (1 bit per way; supports ≤8 ways inline) |
| 15:8 | `l2_way_mask` | L2-private way mask (1 bit per way; supports ≤8 ways inline) |
| 17:16 | `level_sel` | 0=L1+L2, 1=L1 only, 2=L2 only, 3=reserved |
| 18 | `couple` | 1 = enforce equal fraction across L1 and L2 |
| 19 | `lock_en` | 1 = lock minimum ways (prevent eviction, not just replacement) |
| [XLEN-2]:20 | — | Reserved; must be zero |
| [XLEN-1] | 0 | Indicates inline form |

Implementations with more than 8 ways per cache level must use the pointer
form for those levels.

**Pointer form (bit [XLEN-1] = 1):**

Bits [XLEN-2]:0 of `rs2` are a pointer to a `CPE_Assignment_Params` struct
(2-byte aligned; hardware clears bit [XLEN-1] before dereferencing):

```c
struct CPE_Assignment_Params {
    uint16_t l1i_way_mask;   /* L1I way mask */
    uint16_t l1d_way_mask;   /* L1D way mask */
    uint32_t l2_way_mask;    /* L2-private way mask (up to 32 ways) */
    uint8_t  level_sel;      /* 0=L1+L2, 1=L1 only, 2=L2 only */
    uint8_t  flags;          /* bit 0=couple, bit 1=lock_en */
    uint16_t reserved;       /* must be zero */
};
```

**Reserved-bit policy.** Reserved fields must be zero. Non-zero reserved
bits return `CPE_ERR_ILLEGAL_FIELD`.

---

## 7.5 Delegation Descriptor (`rs2` for `cp.it`)

`rs2` is an XLEN-wide value encoding the child ECID and the way counts
to delegate:

**Inline form (bit [XLEN-1] = 0):**

| Bits | Field | Meaning |
|---|---|---|
| 15:0 | `child_ecid` | Child ECID to receive the sub-partition |
| 19:16 | `l1_ways` | Number of L1 ways to delegate (0 = none) |
| 23:20 | `l2_ways` | Number of L2 ways to delegate (0 = none) |
| [XLEN-2]:24 | — | Reserved; must be zero |
| [XLEN-1] | 0 | Indicates inline form |

**Pointer form (bit [XLEN-1] = 1):**

Bits [XLEN-2]:0 are a pointer to a `CPE_Delegation_Params` struct:

```c
struct CPE_Delegation_Params {
    uint16_t child_ecid;
    uint16_t l1_ways;   /* L1 ways to delegate */
    uint16_t l2_ways;   /* L2 ways to delegate */
    uint16_t reserved;  /* must be zero */
};
```

---

## 7.6 Hardware Sanity Rules

The hardware enforces the following invariants on every `cp.ir` and `cp.it`
call. Violations return an error code; no state changes on failure.

1. **Way-mask disjointness.** The set of ways assigned to any two ECIDs at
   the same cache level must be disjoint.
2. **Coupling constraint.** If `couple=1`, the fraction of ways assigned in
   L1 and L2 must be equal (±1 way rounding). If the masks violate this,
   returns `CPE_ERR_COUPLE_MISMATCH`.
3. **Lock constraint.** `lock_en` may not be set if no ways are assigned.
4. **Writeback on reassignment.** Before completing an assignment that
   displaces ways previously held by a different ECID, the implementation
   must writeback and invalidate those ways.
5. **Invalidation on revoke.** `cp.or` and `cp.ot` must invalidate all
   lines in the revoked ways before returning.

---

## 7.7 CPE CSRs

| CSR | Access | Purpose |
|---|---|---|
| `cpe_caps` | RO | Capability bits: supported cache levels, max ways per level, delegation support |
| `cpe_status` | RO | Result code from the last CPE operation on this hart |
| `cpe_violation` | RO (sticky) | Set when an assigned partition boundary was crossed; cleared by writing 1 |
| `cpe_violation_en` | RW (privileged) | Enable interrupt on `cpe_violation` |

`cpe_caps` bit layout (informative; normative layout in a future encoding pass):

* Bits 3:0 — max L1 ways (log2; e.g., 4 = up to 16 L1 ways)
* Bits 7:4 — max L2 ways (log2)
* Bit 8 — L1I partitioning supported
* Bit 9 — L1D partitioning supported
* Bit 10 — L2-private partitioning supported
* Bit 11 — delegation (`cp.it`/`cp.ot`) supported

---

## 7.8 Error Codes

| Code | Name | Meaning |
|---|---|---|
| 0 | OK | Success |
| 1 | `CPE_ERR_INVALID_ECID` | ECID not allocated or generation mismatch |
| 2 | `CPE_ERR_OVERLAP` | Assigned ways overlap with another ECID's partition |
| 3 | `CPE_ERR_CAP_EXCEEDED` | Delegation exceeds parent Contract allocation |
| 4 | `CPE_ERR_COUPLE_MISMATCH` | Coupling constraint violated |
| 5 | `CPE_ERR_ILLEGAL_FIELD` | Reserved or out-of-range field value |
| 6 | `CPE_ERR_UNSUPPORTED` | Requested level or feature not implemented |
| 7 | `CPE_ERR_PERMISSION` | Caller is not a parent or privileged ancestor |

---

## 7.9 Interaction with CME

CPE partition assignments are part of an ECID's architectural state.

* CME stores the CPE state in the non-VMT bank's CP field (Chapter 0 §0.6).
  On `ec.ob`, the hardware restores the target ECID's CPE assignment
  automatically — no separate `cp.ir` is needed per context switch.
* On `ec.oe` (forced destroy), all CPE Contracts held by the target ECID
  and its subtree are revoked as part of the destroy sequence.
* After hart migration, the kernel must re-issue `cp.ir` on the destination
  hart; CPE state is per-hart and does not transfer automatically.

---

## 7.10 Instruction Timing Summary

| Instruction | Cycles | Notes |
|---|---|---|
| `cp.ir` | 1–8 | May extend for writeback of displaced lines |
| `cp.or` | 1–16 | Invalidation latency |
| `cp.it` | 1–8 | — |
| `cp.ot` | 1–16 | Invalidation + subtree depth |

---

## 7.11 Instruction Encoding

All CE Suite instructions share the same R-type format and custom-0 opcode
(`0001011`). See Chapter 3 §3.10.1–§3.10.2 for the bitfield diagram and the
funct3 extension-selector table.

**CPE uses funct3 = `001`.**

### 7.11.1 CPE instruction encoding (funct3 = `001`)

| funct7      | Mnemonic | rd field | rs1 field    | rs2 field               |
|-------------|----------|----------|--------------|-------------------------|
| `0000000`   | `cp.ir`  | result   | target ECID  | partition descriptor    |
| `0000001`   | `cp.or`  | result   | target ECID  | `00000`                 |
| `0000010`   | `cp.it`  | result   | parent ECID  | delegation descriptor   |
| `0000011`   | `cp.ot`  | result   | child ECID   | `00000`                 |

funct7 values `0000100`–`1111111` (4–127) are reserved for future CPE instructions.

`cp.or` and `cp.ot` carry no `rs2` operand; the rs2 field is encoded as `00000` (x0).

### 7.11.2 Encoding examples

`cp.ir a0, a1, a2` — assign partition (descriptor in a2) to ECID in a1, result in a0
(a0=x10=`01010`, a1=x11=`01011`, a2=x12=`01100`):

```
 31      25  24    20  19    15 14  12 11     7 6      0
┌─────────┬────────┬────────┬──────┬────────┬─────────┐
│ 0000000 │ 01100  │ 01011  │ 001  │ 01010  │ 0001011 │
└─────────┴────────┴────────┴──────┴────────┴─────────┘
  cp.ir      rs2=a2   rs1=a1   CPE    rd=a0   custom-0
```

`cp.or a0, a1` — revoke all partitions from ECID in a1, result in a0:

```
 31      25  24    20  19    15 14  12 11     7 6      0
┌─────────┬────────┬────────┬──────┬────────┬─────────┐
│ 0000001 │ 00000  │ 01011  │ 001  │ 01010  │ 0001011 │
└─────────┴────────┴────────┴──────┴────────┴─────────┘
  cp.or      rs2=x0   rs1=a1   CPE    rd=a0   custom-0
```

---

[Next: Chapter 8 — CPE Usage Examples](ch08-cpe-usage-examples.md)
