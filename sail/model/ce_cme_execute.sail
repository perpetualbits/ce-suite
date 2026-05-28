// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — CME execute functions
 * Spec reference: ch03 §3.1–§3.6, ch15 §15.5.1
 *
 * Sail v1 scope:
 *   FULL:  ec.ib, ec.ob  (the fast-path core)
 *   STUB:  ec.im, ec.om, ec.ig, ec.og, ec.it, ec.ot, ec.ir, ec.oe
 *   DECODE-ONLY: ec.iv, ec.ov (execute semantics are implementation-defined
 *                for the encryption algorithm; key management deferred)
 */

/* ------------------------------------------------------------------ */
/* Helper: check CME is enabled; raise illegal instruction if not     */
/* ------------------------------------------------------------------ */

function check_cme_enabled() -> unit = {
  if ~(cme_enabled()) then raise(IllegalInstruction())
}

/* ------------------------------------------------------------------ */
/* ec.ib — Save current context into bank (ch03 §3.1)                */
/*                                                                     */
/* Syntax: ec.ib rd, rs1                                              */
/*   rs1 = register mask (x0 activates dirty-save mode)              */
/*   rd  = bank slot index written (success-path; traps on error)     */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIB(rd, rs1)) = {
  check_cme_enabled();

  /* Determine effective mask: dirty-save mode when rs1 == x0 */
  let mask : regmask_t =
    if rs1 == 0b00000  /* x0 encoding */
    then zero_extend(dirty_bitmap)   /* dirty-save: use dirty-group bitmap */
    else X(rs1);                     /* explicit mask */

  /* Find the bank owned by current_ecid */
  match find_bank(current_ecid) {
    None() => {
      /* No bank resident — trap (ec.ib always succeeds or traps) */
      raise(CE_BankFault())
    },
    Some(slot) => {
      let idx = unsigned(truncate(slot, 3));
      /* Check bank is not sealed (sealed bank cannot be saved over) */
      if bank_pool[idx].sealed then raise(CE_BankFault());

      /* Save register state into the bank.
       * Physical register save is abstracted here; a complete model
       * would copy each register group in the mask. */
      bank_pool[idx] = { bank_pool[idx] with
        owner_ecid = current_ecid,
        valid      = true,
        mask       = mask
      };

      /* Clear dirty bits for saved groups */
      dirty_bitmap = dirty_bitmap & ~(truncate(mask, 8));

      /* Update cme_reg_mask and cme_status */
      cme_reg_mask = mask;
      cme_status[7..0] = CME_OK;

      /* rd = bank slot index (0-based within owning Group) */
      X(rd) = zero_extend(slot);
      RETIRE_SUCCESS
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.ob — Restore context from bank for target ECID (ch03 §3.1)     */
/*                                                                     */
/* Syntax: ec.ob rd, rs1, rs2                                         */
/*   rs1 = target ECID number                                         */
/*   rs2 = register mask                                              */
/*   rd  = 0 on success; error code on failure                        */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECOB(rd, rs1, rs2)) = {
  check_cme_enabled();

  let target_ecid : ecid_t = truncate(X(rs1), 16);
  let mask        : regmask_t = X(rs2);

  /* Look up EC[target_ecid] */
  match lookup_ec(target_ecid) {
    None() => {
      X(rd) = cme_err_to_xlenbits(CME_ERR_INVALID_ECID);
      RETIRE_SUCCESS
    },
    Some(entry) => {
      if ~(entry.allocated) then {
        X(rd) = cme_err_to_xlenbits(CME_ERR_INVALID_ECID);
        RETIRE_SUCCESS
      } else {
        /* Find the bank owned by target_ecid */
        match find_bank(target_ecid) {
          None() => {
            X(rd) = cme_err_to_xlenbits(CME_ERR_NO_BANK);
            RETIRE_SUCCESS
          },
          Some(slot) => {
            let idx = unsigned(truncate(slot, 3));

            /* Refuse sealed banks (ch03 §3.6, ec.ob sealed-bank rule) */
            if bank_pool[idx].sealed then {
              X(rd) = cme_err_to_xlenbits(CME_ERR_ALREADY_SEALED);
              RETIRE_SUCCESS
            } else {
              /* Restore register state from bank.
               * Physical restore is abstracted; a complete model would
               * write each register group in the mask from bank storage. */

              /* Update current_ecid atomically on commit */
              current_ecid = target_ecid;

              /* Clear dirty bitmap for restored groups (ch00 §0.3) */
              dirty_bitmap = dirty_bitmap & ~(truncate(mask, 8));

              /* Update status registers */
              cme_reg_mask = mask;
              cme_status[7..0] = CME_OK;

              X(rd) = cme_err_to_xlenbits(CME_OK);
              RETIRE_SUCCESS
            }
          }
        }
      }
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.im — Spill bank to ECS in RAM (ch03 §3.2) — STUB               */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIM(rd, rs1, rs2)) = {
  check_cme_enabled();
  /* TODO: DMA bank→ECS transfer; involves memory writes (RVWMO store) */
  X(rd) = cme_err_to_xlenbits(CME_OK);  /* stub: always succeeds */
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ec.om — Fill bank from ECS in RAM (ch03 §3.2) — STUB              */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECOM(rd, rs1, rs2)) = {
  check_cme_enabled();
  /* TODO: DMA ECS→bank transfer; involves memory reads (RVWMO load) */
  X(rd) = cme_err_to_xlenbits(CME_OK);  /* stub: always succeeds */
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ec.ig — Assign a free bank to an ECID's Group (ch03 §3.3) — STUB  */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIG(rd, rs1)) = {
  check_cme_enabled();
  /* TODO: allocate from free bank pool; CME_ERR_NO_BANK if empty */
  X(rd) = cme_err_to_xlenbits(CME_OK);
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ec.og — Release a bank from an ECID's Group (ch03 §3.3) — STUB    */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECOG(rd, rs1)) = {
  check_cme_enabled();
  /* TODO: return bank to free pool */
  X(rd) = cme_err_to_xlenbits(CME_OK);
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ec.it — Delegate one bank to a child ECID (ch03 §3.4) — STUB      */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIT(rd, rs1, rs2)) = {
  check_cme_enabled();
  /* TODO: transfer bank ownership from rs1's Group to rs2's Group */
  X(rd) = cme_err_to_xlenbits(CME_OK);
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ec.ot — Revoke resources from a child ECID (ch03 §3.4) — STUB     */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECOT(rd, rs1)) = {
  check_cme_enabled();
  /* TODO: recursive resource revocation */
  X(rd) = cme_err_to_xlenbits(CME_OK);
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ec.ir — Allocate a child ECID (ch03 §3.5) — STUB                  */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIR(rd, rs1)) = {
  check_cme_enabled();
  /* TODO: allocate from radix tree; CME_ERR_CAP_DEPTH if L >= D */
  X(rd) = cme_err_to_xlenbits(CME_OK);  /* stub: returns 0 (failure) */
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ec.oe — Forced destroy of ECID and subtree (ch03 §3.5) — STUB     */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECOE(rd, rs1)) = {
  check_cme_enabled();
  /* TODO: depth-first subtree walk; always succeeds; rd = ECIDs freed */
  X(rd) = zero_extend(0x0001 : bits(16));  /* stub: freed 1 ECID */
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ec.iv / ec.ov — Vault seal/unseal (ch03 §3.6)                     */
/*                                                                     */
/* Execute semantics are out of Sail v1 scope: the encryption         */
/* algorithm is implementation-defined. Decode is modelled above;     */
/* execute raises IllegalInstruction until a future version defines   */
/* the cryptographic semantics.                                       */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIV(rd, rs1, rs2)) = {
  check_cme_enabled();
  /* Vault execute semantics: implementation-defined (encryption algorithm
   * not specified in v1.0). Model as unimplemented for now. */
  raise(IllegalInstruction())
}

function clause execute(CE_ECOV(rd, rs1, rs2)) = {
  check_cme_enabled();
  raise(IllegalInstruction())
}
