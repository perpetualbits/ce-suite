// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — memory ordering obligations test (S17)
 * Spec reference: ch17 §17.3 (ec.im/ec.om ordering), §17.5 (normative migration)
 *
 * Encodes the §17.5 normative migration fence sequence for a single-hart
 * execution and asserts the structural pre/postconditions at each step.
 *
 * Cross-hart memory ordering is verified here at the structural level:
 *   - ec.im uses write_ram → its writes participate in RVWMO as stores.
 *   - ec.om uses read_ram  → its reads participate in RVWMO as loads.
 *   - FENCE W,W on Hart 0 (after ec.im, before signal) ensures ECS writes
 *     are globally visible to Hart 1 before Hart 1 polls the flag.
 *   - FENCE R,R on Hart 1 (after polling, before ec.om) ensures Hart 1
 *     observes Hart 0's ECS write before loading it via ec.om.
 *
 * Actual cross-hart ordering requires running the sail-riscv memory model
 * simulator, which is out of scope for Sail v1 type-checking.
 *
 * Simplified §17.5 steps (single-hart; cross-hart boundary marked):
 *   Hart 0 steps 1–5: revoke resources, ec.ib, ec.im, FENCE W,W, signal
 *   Hart 1 steps 7–11: poll, FENCE R,R, ec.ir, set ecs_ptr, ec.om
 */

$[test]
function test_migration_fence_sequence() -> unit = {
  let ECID_A : ecid_t = 0x0001;  /* source ECID (Hart 0) */
  let ECS_ADDR : physaddrbits = zero_extend(0x80010000 : bits(32));  /* ECS in RAM */
  let GPR_MASK : xlenbits = zero_extend(0x01 : bits(8));  /* GPR only */

  ce_ctrl = CE_CTRL_CME_EN;

  /* --- Hart 0 setup: ECID_A with a bank and known register state --- */
  ec_array[1] = { EC_entry_default with
    ecs_ptr   = ECS_ADDR,   /* kernel has set the ECS pointer */
    allocated = true
  };
  current_ecid = ECID_A;

  bank_pool[0] = { Bank_default with owner_ecid = ECID_A, valid = true };
  X(encdec_reg(0b00001)) = GPR_MASK;  /* x1 = mask */

  /* Hart 0, Step 2: ec.ib — save A's register state to bank */
  let r_ib = execute(CE_ECIB(encdec_reg(0b00000), encdec_reg(0b00001)));
  assert(r_ib == RETIRE_SUCCESS);
  assert(bank_pool[0].valid);  /* bank still assigned to A */

  /* Hart 0, Step 3: ec.im — spill bank to ECS in RAM */
  let r_im = execute(CE_ECIM(encdec_reg(0b00000), encdec_reg(0b00001), encdec_reg(0b00001)));
  assert(r_im == RETIRE_SUCCESS);
  /* ec.im writes ECS via write_ram; bank remains valid (ec.og frees it) */
  assert(bank_pool[0].valid);
  assert(bank_pool[0].owner_ecid == ECID_A);

  /* Hart 0, Step 4: FENCE W,W
   * (ch17 §17.3.1 / §17.5 step 4)
   * Ensures ec.im's ECS stores are globally visible before Hart 0's flag
   * store (step 5). Without this fence, Hart 1 may read a stale ECS.
   * In Sail v1: fence effect is axiomatised; commented here for documentation. */

  /* Hart 0, Step 5: signal Hart 1 (flag store — after FENCE W,W) */
  /* In a real test: write flag_addr using a store instruction. */

  /* -------- CROSS-HART BOUNDARY (Hart 1 begins) -------- */

  /* Hart 1, Step 7: poll flag (omitted — single-hart model) */

  /* Hart 1, Step 8: FENCE R,R
   * (ch17 §17.3.2 / §17.5 step 8)
   * Ensures Hart 1 observes Hart 0's ECS write and all prior stores by A
   * before ec.om reads the ECS. Without this fence, ec.om may read a stale
   * ECS even after the flag is observed. */

  /* Hart 1, Step 9: ec.ir — allocate a new ECID for the migrated EC */
  current_ecid = 0x0000;  /* Hart 1's root ECID (L=0) */
  ec_array[0] = { EC_entry_default with allocated = true };
  X(encdec_reg(0b00010)) = zeros();  /* x2 = flag=0 → leaf child */

  let r_ir = execute(CE_ECIR(encdec_reg(0b00011), encdec_reg(0b00010)));
  assert(r_ir == RETIRE_SUCCESS);
  let new_ecid_val = X(encdec_reg(0b00011));
  /* Allocation succeeded (rd != 0) */
  assert(new_ecid_val != zeros());

  /* Hart 1, Step 10: set EC[new_ecid].ecs_ptr = ECS_ADDR (kernel software step)
   * The kernel writes this directly; not an instruction operand.
   * Modelled here by directly updating ec_array. */
  let new_ecid : ecid_t = truncate(new_ecid_val, 16);
  foreach (i from 0 to 63) {
    if i == unsigned(new_ecid) then
      ec_array[i] = { ec_array[i] with ecs_ptr = ECS_ADDR }
  };

  /* Hart 1, Step 11: ec.om — fill new bank from ECS (after FENCE R,R) */
  current_ecid = new_ecid;
  X(encdec_reg(0b00001)) = GPR_MASK;  /* x1 = mask (same as spill mask) */

  let r_om = execute(CE_ECOM(encdec_reg(0b00000), encdec_reg(0b00011), encdec_reg(0b00001)));
  assert(r_om == RETIRE_SUCCESS);

  /* ec.om postconditions:
   * - A free bank was claimed and assigned to new_ecid
   * - The bank is valid (ready for ec.ob in step 13) */
  var bank_assigned : bool = false;
  foreach (b from 0 to 7) {
    if bank_pool[b].valid & (bank_pool[b].owner_ecid == new_ecid) then
      bank_assigned = true
  };
  assert(bank_assigned)
}
