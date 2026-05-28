// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — fast-path context switch validation test (S7)
 * Spec reference: ch03 §3.1 "Typical switch sequence", ch03 §3.13.1
 *
 * Validates the canonical two-instruction context switch:
 *   ec.ib x0, x1       (save current ECID A into its bank)
 *   ec.ob x0, x2, x1   (restore ECID B from its bank)
 *
 * Precondition state mirrors the §3.13.1 diagram:
 *   current_ecid = A
 *   Live reg file = A's values
 *   Bank[A] = empty (to be filled by ec.ib)
 *   Bank[B] = B's saved values (waiting in SRAM)
 *
 * Postcondition checks:
 *   After ec.ib:  A's sentinel value is in Bank[A]; current_ecid still A.
 *   After ec.ob:  B's sentinel value is live in x3; current_ecid = B.
 */

$[test]
function test_fast_path_context_switch() -> unit = {
  /* ---- Constants ---- */
  let ECID_A   : ecid_t   = 0x0001;
  let ECID_B   : ecid_t   = 0x0002;
  let GPR_MASK : xlenbits = zero_extend(0x01 : bits(8));  /* bit 0 = GPR group */

  /* ---- Setup ---- */

  /* Enable CME */
  ce_ctrl = CE_CTRL_CME_EN;

  /* Allocate EC entries for A and B */
  ec_array[1] = { EC_entry_default with allocated = true };
  ec_array[2] = { EC_entry_default with allocated = true };

  /* Set current context to A */
  current_ecid = ECID_A;

  /* Load A's live register file with distinguishable values:
   *   x1 = GPR_MASK  (operand for ec.ib rs1 and ec.ob rs2)
   *   x2 = ECID_B    (operand for ec.ob rs1)
   *   x3 = A-sentinel (value to verify is saved then overwritten) */
  X(encdec_reg(0b00001)) = GPR_MASK;
  X(encdec_reg(0b00010)) = zero_extend(ECID_B);
  X(encdec_reg(0b00011)) = truncate(0xAAAA000000000003 : bits(64), xlen);

  /* Assign bank 0 to A — valid slot, no saved state yet */
  bank_pool[0] = { Bank_default with owner_ecid = ECID_A, valid = true };

  /* Pre-load bank 1 with B's saved register state */
  var b_gprs : vector(31, dec, bits(64)) = Bank_default.gprs;
  b_gprs[0] = 0xBBBB000000000001 : bits(64);  /* B's x1 */
  b_gprs[1] = 0xBBBB000000000002 : bits(64);  /* B's x2 */
  b_gprs[2] = 0xBBBB000000000003 : bits(64);  /* B's x3 (sentinel) */
  bank_pool[1] = { Bank_default with
    owner_ecid = ECID_B,
    valid      = true,
    gprs       = b_gprs
  };

  /* ---- Step 1: ec.ib x0, x1  (rd = x0, rs1 = x1 = GPR_MASK) ---- */
  let r1 = execute(CE_ECIB(encdec_reg(0b00000), encdec_reg(0b00001)));
  assert(r1 == RETIRE_SUCCESS);

  /* ec.ib postconditions:
   * - current_ecid unchanged (still A)
   * - A's sentinel (x3) is now in bank[A].gprs[2] */
  assert(current_ecid == ECID_A);
  assert(bank_pool[0].valid);
  assert(bank_pool[0].gprs[2] == zero_extend(truncate(0xAAAA000000000003 : bits(64), xlen)));

  /* ---- Step 2: ec.ob x0, x2, x1  (rd=x0, rs1=x2=ECID_B, rs2=x1=mask) ---- */
  let r2 = execute(CE_ECOB(encdec_reg(0b00000), encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r2 == RETIRE_SUCCESS);

  /* ec.ob postconditions:
   * - current_ecid updated to B
   * - B's sentinel value (0xBBBB...0003) is now live in x3 */
  assert(current_ecid == ECID_B);
  assert(X(encdec_reg(0b00011)) == truncate(0xBBBB000000000003 : bits(64), xlen))
}
