// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — ce_ctrl CSR (0x7D0)
 * Spec reference: ch13 §1.1, charter §3.7 (v0.16+)
 *
 * ce_ctrl is M-mode RW, resets to 0 (all extensions disabled).
 * Four independent per-extension enable bits; absent extensions are RO 0.
 */

/* ce_ctrl register: bits 3:0 used, rest WIRI */
register ce_ctrl : bits(4) = 0b0000

/* Bit positions */
let CE_CTRL_CME_EN : bits(4) = 0b0001  /* bit 0 */
let CE_CTRL_CPE_EN : bits(4) = 0b0010  /* bit 1 */
let CE_CTRL_MSE_EN : bits(4) = 0b0100  /* bit 2 */
let CE_CTRL_QOS_EN : bits(4) = 0b1000  /* bit 3 */

/* Predicate: is the given extension enabled? */
function cme_enabled() -> bool = (ce_ctrl & CE_CTRL_CME_EN) != 0b0000
function cpe_enabled() -> bool = (ce_ctrl & CE_CTRL_CPE_EN) != 0b0000
function mse_enabled() -> bool = (ce_ctrl & CE_CTRL_MSE_EN) != 0b0000
function qos_enabled() -> bool = (ce_ctrl & CE_CTRL_QOS_EN) != 0b0000

/* ------------------------------------------------------------------ */
/* cme_priv_ctl — M-mode privilege control (0x7CF)                    */
/* ch14 §14.4.1: bit 0 = S_EN, rest WPRI                             */
/* ------------------------------------------------------------------ */

register cme_priv_ctl : bits(1) = 0b0  /* S_EN: reset = 0 (S-mode disabled) */

/* ------------------------------------------------------------------ */
/* hcme_ctrl — HS-mode privilege control (0x6C0, H extension)        */
/* ch14 §14.4.2: bit 0 = VS_EN, rest WPRI                            */
/* ------------------------------------------------------------------ */

register hcme_ctrl : bits(1) = 0b0     /* VS_EN: reset = 0 (VS-mode disabled) */

/* ------------------------------------------------------------------ */
/* Privilege-level gate (ch14 §14.4.3)                                */
/*                                                                     */
/* M-mode: always allowed                                             */
/* S/HS-mode: allowed when S_EN = 1                                   */
/* VS-mode: allowed when S_EN = 1 AND VS_EN = 1                      */
/* U/VU-mode: never allowed                                           */
/* ------------------------------------------------------------------ */

function cme_priv_allowed() -> bool =
  match cur_privilege {
    Machine           => true,
    Supervisor        => cme_priv_ctl[0] == 0b1,
    VirtualSupervisor => (cme_priv_ctl[0] == 0b1) & (hcme_ctrl[0] == 0b1),
    User              => false,
    VirtualUser       => false
  }

/* Combined gate: CME extension enabled AND caller privilege allowed */
function cme_authorized() -> bool = cme_enabled() & cme_priv_allowed()

/* CSR read/write for ce_ctrl (0x7D0) */
function clause read_CSR(0x7D0) = zero_extend(ce_ctrl)
function clause write_CSR(0x7D0, value) = {
  ce_ctrl = value[3..0];
  Ok(zero_extend(ce_ctrl))
}

/* CSR read/write for cme_priv_ctl (0x7CF, M-mode RW) */
function clause read_CSR(0x7CF) = zero_extend(cme_priv_ctl)
function clause write_CSR(0x7CF, value) = {
  cme_priv_ctl = value[0..0];
  Ok(zero_extend(cme_priv_ctl))
}

/* CSR read/write for hcme_ctrl (0x6C0, M-mode and HS-mode RW) */
function clause read_CSR(0x6C0) = zero_extend(hcme_ctrl)
function clause write_CSR(0x6C0, value) = {
  hcme_ctrl = value[0..0];
  Ok(zero_extend(hcme_ctrl))
}
