
---

# Chapter 4: Hardware Microarchitecture Overview

## Overview

This chapter describes the internal microarchitecture for the Context Management Extension (CME), expressed in terms consistent with Chapter 0’s foundational definitions. All design elements below operate under the ECID, group, and delegation rules specified in Chapter 0:

* **Every bank belongs to exactly one group.**
* **Every group is bound to exactly one ECID by that ECID’s parent** — the parent ECID prepares a child ECID by binding it to a group, assigning resources, setting delegation rights if needed and allowed, etc.
* **Only the parent ECID** of a group may perform `ec.ob` / `ec.om` to load a context from that group.
* **Delegation levels** are enforced in hardware; delegation beyond the maximum allowed level is rejected.

This chapter assumes the `ECID` model described in Chapter 1 and the CME instruction set in Chapter 2.

---

## 1. Context Bank Types

Each hart contains a configurable number of context banks, divided into:

* **Non-Vector (NV) banks** – Hold scalar integer, floating point, PC, SATP, and CSR state.

  * Typical size: \~1 KiB
  * Always bound to a group and therefore to an ECID.
* **Vector/Matrix/Tensor (VMT) banks** – Hold RVV or other wide register state.

  * Typical size: \~4 KiB (based on 1024-bit registers × 32 registers)
  * Always bound to a group and therefore to an ECID.

---

## 2. Bank Ownership and Security Checks

Hardware maintains for each bank:

* **Bank tag** – Contains:

  * Group ID (GID)
  * ECID bound to the group (set by parent ECID)
  * Delegation level
  * Dirty bit(s) per register group (for partial save/restore)
  * Lock bit (for sealed banks)
* **Group parent map** – CAM or small table mapping each group to its parent group.
* **ECID–Group binding** – Ensures that only the correct ECID, or an ECID with valid delegated rights, may access the bank.

On every `ec.ib` / `ec.ob` / `ec.im` / `ec.om`:

1. **Hardware checks** that the executing hart’s current ECID has visibility of the target group.
2. **If delegation is involved**, hardware verifies that the delegation level does not exceed the maximum allowed and that the target ECID is a descendant of the calling ECID’s group.
3. **If check fails**, instruction traps with a CME access fault.

---

## 3. Staging Banks and Copy Engine

To avoid the area/timing cost of direct per-bit 64-way muxing, each hart uses two **staging banks**:

* **S** (Save staging bank) – for Live → Bank transfers
* **R** (Restore staging bank) – for Bank → Live transfers

### Path and Timing

* **Live ↔ S/R**: Fixed 1:1 wiring from each live register bit to its matching bit in S or R; 1 cycle.
* **S/R ↔ Bank**: Transfers via a **wide internal bus** and a **one-hot bank-select decoder**:

  * Bus width: 4096 b (512 B) in the reference fast path
  * Bank decoder: 6→64 one-hot output (only one bank active per transfer)
  * Wordlines in the selected bank are asserted; all others idle.
  * Write drivers or sense amps operate only on the active bank.

---

## 4. Reference Profile: Option A (Fast Path)

**Lane count:** 16
**Lane width:** 256 b (32 B)
**Effective width:** 4096 b (512 B) per beat

Cycle counts (no turnaround bubble):

| Bank Type | Size (bits) | Beats | Save Cycles   | Restore Cycles |
| --------- | ----------- | ----- | ------------- | -------------- |
| NV        | 8192        | 2     | 1 + 2 = **3** | 2 + 1 = **3**  |
| VMT       | 32768       | 8     | 1 + 8 = **9** | 8 + 1 = **9**  |

---

## 5. Masked Transfers

Each bank stores dirty/used bits per register group. On save or restore:

* **Only groups with dirty = 1** are transferred.
* Saves cycles and power.
* For example, GPR+PC only (\~272 B) in Option A:

  * Beats = 2 → Save/Restore = **3 cycles**.

---

## 6. VMT-Ready Flag

Because VMT banks are larger, hardware can allow scalar/FPR execution to resume before VMT state is fully restored:

* On `ec.ob` with VMT state:

  1. Bank→R begins immediately for scalar/FPR groups.
  2. R→Live completes in 1 cycle; hart resumes scalar/FPR execution.
  3. VMT copy continues in background into VMT registers.
  4. First vector/matrix/tensor instruction checks **VMT-ready CSR bit**:

     * If 0, hart stalls until restore completes.
     * If 1, proceed with vector execution.

This mechanism avoids delaying scalar work when vectors aren’t immediately needed.

---

## 7. Bank Allocation Engine

Per hart:

* **Free list** for NV banks and VMT banks, restricted to the ECID’s visible groups.
* Allocates in response to CME instructions, enforcing group/ECID rules.
* Returns `0` or traps on allocation failure.

---

## 8. Group Tracking Logic

* **cme\_group\_map**: hardware-only CAM mapping visible groups.
* **cme\_group\_parent**: parent relationship for delegation checks.
* **cme\_bank\_tags**: group binding, ECID binding, dirty/lock flags.

All updates are atomic and visible only to hardware and privileged code.

---

## 9. DMA Spill/Fill (Slow Path)

When no bank is available:

* **Spill**: `ec.im` saves S to RAM via DMA; tagged bank freed for reuse.
* **Fill**: `ec.om` restores from RAM into R, then into Live registers.
* Banks remain locked until DMA completion.
* ECID/group checks apply before DMA starts.

---

## 10. Secure Vault Engine (Optional)

* Seal/unseal banks with `ec.iv`/`ec.ov`.
* Encrypted contents stored in banks or RAM.
* Lock bit prevents any access until unsealed by authorized ECID.

---

## 11. Fast Context Switching Summary

**NV (Option A)**: 3 cycles save, 3 cycles restore
**VMT (Option A)**: 9 cycles save, 9 cycles restore (proportional to size)
**Masked**: proportional speed-up depending on active register groups
**VMT-ready**: allows scalar resume before vector restore finishes

---

## Placeholder: Diagram – CME Microarchitecture

*Description*: Show:

* Live register file
* S/R staging banks
* Wide bus to bank-select decoder
* NV and VMT banks (with one-hot enables)
* Group/ECID binding tables
* DMA and Secure Vault engines
* VMT-ready CSR flag

---


