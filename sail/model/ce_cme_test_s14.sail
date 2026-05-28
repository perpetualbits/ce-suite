// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — bank exhaustion recovery test (S14)
 * Spec reference: ch03 §3.3 "Bank Exhaustion Recovery"
 *
 * Validates the normative recovery protocol (ch03 §3.3):
 *   1. ec.ig fails with CME_ERR_NO_BANK (pool exhausted)
 *   2. ec.im spills victim's bank state to RAM  (stub: no-op, CME_OK)
 *   3. ec.og releases the victim's bank slot
 *   4. ec.ig retry succeeds; slot is assigned to the requesting ECID
 *
 * Note: ec.im is a stub in Sail v1 (S15 not yet complete) — it returns
 * CME_OK without writing memory.  The test validates the protocol
 * structure: ec.og genuinely frees the slot, making the retry possible.
 */

$[test]
function test_bank_exhaustion_recovery() -> unit = {
  let ECID_E : ecid_t = 0x0005;  /* requesting ECID (needs a new bank) */
  let ECID_V : ecid_t = 0x0006;  /* victim ECID (has a bank to spill and free) */

  ce_ctrl      = CE_CTRL_CME_EN;
  current_ecid = ECID_E;

  ec_array[5] = { EC_entry_default with allocated = true };
  ec_array[6] = { EC_entry_default with allocated = true };

  /* Fill all 8 bank slots so ec.ig has nothing to allocate */
  bank_pool[0] = { Bank_default with owner_ecid = 0x0001, valid = true };
  bank_pool[1] = { Bank_default with owner_ecid = 0x0002, valid = true };
  bank_pool[2] = { Bank_default with owner_ecid = 0x0003, valid = true };
  bank_pool[3] = { Bank_default with owner_ecid = 0x0004, valid = true };
  bank_pool[4] = { Bank_default with owner_ecid = ECID_E, valid = true };
  bank_pool[5] = { Bank_default with owner_ecid = 0x0007, valid = true };
  bank_pool[6] = { Bank_default with owner_ecid = 0x0008, valid = true };
  bank_pool[7] = { Bank_default with owner_ecid = ECID_V, valid = true };

  /* x1 = ECID_E (target for ec.ig) */
  X(encdec_reg(0b00001)) = zero_extend(ECID_E);
  /* x2 = ECID_V (victim for ec.im / ec.og) */
  X(encdec_reg(0b00010)) = zero_extend(ECID_V);
  /* x3 = GPR mask */
  X(encdec_reg(0b00011)) = zero_extend(0x01 : bits(8));

  /* ---- Step 1: ec.ig x4, x1 — pool full, expect CME_ERR_NO_BANK ---- */
  let r1 = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r1 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_ERR_NO_BANK));

  /* ---- Step 2: ec.im x0, x2, x3 — spill victim to RAM (stub ok) ---- */
  let r2 = execute(CE_ECIM(encdec_reg(0b00000), encdec_reg(0b00010), encdec_reg(0b00011)));
  assert(r2 == RETIRE_SUCCESS);
  /* Bank 7 still valid after spill — ec.og releases it */
  assert(bank_pool[7].valid);

  /* ---- Step 3: ec.og x0, x2 — release victim's bank ---- */
  let r3 = execute(CE_ECOG(encdec_reg(0b00000), encdec_reg(0b00010)));
  assert(r3 == RETIRE_SUCCESS);
  assert(~(bank_pool[7].valid));  /* bank 7 now in free pool */

  /* ---- Step 4: ec.ig x4, x1 — retry; bank 7 is the only free slot ---- */
  let r4 = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r4 == RETIRE_SUCCESS);
  assert(bank_pool[7].valid);
  assert(bank_pool[7].owner_ecid == ECID_E);
  assert(X(encdec_reg(0b00100)) == zero_extend(0x07 : bits(8)))
}
