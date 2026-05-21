
---

# Chapter 0 — Fundamental Structure

## 0.1 Scope

This chapter defines the core objects and relationships in the Context Management Extension (CME) architecture.
These definitions are normative: all instruction semantics, delegation rules, and OS integration details in later chapters reference them.

---

## 0.2 Execution Context Identifier (ECID)

An **ECID** denotes a runnable execution context on a hart (thread, process, vCPU, interrupt handler, secure enclave, etc.).
It is the unit the scheduler dispatches and the CME save/restore machinery operates on.

**Identity and namespace.**
An ECID number is a **hart-local** index. Software treats it as an opaque identifier within the hart’s EC namespace.

**Inventory group (1:1 default binding).**
Every ECID E is bound to exactly one **inventory group** `G(E)`. In the caller’s view, `G(E)` appears as group 0. For convenience, the software-visible ID of G(E) equals the ECID number of E. (Types remain distinct: ECID ≠ Group.)

**Required/derived state.**
The ECID record contains (unless noted otherwise, fields are hardware-private and not software-readable):


* **ECID number** (integer, hart-local, NOTE: *not* separately kept in its data set, because it is the index of the ECID array this ECID)
* **Pointer to Execution Context Structure (ECS)** (RV32: 32b, RV64: 64b).
* **Delegation Level L** (2 bits, 0 ≤ L ≤ D ≤ 3, where D is hardware delegation limit, unchangeble by E, L < D implies delegation instructions available, L = D implies delegation instructions not available. See §0.7)
* **Parent_ECID_Cached** (the ECID that owns G(E)'s parent group. Set/updated by hardware on delegation/revocation. Not software-readable)
* **Group ID** (identifier for the bound group which we call its Inventory, NOTE: *not* separately kept in its data set because exactly one group is always bound to an ECID. So Group ID == ECID number)
Explicitly:
* **Up-pointer** (to parent group that owns this ECID; ECID 0 points to group 0; not accessible to E, only to E's parent)
* **Primary non-VMT Bank ID** (optional; set if at least one non-VMT bank is in its Inventory Group)
* **Primary VMT Bank ID** (optional; set if at least one VMT bank is in its Inventory Group)
* **Contracts** (MSE, QoS, CPE) directly bound to the ECID

---

## 0.3 Group

A **Group** is a logical container for resources owned by an ECID.

Resources in a Group:

* **ECIDs** (to bind or delegate resources to, stored in up-pointer 
* **Banks** (context state storage units)
* **Contracts**:

  * **CPE** — Cache Partitioning Extension
  * **MSE** — Memory Scheduling Extension
  * **QoS** — I/O Quality of Service Extension
* Possibly other CME-compatible resources in future revisions

**Up-pointer**:
Each Bank or Contract has a pointer to the Group it belongs to.

---

## 0.4 Banks

A **Bank** is a hardware-resident storage area for a complete or partial set of architectural state.

There are non-VMT and VMT banks. There are typically more non-VMT than VMT banks.

Non-VMT Bank contents include:

* General-purpose registers (GPRs)
* Floating-point registers (FPRs)
* Control and status registers (CSRs)
* Cache Partition configuration (CP)
* Supervisor Address Translation and Protection register (SATP)
Note:
  For RV64 a Non-VMT bank is 1KB:
  * ECID nr and ECID reserved space: 8 bytes (takes spot of x0)
  * GPRs = 31x64 bits = 248 bytes (x1..x31); slot for x0 used by ECID nr and reserved space
  * FPRs = 32x64 bits = 256 bytes
  * CP   = 8 bytes
  * SATP = 8 bytes
  * CSRs and Bank reserved space = 1024 - 2x256 - 2x8 = 496 bytes

  For RV32 a Non-VMT bank is 512 bytes:
  * ECID nr and ECID reserved space: 4 bytes (takes spot of x0)
  * GPRS = 31x32 bits = 124 bytes (x1..x31); slot for x0 used by ECID nr and other
  * FPRs = 32x32 bits = 128 bytes
  * CP   = 4 bytes
  * SATP = 4 bytes
  * CSRs and Bank reserved space = 512 - 2x128 - 2x4 = 248 bytes

VMT Bank contents include: 

* Vector/Matrix/Tensor register files (VMT)
* If not shared between VMT instructions, any Vector, Matrix and Tensor banks are separate
* Size perspective: For 256-bit vector registers, a bank is 1KB like RV64 non-VMT banks, each doubling in bit-size doubles the bank size

The first Bank in an ECID’s Group is bound to that ECID (Primary Bank).
Bank masks are used by the OS in saving and restoring 

---

## 0.5 Contracts

Purpose of Contract:

* A contract is a formal allocation of a slice of a global resource — either:
  * MSE: memory bandwidth/latency
  * QoS: I/O or NoC bandwidth, latency, priority
* Contracts are for CPU-wide resources, not local per-hart such as context banks and cache partitions

---

## 0.6 Execution Context Structure (ECS)

The **ECS** is a memory-resident data structure describing an ECID’s execution context.
It contains:

1. **Header** (first 4–8 bytes): ECID number (for use in CME instructions)
2. ECS metadata (privilege level, flags, scheduling info)
3. Pointers to saved state in banks or memory
4. Contract descriptors
5. OS/hypervisor-private fields

---

## 0.7 Delegation Rules (WITH Groups)

### L < D (can delegate)

* ECID may place resources from its Group into a new Group and bind that Group to a child ECID.
* ECID may bind individual resources directly to child ECIDs.
* Can split contracts and pass derived contracts to child ECIDs.

### L = D (cannot delegate)

* ECID may bind unbound banks directly to ECIDs in its Group (max 1 per target ECID).
* Can split contracts, but derived contracts are bound for self-use only.

---

## 0.8 CME Instruction Operand Conventions

* **ec.ob** / **ec.om**:

  * `rs1` = ECID number (target ECID. rs1 is a child ECID in the caller's namespace. Hardware must check current_ecid == rs1.Parent_ECID_Cached; otherwise trap. On success, hardware restores from rs1.primary_nonvmt_bank_id according to the mask; if PC bit is set, it jumps. ec.ob with rs1 == current_ecid is a NOP)
  * `rs2` = context restore mask (bits for FPR, CP, SATP, VMT, GPR subsets)
  **ec.ob**: If the target ECID has no Primary non-VMT bank, the instruction traps.
  **ec.om**: Because this is DMA-latency bound, hardware may perform additional validation (e.g., prefix/parent checks via group tables) before accepting the operation.
* **ec.ib** / **ec.im**:

  * ECID number implicit (current ECID)
  * ECS pointer known from ECID
  * If bound to a bank, Primary Bank ID is implicit
  * `rs1`/`rs2` unused unless future revisions assign meaning

---

## 0.9 Context Restore Mask

`rs2` is a 64-bit mask; proposed allocation:

* Bits 0–31: individual GPR subsets
* Bits 32–47: FPR subsets
* Bits 48–51: CP, SATP, and other CSRs
* Bits 52–59: VMT subsets
* Bits 60–63: Reserved for future expansion

Exact bit meanings to be finalized in Chapter 2.

---

## 0.10 OS Integration Note

Linux (and other OSes) must set `rs2` bits according to which state must be valid immediately after context restore.
Cases requiring CP restore should be enumerated in Chapter 5, e.g.:

* After context migration between harts
* After delegation/revocation events affecting cache partitioning

---


