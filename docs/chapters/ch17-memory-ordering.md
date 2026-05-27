# Chapter 17 — Memory Ordering

## 17.1 Overview

CE Suite instructions interact with the RISC-V memory model in three distinct
ways, and each way carries different ordering obligations:

1. **SRAM-only operations.** Bank operations (`ec.ib`, `ec.ob`), lifecycle and
   delegation instructions (`ec.ir`, `ec.oe`, `ec.ig`, `ec.og`, `ec.it`, `ec.ot`,
   `ec.iv`, `ec.ov`), and all Contract instructions (`cp.ir`, `cp.or`, `cp.it`,
   `cp.ot`, `ms.ir`, `ms.or`, `ms.it`, `ms.ot`, `qs.ir`, `qs.or`, `qs.it`,
   `qs.ot`) operate on on-chip SRAM or per-hart hardware registers. They are not
   loads or stores to the RISC-V address space. The RVWMO model is invisible to
   them.

2. **Memory-accessing DMA operations.** `ec.im` and `ec.om` transfer state between
   a bank (SRAM) and the ECS in RAM. They issue loads and stores to the RISC-V
   address space and participate in the RVWMO model as described in §17.3.

3. **Pointer-form operands.** Several instructions accept a pointer-form `rs2`
   (e.g., `ms.ir` pointer form, §9.5; `ms.it` pointer form, §9.5). When the
   pointer flag is set, the instruction performs a load from the address in `rs2`.
   That load participates in the RVWMO model exactly as an ordinary load from the
   same address would.

**Baseline rule.** CE instructions obey RVWMO for any memory accesses they
perform. Instructions that do not touch the RISC-V address space are invisible to
the memory model.

---

## 17.2 Bank Operations: `ec.ib` and `ec.ob`

### 17.2.1 No implicit fence

`ec.ib` writes register state to an on-chip SRAM bank. `ec.ob` reads register
state from an on-chip SRAM bank. Neither instruction issues a load or store to
the RISC-V address space. From the RVWMO model's perspective they are
transparent to the memory ordering machinery.

**Consequences:**

- A context switch via `ec.ib` / `ec.ob` does **not** constitute a memory fence.
- If the outgoing context's stores to shared memory must be visible to another
  hart before the switch, the kernel must issue an explicit `FENCE` before
  `ec.ib`.
- If the incoming context must see stores written by another hart, that
  visibility must be established before `ec.ob` is issued, not after. The
  normative migration fence sequence in §17.5 covers this case.

### 17.2.2 Same-hart context switches

When `ec.ib` and `ec.ob` are used to switch between two ECIDs on the same hart,
no memory fence is required for same-hart ordering. RVWMO's Preserved Program
Order (PPO) guarantees that loads and stores issued after `ec.ob` on the same
hart observe all stores issued before `ec.ib`.

The only exception is cross-hart communication through shared memory: if the
outgoing context has written data that another hart must observe, a standard
RISC-V synchronization sequence (FENCE or AMO with RL/AQ) is required, as it
would be for any cross-hart store.

```
    # Kernel context switch on the same hart. No fence needed for
    # registers or for data shared only with this hart's contexts.
    ec.ib  x0, t0     # save current context; t0 = register mask
    ec.ob  x0, B, t0  # restore B; discard rd
    # B runs from here; sees all prior stores on this hart (PPO)
```

If A's stores to shared memory must be globally visible to another hart after
the switch, issue `FENCE W,W` (or stronger) before `ec.ib`.

### 17.2.3 Bank operations and vault operations (`ec.iv`, `ec.ov`)

`ec.iv` and `ec.ov` seal and unseal banks under hardware-managed encryption.
Like `ec.ib` and `ec.ob`, they operate entirely in on-chip SRAM. They have no
memory ordering implications beyond those of bank operations described above.

---

## 17.3 DMA Operations: `ec.im` and `ec.om`

### 17.3.1 `ec.im` — spill to ECS in RAM

`ec.im rd, rs1, rs2` performs a DMA transfer from the bank associated with ECID
`rs1` to the ECS at `EC[rs1].ecs_ptr` in RAM. The transfer is **synchronous**:
when `ec.im` completes (rd is written), all DMA-written bytes are in the memory
system.

From the RVWMO model's perspective, `ec.im`'s ECS writes are stores issued by
the executing hart. They are subject to the same ordering rules as any other
stores on that hart.

**Same-hart ordering:** Any load or store issued after `ec.im` on the same hart
observes the ECS write in program order. No `FENCE` is required between `ec.im`
and a subsequent read of the ECS on the same hart.

**Cross-hart visibility:** A store issued on Hart H is not globally visible to
other harts until sufficient ordering has been established per RVWMO. If Hart 1
will read the ECS written by `ec.im` on Hart 0, Hart 0 must issue a `FENCE W,W`
after `ec.im` before signaling Hart 1. See §17.5 for the normative sequence.

### 17.3.2 `ec.om` — fill from ECS in RAM

`ec.om rd, rs1, rs2` performs a DMA transfer from the ECS at `EC[rs1].ecs_ptr`
in RAM to the bank for ECID `rs1`. The transfer is **synchronous**: when `ec.om`
completes, the bank holds the state from the ECS.

From the RVWMO model's perspective, `ec.om`'s ECS reads are loads issued by the
executing hart.

**Same-hart ordering:** If the same hart previously wrote the ECS (via `ec.im`),
PPO ensures `ec.om` reads the updated values. No `FENCE` is required.

**Cross-hart safety:** If the ECS was written by a different hart, the reading
hart must ensure it observes the write before issuing `ec.om`. Issue a `FENCE
R,R` (or use an AMO with `.aq`) after receiving the migration signal and before
issuing `ec.om`. See §17.5 for the normative sequence.

### 17.3.3 Pointer-form operands in other instructions

When `ms.ir`, `ms.it`, or any other instruction uses a pointer-form `rs2`
(bit `[XLEN-1]` = 1), the instruction loads the parameter struct from the
address in `rs2`. This load participates in RVWMO as an ordinary load:

- Same-hart ordering: PPO applies. No fence needed.
- Cross-hart sharing of the pointed-to struct: apply standard RISC-V
  release/acquire synchronization (FENCE or AMO with `.rl`/`.aq`) as for any
  shared data.

---

## 17.4 Contract Assignment Instructions

### 17.4.1 What these instructions touch

`ms.ir`, `ms.or`, `ms.it`, `ms.ot`, `cp.ir`, `cp.or`, `cp.it`, `cp.ot`,
`qs.ir`, `qs.or`, `qs.it`, and `qs.ot` update per-hart hardware registers,
EC[e] entries in SRAM, and the chip-global admission control state in the memory
and I/O controllers. They do not issue loads or stores to the RISC-V address
space (unless a pointer-form operand is used; see §17.3.3).

**These instructions carry no implicit memory fence.**

### 17.4.2 Same-hart ordering

Contract assignment instructions execute in program order with surrounding
instructions on the same hart. A Contract assignment followed immediately by a
context switch (`ec.ob`) is guaranteed to take effect for the restored context:
`ms.ir` updates `EC[e].bw_class` and `EC[e].lat_class`; the subsequent `ec.ob`
loads those values into the per-hart memory controller registers at the next CN
slot boundary (§9.5).

No `FENCE` is needed between a Contract assignment instruction and the `ec.ob`
that activates it on the same hart.

### 17.4.3 Hart-locality of Contract assignments

ECIDs are hart-local (charter §3.1). `ms.ir` on Hart H can only target an ECID
allocated on Hart H; it updates Hart H's per-hart memory controller registers
and Hart H's EC[e] entry. No other hart's EC[e] entries are affected.

The chip-global impact — updating the shared bandwidth accounting in the memory
controller — is handled by **hardware-level atomic admission control** (charter
§4.3.3). Software does not need to issue a `FENCE` to make this global update
visible to the memory controller.

### 17.4.4 Cross-hart coordination

Cross-hart ordering for Contract operations arises only during EC migration: the
Contract on Hart 0 is revoked, the context is moved to Hart 1, and a new
Contract is assigned on Hart 1. The ordering requirements are covered by the
normative migration sequence in §17.5. No additional per-instruction fence is
needed for Contract assignment itself.

---

## 17.5 Normative Migration Fence Sequence

The following sequence is **normative** for migrating an EC from Hart 0 to
Hart 1. Software that deviates from this sequence has undefined memory-ordering
behavior.

Notation: registers prefixed `H0_` hold values on Hart 0; registers prefixed
`H1_` on Hart 1. `flag_addr` is the address of a shared word in RAM used as the
migration handoff signal; it must be zero before the sequence begins.

```
    ── Hart 0 (source) ─────────────────────────────────────────────────

    # Step 1. Revoke the EC's resources.
    ms.or  x0, A_ecid            # revoke MSE Contract (if any)
    cp.or  x0, A_ecid            # revoke CPE Contract (if any)
    qs.or  x0, A_ecid, x0        # revoke QoS Contract (if any; 0 = all domains)

    # Step 2. Save A's register state to the bank (if not already done).
    ec.ib  x0, save_mask

    # Step 3. Spill the bank to ECS in RAM.
    ec.im  x0, A_ecid, spill_mask

    # Step 4. Release fence: make the ECS write (and all prior stores by A)
    #         globally visible before signaling Hart 1.
    FENCE  W,W

    # Step 5. Signal Hart 1 via a release store.
    li     t0, 1
    sw     t0, 0(flag_addr)       # plain store; FENCE W,W in step 4 covers it

    # Step 6. Destroy the ECID on Hart 0 (optional; may be done after step 5).
    ec.oe  x0, A_ecid

    ── Hart 1 (destination) ─────────────────────────────────────────────

    # Step 7. Acquire: poll for the migration signal.
.poll:
    lw     t1, 0(flag_addr)
    beqz   t1, .poll

    # Step 8. Acquire fence: ensure Hart 1 observes Hart 0's ECS write and
    #         all prior stores by A before proceeding.
    FENCE  R,R

    # Step 9. Allocate a new ECID on Hart 1 for the migrated EC.
    ec.ir  B_ecid, 1              # 1 = delegating child; 0 = leaf

    # Step 10. Set EC[B_ecid].ecs_ptr to point at the same ECS used on Hart 0.
    #          (Kernel writes EC[B_ecid].ecs_ptr directly — software convention,
    #           not an architectural instruction operand.)

    # Step 11. Fill the bank from ECS.
    ec.om  x0, B_ecid, spill_mask

    # Step 12. Assign resources to the new ECID.
    ms.ir  x0, B_ecid, contract_params
    cp.ir  x0, B_ecid, partition_desc
    qs.ir  x0, B_ecid, qos_params

    # Step 13. Restore the context. B resumes execution.
    ec.ob  x0, B_ecid, restore_mask
```

**Why each fence is placed where it is:**

- **Step 4 (`FENCE W,W`):** All writes before this fence — including A's stores
  to shared data and `ec.im`'s write to the ECS — are globally visible before the
  flag store in step 5. Without this fence, Hart 1 might read a stale ECS or miss
  A's data stores even after observing the flag.

- **Step 8 (`FENCE R,R`):** All reads before this fence (including the `lw` that
  observed the flag=1) are ordered before any reads after it (including `ec.om`'s
  reads from the ECS). This ensures Hart 1's `ec.om` sees the ECS written by
  Hart 0's `ec.im`. Because Hart 0's step-4 FENCE W,W placed A's prior stores
  before the flag write in the global order, Hart 1 also sees A's prior stores
  after this fence.

**AMO alternative.** Steps 5 and 7–8 may be replaced by a release/acquire AMO
pair, which is slightly more efficient on implementations with AMO hardware:

```
    # Hart 0 step 5 (replace sw):
    li     t0, 1
    amoswap.w.rl  x0, t0, (flag_addr)   # release store

    # Hart 1 steps 7–8 (replace poll + FENCE R,R):
.poll:
    amoswap.w.aq  t1, x0, (flag_addr)   # acquire swap (reads old value)
    beqz   t1, .poll                    # retry if flag not yet set
    # FENCE R,R is not needed; .aq on the AMO provides acquire semantics
```

The `FENCE W,W` in step 4 is still required even with the AMO alternative,
because AMO `.rl` only orders the AMO's own store after prior stores; it does not
make prior stores globally visible. The `FENCE W,W` + AMO `.rl` sequence is
required for the full release barrier.

---

## 17.6 Ordering Summary

The table below answers the four questions that §P5 poses for each category of
CE Suite instruction. Column headings:

- **Issues mem access?** — does the instruction load or store to the RISC-V
  address space (excluding pointer-form operands, which are always loads)?
- **Implicit fence?** — does the instruction itself constitute a memory barrier?
- **Fence before (cross-hart)?** — must software issue a fence before this
  instruction when the preceding ECS or data write came from another hart?
- **Fence after (cross-hart)?** — must software issue a fence after this
  instruction so another hart can observe its writes?

| Instruction(s) | Issues mem access? | Implicit fence? | Fence before (cross-hart)? | Fence after (cross-hart)? |
|---|---|---|---|---|
| `ec.ib` | No | None | No¹ | No |
| `ec.ob` | No | None | No² | No |
| `ec.im` | Yes (DMA write to ECS) | None | No³ | `FENCE W,W` |
| `ec.om` | Yes (DMA read from ECS) | None | `FENCE R,R` | No |
| `ec.ir`, `ec.oe`, `ec.ig`, `ec.og`, `ec.it`, `ec.ot` | No | None | No | No |
| `ec.iv`, `ec.ov` | No | None | No | No |
| `ms.ir`, `ms.or`, `ms.it`, `ms.ot` | No⁴ | None | No | No |
| `cp.ir`, `cp.or`, `cp.it`, `cp.ot` | No⁴ | None | No | No |
| `qs.ir`, `qs.or`, `qs.it`, `qs.ot` | No⁴ | None | No | No |

**Footnotes:**

1. No fence required for `ec.ib` itself. However, if A's prior stores must be
   globally visible before migration, issue `FENCE W,W` before `ec.ib` — or
   equivalently, before `ec.im` in the same quiesce-and-spill sequence.
2. For same-hart switches: PPO covers ordering, no fence needed. For cross-hart
   migration: the acquire fence is issued before `ec.om` (step 8 in §17.5),
   which precedes `ec.ob`; no additional fence is needed at `ec.ob` itself.
3. Same-hart: PPO applies, no fence needed. Cross-hart migration: the
   `FENCE W,W` goes **after** `ec.im` (step 4 in §17.5), not before it.
4. Inline form only. For pointer-form operands: the load from the struct address
   participates in RVWMO as an ordinary load. Apply standard release/acquire
   synchronization if the struct is written by another hart.

---

## 17.7 Interaction with the `FENCE.I` Instruction

`FENCE.I` (instruction-fetch fence) synchronizes the instruction stream with
data-side stores. CE Suite instructions do not write to executable memory as a
side effect; no `FENCE.I` is required after any CE instruction.

The exception is kernel code that modifies the ECS — including code pointers or
return addresses — via normal stores before issuing `ec.om` to restore a context
whose restored PC points to that code. In that case, the standard RISC-V
`FENCE.I` requirements apply to the code-modification stores as they would for
any self-modifying code or JIT scenario.

---

## 17.8 Interaction with Supervisor and Hypervisor Modes

Chapter 14 specifies the per-privilege-level access rules for CE instructions.
From a memory ordering perspective, CE instructions issued at different privilege
levels obey the same RVWMO rules as described in this chapter. There is no
special ordering relaxation or strengthening at S-mode, HS-mode, or VS-mode.

During a VM-exit or trap, the supervisor or hypervisor may need to save the
current ECID's context (`ec.ib`, `ec.im`) and restore a different context
(`ec.om`, `ec.ob`). The same ordering rules apply: within the trap handler, all
operations are on the same hart, so PPO covers intra-hart ordering. Cross-hart
ordering (e.g., for a vCPU migrated by the hypervisor) requires the migration
fence sequence in §17.5.

---

[Next: Appendix A — ECID Radix-Tree Algorithms](appendix-a-ecid.md)
