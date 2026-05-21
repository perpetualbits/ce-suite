# CME Instruction Set Reference

## Overview

This chapter describes the complete instruction set for the Context Management Extension (CME), including all supported context, group, ECID, migration, and sealing operations. It includes syntax, operand types, cycle estimates, and side effects. All CME instructions are privileged unless noted otherwise.

---

## 1. Context Bank Operations

### `ec.ib` — Save current execution context into context bank

* **Type**: System, user/privileged (configurable)
* **Syntax**: `ec.ib rd, rs1`

  * `rd`: Destination register for bank ID
  * `rs1`: Mask specifying which register groups to save
* **Side Effects**:

  * Overwrites bank contents
  * Updates CSRs: `cme_status`, `cme_last_bank`, `cme_reg_mask`
* **Guaranteed Cycles**:

  * 1 cycle (banked), up to 3 if selective masking

### `ec.ob` — Restore execution context from bank

* **Type**: System, user/privileged (configurable)
* **Syntax**: `ec.ob rd, rs1`

  * `rd`: Bank ID to restore from
  * `rs1`: Mask (which register groups to restore)
* **Side Effects**:

  * Restores registers (selective if masked)
  * May jump if PC bit is set in mask

---

## 2. DMA (Memory) Spill/Fill Operations

### `ec.im` — Save bank contents to memory

* **Type**: System, privileged
* **Syntax**: `ec.im rs1, rs2, imm`

  * `rs1`: Bank ID
  * `rs2`: Memory pointer
  * `imm`: Mask
* **Side Effects**:

  * Bank → memory transfer
  * Bank can be freed afterward
* **Cycles**: Depends on size and DMA bus width (≤ 128 cycles typical)

### `ec.om` — Load context from memory into bank

* **Type**: System, privileged
* **Syntax**: `ec.om rd, rs1, imm`

  * `rd`: Destination bank
  * `rs1`: Memory pointer
  * `imm`: Mask
* **Side Effects**:

  * Memory → bank transfer
  * May fault if no bank available

---

## 3. Group Management

### `ec.ig` — Create or extend group

* **Syntax**: `ec.ig rd, rs1`

  * `rd`: Returns new group ID (as seen from current context)
  * `rs1`:

    * `0` (x0): Create a new group using the first free EC-local bank from group 0
    * `<existing group ID>`: Add the next free EC-local bank from group 0 to the given group
* **Side Effects**:

  * Moves the selected EC-local bank to the group
  * Returns group ID in `rd`
  * Updates group/bank mapping
  * If no free banks, returns error code in `rd`

### `ec.og` — Remove bank from group

* **Syntax**: `ec.og rd, rs1`

  * `rd`: Returns the number of banks left in the group after removal
  * `rs1`: Group ID (from EC-local perspective)
* **Side Effects**:

  * Removes the *last-added* EC-local bank from the group and returns it to group 0
  * If `rd` is 0, the group is now disbanded (no members remain)
  * Hardware updates mapping and invalidates group if empty

**Group membership and visibility:**

* When an EC puts one of its banks into a group, it knows exactly which EC-local bank was moved, as *only EC-local group 0* banks may be added.
* The OS is responsible for tracking which EC-local bank numbers have been assigned to each group (local bookkeeping).
* Hardware maintains only the bank→group mapping; groups do not keep member lists.

**Warning:**

* OS/hypervisor developers: Do not remove banks from groups actively in use by tenants! This may disrupt VMs, processes, or enclaves using that group. To safely evict tenants, use `ec.ot` (revoke group) or `ec.or` (revoke ECID).

### `ec.it` — Assign group to tenant (ECID)

* **Syntax**: `ec.it rs1, rs2`

  * `rs1`: Group ID
  * `rs2`: Tenant ECID
* **Side Effects**:

  * Transfers group to tenant, updates group visibility and group/bank mappings

### `ec.ot` — Revoke group from tenant (ECID)

* **Syntax**: `ec.ot rs1`

  * `rs1`: Group ID
* **Side Effects**:

  * Recursively revokes group and all banks/subgroups from tenant
  * Triggers forced cleanup and group removal

---

## 4. ECID Lifecycle Operations

### `ec.ir` — Allocate/request new ECID (prefix delegation)

* **Syntax**: `ec.ir rd, rs1, rs2`

  * `rd`: New ECID (or 0 if none available)
  * `rs1`: Pointer to ECS in RAM
  * `rs2`: Prefix length (relative to parent ECID)
* **Semantics**:

  * Allocates child ECID; subdelegation possible if prefix >1; hardware enforces limits

### `ec.or` — Revoke/destroy ECID

* **Syntax**: `ec.or rs1`

  * `rs1`: ECID to revoke (must be child/prefix of caller)
* **Semantics**:

  * Recursively reclaims all contracts, groups, banks, subordinate ECIDs/resources

---

## 5. Secure Enclave / Vault Ops

### `ec.iv` — Seal context (encrypt/lock)

* **Syntax**: `ec.iv rs1, rs2`

  * `rs1`: Bank ID
  * `rs2`: Mask
* **Side Effects**:

  * Encrypts contents, accessible only in secure mode

### `ec.ov` — Unseal context

* **Syntax**: `ec.ov rd, rs1`

  * `rd`: Destination bank
  * `rs1`: Mask
* **Side Effects**:

  * Decrypts/unlocks for secure enclave

---

## 6. Register Mask Encoding

| Bit | Register Group | Description              |
| --- | -------------- | ------------------------ |
| 0   | GPR            | Integer registers        |
| 1   | FPR            | Floating-point registers |
| 2   | VEC            | Vector registers (RVV)   |
| 3   | MAT            | Matrix/tensor (future)   |
| 4   | PC             | Program counter          |
| 5   | CSR            | Control/status registers |
| 6   | SATP           | Address translation      |
| 7   | Reserved       |                          |

---

## 7. CSRs

| CSR Name         | Purpose                      |
| ---------------- | ---------------------------- |
| cme\_bank\_count | Number of banks (readonly)   |
| cme\_next\_free  | Next available bank          |
| cme\_status      | Last operation status/error  |
| cme\_reg\_mask   | Mask used in last operation  |
| cme\_group\_map  | Group and ECID mapping table |
| cme\_dma\_addr   | DMA pointer                  |
| cme\_seal\_key   | Vault encryption key         |

---

## 8. Instruction Timing Summary

| Instruction | Cycles (banked) | DMA Path | Secure Path |
| ----------- | --------------- | -------- | ----------- |
| ec.ib/ob    | 1–3             | –        | –           |
| ec.im/om    | –               | 10–128   | –           |
| ec.ig/og    | 1–4             | –        | –           |
| ec.it/ot    | 1–4 (recursive) | –        | –           |
| ec.iv/ov    | –               | –        | 8–16        |
| ec.ir/or    | 1–8 (log tree)  | –        | –           |

---

## 9. Instruction Encoding Sketch

* **Opcode**: 8 bits (e.g., `1101_xxxx`)
* **Function**: 4 bits (operation category)
* **Operands**: rd, rs1, rs2
* **Mask/Imm**: 8 bits
* **Address**: 32–64 bits

---

## 10. Instruction Orthogonality and Relationships

CME’s hierarchical resource management results in **overlapping but orthogonal** effects for group and ECID instructions:

* **`ec.ig`**: Adds EC-local banks to a group (creates group if new). Only EC-local group 0 banks can be added; group is created by first addition. Cannot add banks to tenant-owned groups.
* **`ec.og`**: Removes the *last-added* EC-local bank from a group, returns to group 0. If group is emptied, group is disbanded. Cannot remove banks from tenant-owned groups (unless forcibly revoked).
* **`ec.it`**: Assigns group to a tenant (new ECID).
* **`ec.ot`**: Revokes group from tenant (recursively removes all banks/subgroups; group may be deleted if emptied).
* **`ec.ir`**: Allocates new ECID with prefix; allows delegation and hierarchical contracts.
* **`ec.or`**: Revokes/destroys ECID and all subordinate resources (includes groups, banks, subordinate ECIDs).
* **`ec.iv/ov`**: Secure enclave/vault seal/unseal.

**Best practice:**

* Use `ec.ig`/`ec.og` for resource setup and teardown in cooperative (non-tenant) code.
* Use `ec.it`/`ec.ot` for tenant management (VMs, enclaves).
* Use `ec.or` for full forced cleanup (zombies, hostile or failed guests).

---

## 11. Error and Exception Handling

* All illegal or privilege-violating operations trap to the OS/hypervisor.
* Forced destruction (`ec.or`) always succeeds for the parent; OS must handle cleanup.
* Error codes returned in rd or status CSRs.

---

## 12. Placeholder: Diagrams

* **Instruction Flow Diagram:**
  ECID creation/delegation, forced destruction, group and resource mapping.
* **Radix Tree Example:**
  Visual of ECID prefixes, delegation, and recursive cleanup.

---

[Next: Hardware Microarchitecture Overview](Chapter3-Bank_Group_and_Delegation_Semantics.md)


