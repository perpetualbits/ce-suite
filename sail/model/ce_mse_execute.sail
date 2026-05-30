// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — MSE execute functions
 * Spec reference: ch09 §9.5–§9.6 (ms.ir/ms.or)
 *
 * Cluster D resolution (charter §4.5):
 *   - bw_class / lat_class are pre-flattened on the 0–255 absolute scale
 *   - The chip-global admission check is axiomatised (Sail v1 scope; P8)
 *   - Telescoping (ms.it / ms.ot) is deferred to Sail-C
 */

/* ------------------------------------------------------------------ */
/* Admission axiom (Sail v1 scope decision; sail/work-items.md P8)    */
/* ------------------------------------------------------------------ */

/* The chip-global accounting (whether bandwidth is available) is a
 * black-box function. Implementations enforce; Sail does not model.
 * Always returns true in the standalone build (prelude stub). */
val admit_mse_contract : (ecid_t, bw_class_t, lat_class_t) -> bool

/* ------------------------------------------------------------------ */
/* mse_status + rd write helpers (ch09 §9.5, ch13 §5.6)              */
/* ------------------------------------------------------------------ */

function mse_ret_err(rd : regidx, code : mse_error_t) -> ExecutionResult = {
  mse_status = code;
  X(rd) = mse_err_to_xlenbits(code);
  RETIRE_SUCCESS
}

function mse_ret_ok(rd : regidx, data : xlenbits) -> ExecutionResult = {
  mse_status = MSE_OK;
  X(rd) = data;
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ms.ir — Assign a memory Contract to an ECID (ch09 §9.5)           */
/*                                                                     */
/* Syntax: ms.ir rd, rs1, rs2                                         */
/*   rs1 = target ECID                                                */
/*   rs2 = Contract descriptor (inline form for Sail v1)              */
/*   rd  = 0 on success; error code on failure                        */
/* ------------------------------------------------------------------ */

function clause execute(CE_MSIR(rd, rs1, rs2)) = {
  if ~(mse_enabled()) then Illegal_Instruction()
  else {
    let ecid_value : ecid_t   = truncate(X(rs1), 16);
    let descriptor : xlenbits = X(rs2);

    /* Inline-form and reserved-bits check: bits above 15 must be 0.
     * Covers pointer-form rejection (bit xlen-1=1) and reserved bits. */
    if zero_extend(descriptor[15..0]) != descriptor then
      mse_ret_err(rd, MSE_ERR_DESCRIPTOR_RESERVED)
    else {
      let bw_class  : bw_class_t  = descriptor[7..0];
      let lat_class : lat_class_t = descriptor[15..8];

      /* Validate ECID slot */
      match lookup_ec(ecid_value) {
        None() => mse_ret_err(rd, MSE_ERR_INVALID_ECID),
        Some(entry) => {
          if ~(entry.allocated) then
            mse_ret_err(rd, MSE_ERR_INVALID_ECID)
          else {
            /* Cap check (charter §4.5.6): skip when mse_bw_cap == 0 (no cap) */
            let cap_ok : bool =
              (mse_bw_cap == 0x00) |
              (unsigned(mse_bw_sum) + unsigned(bw_class) <= unsigned(mse_bw_cap));
            if ~(cap_ok) then
              mse_ret_err(rd, MSE_ERR_ADMISSION_DENIED)
            else if ~(admit_mse_contract(ecid_value, bw_class, lat_class)) then
              mse_ret_err(rd, MSE_ERR_ADMISSION_DENIED)
            else {
              /* Find a free slot in the contract pool */
              var found     : bool    = false;
              var free_slot : bits(6) = zeros();
              foreach (i from 0 to 63) {
                if ~(found) & ~(mse_contract_pool[i].valid) then {
                  found     = true;
                  free_slot = to_bits(6, i)
                }
              };
              if ~(found) then
                mse_ret_err(rd, MSE_ERR_ADMISSION_DENIED)
              else {
                let free_idx = unsigned(free_slot);
                foreach (i from 0 to 63) {
                  if i == free_idx then
                    mse_contract_pool[i] = struct {
                      owner_ecid = ecid_value,
                      bw_class   = bw_class,
                      lat_class  = lat_class,
                      precision  = 0x0,
                      valid      = true
                    }
                };
                mse_bw_sum = mse_bw_sum + bw_class;
                mse_ret_ok(rd, zeros())
              }
            }
          }
        }
      }
    }
  }
}

/* ------------------------------------------------------------------ */
/* ms.or — Revoke the memory Contract from an ECID (ch09 §9.6)       */
/*                                                                     */
/* Syntax: ms.or rd, rs1                                              */
/*   rs1 = target ECID                                                */
/*   rd  = 0 on success; error code on failure                        */
/* ------------------------------------------------------------------ */

function clause execute(CE_MSOR(rd, rs1)) = {
  if ~(mse_enabled()) then Illegal_Instruction()
  else {
    let ecid_value : ecid_t = truncate(X(rs1), 16);

    /* Validate ECID slot */
    match lookup_ec(ecid_value) {
      None() => mse_ret_err(rd, MSE_ERR_INVALID_ECID),
      Some(entry) => {
        if ~(entry.allocated) then
          mse_ret_err(rd, MSE_ERR_INVALID_ECID)
        else {
          /* Find the Contract owned by this ECID */
          var found      : bool       = false;
          var found_slot : bits(6)    = zeros();
          var found_bw   : bw_class_t = 0x00;
          foreach (i from 0 to 63) {
            if ~(found) & mse_contract_pool[i].valid &
               (mse_contract_pool[i].owner_ecid == ecid_value)
            then {
              found      = true;
              found_slot = to_bits(6, i);
              found_bw   = mse_contract_pool[i].bw_class
            }
          };
          if ~(found) then
            mse_ret_err(rd, MSE_ERR_NO_CONTRACT)
          else {
            let found_idx = unsigned(found_slot);
            foreach (i from 0 to 63) {
              if i == found_idx then
                mse_contract_pool[i] = MSE_Contract_default
            };
            mse_bw_sum = sub_bits(mse_bw_sum, found_bw);
            mse_ret_ok(rd, zeros())
          }
        }
      }
    }
  }
}
