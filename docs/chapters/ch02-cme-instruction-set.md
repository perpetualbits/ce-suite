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
a letter naming the target or kind. CME uses the following subset:

  | Letter | Target / kind |
  |--------|---------------|
  | `b`    | bank          |
  | `m`    | memory (ECS in RAM) |
  | `s`    | stream / staging bank |
  | `v`    | vault (sealed bank) |
  | `e`    | existence     |

(`g`=group may be added if group-level instructions are defined; `r`, `t`, and
other pool letters do not apply to CME.)

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

### `ec.it` — Delegate resources to a child ECID

* **Syntax**: `ec.it rd, rs1, rs2`
  * `rd`: 0 on success; error code on privilege violation or invalid ECID.
  * `rs1`: Source ECID — the parent whose Group resources are transferred.
  * `rs2`: Child ECID — the recipient.
* **Side effects**: Selected resources from ECID `rs1`'s Group are transferred to
  ECID `rs2`'s Group. Updates owner up-pointers on all affected resources. Requires
  `rs2` to have delegation level `L < D` for the child to be able to re-delegate.
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
  * `rs1`: Maximum delegation depth permitted for the child (must satisfy
    `child_L = parent_L + 1 ≤ D`; pass 0 to prevent further delegation).
* **Side effects**: Allocates a new ECID slot in the calling context's radix-tree
  prefix. Increments the generation counter for the new slot. The kernel subsequently
  writes `EC[new_ecid].ecs_ptr` and any ECS fields in software — these are not
  instruction operands.
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

These operations seal and unseal banks under hardware-managed encryption. Key
derivation, attestation, and rotation are deferred open items (charter §8.7).

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

## 10. Instruction Encoding Sketch

* **Opcode**: 8 bits
* **Function**: 4 bits (operation category per §6.1 naming scheme)
* **Operands**: rd, rs1, rs2
* **Mask/Imm**: 8 bits

Full binary encoding is deferred to the formal opcode assignment stage.

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
| Delegate Group resources to a child ECID              | `ec.it`  |
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

## 13. Placeholder: Diagrams

* **Context switch sequence**: `ec.ib` → `ec.ob`, showing `current_ecid` transition.
* **ECID operand lookup**: how `ec.ob rd, rs1, rs2` locates the bank via `EC[rs1]`.
* **`ec.oe` subtree walk**: radix-tree traversal and generation-counter increments.

---

[Next: Chapter 3 — Bank, Group, and Delegation Semantics](ch03-bank-group-delegation.md)
