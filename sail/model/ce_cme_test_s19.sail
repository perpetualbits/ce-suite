// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — ec.ot (resource revocation) test (S19)
 * Spec reference: ch03 §3.4 (ec.ot)
 *
 * Two scenarios:
 *   1. Valid revocation: child owns a bank → bank transferred to parent;
 *      child ECID stays allocated; CME_OK.
 *   2. Invalid ECID: unallocated slot → CME_ERR_INVALID_ECID.
 */

$[test]
function test_ec_ot() -> unit = {
  let ECID_P : ecid_t = 0x0001;  /* parent, delegation level 1 */
  let ECID_C : ecid_t = 0x0002;  /* child of P, delegation level 2 */

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

  /* ECID_C owns bank slot 0; ECID_P owns bank slot 1 */
  bank_pool[0] = { Bank_default with owner_ecid = ECID_C, valid = true };
  bank_pool[1] = { Bank_default with owner_ecid = ECID_P, valid = true };

  /* x1 = ECID_C */
  X(encdec_reg(0b00001)) = zero_extend(ECID_C);

  /* ---- Scenario 1: valid revocation C → P ---- */
  let r1 = execute(CE_ECOT(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r1 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_OK));
  /* Bank 0 transferred from C to P */
  assert(bank_pool[0].owner_ecid == ECID_P);
  assert(bank_pool[0].valid);
  /* Bank 1 (P's own) untouched */
  assert(bank_pool[1].owner_ecid == ECID_P);
  /* C stays allocated */
  assert(ec_array[2].allocated);

  /* ---- Scenario 2: invalid (unallocated) ECID ---- */
  X(encdec_reg(0b00001)) = zero_extend(0x003F : ecid_t);
  let r2 = execute(CE_ECOT(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r2 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_ERR_INVALID_ECID))
}
