// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — Test S29f: ms.ir / ms.or round-trip
 * Spec reference: ch09 §9.5–§9.6
 *
 * Validates the basic Contract lifecycle:
 *   1. ECID A (slot 1) is allocated in ec_array.
 *   2. ms.ir admits a Contract for ECID A with bw_class=64, lat_class=2.
 *      Assertion: Contract present in mse_contract_pool;
 *      mse_bw_sum == 64; mse_status == MSE_OK; rd == 0.
 *   3. ms.or revokes the Contract.
 *      Assertion: Contract invalid in mse_contract_pool;
 *      mse_bw_sum == 0; mse_status == MSE_OK; rd == 0.
 */

$[test]
function test_mse_ir_or_roundtrip() -> unit = {
  /* ---- Setup ---- */

  /* Enable MSE */
  ce_ctrl = CE_CTRL_MSE_EN;

  /* Allocate ECID A (slot 1) in ec_array */
  let ecid_a : ecid_t = 0x0001;
  ec_array[1] = { EC_entry_default with allocated = true, generation = 0x01 };

  /* Contract descriptor: bw_class=64 (0x40) in bits 7:0,
   * lat_class=2 (0x02) in bits 15:8; all higher bits = 0 (inline form) */
  let descriptor : xlenbits = zero_extend(0x0240 : bits(16));

  /* Load operands: rs1 = x5 = ecid_a, rs2 = x6 = descriptor */
  X(encdec_reg(0b00101)) = zero_extend(ecid_a);
  X(encdec_reg(0b00110)) = descriptor;

  /* ---- Step 1: ms.ir rd=x7, rs1=x5, rs2=x6 ---- */
  let r1 = execute(CE_MSIR(encdec_reg(0b00111),
                            encdec_reg(0b00101),
                            encdec_reg(0b00110)));
  assert(r1 == RETIRE_SUCCESS);

  /* ms.ir postconditions */
  assert(mse_contract_active(ecid_a));
  assert(mse_bw_sum == 0x40);       /* bw_class = 64 */
  assert(mse_status == MSE_OK);
  assert(X(encdec_reg(0b00111)) == zeros());  /* rd = 0 */

  /* ---- Step 2: ms.or rd=x7, rs1=x5 ---- */
  let r2 = execute(CE_MSOR(encdec_reg(0b00111),
                            encdec_reg(0b00101)));
  assert(r2 == RETIRE_SUCCESS);

  /* ms.or postconditions */
  assert(~(mse_contract_active(ecid_a)));
  assert(mse_bw_sum == 0x00);
  assert(mse_status == MSE_OK);
  assert(X(encdec_reg(0b00111)) == zeros())   /* rd = 0 */
}
