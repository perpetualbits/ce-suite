// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — current_ecid_level / current_ecid_parent CSR test (S20)
 * Spec reference: ch13 §3.10 (0xFD1 current_ecid_level),
 *                 ch13 §3.11 (0xFD2 current_ecid_parent)
 *
 * Verifies that read_CSR(0xFD1) and read_CSR(0xFD2) correctly reflect
 * the delegation level and parent ECID of current_ecid after a
 * successful ec.ob.
 *
 * The CSR functions do live lookup_ec(current_ecid) reads, so they
 * automatically track whichever ECID ec.ob switched to.
 *
 * Setup:
 *   ECID_A (0x0001): level 1, parent = root (0x0000)
 *   ECID_B (0x0002): level 2, parent = ECID_A
 *
 * Sequence:
 *   1. Start as ECID_A. Verify CSRs reflect A.
 *   2. Execute ec.ob → switch to ECID_B.
 *   3. Verify CSRs now reflect B.
 */

$[test]
function test_csr_level_parent_after_ecob() -> unit = {
  let ECID_A : ecid_t      = 0x0001;
  let ECID_B : ecid_t      = 0x0002;
  let GEN_B  : generation_t = 0x07;

  ce_ctrl = CE_CTRL_CME_EN;

  ec_array[1] = { EC_entry_default with
    allocated    = true,
    delegation_L = 0b01,
    parent_ecid  = 0x0000
  };
  ec_array[2] = { EC_entry_default with
    allocated    = true,
    generation   = GEN_B,
    delegation_L = 0b10,
    parent_ecid  = ECID_A
  };

  /* ECID_B owns bank slot 0 (needed for ec.ob restore) */
  bank_pool[0] = { Bank_default with owner_ecid = ECID_B, valid = true };

  current_ecid = ECID_A;

  /* ---- Before ec.ob: CSRs reflect ECID_A ---- */
  assert(read_CSR(0xFD1) == zero_extend(0b01 : bits(2)));  /* A's level = 1 */
  assert(read_CSR(0xFD2) == zero_extend(0x0000 : ecid_t));  /* A's parent = root */

  /* rs1 packs (generation_B << 16) | ECID_B; rs2 = GPR mask */
  X(encdec_reg(0b00001)) = zero_extend(GEN_B @ ECID_B);
  X(encdec_reg(0b00010)) = zero_extend(0x01 : bits(8));  /* GPR group */

  /* ---- Execute ec.ob → switch current_ecid to ECID_B ---- */
  let r = execute(CE_ECOB(encdec_reg(0b00000), encdec_reg(0b00001), encdec_reg(0b00010)));
  assert(r == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00000)) == cme_err_to_xlenbits(CME_OK));
  assert(current_ecid == ECID_B);

  /* ---- After ec.ob: CSRs reflect ECID_B ---- */
  assert(read_CSR(0xFD1) == zero_extend(0b10 : bits(2)));  /* B's level = 2 */
  assert(read_CSR(0xFD2) == zero_extend(ECID_A))            /* B's parent = A */
}
