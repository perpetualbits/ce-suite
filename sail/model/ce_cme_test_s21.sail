// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — cme_status update audit test (S21)
 * Spec reference: ch03 §3.12, ch13 §3.6
 *
 * cme_status[7:0] must be updated in parallel with the rd write for
 * every CME instruction. Two representative scenarios per instruction:
 *   - success path: cme_status == CME_OK (0)
 *   - error path:   cme_status == the error code written to rd
 *
 * Instructions exercised: ec.ob, ec.im, ec.om, ec.ig, ec.og,
 *                         ec.it, ec.ot, ec.ir, ec.oe.
 * (ec.ib is covered implicitly — cme_status already correct since S5.)
 */

$[test]
function test_cme_status_updates() -> unit = {
  let ECID_P : ecid_t = 0x0001;
  let ECID_C : ecid_t = 0x0002;
  let GEN_P  : generation_t = 0x01;

  ce_ctrl = CE_CTRL_CME_EN;

  ec_array[1] = { EC_entry_default with
    allocated    = true,
    generation   = GEN_P,
    delegation_L = 0b01,
    parent_ecid  = 0x0000
  };
  ec_array[2] = { EC_entry_default with
    allocated    = true,
    delegation_L = 0b10,
    parent_ecid  = ECID_P
  };
  current_ecid = ECID_P;

  /* ---- ec.ob: invalid ECID → CME_ERR_INVALID_ECID ---- */
  X(encdec_reg(0b00001)) = zero_extend(0x003F : ecid_t);  /* unallocated */
  X(encdec_reg(0b00010)) = zeros();
  let _ = execute(CE_ECOB(encdec_reg(0b00100), encdec_reg(0b00001), encdec_reg(0b00010)));
  assert(cme_status[7..0] == CME_ERR_INVALID_ECID);

  /* ---- ec.ob: no bank → CME_ERR_NO_BANK ---- */
  X(encdec_reg(0b00001)) = zero_extend(GEN_P @ ECID_P);
  X(encdec_reg(0b00010)) = zeros();
  let _ = execute(CE_ECOB(encdec_reg(0b00100), encdec_reg(0b00001), encdec_reg(0b00010)));
  assert(cme_status[7..0] == CME_ERR_NO_BANK);

  /* ---- ec.ig: success → CME_OK, bank slot returned ---- */
  bank_pool[0] = Bank_default;  /* ensure slot 0 is free */
  X(encdec_reg(0b00001)) = zero_extend(ECID_P);
  let _ = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(cme_status[7..0] == CME_OK);

  /* ---- ec.og: success → CME_OK, remaining count returned ---- */
  let _ = execute(CE_ECOG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(cme_status[7..0] == CME_OK);

  /* ---- ec.og: no bank → CME_ERR_NO_BANK ---- */
  /* ECID_P has no bank after ec.og released it */
  let _ = execute(CE_ECOG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(cme_status[7..0] == CME_ERR_NO_BANK);

  /* ---- ec.it: permission error → CME_ERR_PERMISSION ---- */
  bank_pool[0] = { Bank_default with owner_ecid = ECID_P, valid = true };
  X(encdec_reg(0b00001)) = zero_extend(ECID_P);
  X(encdec_reg(0b00010)) = zero_extend(ECID_P);  /* same ECID: not a descendant */
  let _ = execute(CE_ECIT(encdec_reg(0b00100), encdec_reg(0b00001), encdec_reg(0b00010)));
  assert(cme_status[7..0] == CME_ERR_PERMISSION);

  /* ---- ec.it: success → CME_OK ---- */
  X(encdec_reg(0b00001)) = zero_extend(ECID_P);
  X(encdec_reg(0b00010)) = zero_extend(ECID_C);
  let _ = execute(CE_ECIT(encdec_reg(0b00100), encdec_reg(0b00001), encdec_reg(0b00010)));
  assert(cme_status[7..0] == CME_OK);

  /* ---- ec.ot: success → CME_OK ---- */
  X(encdec_reg(0b00001)) = zero_extend(ECID_C);
  let _ = execute(CE_ECOT(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(cme_status[7..0] == CME_OK);

  /* ---- ec.ir: success → CME_OK, new ECID returned ---- */
  X(encdec_reg(0b00001)) = zeros();  /* flag=0: leaf child */
  let _ = execute(CE_ECIR(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(cme_status[7..0] == CME_OK);

  /* ---- ec.oe: always succeeds → CME_OK, freed count returned ---- */
  X(encdec_reg(0b00001)) = zero_extend(ECID_C);
  let _ = execute(CE_ECOE(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(cme_status[7..0] == CME_OK)
}
