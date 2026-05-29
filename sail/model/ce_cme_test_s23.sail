// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — context switch round-trip register preservation (S23)
 * Spec reference: ch03 §3.13.1 (fast-path context switch diagram)
 *
 * Full sequence using real allocation (ec.ir / ec.ig):
 *
 *   1. Allocate ECID_A and ECID_B from the root ECID via ec.ir.
 *   2. Assign one bank to each ECID via ec.ig.
 *   3. Pre-load B's bank with: GPR_MASK, A's ec.ob reference, B's sentinel.
 *      (ec.ob restores all GPRs from the bank, so B's bank must carry the
 *       values needed for the return journey.)
 *   4. Switch current_ecid to A.  Write A's sentinel to x5.
 *   5. ec.ib saves A's live GPRs (including sentinel) to A's bank.
 *   6. ec.ob switches to B — B's bank GPRs go live.
 *   7. Verify: current_ecid == B, x5 == B's sentinel.
 *   8. ec.ob switches back to A — A's saved GPRs go live.
 *   9. Verify: current_ecid == A, x5 == A's original sentinel.  Round-trip preserved.
 *
 * Register layout (before ec.ib as A):
 *   x1 (gprs[0]) = GPR_MASK            (mask for ec.ib / ec.ob)
 *   x2 (gprs[1]) = B's ec.ob reference (gen_B << 16 | ECID_B)
 *   x3 (gprs[2]) = ECID_A value
 *   x4 (gprs[3]) = ECID_B value
 *   x5 (gprs[4]) = SENTINEL_A          ← the value that must survive the round-trip
 *
 * B's pre-loaded bank:
 *   gprs[0] = GPR_MASK                 (x1 after return from B)
 *   gprs[1] = A's ec.ob reference      (x2 after return from B — used to switch back)
 *   gprs[4] = SENTINEL_B               (x5 after switching to B)
 */

$[test]
function test_round_trip_register_preservation() -> unit = {
  let GPR_MASK : xlenbits = zero_extend(0x01 : bits(8));  /* bit 0: save GPRs */

  /* Sentinel values stored in the Bank struct (always bits(64));
   * truncated to xlen when written to / compared against live registers. */
  let SENTINEL_A : bits(64) = 0xAAAA000000000005 : bits(64);
  let SENTINEL_B : bits(64) = 0xBBBB000000000005 : bits(64);

  ce_ctrl       = CE_CTRL_CME_EN;
  cur_privilege = Machine;
  cme_priv_ctl  = 0b0;

  /* ---- Root ECID setup ---- */
  ec_array[0] = { EC_entry_default with allocated = true, delegation_L = 0b00 };
  current_ecid = 0x0000;

  /* ---- Step 1: allocate ECID_A via ec.ir ---- */
  X(encdec_reg(0b00001)) = zeros();  /* flag = 0: leaf child */
  let r_ir_a = execute(CE_ECIR(encdec_reg(0b00011), encdec_reg(0b00001)));
  assert(r_ir_a == RETIRE_SUCCESS);
  let ECID_A : ecid_t = truncate(X(encdec_reg(0b00011)), 16);  /* slot 1 */
  assert(ECID_A != 0x0000);  /* allocation succeeded */

  /* ---- Step 2: allocate ECID_B via ec.ir ---- */
  let r_ir_b = execute(CE_ECIR(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r_ir_b == RETIRE_SUCCESS);
  let ECID_B : ecid_t = truncate(X(encdec_reg(0b00100)), 16);  /* slot 2 */
  assert(ECID_B != 0x0000);
  assert(ECID_A != ECID_B);

  /* ---- Step 3: assign banks via ec.ig ---- */
  X(encdec_reg(0b00001)) = zero_extend(ECID_A);
  let r_ig_a = execute(CE_ECIG(encdec_reg(0b00101), encdec_reg(0b00001)));
  assert(r_ig_a == RETIRE_SUCCESS);  /* bank_pool[0] → ECID_A */

  X(encdec_reg(0b00001)) = zero_extend(ECID_B);
  let r_ig_b = execute(CE_ECIG(encdec_reg(0b00101), encdec_reg(0b00001)));
  assert(r_ig_b == RETIRE_SUCCESS);  /* bank_pool[1] → ECID_B */

  /* ---- Step 4: pre-load B's bank with return-journey values ----
   * ec.ob restores all GPRs from the target bank.  B's bank must carry:
   *   gprs[0] = GPR_MASK   so x1 is the mask for the return ec.ob
   *   gprs[1] = A_REF      so x2 is A's ec.ob reference for the return
   *   gprs[4] = SENTINEL_B so x5 carries B's verifiable value
   * Newly allocated ECIDs have generation = 0x01 (ec.ir increments from 0). */
  let GEN_A : generation_t = 0x01;
  let GEN_B : generation_t = 0x01;
  let a_ref : bits(24) = GEN_A @ ECID_A;  /* (gen_A << 16) | ECID_A */
  let b_ref : bits(24) = GEN_B @ ECID_B;  /* (gen_B << 16) | ECID_B */

  var b_gprs : vector(31, dec, bits(64)) = Bank_default.gprs;
  b_gprs[0] = zero_extend(0x01 : bits(8));  /* x1 = GPR_MASK after restore */
  b_gprs[1] = zero_extend(a_ref);           /* x2 = A's ec.ob reference */
  b_gprs[4] = SENTINEL_B;                   /* x5 = B's sentinel */
  bank_pool[1] = { bank_pool[1] with gprs = b_gprs };

  /* ---- Step 5: switch to ECID_A, write A's live register file ---- */
  current_ecid = ECID_A;

  X(encdec_reg(0b00001)) = GPR_MASK;              /* x1 = mask for ec.ib */
  X(encdec_reg(0b00010)) = zero_extend(b_ref);    /* x2 = B's ec.ob reference */
  X(encdec_reg(0b00011)) = zero_extend(ECID_A);   /* x3 = ECID_A (informational) */
  X(encdec_reg(0b00100)) = zero_extend(ECID_B);   /* x4 = ECID_B (informational) */
  X(encdec_reg(0b00101)) = truncate(SENTINEL_A, xlen);  /* x5 = A's sentinel */

  /* ---- Step 6: ec.ib — save A's live GPRs to A's bank ---- */
  let r_ib = execute(CE_ECIB(encdec_reg(0b00000), encdec_reg(0b00001)));
  assert(r_ib == RETIRE_SUCCESS);
  assert(current_ecid == ECID_A);  /* current_ecid unchanged by ec.ib */

  /* A's sentinel is now preserved in bank_pool[0].gprs[4] */
  assert(bank_pool[0].gprs[4] == zero_extend(truncate(SENTINEL_A, xlen)));

  /* ---- Step 7: ec.ob → switch to ECID_B ---- */
  /* x2 = b_ref (B's ec.ob reference), x1 = GPR_MASK */
  let r_ob_b = execute(CE_ECOB(encdec_reg(0b00000), encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r_ob_b == RETIRE_SUCCESS);
  assert(current_ecid == ECID_B);

  /* B's sentinels are now live — check x5 */
  assert(X(encdec_reg(0b00101)) == truncate(SENTINEL_B, xlen));

  /* ---- Step 8: ec.ob → switch back to ECID_A ---- */
  /* x2 is now a_ref (pre-loaded into B's bank), x1 is GPR_MASK (ditto) */
  let r_ob_a = execute(CE_ECOB(encdec_reg(0b00000), encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r_ob_a == RETIRE_SUCCESS);
  assert(current_ecid == ECID_A);

  /* ---- Step 9: verify A's original GPR values are restored ---- */
  assert(X(encdec_reg(0b00101)) == truncate(SENTINEL_A, xlen));  /* x5: A's sentinel */
  assert(X(encdec_reg(0b00001)) == GPR_MASK);                    /* x1: mask preserved */
  assert(X(encdec_reg(0b00011)) == zero_extend(ECID_A));         /* x3: ECID_A preserved */
  assert(X(encdec_reg(0b00100)) == zero_extend(ECID_B))          /* x4: ECID_B preserved */
}
