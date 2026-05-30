// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — CSR read/write clauses (excluding ce_ctrl)
 * Spec reference: ch13 §3–§6
 *
 * All CE CSRs are per-hart. When an extension is disabled (ce_ctrl bit = 0),
 * all CSRs for that extension read as 0 (ch13 §2, "CE disabled" convention).
 */

/* ------------------------------------------------------------------ */
/* CME CSRs                                                           */
/* ------------------------------------------------------------------ */

/* 0xFC0 — current_ecid (RO) */
function clause read_CSR(0xFC0) =
  if cme_enabled() then zero_extend(current_ecid) else zeros()

/* 0x7C0 — cme_ec_table_base (WARL) */
function clause read_CSR(0x7C0) =
  if cme_enabled() then cme_ec_table_base else zeros()
function clause write_CSR(0x7C0, value) = {
  if cme_enabled() then cme_ec_table_base = value else ();
  Ok(cme_ec_table_base)
}

/* 0xFC1 — cme_del_cap (RO) */
function clause read_CSR(0xFC1) =
  if cme_enabled() then zero_extend(cme_del_cap_D) else zeros()

/* 0xFC2 — cme_bank_count (RO) */
function clause read_CSR(0xFC2) =
  if cme_enabled()
  then zero_extend(cme_bank_count_VMT @ cme_bank_count_NV)
  else zeros()

/* 0xFC3 — cme_status (RO) */
function clause read_CSR(0xFC3) =
  if cme_enabled() then zero_extend(cme_status) else zeros()

/* 0xFC4 — cme_reg_mask (RO) */
function clause read_CSR(0xFC4) =
  if cme_enabled() then cme_reg_mask else zeros()

/* 0x7C3 — cme_seal_key (WARL, M-mode only; write-once implementations
 * may return 0 on read after programming — modelled as readable here) */
function clause read_CSR(0x7C3) =
  if cme_enabled() then cme_seal_key else zeros()
function clause write_CSR(0x7C3, value) = {
  if cme_enabled() then cme_seal_key = value else ();
  Ok(cme_seal_key)
}

/* 0xFD1 — current_ecid_level (RO, S/HS/VS accessible when S_EN=1) */
function clause read_CSR(0xFD1) =
  if cme_enabled() then {
    match lookup_ec(current_ecid) {
      None()      => zeros(),
      Some(entry) => zero_extend(entry.delegation_L)
    }
  } else zeros()

/* 0xFD2 — current_ecid_parent (RO, S/HS/VS accessible when S_EN=1) */
function clause read_CSR(0xFD2) =
  if cme_enabled() then {
    match lookup_ec(current_ecid) {
      None()      => zeros(),
      Some(entry) => zero_extend(entry.parent_ecid)
    }
  } else zeros()

/* ------------------------------------------------------------------ */
/* CPE CSRs — stubs (ch13 §4)                                        */
/* ------------------------------------------------------------------ */

/* 0xFC5 — cpe_caps (RO) — TODO: populate once CPE execute is modelled */
function clause read_CSR(0xFC5) =
  if cpe_enabled() then zeros() /* placeholder */ else zeros()

/* ------------------------------------------------------------------ */
/* MSE CSRs (ch13 §5)                                                */
/* ------------------------------------------------------------------ */

/* 0x7C6 — mse_slot_ratio (WARL) */
function clause read_CSR(0x7C6) =
  if mse_enabled() then zero_extend(mse_slot_ratio) else zeros()
function clause write_CSR(0x7C6, value) = {
  if mse_enabled() then mse_slot_ratio = value[7..0] else ();
  Ok(zero_extend(mse_slot_ratio))
}

/* 0xFC7 — mse_slot_ns (RO) */
function clause read_CSR(0xFC7) =
  if mse_enabled() then zero_extend(mse_slot_ns_val) else zeros()

/* 0xFC8 — mse_max_nesting (RO) */
function clause read_CSR(0xFC8) =
  if mse_enabled() then zero_extend(mse_max_nesting) else zeros()

/* 0x7C7 — mse_bw_cap (WARL) */
function clause read_CSR(0x7C7) =
  if mse_enabled() then zero_extend(mse_bw_cap) else zeros()
function clause write_CSR(0x7C7, value) = {
  if mse_enabled() then mse_bw_cap = value[7..0] else ();
  Ok(zero_extend(mse_bw_cap))
}

/* 0xFC9 — mse_bw_sum (RO) */
function clause read_CSR(0xFC9) =
  if mse_enabled() then zero_extend(mse_bw_sum) else zeros()

/* 0xFCA — mse_status (RO) */
function clause read_CSR(0xFCA) =
  if mse_enabled() then zero_extend(mse_status) else zeros()

/* 0x7C8 — mse_violation (W1C) */
function clause read_CSR(0x7C8) =
  if mse_enabled() then zero_extend(mse_violation) else zeros()
function clause write_CSR(0x7C8, value) = {
  if mse_enabled() then {
    if value[0] == 0b1 then mse_violation = 0b0
  } else ();
  Ok(zero_extend(mse_violation))
}

/* 0x7C9 — mse_violation_en (RW) */
function clause read_CSR(0x7C9) =
  if mse_enabled() then zero_extend(mse_violation_en) else zeros()
function clause write_CSR(0x7C9, value) = {
  if mse_enabled() then mse_violation_en = value[0..0] else ();
  Ok(zero_extend(mse_violation_en))
}

/* 0xFD3 — mse_absolute_bw (RO) */
function clause read_CSR(0xFD3) =
  if mse_enabled() then
    match find_mse_contract(current_ecid) {
      Some(contract) => zero_extend(contract.bw_class),
      None()         => zeros()
    }
  else zeros()

/* 0xFD4 — mse_caps (RO) */
function clause read_CSR(0xFD4) =
  if mse_enabled() then zero_extend(mse_caps_val) else zeros()

/* ------------------------------------------------------------------ */
/* QoS CSRs — stubs (ch13 §6)                                        */
/* ------------------------------------------------------------------ */

/* 0xFCB — qos_domain_count (RO) */
function clause read_CSR(0xFCB) =
  if qos_enabled() then zeros() /* TODO */ else zeros()
