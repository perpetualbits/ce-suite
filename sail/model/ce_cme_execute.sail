// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — CME execute functions
 * Spec reference: ch03 §3.1–§3.6, ch15 §15.5.1
 *
 * Sail v1 scope:
 *   FULL:  ec.ib, ec.ob, ec.it, ec.ot  (fast-path core + bank delegation)
 *   STUB:  ec.im, ec.om, ec.ig, ec.og, ec.ir, ec.oe
 *   ALL instructions now update cme_status[7:0] via cme_ret_err/cme_ret_ok (S21)
 *   DECODE-ONLY: ec.iv, ec.ov (execute semantics are implementation-defined
 *                for the encryption algorithm; key management deferred)
 *
 * NOTE: CE_BankFault should generate a CE trap (cause 16, CE_EXC_BANK_FAULT)
 * in the full implementation. For Sail v1 it returns Illegal_Instruction()
 * as a stub; proper trap wiring is deferred to S5/S6.
 */

/* ------------------------------------------------------------------ */
/* cme_status + rd write helpers (ch03 §3.12, ch13 §3.6)             */
/*                                                                     */
/* Every CME instruction updates cme_status[7:0] in parallel with rd. */
/* Use cme_ret_err for error/success codes, cme_ret_ok for success    */
/* paths that return data (bank slot index, ECID number, count).      */
/* ------------------------------------------------------------------ */

function cme_ret_err(rd : regidx, code : cme_error_t) -> ExecutionResult = {
  cme_status[7..0] = code;
  X(rd) = cme_err_to_xlenbits(code);
  RETIRE_SUCCESS
}

function cme_ret_ok(rd : regidx, data : xlenbits) -> ExecutionResult = {
  cme_status[7..0] = CME_OK;
  X(rd) = data;
  RETIRE_SUCCESS
}

/* ------------------------------------------------------------------ */
/* ec.ib — Save current context into bank (ch03 §3.1)                */
/*                                                                     */
/* Syntax: ec.ib rd, rs1                                              */
/*   rs1 = register mask (x0 activates dirty-save mode)              */
/*   rd  = bank slot index written (success-path; traps on error)     */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIB(rd, rs1)) = {
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    /* Determine effective mask: dirty-save mode when rs1 == x0 */
    let mask : regmask_t =
      if encdec_reg(rs1) == 0b00000  /* x0 encoding */
      then zero_extend(dirty_bitmap)   /* dirty-save: use dirty-group bitmap */
      else X(rs1);                     /* explicit mask */

    /* Find the bank owned by current_ecid */
    match find_bank(current_ecid) {
      None() =>
        /* No bank resident — stub: Illegal_Instruction (should be CE trap) */
        Illegal_Instruction(),
      Some(slot) => {
        let idx = unsigned(truncate(slot, 3));
        if bank_pool[idx].sealed then
          /* Sealed bank — stub: Illegal_Instruction (should be CE trap) */
          Illegal_Instruction()
        else {
          /* Save register groups indicated by mask (ch03 §3.7) */
          let b = bank_pool[idx];

          var gs : vector(31, dec, bits(64)) = b.gprs;
          if mask[0] == 0b1 then  /* bit 0: GPR group (x1..x31) */
            foreach (i from 1 to 31) {
              gs[i-1] = zero_extend(X(encdec_reg(to_bits(5, i))))
            };

          var fs : vector(32, dec, bits(64)) = b.fprs;
          if mask[1] == 0b1 then  /* bit 1: FPR group (f0..f31) */
            foreach (i from 0 to 31) {
              fs[i] = zero_extend(F(Fregidx(to_bits(5, i))))
            };

          /* bits 2 (VEC), 3 (MAT), 5 (CSR): TODO in later Sail versions */

          let new_pc : bits(64) =
            if mask[4] == 0b1 then zero_extend(get_arch_pc())  /* bit 4: PC */
            else b.pc;

          let new_satp : xlenbits =
            if mask[6] == 0b1 then satp   /* bit 6: SATP */
            else b.satp_val;

          bank_pool[idx] = { b with
            owner_ecid = current_ecid,
            valid      = true,
            mask       = mask,
            gprs       = gs,
            fprs       = fs,
            pc         = new_pc,
            satp_val   = new_satp
          };

          /* Clear dirty bits for saved groups */
          dirty_bitmap = dirty_bitmap & ~(truncate(mask, 8));

          cme_reg_mask = mask;
          /* rd = bank slot index (0-based within owning Group) */
          cme_ret_ok(rd, zero_extend(slot))
        }
      }
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
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    /* rs1 packs (expected_generation | target_ecid):
     *   bits 15:0  = ECID slot index  (ecid_t)
     *   bits 23:16 = expected generation counter (generation_t)
     * Software holds the (ECID, generation) pair from ec.ir and passes
     * it here; hardware validates against EC[e].generation (ch00 §0.2). */
    let rs1_val      = X(rs1);
    let target_ecid  : ecid_t      = truncate(rs1_val, 16);
    let expected_gen : generation_t = rs1_val[23..16];
    let mask         : regmask_t   = X(rs2);

    /* Look up EC[target_ecid] */
    match lookup_ec(target_ecid) {
      None() => cme_ret_err(rd, CME_ERR_INVALID_ECID),
      Some(entry) => {
        /* Fail if unallocated or generation mismatch (stale reference) */
        if ~(entry.allocated) | (entry.generation != expected_gen) then
          cme_ret_err(rd, CME_ERR_INVALID_ECID)
        else {
          /* Find the bank owned by target_ecid */
          match find_bank(target_ecid) {
            None() => cme_ret_err(rd, CME_ERR_NO_BANK),
            Some(slot) => {
              let idx = unsigned(truncate(slot, 3));

              /* Refuse sealed banks (ch03 §3.6, ec.ob sealed-bank rule) */
              if bank_pool[idx].sealed then
                cme_ret_err(rd, CME_ERR_ALREADY_SEALED)
              else {
                /* Restore register groups indicated by mask (ch03 §3.7) */
                let b = bank_pool[idx];

                if mask[0] == 0b1 then  /* bit 0: GPR group (x1..x31) */
                  foreach (i from 1 to 31) {
                    X(encdec_reg(to_bits(5, i))) = truncate(b.gprs[i-1], xlen)
                  };

                if mask[1] == 0b1 then  /* bit 1: FPR group (f0..f31) */
                  foreach (i from 0 to 31) {
                    F(Fregidx(to_bits(5, i))) = truncate(b.fprs[i], flen)
                  };

                /* bits 2 (VEC), 3 (MAT), 5 (CSR): TODO in later Sail versions */

                /* D6 resolution (charter §6.8, v0.19): SATP restore via ec.ob
                   with bit 6 set performs TLB invalidation if SATP differs;
                   skipped if unchanged (permitted optimization).
                   Scope: full flush (D6.1 unresolved; refinement is mechanical). */
                if mask[6] == 0b1 then {  /* bit 6: SATP */
                  let old_satp = satp;
                  let new_satp = b.satp_val;
                  satp = new_satp;
                  if old_satp != new_satp then
                    flush_TLB(None(), None())
                };

                if mask[4] == 0b1 then  /* bit 4: PC — redirect execution on commit */
                  set_next_pc(truncate(b.pc, xlen));

                /* Update current_ecid atomically on commit */
                current_ecid = target_ecid;

                /* Clear dirty bitmap for restored groups (ch00 §0.3) */
                dirty_bitmap = dirty_bitmap & ~(truncate(mask, 8));

                cme_reg_mask = mask;
                cme_ret_err(rd, CME_OK)
              }
            }
          }
        }
      }
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.im — Spill bank to ECS in RAM (ch03 §3.2)                      */
/*                                                                     */
/* ECS memory layout (implementation-defined, Sail v1):               */
/*   ecs_ptr +   0 : GPRs x1..x31 (31 × 8 bytes = 248 bytes)         */
/*   ecs_ptr + 248 : FPRs f0..f31 (32 × 8 bytes = 256 bytes)         */
/*   ecs_ptr + 504 : PC  (8 bytes)                                    */
/*   ecs_ptr + 512 : mask (8 bytes)                                   */
/* The bank remains allocated after spill; ec.og releases it.         */
/* ch17 §17.3.1: caller issues FENCE W,W after ec.im.                */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIM(rd, rs1, rs2)) = {
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    let target_ecid : ecid_t   = truncate(X(rs1), 16);
    let mask        : regmask_t = X(rs2);

    match lookup_ec(target_ecid) {
      None() => cme_ret_err(rd, CME_ERR_INVALID_ECID),
      Some(entry) => {
        if ~(entry.allocated) then
          cme_ret_err(rd, CME_ERR_INVALID_ECID)
        else {
          match find_bank(target_ecid) {
            None() => cme_ret_err(rd, CME_ERR_NO_BANK),
            Some(slot) => {
              let bank    = bank_pool[unsigned(truncate(slot, 3))];
              let ecs_ptr = entry.ecs_ptr;

              if mask[0] == 0b1 then  /* GPR group (ch03 §3.7 bit 0) */
                foreach (i from 1 to 31) {
                  let _ : bool = write_ram(Write_plain,
                    Physaddr(ecs_ptr + zero_extend(to_bits(32, (i - 1) * 8))),
                    8, bank.gprs[i-1], default_meta);
                  ()
                };

              if mask[1] == 0b1 then  /* FPR group (bit 1) */
                foreach (i from 0 to 31) {
                  let _ : bool = write_ram(Write_plain,
                    Physaddr(ecs_ptr + zero_extend(to_bits(32, 248 + i * 8))),
                    8, bank.fprs[i], default_meta);
                  ()
                };

              /* bits 2 (VEC), 3 (MAT), 5 (CSR), 6 (SATP): TODO */

              if mask[4] == 0b1 then {  /* PC group (bit 4) */
                let _ : bool = write_ram(Write_plain,
                  Physaddr(ecs_ptr + zero_extend(to_bits(32, 504))),
                  8, bank.pc, default_meta);
                ()
              };

              /* Write the effective mask so ec.om can restore the same groups */
              let _ : bool = write_ram(Write_plain,
                Physaddr(ecs_ptr + zero_extend(to_bits(32, 512))),
                8, zero_extend(mask), default_meta);

              cme_ret_err(rd, CME_OK)
            }
          }
        }
      }
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.om — Fill bank from ECS in RAM (ch03 §3.2)                     */
/*                                                                     */
/* Reads register groups from EC[rs1].ecs_ptr using the same ECS     */
/* layout defined for ec.im (S15). Claims a free bank slot.          */
/* ch17 §17.3.2: caller issues FENCE R,R before ec.om on cross-hart. */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECOM(rd, rs1, rs2)) = {
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    let target_ecid : ecid_t   = truncate(X(rs1), 16);
    let mask        : regmask_t = X(rs2);

    match lookup_ec(target_ecid) {
      None() => cme_ret_err(rd, CME_ERR_INVALID_ECID),
      Some(entry) => {
        if ~(entry.allocated) then
          cme_ret_err(rd, CME_ERR_INVALID_ECID)
        else {
          let ecs_ptr = entry.ecs_ptr;

          /* Claim a free bank slot (ec.om acts like ec.ig + fill) */
          var found     : bool = false;
          var free_slot : nat  = 0;
          foreach (i from 0 to 7) {
            if ~(found) & ~(bank_pool[i].valid) then {
              found     = true;
              free_slot = i
            }
          };

          if ~(found) then
            cme_ret_err(rd, CME_ERR_NO_BANK)
          else {
            /* Read register groups from ECS (mirrors ec.im layout) */
            var new_gprs : vector(31, dec, bits(64)) = Bank_default.gprs;
            if mask[0] == 0b1 then  /* GPR group */
              foreach (i from 1 to 31) {
                let (v, _) = read_ram(Read_plain,
                  Physaddr(ecs_ptr + zero_extend(to_bits(32, (i - 1) * 8))),
                  8, false);
                new_gprs[i-1] = v
              };

            var new_fprs : vector(32, dec, bits(64)) = Bank_default.fprs;
            if mask[1] == 0b1 then  /* FPR group */
              foreach (i from 0 to 31) {
                let (v, _) = read_ram(Read_plain,
                  Physaddr(ecs_ptr + zero_extend(to_bits(32, 248 + i * 8))),
                  8, false);
                new_fprs[i] = v
              };

            /* bits 2 (VEC), 3 (MAT), 5 (CSR), 6 (SATP): TODO */

            let new_pc : bits(64) =
              if mask[4] == 0b1 then {  /* PC group */
                let (v, _) = read_ram(Read_plain,
                  Physaddr(ecs_ptr + zero_extend(to_bits(32, 504))),
                  8, false);
                v
              } else Bank_default.pc;

            /* Populate the free bank slot */
            foreach (i from 0 to 7) {
              if i == free_slot then
                bank_pool[i] = { Bank_default with
                  owner_ecid = target_ecid,
                  valid      = true,
                  gprs       = new_gprs,
                  fprs       = new_fprs,
                  pc         = new_pc,
                  mask       = mask
                }
            };

            cme_ret_err(rd, CME_OK)
          }
        }
      }
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.ig — Assign a free bank to an ECID's Group (ch03 §3.3)         */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIG(rd, rs1)) = {
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    let target_ecid : ecid_t = truncate(X(rs1), 16);

    /* Find the first free bank slot */
    var found     : bool    = false;
    var free_slot : bits(3) = zeros();
    foreach (i from 0 to 7) {
      if ~(found) & ~(bank_pool[i].valid) then {
        found     = true;
        free_slot = to_bits(3, i)
      }
    };

    if ~(found) then
      cme_ret_err(rd, CME_ERR_NO_BANK)
    else {
      let free_idx = unsigned(free_slot);
      /* Claim the free slot for target_ecid */
      foreach (i from 0 to 7) {
        if i == free_idx then
          bank_pool[i] = { bank_pool[i] with
            owner_ecid = target_ecid,
            valid      = true
          }
      };
      cme_ret_ok(rd, zero_extend(free_slot))
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.og — Release a bank from an ECID's Group (ch03 §3.3)           */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECOG(rd, rs1)) = {
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    let target_ecid : ecid_t = truncate(X(rs1), 16);

    match find_bank(target_ecid) {
      None() => cme_ret_err(rd, CME_ERR_NO_BANK),
      Some(slot) => {
        let slot_idx = unsigned(truncate(slot, 3));

        /* Release the bank back to the free pool */
        foreach (i from 0 to 7) {
          if i == slot_idx then
            bank_pool[i] = { bank_pool[i] with
              owner_ecid = zeros(),
              valid      = false
            }
        };

        /* Count banks remaining in the Group after release (0..7 fits in bits(4)) */
        var remaining : bits(4) = zeros();
        foreach (i from 0 to 7) {
          if bank_pool[i].valid & (bank_pool[i].owner_ecid == target_ecid) then
            remaining = remaining + 0x1
        };

        cme_ret_ok(rd, zero_extend(remaining))
      }
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.it — Delegate one bank to a child ECID (ch03 §3.4)             */
/*                                                                     */
/* Syntax: ec.it rd, rs1, rs2                                         */
/*   rs1 = source (parent) ECID — Group that donates a bank           */
/*   rs2 = destination (child) ECID — Group that receives the bank    */
/*   rd  = 0 on success; error code on failure                        */
/*                                                                     */
/* Caller permission check (current_ecid must be ancestor of rs1)    */
/* is deferred to S22 (ce_ctrl privilege model integration).          */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIT(rd, rs1, rs2)) = {
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    let parent_ecid : ecid_t = truncate(X(rs1), 16);
    let child_ecid  : ecid_t = truncate(X(rs2), 16);

    match lookup_ec(parent_ecid) {
      None() => cme_ret_err(rd, CME_ERR_INVALID_ECID),
      Some(parent_entry) => {
        if ~(parent_entry.allocated) then
          cme_ret_err(rd, CME_ERR_INVALID_ECID)
        else {
          match lookup_ec(child_ecid) {
            None() => cme_ret_err(rd, CME_ERR_INVALID_ECID),
            Some(child_entry) => {
              if ~(child_entry.allocated) then
                cme_ret_err(rd, CME_ERR_INVALID_ECID)
              else {
                /* rs1 must be a proper ancestor of rs2 (ch03 §3.4) */
                if ~(is_ancestor(parent_ecid, child_ecid)) then
                  cme_ret_err(rd, CME_ERR_PERMISSION)
                else {
                  match find_bank(parent_ecid) {
                    None() => cme_ret_err(rd, CME_ERR_NO_BANK),
                    Some(slot) => {
                      let slot_idx = unsigned(truncate(slot, 3));
                      /* Transfer ownership from parent to child */
                      foreach (i from 0 to 7) {
                        if i == slot_idx then
                          bank_pool[i] = { bank_pool[i] with owner_ecid = child_ecid }
                      };
                      cme_ret_err(rd, CME_OK)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.ot — Revoke resources from a child ECID (ch03 §3.4)            */
/*                                                                     */
/* Syntax: ec.ot rd, rs1                                              */
/*   rs1 = child ECID whose banks are reclaimed                       */
/*   rd  = 0 on success; error code on invalid ECID                   */
/*                                                                     */
/* All banks owned by rs1's Group are returned to rs1's parent Group. */
/* rs1 itself remains allocated but holds no resources.               */
/* Contract revocation and recursive child ECID handling are out of   */
/* Sail v1 scope (axiomatised as no-op).                              */
/* Caller permission check deferred to S22.                           */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECOT(rd, rs1)) = {
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    let target_ecid : ecid_t = truncate(X(rs1), 16);

    match lookup_ec(target_ecid) {
      None() => cme_ret_err(rd, CME_ERR_INVALID_ECID),
      Some(entry) => {
        if ~(entry.allocated) then
          cme_ret_err(rd, CME_ERR_INVALID_ECID)
        else {
          let parent_ecid = entry.parent_ecid;
          /* Transfer all banks owned by target_ecid to its parent Group */
          foreach (i from 0 to 7) {
            if bank_pool[i].valid & (bank_pool[i].owner_ecid == target_ecid) then
              bank_pool[i] = { bank_pool[i] with owner_ecid = parent_ecid }
          };
          cme_ret_err(rd, CME_OK)
        }
      }
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.ir — Allocate a child ECID (ch03 §3.5)                         */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIR(rd, rs1)) = {
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    let flag = X(rs1);

    /* rs1 > 1: reserved bits set → ILLEGAL_FIELD (ch03 §3.5) */
    if unsigned(flag) > 1 then
      cme_ret_err(rd, CME_ERR_ILLEGAL_FIELD)
    else {
      let is_leaf = (flag[0] == 0b0);  /* flag=0 → leaf, flag=1 → delegating */

      /* Look up parent (current context) */
      match lookup_ec(current_ecid) {
        None() => cme_ret_ok(rd, zeros()),  /* internal error: current_ecid invalid */
        Some(parent_entry) => {
          let parent_L_val = unsigned(parent_entry.delegation_L);
          let D_val        = unsigned(cme_del_cap_D);

          /* Delegating child: parent must be below the depth cap */
          if ~(is_leaf) & (parent_L_val >= D_val) then
            cme_ret_err(rd, CME_ERR_CAP_DEPTH)
          else {
            /* Child delegation level (ch00 §0.8) */
            let child_L : del_level_t =
              if is_leaf then cme_del_cap_D           /* leaf → pinned at D */
              else to_bits(2, parent_L_val + 1);      /* delegating → L+1 */

            /* Find the first free slot; skip slot 0 (root/null) */
            var found      : bool    = false;
            var child_slot : bits(6) = zeros();  /* 64 slots → 6 bits */
            foreach (i from 1 to 63) {
              if ~(found) & ~(ec_array[i].allocated) then {
                found      = true;
                child_slot = to_bits(6, i)
              }
            };

            if ~(found) then
              cme_ret_ok(rd, zeros())  /* no free slots: rd = 0, cme_status = OK */
            else {
              let child_idx = unsigned(child_slot);
              /* Write new entry; foreach satisfies the bounds checker */
              foreach (i from 1 to 63) {
                if i == child_idx then
                  ec_array[i] = { EC_entry_default with
                    generation   = ec_array[i].generation + 0x01,
                    delegation_L = child_L,
                    parent_ecid  = current_ecid,
                    allocated    = true
                  }
              };
              cme_ret_ok(rd, zero_extend(child_slot))
            }
          }
        }
      }
    }
  }
}

/* ------------------------------------------------------------------ */
/* ec.oe — Forced destroy of ECID and subtree (ch03 §3.5)            */
/*                                                                     */
/* Always succeeds (ch03 §3.5, invariant 1).                         */
/* Permission check (caller must be ancestor) deferred to S22.        */
/* Contract revocation is a no-op in Sail v1 (CPE/MSE/QoS stubs).   */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECOE(rd, rs1)) = {
  if ~(cme_authorized()) then Illegal_Instruction()
  else {
    let target_ecid = truncate(X(rs1), 16);

    /* ---- Phase 1: mark the target and all descendants ---- */
    /* mark[i] = true iff ec_array slot i is in the subtree  */
    var marked : vector(64, dec, bool) = vector_init(false);

    /* Mark the target slot (if in range and allocated) */
    foreach (j from 0 to 63) {
      if j == unsigned(target_ecid) & ec_array[j].allocated then
        marked[j] = true
    };

    /* Three propagation sweeps cover trees up to D=3 levels deep.
     * Each sweep marks any allocated node whose parent is already marked. */
    foreach (sweep from 0 to 2) {
      foreach (i from 0 to 63) {
        if ec_array[i].allocated & ~(marked[i]) then
          foreach (j from 0 to 63) {
            if j == unsigned(ec_array[i].parent_ecid) & marked[j] then
              marked[i] = true
          }
      }
    };

    /* ---- Phase 2: free every marked slot ---- */
    /* Leaves and parents alike — order does not matter for the free
     * since we already have the full mark set.  Depth-first semantics
     * hold because every node in the subtree is freed atomically.   */
    var freed_count : bits(7) = zeros();  /* 0..64 freed ECIDs, 7 bits sufficient */
    foreach (i from 0 to 63) {
      if marked[i] then {
        /* Free all banks owned by this ECID */
        foreach (b from 0 to 7) {
          if bank_pool[b].valid & (bank_pool[b].owner_ecid == to_bits(16, i)) then
            bank_pool[b] = { bank_pool[b] with valid = false, owner_ecid = zeros() }
        };
        /* Increment generation (ABA safety) and mark slot free */
        ec_array[i] = { ec_array[i] with
          generation = ec_array[i].generation + 0x01,
          allocated  = false
        };
        freed_count = freed_count + to_bits(7, 1)
      }
    };

    cme_ret_ok(rd, zero_extend(freed_count))
  }
}

/* ------------------------------------------------------------------ */
/* ec.iv / ec.ov — Vault seal/unseal (ch03 §3.6)                     */
/*                                                                     */
/* Execute semantics are out of Sail v1 scope: the encryption         */
/* algorithm is implementation-defined. Decode is modelled above;     */
/* execute raises Illegal_Instruction until a future version defines  */
/* the cryptographic semantics.                                       */
/* ------------------------------------------------------------------ */

function clause execute(CE_ECIV(rd, rs1, rs2)) = Illegal_Instruction()

function clause execute(CE_ECOV(rd, rs1, rs2)) = Illegal_Instruction()
