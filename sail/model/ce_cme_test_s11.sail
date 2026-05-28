// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — generation counter validation test (S11)
 * Spec reference: ch00 §0.2 (generation counters), ch03 §3.1 (ec.ob)
 *
 * Validates the ABA-safety mechanism: a software reference (ECID, generation)
 * is stale when EC[e].generation no longer matches the expected value.
 *
 * rs1 encoding for ec.ob (ch00 §0.2, Sail v1 convention):
 *   bits 15:0  = ECID slot index
 *   bits 23:16 = expected generation
 *
 * Two scenarios:
 *   1. Wrong generation (6) for a slot at generation 7 → CME_ERR_INVALID_ECID
 *   2. Correct generation (7) → RETIRE_SUCCESS, rd = CME_OK
 */

$[test]
function test_generation_check() -> unit = {
  let ECID_D : ecid_t = 0x0004;

  ce_ctrl      = CE_CTRL_CME_EN;
  current_ecid = 0x0001;  /* caller; not the target */

  /* Set up ECID 4 with a known generation = 7, allocated */
  ec_array[4] = { EC_entry_default with
    generation = 0x07,
    allocated  = true
  };

  /* Assign bank 3 to ECID_D (the bank ec.ob would restore) */
  bank_pool[3] = { Bank_default with owner_ecid = ECID_D, valid = true };

  /* x1 = GPR mask (bit 0 set) */
  X(encdec_reg(0b00001)) = zero_extend(0x01 : bits(8));

  /* ---- Scenario 1: stale reference (generation = 6, wrong) ---- */
  /* X(x2) = (gen=6 << 16) | ecid=4  =  0x0006_0004 */
  X(encdec_reg(0b00010)) = zero_extend(0x00060004 : bits(32));

  /* ec.ob x4, x2, x1 — rd written to x4 */
  let r1 = execute(CE_ECOB(encdec_reg(0b00100), encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r1 == RETIRE_SUCCESS);
  /* Stale generation → INVALID_ECID; bank and ec_array unchanged */
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_ERR_INVALID_ECID));
  assert(bank_pool[3].valid);  /* bank untouched by the failed lookup */

  /* ---- Scenario 2: valid reference (generation = 7, correct) ---- */
  /* X(x2) = (gen=7 << 16) | ecid=4  =  0x0007_0004 */
  X(encdec_reg(0b00010)) = zero_extend(0x00070004 : bits(32));

  let r2 = execute(CE_ECOB(encdec_reg(0b00100), encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r2 == RETIRE_SUCCESS);
  /* Correct generation → success; rd = CME_OK = 0 */
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_OK));
  /* current_ecid updated to the restored context */
  assert(current_ecid == ECID_D)
}
