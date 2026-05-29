// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — delegation depth cap enforcement (S24)
 * Spec reference: ch03 §3.5 (ec.ir), ch00 §0.8, ch13 §3.3
 *
 * D = 3 (the architectural maximum; Sail v1 constant in ce_state.sail).
 *
 * Build the delegation chain to L=D by allocating three delegating children:
 *
 *   L=0 (root)  --ec.ir rs1=1-->  ECID_L1 (L=1)
 *   ECID_L1     --ec.ir rs1=1-->  ECID_L2 (L=2)
 *   ECID_L2     --ec.ir rs1=1-->  ECID_L3 (L=3 = D)
 *
 * From ECID_L3 (L=D):
 *   ec.ir rs1=1 → CME_ERR_CAP_DEPTH  (cannot delegate further)
 *   ec.ir rs1=0 → success            (leaf is always allowed; pinned at L=D)
 *
 * Also verify that a delegating allocation from L=D-1=2 still succeeds,
 * confirming the boundary is exactly at parent_L >= D.
 */

$[test]
function test_delegation_depth_cap() -> unit = {
  ce_ctrl       = CE_CTRL_CME_EN;
  cur_privilege = Machine;

  /* ---- Setup: root ECID at L=0 ---- */
  ec_array[0] = { EC_entry_default with allocated = true, delegation_L = 0b00 };
  current_ecid = 0x0000;

  /* x1 = flag (0 = leaf, 1 = delegating) */
  /* x2 = result register */

  /* ---- Build chain to L=D ---- */

  /* L=0 → L=1: delegating child */
  X(encdec_reg(0b00001)) = zero_extend(0b1 : bits(1));
  let r1 = execute(CE_ECIR(encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r1 == RETIRE_SUCCESS);
  let ECID_L1 : ecid_t = truncate(X(encdec_reg(0b00010)), 16);
  assert(ECID_L1 != 0x0000);  /* allocation succeeded */

  /* L=1 → L=2: delegating child */
  current_ecid = ECID_L1;
  let r2 = execute(CE_ECIR(encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r2 == RETIRE_SUCCESS);
  let ECID_L2 : ecid_t = truncate(X(encdec_reg(0b00010)), 16);
  assert(ECID_L2 != 0x0000);

  /* L=2 → L=3 (=D): delegating child — still allowed (parent_L=2 < D=3) */
  current_ecid = ECID_L2;
  let r3 = execute(CE_ECIR(encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r3 == RETIRE_SUCCESS);
  let ECID_L3 : ecid_t = truncate(X(encdec_reg(0b00010)), 16);
  assert(ECID_L3 != 0x0000);

  /* Verify ECID_L3 is at delegation_L = D = 3 */
  foreach (i from 0 to 63) {
    if i == unsigned(ECID_L3) then
      assert(ec_array[i].delegation_L == cme_del_cap_D)
  };

  /* ---- Test 1: ec.ir rs1=1 from L=D → CME_ERR_CAP_DEPTH ---- */
  current_ecid = ECID_L3;
  let r_cap = execute(CE_ECIR(encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r_cap == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00010)) == cme_err_to_xlenbits(CME_ERR_CAP_DEPTH));
  assert(cme_status[7..0] == CME_ERR_CAP_DEPTH);

  /* ---- Test 2: ec.ir rs1=0 from L=D → success (leaf allowed) ---- */
  X(encdec_reg(0b00001)) = zeros();  /* flag = 0: leaf */
  let r_leaf = execute(CE_ECIR(encdec_reg(0b00010), encdec_reg(0b00001)));
  assert(r_leaf == RETIRE_SUCCESS);
  let ECID_LEAF : ecid_t = truncate(X(encdec_reg(0b00010)), 16);
  assert(ECID_LEAF != 0x0000);       /* allocation succeeded */
  assert(cme_status[7..0] == CME_OK);

  /* Leaf child must be pinned at delegation_L = D */
  foreach (i from 0 to 63) {
    if i == unsigned(ECID_LEAF) then
      assert(ec_array[i].delegation_L == cme_del_cap_D)
  }
}
