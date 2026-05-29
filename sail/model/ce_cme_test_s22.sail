// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — ce_ctrl privilege gating test (S22)
 * Spec reference: ch14 §14.2–§14.5, ch13 §1.1
 *
 * cme_authorized() = cme_enabled() AND cme_priv_allowed(). Four scenarios:
 *   1. M-mode + CME_EN=1: always allowed.
 *   2. CME_EN=0, M-mode: Illegal_Instruction (extension disabled).
 *   3. S-mode + S_EN=0: Illegal_Instruction (privilege denied).
 *   4. S-mode + S_EN=1: allowed.
 *   5. U-mode + S_EN=1: Illegal_Instruction (U-mode never allowed).
 *
 * ec.ig is used as the representative instruction; the gate is shared.
 */

$[test]
function test_privilege_gating() -> unit = {
  let ECID_A : ecid_t = 0x0001;

  ec_array[1] = { EC_entry_default with allocated = true };
  bank_pool[0] = Bank_default;  /* slot 0 free */
  X(encdec_reg(0b00001)) = zero_extend(ECID_A);

  /* ---- Scenario 1: M-mode, CME_EN=1 → allowed ---- */
  ce_ctrl       = CE_CTRL_CME_EN;
  cme_priv_ctl  = 0b0;  /* S_EN = 0, but irrelevant for M-mode */
  cur_privilege = Machine;
  let r1 = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r1 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == zero_extend(0x00 : bits(8)));  /* slot 0 */

  /* Release the bank so later tests have a free slot */
  bank_pool[0] = Bank_default;

  /* ---- Scenario 2: M-mode, CME_EN=0 → Illegal_Instruction ---- */
  ce_ctrl       = 0b0000;  /* CME disabled */
  cur_privilege = Machine;
  let r2 = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r2 == Illegal_Instruction());

  /* ---- Scenario 3: S-mode, CME_EN=1, S_EN=0 → Illegal_Instruction ---- */
  ce_ctrl       = CE_CTRL_CME_EN;
  cme_priv_ctl  = 0b0;  /* S_EN = 0 */
  cur_privilege = Supervisor;
  let r3 = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r3 == Illegal_Instruction());

  /* ---- Scenario 4: S-mode, CME_EN=1, S_EN=1 → allowed ---- */
  ce_ctrl       = CE_CTRL_CME_EN;
  cme_priv_ctl  = 0b1;  /* S_EN = 1 */
  cur_privilege = Supervisor;
  let r4 = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r4 == RETIRE_SUCCESS);
  assert(X(encdec_reg(0b00100)) == zero_extend(0x00 : bits(8)));  /* slot 0 */

  bank_pool[0] = Bank_default;

  /* ---- Scenario 5: U-mode, CME_EN=1, S_EN=1 → Illegal_Instruction ---- */
  ce_ctrl       = CE_CTRL_CME_EN;
  cme_priv_ctl  = 0b1;
  cur_privilege = User;
  let r5 = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r5 == Illegal_Instruction());

  /* ---- Scenario 6: VS-mode, S_EN=1, VS_EN=1 → allowed ---- */
  ce_ctrl       = CE_CTRL_CME_EN;
  cme_priv_ctl  = 0b1;
  hcme_ctrl     = 0b1;
  cur_privilege = VirtualSupervisor;
  let r6 = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r6 == RETIRE_SUCCESS);

  bank_pool[0] = Bank_default;

  /* ---- Scenario 7: VS-mode, S_EN=1, VS_EN=0 → Illegal_Instruction ---- */
  hcme_ctrl     = 0b0;
  cur_privilege = VirtualSupervisor;
  let r7 = execute(CE_ECIG(encdec_reg(0b00100), encdec_reg(0b00001)));
  assert(r7 == Illegal_Instruction());

  /* Restore safe state */
  cur_privilege = Machine;
  cme_priv_ctl  = 0b0;
  hcme_ctrl     = 0b0
}
