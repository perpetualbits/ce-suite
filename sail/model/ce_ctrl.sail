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

/* CSR read: zero-extend to XLEN */
function clause read_CSR(0x7D0) = zero_extend(ce_ctrl)

/* CSR write: only bits 3:0 writable; implementation-absent bits treated as RO 0.
 * Sail v1 assumes all four extensions are present. */
function clause write_CSR(0x7D0, value) = {
  ce_ctrl = value[3..0];
  Ok(zero_extend(ce_ctrl))
}
