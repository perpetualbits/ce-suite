# Chapter 2 — CME Instruction Set Reference

## Overview

This chapter is the normative reference for all CME instructions. Three rules govern
every instruction in this chapter:

1. **ECID-first operands.** Any instruction that targets a context other than the
   currently running one takes an **ECID number** as its primary operand — never a raw
   pointer, never a bank ID. (Charter §6.2)
2. **Implicit current ECID.** Instructions that operate on the currently running context
   consult `current_ecid` implicitly and omit the ECID operand. (Charter §6.2)
3. **Unified error reporting via `rd`.** Every instruction that can fail writes 0
   (success) or a non-zero error code in `rd`; pass `x0` to discard. Status CSRs
   (`cme_status` etc.) are updated for diagnostics but are not the primary channel.
   Two exceptions carry no `rd`: `ec.ib` (always succeeds or traps) and `ec.oe`
   (always succeeds). Silent ignore is prohibited. (Charter §6.6)

All CME instructions are privileged unless noted otherwise. The mnemonic scheme is
`ec.<dir><target>` (Charter §6.1), where `<dir>` ∈ `{i, o}` and `<target>` is
a letter naming the target or kind. CME uses the subset `{b, m, g, t, r, e, v}`:

  | Letter | Target / kind | Instructions |
  |--------|---------------|--------------|
  | `b`    | bank          | `ec.ib`, `ec.ob` |
  | `m`    | memory (ECS in RAM) | `ec.im`, `ec.om` |
  | `g`    | group (bank assignment) | `ec.ig`, `ec.og` |
  | `t`    | tenant (delegation) | `ec.it`, `ec.ot` |
  | `r`    | resource (ECID lifecycle) | `ec.ir` |
  | `e`    | existence (forced destroy) | `ec.oe` |
  | `v`    | vault (sealed bank) | `ec.iv`, `ec.ov` |

Staging banks (`s`) are hardware-internal; no software instruction targets them directly.

---

## 1. Fast-Path Bank Operations

These instructions operate through SRAM-resident staging banks and constitute the
1–9 cycle context-switch path. They never touch ECS.

### `ec.ib` — Save current context into bank

* **Syntax**: `ec.ib rs1`
  * `rs1`: Register mask — which register groups to save (see §7).
* **Operand notes**: Operates on `current_ecid` implicitly. No explicit ECID argument.
  No `rd`: `ec.ib` always succeeds or raises a trap; no soft failure is possible.
* **Side effects**: Writes state from the active register file into the bank associated
  with `current_ecid`. Updates `cme_status`.
* **Guaranteed cycles**: 1 cycle (full save), up to 3 with selective masking.

### `ec.ob` — Restore context from bank for target ECID

* **Syntax**: `ec.ob rd, rs1, rs2`
  * `rd`: 0 on success; error code if the target ECID is invalid or unbanked.
  * `rs1`: Target ECID number.
  * `rs2`: Register mask — which register groups to restore (see §7).
* **Side effects**: Restores registers from the bank owned by ECID `rs1`. If the PC
  bit is set in the mask, execution jumps to the restored program counter on commit.
* **Guaranteed cycles**: 1–3.

> **Typical switch sequence**: `ec.ib mask` (save current), then
> `ec.ob x0, next_ecid, mask` (restore next, discard result). The transition
> between `current_ecid` and `next_ecid` is complete when `ec.ob` commits.

---

## 2. DMA Spill/Fill Operations

These instructions transfer state between a bank and the ECS in RAM. The memory
address is derived architecturally from `EC[rs1].ecs_ptr` (at offset 0 of the
EC entry) — the instruction does not take a separate pointer operand.

### `ec.im` — Spill bank to memory

* **Syntax**: `ec.im rd, rs1, rs2`
  * `rd`: 0 on success; error code on DMA fault or invalid ECID.
  * `rs1`: Target ECID number.
  * `rs2`: Register mask (which groups to spill).
* **Address**: `EC[rs1].ecs_ptr`. The kernel is responsible for setting this field
  before invoking `ec.im`; it is a software-managed pointer, not an instruction operand.
* **Side effects**: Bank → ECS DMA transfer. The bank may be freed by the kernel
  after completion.
* **Cycles**: 10–128 (DMA bus width dependent).

### `ec.om` — Fill bank from memory

* **Syntax**: `ec.om rd, rs1, rs2`
  * `rd`: 0 on success; error code if no free bank is available or ECID is invalid.
  * `rs1`: Target ECID number.
  * `rs2`: Register mask.
* **Address**: `EC[rs1].ecs_ptr`, same as `ec.im`.
* **Side effects**: ECS → bank DMA transfer. Faults if no free bank is available for
  ECID `rs1`.
* **Cycles**: 10–128.

---

## 3. Bank–Group Assignment

Banks belong to Groups; GroupID equals the owning ECID number (charter §4.1). These
instructions assign or release banks from a given ECID's Group without touching the
ECID itself. The Group maintains no explicit member list; ownership is encoded in each
bank's up-pointer and checked at the bank (the reversal trick).

### `ec.ig` — Assign a free bank to an ECID's Group

* **Syntax**: `ec.ig rd, rs1`
  * `rs1`: Target ECID (GroupID = `rs1`).
  * `rd`: Assigned bank selector, or error code if no bank is available.
* **Side effects**: A bank from the free pool is claimed for ECID `rs1`'s Group.
  The bank's owner field is set to `rs1`. Group has no member list to update.
* **Cycles**: 1–4.

### `ec.og` — Release a bank from an ECID's Group

* **Syntax**: `ec.og rd, rs1`
  * `rs1`: Target ECID (GroupID = `rs1`).
  * `rd`: Count of banks remaining in ECID `rs1`'s Group after release, or error code.
* **Side effects**: One bank is removed from ECID `rs1`'s Group and returned to the
  free pool. Its owner field is cleared.
* **Warning**: Do not release banks from an ECID whose context is currently running or
  actively scheduled. To safely reclaim resources from a tenant, use `ec.ot` or `ec.oe`.
* **Cycles**: 1–4.

---

## 4. Resource Delegation

These instructions delegate Group resources (banks, contracts, child ECIDs) from a
parent ECID to a child, or revoke them. The delegation tree is bounded by depth D ≤ 3
(charter §5).

### `ec.it` — Delegate one bank to a child ECID

* **Syntax**: `ec.it rd, rs1, rs2`
  * `rd`: 0 on success; error code if `rs1` has no banks, privilege violation, or
    invalid ECID.
  * `rs1`: Source ECID — the parent Group from which one bank is taken.
  * `rs2`: Child ECID — the recipient Group.
* **Scope**: Banks only. `ec.it` transfers exactly **one** bank per call;
  the implementation selects which bank from `rs1`'s Group. To delegate N banks,
  call `ec.it` N times. Contract delegation is handled by per-extension instructions:
  `ms.it` for MSE, `qs.it` for QoS (charter §4.3).
* **Side effects**: The selected bank's owner field is updated from `rs1` to `rs2`.
  Requires `rs1` to be a privileged ancestor of `rs2`. Requires `rs2` to have
  `L < D` if the child is to be able to re-delegate the bank further.
* **Cycles**: 1–4.

### `ec.ot` — Revoke resources from a child ECID

* **Syntax**: `ec.ot rd, rs1`
  * `rd`: 0 on success; error code on privilege violation or invalid ECID.
  * `rs1`: Child ECID from which all resources are revoked.
* **Side effects**: All resources in ECID `rs1`'s Group (banks, contracts, child
  ECIDs) are recursively revoked and returned to the parent's Group. ECID `rs1` itself
  remains valid but holds no resources.
* **Cycles**: 1–8 (proportional to subtree size).

---

## 5. ECID Lifecycle

### `ec.ir` — Allocate a child ECID

* **Syntax**: `ec.ir rd, rs1`
  * `rd`: New child ECID number, or 0 if allocation failed.
  * `rs1`:
    * `rs1 = 0` — allocate a **leaf** child: `EC[child].delegation_L = D` (the child
      cannot create further children or delegate resources).
    * `rs1 = 1` — allocate a **delegating** child: `EC[child].delegation_L = parent_L + 1`.
      Fails (rd = error) if `parent_L ≥ D` (parent is already at the cap).
    * `rs1 > 1` — reserved; returns error code `ILLEGAL_FIELD`.
* **Side effects**: Allocates a new ECID slot in the calling context's radix-tree
  prefix. Increments the generation counter for the new slot. The kernel subsequently
  writes `EC[new_ecid].ecs_ptr` and any ECS fields in software — these are not
  instruction operands.
* **Note**: The child's delegation level is always hardware-derived from the parent's
  level and the leaf flag. Software cannot request an arbitrary `L` value.
* **Cycles**: 1–8 (log of radix tree depth).

### `ec.oe` — Forced destroy of ECID and subtree

* **Syntax**: `ec.oe rs1`
  * `rs1`: Target ECID to destroy.
* **Semantics** (per charter §6.5):
  1. Revokes all Contracts held by `rs1` and every descendant in its subtree.
  2. Frees all Banks owned by `rs1` and descendants; returns them to the parent Group.
  3. Marks the radix-tree subtree rooted at `rs1` as free.
  4. Increments the generation counter for every freed `EC[e]` slot.
  5. **Always succeeds.** Zombies and hostile contexts cannot stall reclamation.
* **Privileged**: Yes. The caller must be a parent or privileged ancestor of `rs1`.
* **Cycles**: O(log N) average; proportional to subtree size.

---

## 6. Secure Vault Operations

> **Status — instruction shells only.** `ec.iv` and `ec.ov` are defined as
> instruction placeholders. The cryptographic semantics — key derivation, key
> rotation, attestation, sealed-bank representation, and unsealing authentication
> — are **not yet normative** (charter §8, open item 6). An implementer cannot
> build a secure vault from this chapter alone. Do not rely on vault instruction
> semantics for any security-critical design until they are fully specified.

These operations seal and unseal banks under hardware-managed encryption.

### `ec.iv` — Seal a bank (encrypt)

* **Syntax**: `ec.iv rd, rs1, rs2`
  * `rd`: 0 on success; error code if the bank is already sealed or ECID is invalid.
  * `rs1`: Target ECID whose bank is to be sealed.
  * `rs2`: Register mask.
* **Side effects**: The bank associated with ECID `rs1` is encrypted. Contents are
  inaccessible except in a secure mode that can present the appropriate key.

### `ec.ov` — Unseal a bank (decrypt)

* **Syntax**: `ec.ov rd, rs1, rs2`
  * `rd`: 0 on success; error code if the bank is not sealed or authentication fails.
  * `rs1`: Target ECID whose bank is to be unsealed.
  * `rs2`: Register mask.
* **Side effects**: Decrypts and makes the bank's contents accessible to a secure
  enclave executing as ECID `rs1`.

---

## 7. Register Mask Encoding

The mask is an XLEN-wide value held in one instruction operand register (32 bits
on RV32, 64 bits on RV64). The coarse-grained group bits are:

| Bit | Register Group | Notes                    |
|-----|----------------|--------------------------|
| 0   | GPR            | Integer registers         |
| 1   | FPR            | Floating-point registers  |
| 2   | VEC            | Vector registers (RVV)    |
| 3   | MAT            | Matrix/tensor (future)    |
| 4   | PC             | Program counter           |
| 5   | CSR            | Control/status registers  |
| 6   | SATP           | Address translation       |
| 7   | —              | Reserved                  |

Bits 8–31 are reserved for future GPR subset selection. Bits 32–63 (RV64 only)
are reserved for FPR subsets, CP/CSR subsets, and VMT subsets. See Chapter 0
§0.10 for the full table. On RV32, bits 32–63 are unreachable; all currently
defined coarse-grained groups (bits 0–6) work identically on RV32 and RV64.

If bit 4 (PC) is set in an `ec.ob` mask, execution jumps to the restored program
counter immediately on commit of the instruction.

**Reserved-bit policy.** All bits marked Reserved in the table above must be zero.
If any reserved bit is non-zero, the instruction must return error code
`ILLEGAL_FIELD` (or the implementation-equivalent), or raise an
illegal-operand trap. Silent ignore of reserved bits is prohibited.

---

## 8. CSRs

| CSR Name            | Purpose                                                         |
|---------------------|-----------------------------------------------------------------|
| `current_ecid`      | ECID of the currently executing context (read-only to user mode). |
| `cme_ec_table_base` | Base address of the `EC[e]` array for this hart.                |
| `cme_bank_count`    | Number of banks on this hart (read-only).                       |
| `cme_next_free`     | Implementation hint: next available bank slot.                  |
| `cme_status`        | Result code from the last CME operation.                        |
| `cme_reg_mask`      | Register mask used in the last operation.                       |
| `cme_dma_addr`      | DMA progress address (implementation-defined).                  |
| `cme_seal_key`      | Vault encryption key (privileged).                              |

`EC[e]` entries are located via `cme_ec_table_base + e * stride`, where `stride` is
implementation-defined but fixed per hart. The `ecs_ptr` field is at offset 0 within
each entry (charter §3.2).

---

## 9. Instruction Timing Summary

| Instruction | Fast path (banked) | DMA path | Vault path |
|-------------|-------------------|----------|------------|
| `ec.ib`     | 1–3               | —        | —          |
| `ec.ob`     | 1–3               | —        | —          |
| `ec.im`     | —                 | 10–128   | —          |
| `ec.om`     | —                 | 10–128   | —          |
| `ec.ig`     | 1–4               | —        | —          |
| `ec.og`     | 1–4               | —        | —          |
| `ec.it`     | 1–4               | —        | —          |
| `ec.ot`     | 1–8               | —        | —          |
| `ec.ir`     | 1–8               | —        | —          |
| `ec.oe`     | 1–8               | —        | —          |
| `ec.iv`     | —                 | —        | 8–16       |
| `ec.ov`     | —                 | —        | 8–16       |

---

## 10. Instruction Encoding

> **Proposal encoding.** CE Suite instructions use RISC-V custom-0 opcode space
> (`0001011`, 0x0B) for proposal and prototyping purposes. If CE Suite is ratified
> by RISC-V International, the foundation will assign a permanent opcode allocation
> through the standard opcode-reservation process; the encoding below is subject to
> change at that time. Everything else in this section (R-type format, funct3/funct7
> scheme, register-field conventions) reflects the architectural intent.

### 10.1 Instruction format

All CE Suite instructions are 32-bit R-type:

```
 31      25  24    20  19    15 14  12 11     7 6      0
┌─────────┬────────┬────────┬──────┬────────┬─────────┐
│ funct7  │  rs2   │  rs1   │ fn3  │   rd   │ opcode  │
│  7 bits │ 5 bits │ 5 bits │3 bits│ 5 bits │ 7 bits  │
└─────────┴────────┴────────┴──────┴────────┴─────────┘
```

* **opcode** = `0001011` (custom-0, 0x0B) for all CE Suite instructions.
* **funct3** [14:12] selects the extension (see §10.2).
* **funct7** [31:25] selects the instruction within that extension (see §10.3).
* **rd**, **rs1**, **rs2** are standard 5-bit RISC-V register fields.
* Instructions that carry no `rd` operand encode rd = `00000` (x0).
* Instructions that carry no `rs2` operand encode rs2 = `00000` (x0).

All variable-width operands (register masks, partition descriptors, delegation
descriptors, contract parameters) are passed in registers — no I-type variants
are needed.

### 10.2 Extension selector (funct3)

| funct3 | Extension | Prefix |
|--------|-----------|--------|
| `000`  | CME       | `ec.*` |
| `001`  | CPE       | `cp.*` |
| `010`  | MSE       | `ms.*` |
| `011`  | QoS       | `qs.*` |
| `100`–`111` | Reserved | — |

CPE, MSE, and QoS instruction encoding tables are in chapters 7, 8, and 9
respectively. This section covers CME (funct3 = `000`).

### 10.3 CME instruction encoding (funct3 = `000`)

| funct7      | Mnemonic | rd field      | rs1 field          | rs2 field          |
|-------------|----------|---------------|--------------------|--------------------|
| `0000000`   | `ec.ib`  | `00000` (none)| mask register      | `00000`            |
| `0000001`   | `ec.ob`  | result        | target ECID        | mask register      |
| `0000010`   | `ec.im`  | result        | target ECID        | mask register      |
| `0000011`   | `ec.om`  | result        | target ECID        | mask register      |
| `0000100`   | `ec.ig`  | result        | target ECID        | `00000`            |
| `0000101`   | `ec.og`  | result        | target ECID        | `00000`            |
| `0000110`   | `ec.it`  | result        | source ECID        | child ECID         |
| `0000111`   | `ec.ot`  | result        | child ECID         | `00000`            |
| `0001000`   | `ec.ir`  | new ECID / 0  | leaf flag (0 or 1) | `00000`            |
| `0001001`   | `ec.oe`  | `00000` (none)| target ECID        | `00000`            |
| `0001010`   | `ec.iv`  | result        | target ECID        | mask register      |
| `0001011`   | `ec.ov`  | result        | target ECID        | mask register      |

funct7 values `0001100`–`1111111` (12–127) are reserved for future CME instructions.

### 10.4 Encoding examples

`ec.ib a0` — save current context, mask in a0 (x10 = `01010`):

```
 31      25  24    20  19    15 14  12 11     7 6      0
┌─────────┬────────┬────────┬──────┬────────┬─────────┐
│ 0000000 │ 00000  │ 01010  │ 000  │ 00000  │ 0001011 │
└─────────┴────────┴────────┴──────┴────────┴─────────┘
  ec.ib      rs2=x0   rs1=a0   CME    rd=x0   custom-0
```

`ec.ob x0, a1, a2` — restore ECID in a1 (x11 = `01011`), mask in a2 (x12 = `01100`), discard result:

```
 31      25  24    20  19    15 14  12 11     7 6      0
┌─────────┬────────┬────────┬──────┬────────┬─────────┐
│ 0000001 │ 01100  │ 01011  │ 000  │ 00000  │ 0001011 │
└─────────┴────────┴────────┴──────┴────────┴─────────┘
  ec.ob      rs2=a2   rs1=a1   CME    rd=x0   custom-0
```

---

## 11. Instruction Relationships

| To accomplish…                                        | Use      |
|-------------------------------------------------------|----------|
| Save running context to bank                          | `ec.ib`  |
| Restore a context from its bank (fast switch)         | `ec.ob`  |
| Spill bank state to ECS in RAM                        | `ec.im`  |
| Fill bank state from ECS in RAM                       | `ec.om`  |
| Add a free bank to an ECID's Group                    | `ec.ig`  |
| Return a bank from an ECID's Group to the free pool   | `ec.og`  |
| Delegate one bank to a child ECID (call N times for N banks) | `ec.it`  |
| Revoke all resources from a child ECID                | `ec.ot`  |
| Allocate a new child ECID                             | `ec.ir`  |
| Destroy an ECID and its entire subtree (forced)       | `ec.oe`  |
| Seal a bank under hardware encryption                 | `ec.iv`  |
| Unseal a bank for a secure enclave                    | `ec.ov`  |

**Cooperative teardown vs. forced teardown:**

* Cooperative (tenant responsive): `ec.ot` to reclaim resources, then release the ECID
  with the parent's bookkeeping.
* Forced (zombie, hostile, or failed context): `ec.oe` — always succeeds, full subtree.

---

## 12. Error and Exception Handling

Every CME instruction that can fail writes its result in `rd`: **0** = success,
**non-zero** = error code. Callers who do not need the result write `rd = x0`.
`cme_status` is updated in parallel for diagnostic use (e.g., exception handlers
logging the cause) but is not the primary error channel (charter §6.6).

Any instruction that encounters an invalid ECID (unallocated slot, generation
mismatch, privilege violation, or Group ownership failure) must either:

* Raise a defined trap to the OS or hypervisor, or
* Return a documented error code in `rd`.

Silent ignore is prohibited (charter §6.6).

**Exceptions to the `rd` rule (no soft failure possible):**

* **`ec.ib rs1`** — always succeeds or raises a trap; no `rd`.
* **`ec.oe rs1`** — always succeeds; no `rd`. Forward progress is guaranteed;
  zombies cannot stall reclamation.

---

## 13. Diagrams

### 13.1 Fast-path context switch sequence

```
  ┌───────────────────────────────────────────────────────────────────┐
  │                    FAST-PATH CONTEXT SWITCH                       │
  └───────────────────────────────────────────────────────────────────┘

  State before:
    current_ecid CSR  ── A
    Active reg file   ── [A's GPRs, FPRs, PC, ...]
    Bank[A] (owner A) ── empty / stale
    Bank[B] (owner B) ── [B's GPRs, FPRs, PC, ...]   ← waiting in SRAM

  ─── Step 1: ec.ib mask ─────────────────────────────────────────────
    Active reg file  ──→  Bank[A]         (state saved to SRAM)
    current_ecid unchanged  (still A)
    No rd; always succeeds or traps.

  ─── Step 2: ec.ob x0, B, mask ──────────────────────────────────────
    EC[B].bank_ref   ──→  Bank[B] located
    Bank[B]          ──→  Active reg file  (state restored from SRAM)
    current_ecid     ──→  B               (updated on commit)
    If PC bit set in mask: execution jumps to restored PC immediately.

  State after:
    current_ecid CSR  ── B
    Active reg file   ── [B's GPRs, FPRs, PC, ...]
    Bank[A] (owner A) ── [A's GPRs, FPRs, PC, ...]   ← waiting in SRAM
    Bank[B] (owner B) ── now live in active reg file
```

### 13.2 ECID operand lookup

```
  ┌───────────────────────────────────────────────────────────────────┐
  │             ECID OPERAND LOOKUP  (ec.ob rd, rs1, rs2)            │
  └───────────────────────────────────────────────────────────────────┘

  rs1 ── ECID number e (e.g. 42)
    │
    │  entry_addr = cme_ec_table_base + e × stride
    ▼
  ┌────────────────────────────────────┐
  │  EC[42]  (SRAM-resident entry)     │
  │  offset 0: ecs_ptr  → ECS in RAM  │
  │            generation  = 7        │
  │            delegation_L = 1       │
  │            parent_ecid = 0        │
  │            bank_ref  ─────────────┼──────────────────────────────→ Bank[42]
  └────────────────────────────────────┘                               ┌──────────────┐
                                                                        │ owner  = 42  │
  Ownership check (O(1) via up-pointer):                               │ GPRs         │
    bank.owner == rs1  ?                                               │ FPRs         │
      yes → proceed with restore                                       │ PC, CSRs     │
      no  → rd = CME_ERR_PERMISSION                                    │ SATP, CP     │
                                                                        └──────────────┘
                                                                               │
                                                                               ▼
                                                                        Active reg file
                                                                        (restored per mask)
```

### 13.3 `ec.oe` subtree walk

```
  ┌───────────────────────────────────────────────────────────────────┐
  │              ec.oe SUBTREE WALK  (forced destroy of A)           │
  └───────────────────────────────────────────────────────────────────┘

  Delegation tree before ec.oe A:

            A  (L=0, gen=5)
           / \
          B   C   (L=1, gen=3 each)
         / \
        D   E     (L=2, gen=1 each)

  Walk order — depth-first, leaves first — bounded by D ≤ 3:

    ① D  revoke Contracts → free Banks → gen[D]++ → slot free
    ② E  revoke Contracts → free Banks → gen[E]++ → slot free
    ③ B  revoke Contracts → free Banks → gen[B]++ → slot free
    ④ C  revoke Contracts → free Banks → gen[C]++ → slot free
    ⑤ A  revoke Contracts → free Banks → gen[A]++ → slot free

  Delegation tree after ec.oe A:

            (all five slots freed; Banks/Contracts returned to A's parent)

  Invariants:
    • Always succeeds — a hostile or zombie child cannot stall any step.
    • All freed Banks returned to the parent Group of A.
    • Any stale reference (hart, ECID, old_gen) is detectable:
        EC[e].generation no longer matches → reference is invalid.
    • Detection requires no lock; it is a single load-and-compare.
```

---

[Next: Chapter 3 — Bank, Group, and Delegation Semantics](ch03-bank-group-delegation.md)
