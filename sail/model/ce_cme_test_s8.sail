// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — dirty-save mode validation test (S8)
 * Spec reference: ch03 §3.1 "Dirty-Save Mode", ch00 §0.3
 *
 * Verifies the critical distinction from the spec (ch03 §3.1):
 *
 *   "The dirty-save trigger is the register-field encoding 00000 (x0),
 *    not the value zero.  An instruction ec.ib rd, a0 where a0 = 0 uses
 *    explicit-mask mode with an all-zeros mask (save nothing) — it does
 *    not activate dirty-save mode."
 *
 * Two scenarios:
 *   1. rs1 = x0 (encoding 00000) → dirty-save mode:
 *        effective mask = dirty_bitmap; dirty bits cleared after save.
 *   2. rs1 = a1 where X(a1) = 0 → explicit-mask mode:
 *        effective mask = 0; nothing saved; dirty_bitmap unchanged.
 */

$[test]
function test_dirty_save_mode() -> unit = {
  /* ---- Shared setup ---- */
  let ECID_C   : ecid_t  = 0x0003;
  let SENTINEL : bits(64) = 0xCCCC000000000003;

  ce_ctrl = CE_CTRL_CME_EN;
  ec_array[3] = { EC_entry_default with allocated = true };
  current_ecid = ECID_C;

  /* Set x3 to a known sentinel (will be saved when GPR group is dirty) */
  X(encdec_reg(0b00011)) = truncate(SENTINEL, xlen);

  /* ------------------------------------------------------------------ */
  /* Scenario 1: ec.ib x0, x0 — dirty-save mode                        */
  /* dirty_bitmap = 0x01 (GPR dirty); rs1 = x0 → use dirty_bitmap      */
  /* ------------------------------------------------------------------ */
  dirty_bitmap = 0x01;
  bank_pool[2] = { Bank_default with owner_ecid = ECID_C, valid = true };

  let r1 = execute(CE_ECIB(encdec_reg(0b00000), encdec_reg(0b00000)));
  assert(r1 == RETIRE_SUCCESS);

  /* Effective mask was dirty_bitmap (0x01 = GPR group) */
  assert(bank_pool[2].mask == zero_extend(0x01 : bits(8)));
  /* GPR group was in dirty set — sentinel saved in gprs[2] (x3) */
  assert(bank_pool[2].gprs[2] == zero_extend(truncate(SENTINEL, xlen)));
  /* Dirty bits for saved groups are cleared on commit */
  assert(dirty_bitmap == 0x00);

  /* ------------------------------------------------------------------ */
  /* Scenario 2: ec.ib x0, a1 where X(a1) = 0 — explicit-mask mode    */
  /* rs1 = a1 (encoding 01011 ≠ 00000) → explicit mask = X(a1) = 0    */
  /* ------------------------------------------------------------------ */
  dirty_bitmap = 0x01;  /* GPR still dirty — should be unchanged after */
  bank_pool[2] = { Bank_default with owner_ecid = ECID_C, valid = true };

  /* Set a1 (x11) to zero — this is an explicit mask of 0, not x0 */
  X(encdec_reg(0b01011)) = zeros();

  let r2 = execute(CE_ECIB(encdec_reg(0b00000), encdec_reg(0b01011)));
  assert(r2 == RETIRE_SUCCESS);

  /* Explicit-mask mode with mask=0: no groups saved */
  assert(bank_pool[2].mask == zeros());
  /* dirty_bitmap unchanged — no groups were saved, so no bits cleared */
  assert(dirty_bitmap == 0x01)
}
