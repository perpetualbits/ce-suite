
---

# Chapter 4: Hardware Microarchitecture Overview

## Overview

This chapter describes the hardware that implements the Context Management Extension (CME). It covers:

- The context bank arrays (non-VMT and VMT) and their per-ECID ownership model.
- The `EC[e]` array: how hardware locates per-ECID metadata, and how implementations trade SRAM speed against RAM capacity.
- The S/R staging banks and copy engine that deliver 1–9 cycle context switches.
- Masked transfers, the VMT-ready flag, and the DMA slow path.
- The radix-tree lookup path: the relationship between the kernel's ECID allocator and the flat `EC[e]` array visible to hardware.

This chapter assumes the foundational definitions from Chapter 0 and the instruction semantics from Chapter 2. Three invariants govern all hardware decisions:

- Every bank belongs to exactly one ECID. The bank tag records the owning ECID number directly; GroupID = ECID (Chapter 0 §0.5).
- Ownership is verified at the resource via an up-pointer, not by walking a membership list. This is the O(1) enforcement property.
- Delegation depth is bounded by D ≤ 3; hardware rejects any attempt to exceed it.

---

## 1. Context Bank Types

Each hart contains a configurable number of context banks:

**Non-VMT (NV) banks** — hold GPRs, FPRs, PC, SATP, cache partition configuration, and selected CSRs.

- 1 KB on RV64; 512 B on RV32 (layout in Chapter 0 §0.6).
- Tagged with the owning ECID.

**Vector/Matrix/Tensor (VMT) banks** — hold vector, matrix, and tensor register files.

- Typical size: ~4 KB (1024-bit registers × 32 entries); scales with the implementation's vector width.
- Tagged with the owning ECID.
- Allocated and managed separately from NV banks.

---

## 2. EC[e] Array and SRAM Residency

The `EC[e]` array is the primary hardware-visible per-ECID data structure (Chapter 0 §0.3). Each entry holds:

```c
struct EC_entry {
    void     *ecs_ptr;      /* ECS pointer — always at offset 0            */
    uint8_t   generation;   /* incremented on every slot reuse             */
    uint8_t   delegation_L; /* delegation level, 0 ≤ L ≤ D                */
    uint16_t  parent_ecid;  /* ECID of the parent in the delegation tree   */
    /* implementation-defined: cached bank refs, flags, etc.               */
};
```

The `cme_ec_table_base` CSR and an implementation-defined `stride` give the lookup address for ECID `e`:

```text
entry_addr(e) = cme_ec_table_base + e × stride
ecs_ptr(e)    = *entry_addr(e)          // ecs_ptr is always at offset 0
```

### 2.1 SRAM vs RAM residency

The full `EC[e]` table is RAM-resident. Implementations keep a **hot set** of entries in on-chip SRAM — typically the entries for ECIDs currently runnable on that hart.

- **Fast path** (`ec.ib`, `ec.ob`): touches only SRAM-resident `EC[e]` entries and the bank arrays. No RAM access on the critical path.
- **DMA path** (`ec.im`, `ec.om`): may access the RAM-resident table to locate `ecs_ptr` and initiate the transfer.

A fast-path access to an entry not in the SRAM hot set must either stall until the entry is promoted, or be handled by a hardware prefetch mechanism. Implementations may expose the hot-set capacity as a read-only parameter CSR.

### 2.2 Generation checks

Before acting on any `EC[e]` entry, hardware compares the stored `generation` field against any software-held reference. A mismatch indicates the slot was freed and reallocated; the instruction must trap or return a documented failure code (Chapter 0 §0.9). Silent ignore is prohibited.

---

## 3. Bank Ownership and Security Checks

Hardware maintains a **bank tag** per bank:

- **Owning ECID** (= GroupID) — the 16-bit ECID number of the owning context (Chapter 0 §0.5, §0.6).
- **Delegation level** — cached from `EC[e].delegation_L` of the owning ECID; an implementation convenience.
- **Dirty bits** — one per register group, for masked transfers (§6).
- **Lock bit** — set when the bank is sealed; no access permitted until unsealed.

The parent relationship used for delegation checks is read from `EC[e].parent_ecid` of the owning ECID. No separate parent-mapping CAM is required; the `EC[e]` SRAM hot set supplies this field on the fast path.

On every `ec.ib` / `ec.ob` / `ec.im` / `ec.om`:

1. Hardware looks up `EC[e]` for the target ECID.
2. Hardware verifies that the calling ECID is the owner or holds delegated rights. Delegation is verified by following `parent_ecid` links upward — at most D steps, where D ≤ 3.
3. Hardware checks that neither the caller nor the target exceeds the delegation cap D.
4. If any check fails: the instruction traps with a CME access fault (Chapter 0 §0.9).

---

## 4. Staging Banks and Copy Engine

Direct per-bit N-way muxing from the live register file to any bank is area- and timing-prohibitive at scale. Each hart therefore uses two **staging banks**:

- **S** (save staging bank) — for Live → Bank transfers.
- **R** (restore staging bank) — for Bank → Live transfers.

### Path and timing

**Live ↔ S/R**: fixed 1:1 wiring from each live register bit to the corresponding bit in S or R; completes in 1 cycle.

**S/R ↔ Bank**: a wide internal bus with a one-hot bank-select decoder:

- Bus width: 4096 b (512 B) in the reference fast path.
- Decoder: 6-to-64 one-hot; only the selected bank's wordlines are asserted; all others idle.
- Write drivers or sense amplifiers operate only on the active bank.

---

## 5. Reference Profile: Option A (Fast Path)

**Lane count:** 16  
**Lane width:** 256 b (32 B)  
**Effective width per beat:** 4096 b (512 B)

| Bank type | Size (bits) | Beats | Save cycles   | Restore cycles |
|-----------|-------------|-------|---------------|----------------|
| NV        | 8 192       | 2     | 1 + 2 = **3** | 2 + 1 = **3**  |
| VMT       | 32 768      | 8     | 1 + 8 = **9** | 8 + 1 = **9**  |

The "+1" on each end is the Live ↔ S/R wiring cycle.

---

## 6. Masked Transfers

Each bank stores dirty/used bits per register group. On save or restore, only register groups with dirty = 1 are transferred. This saves cycles and power proportionally to the number of inactive groups.

Example: GPR + PC only (~272 B in Option A) → 2 beats → save/restore = **3 cycles**.

---

## 7. VMT-Ready Flag

VMT banks are larger than NV banks; restoring them in full before resuming execution would penalize scalar-only code. Hardware supports early scalar resume:

On `ec.ob` with VMT state:
1. Bank → R begins immediately for scalar and FPR groups.
2. R → Live completes in 1 cycle; the hart resumes scalar/FPR execution.
3. The VMT copy continues in the background into the VMT registers.
4. The first vector, matrix, or tensor instruction checks the **VMT-ready CSR bit**:
   - 0: the hart stalls until the VMT restore completes.
   - 1: the instruction proceeds.

---

## 8. Bank Allocation Engine

Per hart:

- Separate free lists for NV banks and VMT banks.
- On allocation, the requesting ECID is recorded in the bank tag as the owning ECID (= GroupID).
- On allocation failure, the instruction returns a documented failure code; no silent failure.

---

## 9. Radix-Tree Lookup Path

The kernel maintains a **radix tree** keyed on ECID numbers to track allocation, ownership, and per-prefix quotas (Chapter 0 §0.2). Hardware does not traverse this tree. From the hardware perspective, ECID `e` is simply an index into the flat `EC[e]` array.

The two layers interact as follows:

- **Kernel** allocates ECID `e` by inserting it into the radix tree and populating `EC[e]` via privileged writes to the EC table.
- **Hardware** looks up `EC[e]` directly via `cme_ec_table_base + e × stride`. No tree traversal occurs in hardware.
- **Forced destruction** (`ec.od`): hardware clears the `EC[e]` entries for the target ECID and all descendants, increments their generation counters, frees their banks, and revokes their Contracts. The kernel is then responsible for updating the radix tree to reflect the freed slots. Hardware guarantees that the `EC[e]` entries are invalidated and cannot be reached via stale references.

This separation is intentional. The radix tree is a kernel policy structure — it enforces quotas, tracks ownership lineage, and supports fast subtree revocation. The `EC[e]` array is the architectural interface — indexed directly by ECID number, fast enough for the hardware fast path.

---

## 10. DMA Spill/Fill (Slow Path)

When no bank is available for the requested ECID:

- **Spill** (`ec.im`): saves staging bank S to RAM via DMA. The target ECS is located via `EC[e].ecs_ptr`. The bank is freed for reuse once the DMA completes.
- **Fill** (`ec.om`): restores from the ECS in RAM (located via `EC[e].ecs_ptr`) into staging bank R via DMA, then R → live registers.

Banks remain locked (unavailable for reuse) until the DMA transfer completes. Ownership checks (§3) apply before DMA begins.

---

## 11. Secure Vault Engine (Optional)

- **Seal** (`ec.iv`): encrypts a bank's contents and sets the lock bit. No access is permitted until the bank is unsealed.
- **Unseal** (`ec.ov`): decrypts the bank for the authorized ECID and clears the lock bit.

Key derivation, attestation, and rotation are charter open items (charter §8.7) and are not specified here.

---

## 12. Fast Context Switching Summary

| Scenario                   | Save         | Restore                          |
|----------------------------|--------------|----------------------------------|
| NV, full (Option A)        | 3 cycles     | 3 cycles                         |
| VMT, full (Option A)       | 9 cycles     | 9 cycles                         |
| Masked (partial registers) | proportional | proportional                     |
| VMT-ready: scalar resume   | —            | 3 cycles (VMT continues in background) |

---

## Placeholder: Diagram — CME Microarchitecture

Show:

- Live register file
- S staging bank and R staging bank
- Wide bus to bank-select decoder (one-hot, 6→64)
- NV and VMT bank arrays with bank tags (owning ECID, dirty bits, lock bit)
- EC[e] SRAM hot set and RAM-resident table, with `cme_ec_table_base` pointer
- DMA engine path: S/R staging ↔ ECS in RAM via `EC[e].ecs_ptr`
- VMT-ready CSR flag
- Secure Vault engine (optional, labeled)

---
