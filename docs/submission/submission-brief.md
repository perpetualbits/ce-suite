# CE Suite — RISC-V ISA Extension Proposal: Opcode and Name Allocation Request

**Version:** 0.1 (draft)
**Date:** 2026-05-26
**Submitter:** Roland Nagtegaal — perpetualbits@gmail.com
**Specification repository:** *(to be supplied)*

---

## 1. Summary of requests

This brief requests three formal allocations from RISC-V International in
support of the CE Suite extension proposal:

1. **ISA string name registration** for five extension names:
   `Xce`, `Xcecme`, `Xcecpe`, `Xcemse`, `Xceqos` (currently provisional
   `X`-prefix names; formal registration and final name form subject to
   RISC-V International conventions).

2. **Opcode space allocation** — or confirmation that RISC-V custom-0
   (`0001011`) is the appropriate encoding vehicle for the proposal stage.
   All 24 CE Suite instructions currently use custom-0 as a placeholder.

3. **CSR address allocation** for 31 new CSRs currently occupying two
   provisional custom ranges: `0x7C0–0x7CE` (M-mode RW) and `0xFC0–0xFCF`
   (M-mode RO), plus three individually-placed CSRs at `0x7CF`, `0x6C0`,
   and `0xFD0`.

None of these requests alter the instruction semantics or the architectural
model, which are fully specified. The allocations are the sole remaining
process gate before a formal submission package is prepared.

---

## 2. What is CE Suite

The **Context Extensions (CE) Suite** is a set of five coordinated RISC-V
extensions that together deliver hardware-guaranteed determinism for shared
SoCs — without sacrificing throughput on average-case workloads.

Throughout this document, *context* means *execution context* (EC): any
schedulable unit of work that a kernel, hypervisor, or firmware dispatches
to a hardware thread. This includes OS threads, processes, vCPUs running
guest operating systems, interrupt handlers, container tasks, and secure
enclaves. CE Suite treats all of these uniformly — the hardware machinery for
saving register state, partitioning caches, and arbitrating memory bandwidth
is identical regardless of what kind of scheduled work is running. An
*Execution Context Identifier* (ECID) is the hardware-managed token that
names one such context while it is bound to a specific hart.

| Extension | Name | Purpose |
|-----------|------|---------|
| **CME** | Context Management Extension | Hardware-resident context banks per hart; 1–9 cycle save/restore; delegation and revocation of banks to child contexts |
| **CPE** | Cache Partitioning Extension | Per-hart partitioning of L1 and L2-private caches per ECID |
| **MSE** | Memory Scheduling Extension | Deterministic DRAM arbitration with alternating best-effort and contract time slots; per-EC bandwidth and latency classes |
| **QoS** | I/O Quality-of-Service Extension | The same arbitration philosophy as MSE, applied to the NoC, DMA, and peripheral interconnect |
| **ECID substrate** | *(shared foundation)* | Hardware-managed per-hart execution context identifiers, group/contract ownership model, and delegation tree — the identity layer that all four extensions share |

The target outcome is provable Worst-Case Execution Time and certifiability
for ASIL D, FDA Class III, and DO-178C workloads, at an estimated 5–15%
transistor overhead per core (dominated by bank SRAM; see §6).

CE Suite is specified for both RV32 and RV64.

---

## 3. Instruction inventory

All 24 CE Suite instructions are R-type. The full inventory by extension is
given below, with the funct7 value used in the proposed encoding.

### 3.1 CME — Context Management Extension (funct3 = `000`)

| funct7    | Mnemonic | Description |
|-----------|----------|-------------|
| `0000000` | `ec.ib`  | Save running context to on-chip bank |
| `0000001` | `ec.ob`  | Restore context from bank (fast switch) |
| `0000010` | `ec.im`  | Save context to ECS in RAM (synchronous DMA) |
| `0000011` | `ec.om`  | Restore context from ECS in RAM (synchronous DMA) |
| `0000100` | `ec.ig`  | Assign a free bank to an ECID's group |
| `0000101` | `ec.og`  | Release a bank from an ECID's group |
| `0000110` | `ec.it`  | Delegate one bank to a child ECID |
| `0000111` | `ec.ot`  | Revoke a delegated bank from a child ECID |
| `0001000` | `ec.ir`  | Allocate a new child ECID |
| `0001001` | `ec.oe`  | Forced destroy: remove ECID and its entire delegation subtree |
| `0001010` | `ec.iv`  | Seal a bank (vault — cryptographically protected) |
| `0001011` | `ec.ov`  | Unseal a bank (vault) |

funct7 values 12–127 are reserved for future CME instructions.

### 3.2 CPE — Cache Partitioning Extension (funct3 = `001`)

| funct7    | Mnemonic | Description |
|-----------|----------|-------------|
| `0000000` | `cp.ir`  | Assign a cache partition to an ECID |
| `0000001` | `cp.or`  | Revoke a cache partition from an ECID |
| `0000010` | `cp.it`  | Delegate a CPE contract to a child ECID |
| `0000011` | `cp.ot`  | Revoke a CPE contract from a child ECID |

funct7 values 4–127 are reserved for future CPE instructions.

### 3.3 MSE — Memory Scheduling Extension (funct3 = `010`)

| funct7    | Mnemonic | Description |
|-----------|----------|-------------|
| `0000000` | `ms.ir`  | Assign a memory bandwidth/latency contract to an ECID |
| `0000001` | `ms.or`  | Revoke a memory contract from an ECID |
| `0000010` | `ms.it`  | Delegate an MSE contract to a child ECID |
| `0000011` | `ms.ot`  | Revoke a delegated MSE contract from a child ECID |

funct7 values 4–127 are reserved for future MSE instructions.

### 3.4 QoS — I/O Quality-of-Service Extension (funct3 = `011`)

| funct7    | Mnemonic | Description |
|-----------|----------|-------------|
| `0000000` | `qs.ir`  | Assign an I/O bandwidth/latency contract to an ECID |
| `0000001` | `qs.or`  | Revoke an I/O contract from an ECID (rs2 = domain selector) |
| `0000010` | `qs.it`  | Delegate a QoS contract to a child ECID |
| `0000011` | `qs.ot`  | Revoke a delegated QoS contract from a child ECID (rs2 = domain) |

funct7 values 4–127 are reserved for future QoS instructions.

---

## 4. Binary encoding scheme

### 4.1 Format

All 24 instructions share a single R-type encoding:

```
 31      25  24    20  19    15 14  12 11     7 6      0
┌─────────┬────────┬────────┬──────┬────────┬─────────┐
│  funct7 │  rs2   │  rs1   │ fn3  │   rd   │ opcode  │
└─────────┴────────┴────────┴──────┴────────┴─────────┘
```

- **opcode** [6:0]: `0001011` (custom-0, 0x0B) — provisional placeholder.
- **funct3** [14:12]: selects the extension (see §4.2).
- **funct7** [31:25]: selects the instruction within that extension (see §3).
- **rd, rs1, rs2**: per-instruction operands as documented in §3. Fields
  unused by a given instruction are encoded as `00000`.

### 4.2 Extension selector (funct3)

| funct3 | Extension | Notes |
|--------|-----------|-------|
| `000`  | CME       | 12 instructions assigned; 116 funct7 slots reserved |
| `001`  | CPE       | 4 instructions assigned; 124 funct7 slots reserved |
| `010`  | MSE       | 4 instructions assigned; 124 funct7 slots reserved |
| `011`  | QoS       | 4 instructions assigned; 124 funct7 slots reserved |
| `100`–`111` | *(unassigned)* | Reserved for future CE Suite extensions |

### 4.3 Encoding example

`ec.ib a0` — save current context, register mask in a0:

```
 31      25  24    20  19    15 14  12 11     7 6      0
┌─────────┬────────┬────────┬──────┬────────┬─────────┐
│ 0000000 │ 00000  │ 01010  │ 000  │ 00000  │ 0001011 │
└─────────┴────────┴────────┴──────┴────────┴─────────┘
  ec.ib      rs2=x0   rs1=a0   CME    rd=x0   custom-0
```

### 4.4 Opcode space consumed

Within one major opcode (custom-0 = 7 bits):

- funct3 values consumed: 4 of 8 (50%).
- funct7 values consumed per extension: CME uses 12/128; CPE/MSE/QoS each
  use 4/128. Total assigned: 24/512 R-type slots within the chosen opcode.

A single custom opcode accommodates all four extensions with substantial
headroom for future additions. If RISC-V International prefers a different
opcode, the entire encoding table migrates mechanically — no semantic
changes are required.

---

## 5. ISA string names

### 5.1 Proposed names (provisional)

| ISA string | Meaning | Notes |
|------------|---------|-------|
| `Xce`      | CE Suite umbrella | Implies all four extensions |
| `Xcecme`   | CME only | |
| `Xcecpe`   | CPE only | |
| `Xcemse`   | MSE only | |
| `Xceqos`   | QoS only | |

The `X` prefix denotes a non-standard (vendor) extension under current
RISC-V convention. If CE Suite is ratified, RISC-V International would
assign formal names following the convention in use at that time (e.g.,
`Z`-prefixed subextensions, `S`-prefixed supervisor extensions, or a new
single-letter allocation).

All spec chapters, device-tree `riscv,isa` strings, and the discovery CSR
(`ce_present`, §5.2 of this brief) use the provisional `X` names and note
explicitly that they are subject to change upon ratification.

### 5.2 Discovery CSR (`ce_present`)

CE Suite defines one discovery CSR (`ce_present`, provisional address
`0xFD0`) that M-mode firmware writes at boot to report which extensions
are present. Bits 0–4 correspond to CME, CPE, MSE, QoS, and the H-extension
CE integration. The ISA string names and this CSR's bit layout are
consistent: registering the final ISA string names updates both places
mechanically.

---

## 6. CSR allocation

### 6.1 Scope

CE Suite introduces 31 new per-hart CSRs. "Per-hart" means each hart holds
its own instance; no CE Suite CSR is shared across harts.

### 6.2 Provisional address assignments

| Range | Class | Access | Count | Contents |
|-------|-------|--------|-------|----------|
| 0x7C0–0x7CE | M-mode custom RW | RW | 15 | CME RW CSRs (base, next-free, control) and CPE/MSE/QoS RW CSRs |
| 0xFC0–0xFCF | M-mode custom RO | RO | 16 | CE RO capability/status CSRs (current_ecid, del_cap, bank counts, status) |
| 0x7CF | M-mode custom RW | RW | 1 | `cme_priv_ctl` — S/HS-mode CE enable |
| 0x6C0 | HS-mode custom RW | RW | 1 | `hcme_ctrl` — VS-mode CE enable (requires H extension) |
| 0xFD0 | M-mode custom RO | RO | 1 | `ce_present` — extension discovery |

**Total: 31 CSRs.**

All addresses are provisional. The spec notes this explicitly throughout
Chapter 13 and references that formal allocation is required before
submission.

### 6.3 Distribution by extension

| Extension | RW CSRs | RO CSRs | Total |
|-----------|---------|---------|-------|
| CME | 5 | 6 | 11 |
| CPE | 1 | 1 | 2 |
| MSE | 4 | 3 | 7 |
| QoS | 5 | 3 | 8 |
| Cross-extension | 2 (priv control) | 1 (discovery) | 3 |
| **Total** | **17** | **14** | **31** |

---

## 7. Implementer cost

### 7.1 Area overhead

The 5–15% per-core area overhead estimate breaks down by component:

| Component | Area driver | Character |
|-----------|-------------|-----------|
| CME bank SRAM | Fast on-chip SRAM, 1 KB per non-VMT bank (RV64) | The dominant variable; scales linearly with the number of simultaneously-resident banks per hart |
| ECID EC[] array | Small SRAM per hart (≈1 KB for 16 active ECID entries) | Fixed overhead; cheap |
| CPE tag bits | Additional tag bits in existing L1/L2 cache arrays | Roughly 10–20% of tag SRAM area; distributed |
| MSE arbiter | Contract table + time-slot scheduler at the memory controller | Shared across all cores; not per-core cost |
| QoS arbiter | Equivalent to MSE, placed at the NoC/DMA | Shared; not per-core cost |
| Instruction decode | 24 R-type instructions, one funct3/funct7 decode tree | Negligible |

The dominant variable is the CME bank SRAM. An implementation with 16
non-VMT banks per hart (16 KB) on a 7 nm process contributes roughly
0.1–0.3% of core area. Scaling to 64 banks drives the estimate toward the
upper end of the 5–15% range. MSE and QoS arbiter logic is a one-time
per-chip cost, not a per-core cost, which amortizes well on many-core SoCs.

The 5–15% range is comparable to the cost of adding a hardware FPU,
and provides in return: provable WCET, 1–9 cycle context switches, and a
hardware-enforced isolation substrate for safety-critical certification.

### 7.2 Software compatibility

CE is opt-in at every level:

- **Firmware disable.** M-mode firmware may disable CE entirely; all CE CSRs
  read as zero and all CE instructions trap as illegal. The system behaves
  as a standard RISC-V system.
- **Privileged ignore.** Any privilege level may ignore CE even when the
  hardware is enabled. A conventional kernel and userspace run without
  modification.
- **ISA string.** Implementations that omit CE do not advertise the `Xce*`
  ISA string names.

No existing software is broken by a CE-capable implementation. No existing
software is required to use CE.

---

## 8. Specification status

The CE Suite specification is complete. All tracked design decisions,
specification fixes, and gap-filling work items are resolved.

| Deliverable | Status |
|-------------|--------|
| Chapter 0 — Fundamental Structure | Complete |
| Chapter 1 — Execution Context Model | Complete |
| Chapter 2 — Bank/Group/Delegation Semantics | Complete |
| Chapter 3 — CME Instruction Set Reference | Complete |
| Chapter 4 — Hardware Microarchitecture Overview | Complete |
| Chapter 5 — Linux Kernel Integration | Complete |
| Chapter 6 — CME Usage Examples | Complete |
| Chapter 7 — CPE Instruction Set Reference | Complete |
| Chapter 8 — CPE Usage Examples | Complete |
| Chapter 9 — MSE Instruction Set Reference | Complete |
| Chapter 10 — MSE Usage Examples | Complete |
| Chapter 11 — QoS Instruction Set Reference | Complete |
| Chapter 12 — QoS Usage Examples | Complete |
| Chapter 13 — CSR Reference | Complete |
| Chapter 14 — Privilege Model | Complete |
| Chapter 15 — Trap and Exception Table | Complete |
| Chapter 16 — Discovery Mechanism | Complete |
| Chapter 17 — Memory Ordering Guarantees | Complete |
| Chapter 18 — CLIC Interrupt Integration | Complete |
| Chapter 19 — Interoperability with Ratified Extensions | Complete |
| Appendix A — ECID Radix-Tree Algorithms | Complete |
| Appendix B — Capability Profiles | Complete |

The specification is written in Markdown and requires conversion to
AsciiDoc per RISC-V International toolchain requirements before a formal
submission package can be assembled. A Sail formal model is planned as a
separate deliverable.

---

## 9. Open architectural items

The following items are acknowledged in the specification as deferred to
a later version. They do not affect the encoding requests in this brief,
and none require changes to the 24-instruction ISA or the 31 CSRs listed
above:

1. NUMA-aware Contract assignment (multi-socket MSE semantics).
2. Whether a single Contract can span multiple resource classes.
3. The software slow-path when hardware Contract slots are exhausted.
4. Cross-hart ECS sharing during migration handover.
5. UCS (Unified Context Structure) — kernel-side abstraction, non-normative.
6. Secure Vault key derivation, attestation, and rotation.
7. CE-disable CSR naming, bit layout, and per-extension granularity.

---

## 10. What changes after formal allocation

When RISC-V International allocates formal names and opcode/CSR addresses:

- All chapters that reference the provisional `X`-prefix ISA string names
  (`Xce`, `Xcecme`, etc.) are updated to the ratified names.
- All chapters that reference custom-0 (`0001011`) are updated to the
  allocated opcode.
- All Chapter 13 CSR address entries are updated to the allocated addresses.
- The discovery CSR (`ce_present`) bit layout is unchanged; only its address
  changes.
- No semantic changes to any instruction, CSR field, or architectural model
  are required. The update is purely mechanical.

---

## 11. Next steps

| Step | Owner | Prerequisite |
|------|-------|--------------|
| Identify a RISC-V International sponsor (member company or SIG) | Submitter | This brief |
| Form a Task Group (TG) proposal | Submitter + sponsor | Sponsor identified |
| Submit formal allocation requests (names, opcode, CSRs) | TG | TG formed |
| AsciiDoc conversion of the full specification | Submitter | TG formed |
| Sail formal model | Submitter (separate project) | None |
| TG ratification review | TG + RISC-V International | AsciiDoc spec + Sail model |

---

*End of CE Suite Submission Brief.*
