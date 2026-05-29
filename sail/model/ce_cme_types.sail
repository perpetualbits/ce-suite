// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — CME architectural types
 * Spec reference: ch00 §0.3 (EC_entry), ch00 §0.6 (Bank), ch00 §0.8 (delegation)
 */

/* ------------------------------------------------------------------ */
/* EC[e] entry (ch00 §0.3)                                            */
/* ecs_ptr is architecturally at offset 0; Sail models it directly.   */
/* ------------------------------------------------------------------ */

struct EC_entry = {
  ecs_ptr      : physaddrbits,  /* ECS pointer — always at offset 0 */
  generation   : generation_t,  /* incremented on every slot reuse (ABA safety) */
  delegation_L : del_level_t,   /* delegation level, 0 ≤ L ≤ D */
  parent_ecid  : ecid_t,        /* parent in the delegation tree; 0 for root */
  allocated    : bool           /* true iff this slot holds a live ECID */
}

let EC_entry_default : EC_entry = struct {
  ecs_ptr      = zeros(),
  generation   = 0x00,
  delegation_L = 0b00,
  parent_ecid  = 0x0000,
  allocated    = false
}

/* ------------------------------------------------------------------ */
/* Bank abstraction (ch00 §0.6)                                       */
/*                                                                     */
/* Hardware banks are SRAM; Sail models them as abstract saved state.  */
/* The physical size (1 KB / 512 B) and staging mechanism are         */
/* microarchitectural and outside Sail v1 scope.                      */
/* ------------------------------------------------------------------ */

/* A bank holds the saved register state for one Group, plus sealed flag. */
struct Bank = {
  owner_ecid : ecid_t,    /* GroupID = owning ECID number (ch00 §0.5) */
  valid      : bool,      /* true iff this bank slot is in use */
  sealed     : bool,      /* true iff bank is encrypted (ec.iv) */
  /* Saved register state — abstracted as bitvectors per group.
   * Real widths are XLEN-dependent; modelled at 64 bits for RV64. */
  gprs     : vector(31, dec, bits(64)),  /* x1..x31 (x0 slot holds Group ID) */
  fprs     : vector(32, dec, bits(64)),  /* f0..f31 */
  pc       : bits(64),
  satp_val : xlenbits,  /* SATP register state (mask bit 6) */
  /* CSR state (bit 5) omitted in Sail v1 */
  mask     : regmask_t  /* which groups were saved */
}

/* ------------------------------------------------------------------ */
/* Dirty-group bitmap (ch00 §0.3, ch03 §3.1 dirty-save mode)         */
/* One bit per register group; positions match the register mask.     */
/* ------------------------------------------------------------------ */

let Bank_default : Bank = struct {
  owner_ecid = 0x0000,
  valid      = false,
  sealed     = false,
  gprs       = vector_init(zeros()),
  fprs       = vector_init(zeros()),
  pc         = zeros(),
  satp_val   = zeros(),
  mask       = zeros()
}

type dirty_bitmap_t = bits(8)  /* bits 0–6 used; bit 7 reserved */

let DIRTY_GPR  : dirty_bitmap_t = 0x01
let DIRTY_FPR  : dirty_bitmap_t = 0x02
let DIRTY_VEC  : dirty_bitmap_t = 0x04
let DIRTY_MAT  : dirty_bitmap_t = 0x08
let DIRTY_PC   : dirty_bitmap_t = 0x10
let DIRTY_CSR  : dirty_bitmap_t = 0x20
let DIRTY_SATP : dirty_bitmap_t = 0x40
