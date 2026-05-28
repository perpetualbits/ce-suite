// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — ec.it (bank delegation) test (S18)
 * Spec reference: ch03 §3.4 (ec.it)
 *
 * Three scenarios:
 *   1. Valid delegation: parent owns a bank, child is a direct descendant →
 *      CME_OK, bank ownership transferred from parent to child.
 *   2. No bank: parent has no bank remaining after first delegation →
 *      CME_ERR_NO_BANK.
 *   3. Privilege violation: target is not a descendant of the source →
 *      CME_ERR_PERMISSION, no transfer.
 */

$[test]
function test_ec_it() -> unit = {
  let ECID_P : ecid_t = 0x0001;  /* parent, delegation level 1 */
  let ECID_C : ecid_t = 0x0002;  /* child of P, delegation level 2 */
  let ECID_X : ecid_t = 0x0003;  /* unrelated ECID (not in P's subtree) */

  ce_ctrl      = CE_CTRL_CME_EN;
  current_ecid = ECID_P;

  ec_array[1] = { EC_entry_default with
    allocated    = true,
    delegation_L = 0b01,
    parent_ecid  = 0x0000
  };
  ec_array[2] = { EC_entry_default with
    allocated    = true,
    delegation_L = 0b10,
    parent_ecid  = ECID_P
  };
  ec_array[3] = { EC_entry_default with
    allocated    = true,
    delegation_L = 0b01,
    parent_ecid  = 0x0000
  };

  /* ECID_P owns bank slot 0; all other slots free */
  bank_pool[0] = { Bank_default with owner_ecid = ECID_P, valid = true };

  /* x1 = ECID_P, x2 = ECID_C, x3 = ECID_X */
  X(encdec_reg(0b00001)) = zero_extend(ECID_P);
  X(encdec_reg(0b00010)) = zero_extend(ECID_C);
  X(encdec_reg(0b00011)) = zero_extend(ECID_X);

  /* ---- Scenario 1: valid delegation P → C ---- */
  let r1 = execute(CE_ECIT(encdec_reg(0b00100), encdec_reg(0b00001), encdec_reg(0b00010)));
  assert(r1 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_OK));
  assert(bank_pool[0].owner_ecid == ECID_C);  /* ownership transferred */
  assert(bank_pool[0].valid);                  /* bank remains valid */

  /* ---- Scenario 2: P now has no bank → CME_ERR_NO_BANK ---- */
  let r2 = execute(CE_ECIT(encdec_reg(0b00100), encdec_reg(0b00001), encdec_reg(0b00010)));
  assert(r2 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_ERR_NO_BANK));

  /* ---- Scenario 3: X is not in P's subtree → CME_ERR_PERMISSION ---- */
  /* Give P a new bank for this scenario */
  bank_pool[1] = { Bank_default with owner_ecid = ECID_P, valid = true };
  let r3 = execute(CE_ECIT(encdec_reg(0b00100), encdec_reg(0b00001), encdec_reg(0b00011)));
  assert(r3 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_ERR_PERMISSION));
  assert(bank_pool[1].owner_ecid == ECID_P)  /* no transfer: bank stays with P */
}
