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

