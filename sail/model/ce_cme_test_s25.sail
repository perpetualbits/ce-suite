// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — sealed bank: ec.ob refusal (S25)
 * Spec reference: ch03 §3.6 "Sealed bank state"
 *
 * ec.ob must refuse to restore a sealed bank and return
 * CME_ERR_ALREADY_SEALED (6) without modifying any state (ch03 §3.6):
 *   "ec.ob refuses to restore a sealed bank — returns CME_ERR_ALREADY_SEALED.
 *    Unseal with ec.ov before restoring."
 *
 * ec.iv/ec.ov are implementation-defined (encrypt algorithm deferred); the
 * sealed flag is set directly here as permitted for unit tests.
 *
 * Two scenarios:
 *   1. Sealed bank → CME_ERR_ALREADY_SEALED; current_ecid and bank unchanged.
 *   2. Same bank unsealed → ec.ob succeeds, restoring register state.
 */

$[test]
function test_sealed_bank_refusal() -> unit = {
  let ECID_CTX : ecid_t      = 0x0000;  /* running context (unchanged on failure) */
  let ECID_A   : ecid_t      = 0x0001;  /* target ECID whose bank is sealed */
  let GEN_A    : generation_t = 0x05;
  let GPR_MASK : xlenbits    = zero_extend(0x01 : bits(8));

  ce_ctrl       = CE_CTRL_CME_EN;
  cur_privilege = Machine;

  ec_array[0] = { EC_entry_default with allocated = true };
  ec_array[1] = { EC_entry_default with
    allocated  = true,
    generation = GEN_A
  };
  current_ecid = ECID_CTX;

  /* Bank slot 0: owned by ECID_A, with a sentinel in gprs[2] (x3) */
  let SENTINEL : bits(64) = 0xDEAD000000000003 : bits(64);
  var a_gprs : vector(31, dec, bits(64)) = Bank_default.gprs;
  a_gprs[2] = SENTINEL;

  /* ---- Scenario 1: sealed bank → ec.ob must be refused ---- */
  bank_pool[0] = { Bank_default with
    owner_ecid = ECID_A,
    valid      = true,
    sealed     = true,      /* sealed: ec.ob must refuse */
    gprs       = a_gprs
  };

  /* rs1 = (GEN_A << 16) | ECID_A; rs2 = GPR_MASK */
  X(encdec_reg(0b00001)) = zero_extend(GEN_A @ ECID_A);
  X(encdec_reg(0b00010)) = GPR_MASK;

  let r1 = execute(CE_ECOB(encdec_reg(0b00100), encdec_reg(0b00001), encdec_reg(0b00010)));
  assert(r1 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_ERR_ALREADY_SEALED));
  assert(cme_status[7..0] == CME_ERR_ALREADY_SEALED);

  /* State must be completely unchanged */
  assert(current_ecid == ECID_CTX);        /* did not switch to ECID_A */
  assert(bank_pool[0].sealed);             /* bank still sealed */
  assert(bank_pool[0].gprs[2] == SENTINEL); /* bank contents intact */

  /* ---- Scenario 2: unsealed bank → ec.ob succeeds ---- */
  bank_pool[0] = { bank_pool[0] with sealed = false };

  let r2 = execute(CE_ECOB(encdec_reg(0b00100), encdec_reg(0b00001), encdec_reg(0b00010)));
  assert(r2 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == cme_err_to_xlenbits(CME_OK));

  /* Restored: current_ecid switched to ECID_A; x3 carries the sentinel */
  assert(current_ecid == ECID_A);
  assert(X(encdec_reg(0b00011)) == truncate(SENTINEL, xlen))
}
