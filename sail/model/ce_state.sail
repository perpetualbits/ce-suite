// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — per-hart architectural state
 * Spec reference: ch00 §0.2–§0.3, ch13
 *
 * All CE state is per-hart. No CE register is shared across harts (ch13 §1).
 */

/* ------------------------------------------------------------------ */
/* Core CME state                                                      */
/* ------------------------------------------------------------------ */

/* ECID of the currently executing context (ch13 §3.1, 0xFC0) */
register current_ecid : ecid_t = 0x0000

/* Base address of the EC[e] array for this hart (ch13 §3.2, 0x7C0) */
register cme_ec_table_base : xlenbits = zeros()

/* Delegation depth cap D, RO (ch13 §3.3, 0xFC1).
 * Set by implementation; Sail v1 uses D=3 (the architectural maximum). */
let cme_del_cap_D : del_level_t = 0b11  /* D = 3 */

/* Bank count, RO (ch13 §3.4, 0xFC2).
 * Parameterised; set to a small default for modelling. */
let cme_bank_count_NV : bits(8) = 0x08  /* 8 non-VMT banks */
let cme_bank_count_VMT : bits(8) = 0x00  /* no VMT banks in v1 model */

/* CME status register (ch13 §3.6, 0xFC3) */
register cme_status : bits(9) = zeros()  /* [8]=VMT_RDY=1, [7:0]=CODE=0 */

/* Register mask from last ec.ib / ec.ob (ch13 §3.7, 0xFC4) */
register cme_reg_mask : regmask_t = zeros()

/* Vault encryption key, M-mode only (ch13 §3.9, 0x7C3) */
register cme_seal_key : xlenbits = zeros()

/* ------------------------------------------------------------------ */
/* EC array abstraction                                                */
/* ------------------------------------------------------------------ */

/* Sail v1 models the EC array as a fixed-size vector (64 slots).
 * A production model would parameterise this on ECID width (2^16).  */
let CE_MAX_ECIDS : nat = 64

register ec_array : vector(64, dec, EC_entry) =
  vector_init(EC_entry_default)

/* Dirty-group bitmap for the currently running ECID (ch00 §0.3) */
register dirty_bitmap : dirty_bitmap_t = 0x00

/* ------------------------------------------------------------------ */
/* Bank pool abstraction                                               */
/* ------------------------------------------------------------------ */

/* Bank pool: NV banks, indexed 0..cme_bank_count_NV-1 */
register bank_pool : vector(8, dec, Bank) = vector_init(Bank_default)

/* ------------------------------------------------------------------ */
/* MSE state                                                           */
/* ------------------------------------------------------------------ */

/* mse_slot_ratio: CN slot fraction (ch13 §5.1, 0x7C6); reset = 128 (50%) */
register mse_slot_ratio : bits(8) = 0x80

/* mse_bw_cap: pre-flattened bandwidth cap for current ECID (ch13 §5.4, 0x7C7) */
register mse_bw_cap : bits(8) = 0x00

/* mse_bw_sum: running sum of bw_class across active Contract holders (ch13 §5.5, 0xFC9) */
register mse_bw_sum : bits(8) = 0x00

/* mse_status: result code from last MSE op (ch13 §5.6, 0xFCA) */
register mse_status : bits(8) = 0x00

/* mse_violation: sticky CN slot guarantee missed (ch13 §5.7, 0x7C8); W1C */
register mse_violation : bits(1) = 0b0

/* mse_violation_en: interrupt enable for mse_violation (ch13 §5.8, 0x7C9) */
register mse_violation_en : bits(1) = 0b0

/* mse_slot_ns_val: impl-defined slot size; 100 ns default in Sail v1 (ch13 §5.2, bits 15:0) */
let mse_slot_ns_val : bits(16) = to_bits(16, 100)

/* mse_max_nesting: impl-defined K = 3 in Sail v1 (ch13 §5.3) */
let mse_max_nesting : bits(4) = 0x3

/* mse_caps_val: v0.21-compliant capability constant (ch13 §5.10, bits 23:0)
 * bits 7:4 = DITHER|OVERFLOW|TELESCOPING|RECONFIG_ATOMIC = 0xF
 * bits 3:0 = reserved = 0x0  → byte 0 = 0xF0
 * bits 11:8 = BW_BITS = 0x8; bits 15:12 = LAT_BITS = 0x8  → byte 1 = 0x88
 * bits 19:16 = MAX_NESTING = 0x3; bits 23:20 = MAX_PRECISION = 0x8  → byte 2 = 0x83
 * bits xlen-1:24 = 0 (zero_extend at read time) */
let mse_caps_val : bits(24) = 0x8388F0

/* MSE Contract pool: indexed by slot number, mirrors ec_array sizing */
register mse_contract_pool : vector(64, dec, MSE_Contract) =
  vector_init(MSE_Contract_default)

/* ------------------------------------------------------------------ */
/* Convenience accessors                                               */
/* ------------------------------------------------------------------ */

/* Find the MSE Contract owned by ECID e. Returns None() if no live Contract. */
function find_mse_contract(e : ecid_t) -> option(MSE_Contract) = {
  var result : option(MSE_Contract) = None();
  foreach (i from 0 to 63) {
    if mse_contract_pool[i].valid & (mse_contract_pool[i].owner_ecid == e)
    then result = Some(mse_contract_pool[i])
    else ()
  };
  result
}

/* True iff a live MSE Contract exists for ECID e. */
function mse_contract_active(e : ecid_t) -> bool = {
  match find_mse_contract(e) {
    Some(_) => true,
    None()  => false
  }
}

/* ------------------------------------------------------------------ */
/* Convenience accessors (CME)                                        */
/* ------------------------------------------------------------------ */

/* Look up EC[e]. Returns None() if e is out of range or unallocated slot index. */
function lookup_ec(e : ecid_t) -> option(EC_entry) = {
  var result : option(EC_entry) = None();
  foreach (i from 0 to 63) {
    if i == unsigned(e) then result = Some(ec_array[i])
    else ()
  };
  result
}

/* Check if an ECID slot is allocated with the expected generation. */
function ec_valid(e : ecid_t, gen : generation_t) -> bool = {
  match lookup_ec(e) {
    None()  => false,
    Some(entry) => entry.allocated & (entry.generation == gen)
  }
}

/* Find the bank owned by a given ECID. Returns None() if not banked. */
function find_bank(e : ecid_t) -> option(bank_slot_t) = {
  var result : option(bank_slot_t) = None();
  foreach (i from 0 to 7) {
    if bank_pool[i].valid & (bank_pool[i].owner_ecid == e)
    then result = Some(to_bits(8, i))
    else ()
  };
  result
}

/* Check whether anc is a proper ancestor of desc in the delegation tree.
 * Walks at most D+1=4 steps up from desc (ch00 §0.8, D ≤ 3). */
function is_ancestor(anc : ecid_t, desc : ecid_t) -> bool = {
  var found : bool   = false;
  var cur   : ecid_t = desc;
  foreach (step from 0 to 3) {
    if ~(found) then {
      match lookup_ec(cur) {
        None() => (),
        Some(entry) => {
          if entry.allocated then {
            cur = entry.parent_ecid;
            if cur == anc then found = true
          }
        }
      }
    }
  };
  found
}
