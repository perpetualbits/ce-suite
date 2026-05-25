# Chapter 7: CPE Instruction Set Reference (Per-Hart Cache Partitioning)

## 1. Overview

The **Cache Partitioning Extension (CPE)** provides hardware mechanisms for isolating and reserving portions of **per-hart private caches** (L1I, L1D, and L2-private) for specific Execution Contexts (ECIDs). This ensures that a hard real-time EC can operate without cache line evictions caused by other ECs scheduled on the same hart.

CPE v1 is **per-hart only** and does **not** manage shared caches (e.g., L3). L3 cache partitioning may be handled by platform-specific mechanisms or a future CPE-S extension.

Key design points:

* Focus on **isolation and determinism** for hard real-time contexts.
* Supports **coupled** or **independent** allocation of L1 and L2-private.
* Allows **inline descriptors** for common operations and **pointer-based descriptors** for complex configurations.
* Sanity rules enforced in hardware to prevent unsafe or conflicting assignments.

---

## 2. Instruction Naming Convention

All CPE instructions follow the CE suite pattern:

```text
cp.ir   // cache partition: assign (in) resource
cp.or   // cache partition: revoke (out) resource
```

`cp` = CPE extension; `i`/`o` = direction (in/out); `r` = resource/region (per charter §6.1).
CPE uses the subset `{r}` from the target-letter table.

---

## 3. Operand Overview

### rs1: Target ECID + Control Fields

```
[63:48] ECID              ; 16 bits (hart-local ECID)
[47:46] LEVEL_SEL         ; 0=Auto (L1+L2 together), 1=L1 only, 2=L2-private only, 3=Reserved
[45]    COUPLE_L1L2       ; 1=Enforce equal ratio between L1 & L2
[44]    MODE              ; 0=WAY_MASK, 1=PERCENT (both map to ways internally)
[43]    INLINE            ; 1=rs2 is inline descriptor, 0=rs2 is pointer to CPD
[42]    LOCK_EN           ; 1=Lock minimum ways to prevent replacement
[41]    INSTR_DATA_SEL    ; 0=Both L1I+L1D, 1=Data-only
[40]    PREFETCH_CLASS    ; 0=Default, 1=Low, 2=Med, 3=High (hint)
[39:32] WEIGHT            ; QoS weight for fills (hint)
[31:24] OPC               ; 0=ASSIGN, 1=MODIFY, 2=REVOKE, 3=QUERY
[23:16] VERSION           ; Encoding version (start=1)
[15:0]  RESERVED
```

### rs2: Partition Descriptor

* If **INLINE=1**, rs2 contains mask/percent values directly.
* If **INLINE=0**, rs2 contains a pointer to a **Cache Partition Descriptor (CPD)** in memory.

#### 3.1 INLINE + MODE=WAY\_MASK

```
[63:48] L2_WAY_MASK_HI
[47:32] L2_WAY_MASK_LO
[31:16] L1D_WAY_MASK
[15:0]  L1I_WAY_MASK
```

Validity: If COUPLE\_L1L2=1, ratio of set bits in L1 and L2 masks must match.

#### 3.2 INLINE + MODE=PERCENT

```
[63:56] PCT_256_L2   ; percent * 256 (e.g., 128=50%)
[55:48] PCT_256_L1D
[47:40] PCT_256_L1I
[39:24] LOCK_MIN_WAYS
[23:0]  RESERVED
```

Validity: If COUPLE\_L1L2=1, L1D and L2 percentages must be equal.

#### 3.3 CPD in Memory (INLINE=0)

```c
struct CPE_CPD_v1 {
    u16 version;     // must match rs1.VERSION
    u8  level_sel;   // LEVEL_SEL
    u8  flags;       // COUPLE_L1L2, LOCK_EN, INSTR_DATA_SEL, PREFETCH_CLASS
    u8  mode;        // WAY_MASK or PERCENT
    u8  reserved[3];
    union {
        struct { u64 l2_mask; u32 l1d_mask; u32 l1i_mask; u16 lock_min; } way;
        struct { u8 pct256_l2, pct256_l1d, pct256_l1i; u16 lock_min; } percent;
    } cfg;
};
```

---

## 4. Sanity Rules (Hardware-Enforced)

1. Masks for different ECIDs at the same level must be disjoint.
2. If COUPLE\_L1L2=1, allocated fraction must match across L1 and L2.
3. LOCK\_EN cannot lock more ways than assigned.
4. ASSIGN may require writeback+invalidate of prior occupant’s lines before completion.
5. REVOKE must invalidate all assigned lines for that ECID.

---

## 5. Example Usage

### Example 1: Assign 4 ways to ECID 0x1234, coupled L1/L2

```
rs1 = {ECID=0x1234, LEVEL_SEL=Auto, COUPLE=1, MODE=WAY_MASK, INLINE=1, LOCK_EN=0, OPC=ASSIGN}
rs2 = {L2 mask=0x000F, L1D mask=0x0F, L1I mask=0x00}
cp.ir rs1, rs2
```

### Example 2: Reserve 50% of L1D and L2 for ECID 0x1234

```
rs1 = {ECID=0x1234, LEVEL_SEL=Auto, COUPLE=1, MODE=PERCENT, INLINE=1, OPC=ASSIGN}
rs2 = {PCT_256_L2=128, PCT_256_L1D=128, PCT_256_L1I=0}
cp.ir rs1, rs2
```

### Example 3: Revoke ECID’s Partition

```
rs1 = {ECID=0x1234, LEVEL_SEL=Auto, OPC=REVOKE}
cp.or rs1, x0
```

---

## 6. Status Reporting

CPE operations return status via `rd` or a dedicated CSR:

* `OK`
* `UNSUPPORTED_LEVEL`
* `INVALID_MASK`
* `COUPLE_MISMATCH`
* `INSUFFICIENT_WAYS`
* `PERMISSION_DENIED`
* `BUSY_TRY_AGAIN`

---

## 7. Interaction with CME and OS

* Partition assignments are **per-hart** and bound to ECID.
* CME restores CP state from bank when context is resumed.
* OS must reapply CPE settings on context migration between harts.

---

## 8. Out-of-Scope for v1

* Shared L3 cache partitioning.
* Dynamic repartitioning during a running timeslice without OS cooperation.

---

**Next:** Chapter 8 – MSE (Memory Scheduling Extension)

