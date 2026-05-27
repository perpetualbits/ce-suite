# Chapter 13 — CE Suite Control and Status Registers

**Status:** Normative.

This chapter specifies every Control and Status Register (CSR) introduced by the
CE Suite. For each CSR it gives: the provisional address, the minimum privilege
level required to access it, a complete bit-field table with access type and reset
value, and the behavior on illegal access.

---

## 1. Address allocation

CE Suite CSRs occupy two provisional ranges in the RISC-V custom (non-standard)
CSR address map:

| Range | RISC-V encoding [11:8] | Access | Count |
|-------|------------------------|--------|-------|
| 0x7C0–0x7CE | 0111 (M-mode RW) | Read/Write | 15 |
| 0xFC0–0xFCF | 1111 (M-mode RO) | Read-Only | 16 |
| 0xFD1–0xFD2 | 1111 (M-mode RO) | Read-Only | 2 |

**Note.** The 0xFC0–0xFCF range (16 entries) is fully assigned. The two CME
virtualization CSRs added in E5 use provisional addresses 0xFD1–0xFD2 in the
same M-mode RO encoding class. Address 0xFD0 is provisionally assigned to
`ce_present` by Chapter 16 (discovery).

**All addresses are provisional.** Real submission to RISC-V International
requires allocated CSR addresses. The assignments here serve as a complete
proposal basis; they are subject to change during ratification without
architectural impact on the bit-field definitions.

All CE Suite CSRs are **per-hart**: each hart holds its own independent
instance. No CE Suite CSR is shared across harts.

### 1.1 CE-disable CSR

The charter (§3.7, §8.7) establishes that CE may be disabled by firmware and
that CE CSRs read as 0 when CE is disabled. The naming, bit layout, and
per-extension granularity of the CE-disable CSR are deferred open items
(charter §8.7) and are not specified in this chapter.

---

## 2. Conventions

**Minimum privilege.** Unless otherwise noted, all CE Suite CSRs require
M-mode. Lower-privilege access causes an *illegal instruction* exception.
Relaxations for S-mode (kernel) and HS-mode (hypervisor) are specified
in Chapter 14 (P2 — privilege model integration).

**Access types used in bit-field tables:**

| Type | Meaning |
|------|---------|
| RO | Read-only; hardware writes. Writes to an RO-addressed CSR (0xFC0 range) cause *illegal instruction*. |
| RW | Software reads and writes; hardware interprets the stored value. |
| WARL | Write Any, Read Legal. Hardware rounds any written value to the nearest legal value. Legal range documented per field. |
| W1C | Write 1 to Clear. Hardware sets the field; writing 1 clears it; writing 0 has no effect. |
| WIRI | Writes Ignored, Reads as zero. Used for reserved fields. |

**Reserved fields.** All fields not listed in a bit-field table are reserved:
WIRI (reads as 0, writes ignored).

**Reset values.** `impl` means the value is implementation-defined, fixed per
hart, and non-zero unless noted. `0` means the field reads as 0 out of reset.

**CE disabled.** When CE is disabled (charter §3.7), all CE Suite CSRs read as
0 and accept writes silently — no *illegal instruction* exception is raised.
This allows a CE-unaware OS to probe for CE presence without taking unexpected
traps.

---

## 3. CME CSRs

### 3.1 `current_ecid` — 0xFC0

ECID of the currently executing context on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:16 | *reserved* | WIRI | 0 | — |
| 15:0 | ECID | RO | 0 | ECID of the running context; 0 when CE is disabled or before the first `ec.ig` |

**Semantics.** Hardware updates `ECID` at the commit of every successful
`ec.ob`. No instruction or CSR write may modify this field directly; it is
maintained exclusively by CME hardware.

**Privilege note.** Per charter §3.1.2, a process may not read its own ECID.
Whether S-mode may read `current_ecid` is subject to P2. Implementations that
expose a user-readable shadow must use a separate address in the user-accessible
CSR range; no such shadow is defined in this version of the spec.

---

### 3.2 `cme_ec_table_base` — 0x7C0

Base address of the `EC[e]` array for this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:0 | BASE | WARL | 0 | Physical base address of the `EC[e]` array |

**Semantics.** Hardware computes `EC[e]` entry addresses as
`BASE + e × stride`, where `stride` is implementation-defined and fixed per
hart (charter §3.3). M-mode firmware sets `BASE` during CE initialization.

**Legal range.** Any XLEN-wide physical address aligned to `stride`. Unaligned
writes are rounded down to the nearest `stride`-aligned address. Writing 0
is legal and disables EC-table lookups; CME instructions that require an EC-table
lookup will return a documented failure code.

---

### 3.3 `cme_del_cap` — 0xFC1

Delegation depth cap for this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:2 | *reserved* | WIRI | 0 | — |
| 1:0 | D | RO | impl | Maximum delegation depth, 0–3 (charter §5.1) |

**Semantics.** Exposes the implementation's delegation depth cap D, where D ≤ 3
(charter §5.1). An ECID whose delegation level equals D may not create child
ECIDs. Software reads this CSR once at boot to determine the maximum hierarchy
depth supported on this hart.

**Note.** This CSR names the "read-only cap D via a CSR" referenced in Chapter 0
§0.3, Chapter 1 §1.4, and charter §5.1, which did not previously assign a CSR
name to this field.

---

### 3.4 `cme_bank_count` — 0xFC2

Number of context banks on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:16 | *reserved* | WIRI | 0 | — |
| 15:8 | VMT | RO | impl | Number of VMT banks; 0 if VMT is not implemented |
| 7:0 | NV | RO | impl | Number of non-VMT banks; at least 1 if CME is implemented |

**Semantics.** Software reads this CSR before allocating banks. `NV` must be
at least 1 for CME to provide fast-path context switches. `VMT` may be 0 on
implementations without vector/matrix/tensor support; in that case
`cme_status.VMT_RDY` is always 1.

---

### 3.5 `cme_next_free` — 0x7C1

Hint register for bank allocation.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:16 | *reserved* | WIRI | 0 | — |
| 15:0 | HINT | WARL | 0 | Index of the next expected free bank slot |

**Semantics.** Hardware updates `HINT` after each successful bank allocation
to indicate the next available slot. Software may write a preferred slot index;
hardware rounds the written value to the nearest currently-free legal slot
(WARL). A stale read of `HINT` is not an error — the hardware retries allocation
if the hinted slot is taken.

---

### 3.6 `cme_status` — 0xFC3

Result code and status for the last CME operation on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:9 | *reserved* | WIRI | 0 | — |
| 8 | VMT_RDY | RO | 1 | VMT bank restore complete: 1 = ready, 0 = in progress |
| 7:0 | CODE | RO | 0 | Last CME operation result code (0 = success) |

**Semantics.** Hardware updates `CODE` in parallel with the `rd` write of
every CME instruction (charter §6.6). The `rd` write is the primary error
channel; `CODE` is diagnostic. Error code values are defined in Chapter 3.

`VMT_RDY` is cleared to 0 at the start of an `ec.ob` that initiates a
background VMT-bank restore (Chapter 4 §7 — early scalar resume path). Hardware
sets it to 1 when the restore completes. A VMT instruction issued while
`VMT_RDY = 0` stalls the hart until the restore finishes. `VMT_RDY` is always
1 if the implementation does not support background VMT restore, or if no VMT
restore is in progress.

**Note.** This bit is the "VMT-ready CSR bit" referenced in Chapter 4 §7 and
§10; those sections did not previously assign a CSR name or bit position to it.

---

### 3.7 `cme_reg_mask` — 0xFC4

Register mask captured from the last `ec.ib` or `ec.ob` operation.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:0 | MASK | RO | 0 | Effective register mask used by the last `ec.ib` or `ec.ob` |

**Semantics.** Hardware latches the mask operand actually used by the most
recent `ec.ib` or `ec.ob` into `MASK`. Diagnostic use; not updated by
`ec.im` or `ec.om`. Reads as 0 before any `ec.ib`/`ec.ob` has executed.

---

### 3.8 `cme_dma_addr` — 0x7C2

DMA progress address for ongoing `ec.im`/`ec.om` operations.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:0 | ADDR | WARL | 0 | Current or last DMA transfer address; implementation-defined |

**Semantics.** Hardware updates `ADDR` as an `ec.im` or `ec.om` DMA transfer
progresses; on completion, `ADDR` holds the address of the last transferred
unit. Software may write `ADDR` to resume a partially-completed transfer;
implementations that do not support resumable transfers treat writes as
WARL → 0 (the transfer must be restarted in full).

---

### 3.9 `cme_seal_key` — 0x7C3

Vault encryption key for `ec.iv`/`ec.ov` (M-mode only).

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:0 | KEY | WARL | 0 | Key material for vault seal/unseal operations |

**Semantics.** M-mode firmware writes the vault key before executing `ec.iv`
(seal) or `ec.ov` (unseal). The hardware uses this value for the vault
encryption operation described in Chapter 3 §6. Implementations may make this
field non-readable after a write (reads return 0 after programming) for security
isolation; that is legal WARL behavior.

**Access restriction.** This CSR is M-mode only regardless of any P2 privilege
relaxations. S-mode or lower access always causes an *illegal instruction*
exception.

**Specification status.** The key derivation, attestation, and rotation
semantics of the vault are currently shell-only (work item F7); they are deferred
to a future revision (charter §8.6). This CSR is defined here for completeness;
full key-management semantics will be added when charter §8.6 is resolved.

---

### 3.10 `current_ecid_level` — 0xFD1

Delegation level of the currently executing context on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:2 | *reserved* | WIRI | 0 | — |
| 1:0 | L | RO | 0 | Delegation level of the running ECID; 0 when CE is disabled or no ECID is bound |

**Semantics.** Hardware updates `L` atomically with `current_ecid` at the commit
of every successful `ec.ob`. No instruction or CSR write may modify this field
directly. A root ECID created by M-mode has `L = 0`; each delegation step
increments `L` by 1 in the child, matching `EC[current_ecid].delegation_L`.
Together with `cme_del_cap` (0xFC1), this CSR lets software determine whether the
current ECID may further delegate: the ECID may delegate iff `L < cme_del_cap.D`.

**Privilege note.** S-mode, HS-mode, and VS-mode may read this CSR when enabled
per Chapter 14 §14.6. A nested hypervisor deciding whether it can create further
child ECIDs reads `current_ecid_level` directly, avoiding a full `EC[e]` table
lookup on every scheduling decision.

---

### 3.11 `current_ecid_parent` — 0xFD2

Parent ECID of the currently executing context on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:16 | *reserved* | WIRI | 0 | — |
| 15:0 | PARENT | RO | 0 | ECID number of the parent of the running context; 0 if the running ECID is a root (L = 0) or CE is disabled |

**Semantics.** Hardware updates `PARENT` atomically with `current_ecid` at the
commit of every successful `ec.ob`. No instruction or CSR write may modify this
field directly. For a root ECID (`L = 0`), `PARENT` reads as 0. For all other
ECIDs, `PARENT` mirrors `EC[current_ecid].parent_ecid`.

**Privilege note.** S-mode, HS-mode, and VS-mode may read this CSR when enabled
per Chapter 14 §14.6. A nested hypervisor may read `current_ecid_parent` to
identify its supervisor context for upward resource coordination, without a full
`EC[e]` table lookup.

---

## 4. CPE CSRs

### 4.1 `cpe_caps` — 0xFC5

CPE capability flags for this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:12 | *reserved* | WIRI | 0 | — |
| 11 | DELEG | RO | impl | 1 = `cp.it`/`cp.ot` delegation supported (charter §4.3.7) |
| 10 | L2P | RO | impl | 1 = L2-private cache partitioning supported |
| 9 | L1D | RO | impl | 1 = L1D cache partitioning supported |
| 8 | L1I | RO | impl | 1 = L1I cache partitioning supported |
| 7:4 | L2_WAYS | RO | impl | log2(max L2 ways per ECID); 0 if `L2P = 0` |
| 3:0 | L1_WAYS | RO | impl | log2(max L1 ways per ECID); 0 if `L1I = 0` and `L1D = 0` |

**Semantics.** Software reads `cpe_caps` before any CPE partition assignment.
A `cp.ir` targeting a cache level whose support bit is 0 returns
`CPE_ERR_UNSUPPORTED`. `L1_WAYS = 4` means up to 16 L1 ways are available
per partition.

**Normative status.** The bit layout defined here is normative and supersedes
the "informative" caveat in Chapter 7 §7 and Chapter 8. Software must treat
this chapter as authoritative for `cpe_caps` bit positions.

---

### 4.2 `cpe_status` — 0xFC6

Result code from the last CPE operation on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | CODE | RO | 0 | Last CPE operation result code (0 = success; Chapter 7 §8 for codes) |

Updated in parallel with the `rd` result of every CPE instruction. Diagnostic;
`rd` is the primary error channel.

---

### 4.3 `cpe_violation` — 0x7C4

Cache partition boundary violation flag (sticky).

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:1 | *reserved* | WIRI | 0 | — |
| 0 | VIOL | W1C | 0 | 1 = a cache access crossed a partition boundary; write 1 to clear |

**Semantics.** Hardware sets `VIOL` on detection of an EC loading from cache
ways assigned to a different ECID. The flag is sticky until software writes 1
to bit 0. If `cpe_violation_en.EN = 1`, the hardware also raises an
implementation-defined platform-level interrupt to M-mode when `VIOL` is set.
Detection granularity (cache-line or way) is implementation-defined.

---

### 4.4 `cpe_violation_en` — 0x7C5

Interrupt enable for `cpe_violation`.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:1 | *reserved* | WIRI | 0 | — |
| 0 | EN | RW | 0 | 1 = raise platform interrupt when `cpe_violation.VIOL` becomes 1 |

**Semantics.** The interrupt is level-triggered and remains asserted while
`VIOL = 1`. The specific interrupt line and routing to the platform interrupt
controller are implementation-defined; firmware must configure the interrupt
controller before setting `EN`.

---

## 5. MSE CSRs

### 5.1 `mse_slot_ratio` — 0x7C6

Contract-Normal / Best-Effort slot split for this hart's DRAM channel.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | CN_FRAC | WARL | 128 | CN slot fraction out of 256; 128 = 50 % CN, 50 % BE |

**Semantics.** The DRAM arbitration cycle alternates between CN and BE slots.
`CN_FRAC / 256` gives the fraction of slots allocated to CN traffic. The reset
value 128 corresponds to a 50 % split. Implementations may restrict legal values
to a minimum granularity; WARL rounds a written value to the nearest legal
setting. The BE fraction must remain at least one slot per cycle.

**Effect timing.** Changes take effect at the next slot boundary
(implementation-defined latency, typically one slot period).

---

### 5.2 `mse_slot_ns` — 0xFC7

DRAM slot duration in nanoseconds.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:16 | *reserved* | WIRI | 0 | — |
| 15:0 | NS | RO | impl | Slot size in nanoseconds; non-zero, fixed per implementation |

Software uses `NS` to convert `bw_class` and `lat_class` values to real-time
guarantees. This value is a fixed property of the memory subsystem.

---

### 5.3 `mse_max_nesting` — 0xFC8

Maximum interrupt nesting depth supported by MSE.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:4 | *reserved* | WIRI | 0 | — |
| 3:0 | K | RO | impl | Maximum interrupt nesting depth K |

**Semantics.** MSE supports stacking up to K levels of Contract contexts per
hart (Chapter 9 §4). K = 0 means MSE does not support interrupt-nesting
Contract save/restore; software must manage bandwidth classes explicitly in
interrupt handlers.

---

### 5.4 `mse_bw_cap` — 0x7C7

Bandwidth cap for the current ECID's Contract on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | CAP | WARL | 0 | `bw_class` ceiling for the current ECID's group; 0 = no cap |

**Semantics.** Hardware updates `CAP` on every `ms.ir`, `ms.it`, and `ms.ot`
call to reflect the active ECID's Contract-assigned bandwidth allocation.
M-mode firmware may also write `CAP` directly to impose an additional ceiling;
hardware stores the minimum of the written value and the Contract-assigned value.
Writing 0 removes any software-imposed cap.

---

### 5.5 `mse_bw_sum` — 0xFC9

Running sum of `bw_class` across admitted CN Contract holders on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | SUM | RO | 0 | Sum of `bw_class` for all currently-admitted CN Contracts on this hart |

**Semantics.** Hardware maintains this sum for admission control
(Chapter 9 §7.3). Software reads it to assess remaining CN bandwidth budget
before admitting new Contracts. The hardware invariant `SUM ≤ total_cn_budget`
is enforced atomically on every `ms.ir` and `ms.it`.

---

### 5.6 `mse_status` — 0xFCA

Result code from the last MSE operation on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | CODE | RO | 0 | Last MSE operation result code (0 = success; Chapter 9 for codes) |

Updated in parallel with the `rd` result of every MSE instruction. Diagnostic;
`rd` is the primary error channel.

---

### 5.7 `mse_violation` — 0x7C8

CN slot guarantee missed (sticky).

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:1 | *reserved* | WIRI | 0 | — |
| 0 | VIOL | W1C | 0 | 1 = a Contract holder missed its guaranteed CN slot; write 1 to clear |

**Semantics.** Hardware sets `VIOL` when an admitted Contract holder does not
receive a CN slot within the expected window (due to arbitration pressure or
admission overcommitment — the latter should not occur if admission control
functions correctly). Sticky until cleared. If `mse_violation_en.EN = 1`, an
implementation-defined platform-level interrupt is raised to M-mode.

---

### 5.8 `mse_violation_en` — 0x7C9

Interrupt enable for `mse_violation`.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:1 | *reserved* | WIRI | 0 | — |
| 0 | EN | RW | 0 | 1 = raise platform interrupt when `mse_violation.VIOL` becomes 1 |

Level-triggered; remains asserted while `VIOL = 1`. Interrupt routing is
implementation-defined.

---

## 6. QoS CSRs

QoS CSRs are **domain-scoped**: `qos_domain_sel` (§6.3) determines which
domain's registers subsequent accesses target. When this chapter refers to
"the selected domain" it means the domain whose ID is in `qos_domain_sel`.
Accessing a domain-scoped CSR while `qos_domain_sel.SEL` holds an invalid
domain ID causes an *illegal instruction* exception.

---

### 6.1 `qos_domain_count` — 0xFCB

Number of I/O QoS domains present on this system.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | COUNT | RO | impl | Number of I/O fabric domains; 0 if QoS is not implemented |

**Semantics.** Domain IDs are 0-based and consecutive: 0, 1, …, COUNT−1.
Software reads this CSR at boot before accessing `qos_domain_base` or writing
`qos_domain_sel`.

---

### 6.2 `qos_domain_base` — 0xFCC

Base address of the domain descriptor array.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:0 | BASE | RO | impl | Physical base address of the domain descriptor array (Chapter 11 §6.1) |

**Semantics.** The array contains one descriptor per domain in order of domain
ID. Descriptor format is defined in Chapter 11 §6.1. Software reads this CSR
and walks the array at boot to learn the class, slot duration, and CN budget of
each domain.

---

### 6.3 `qos_domain_sel` — 0x7CA

Domain selector for domain-scoped QoS CSR accesses.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | SEL | WARL | 0 | Selected domain ID; legal range 0 to `qos_domain_count − 1` |

**Semantics.** After writing `SEL`, all subsequent accesses to `qos_slot_ratio`,
`qos_bw_cap`, `qos_bw_sum`, `qos_violation`, and `qos_violation_en` target that
domain's register set. WARL rounds out-of-range values to 0; no *illegal
instruction* exception is raised on the write to `qos_domain_sel` itself.

---

### 6.4 `qos_slot_ratio` — 0x7CB

CN/BE slot split for the selected domain.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | CN_FRAC | WARL | 128 | CN slot fraction for the selected domain; 128 = 50 % CN |

Semantics are analogous to `mse_slot_ratio` (§5.1), applied to the I/O
arbitration cycle of the selected domain.

---

### 6.5 `qos_max_nesting` — 0xFCD

Maximum QoS interrupt nesting depth (system-wide).

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:4 | *reserved* | WIRI | 0 | — |
| 3:0 | K | RO | impl | Maximum QoS interrupt nesting depth K |

Analogous to `mse_max_nesting` (§5.3), for the I/O QoS domain. K is
system-wide, not per-domain.

---

### 6.6 `qos_bw_cap` — 0x7CC

Bandwidth cap for the current ECID's Contract on the selected domain.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | CAP | WARL | 0 | `bw_class` ceiling for the current ECID's group on the selected domain; 0 = no cap |

Analogous to `mse_bw_cap` (§5.4), scoped to the selected I/O domain.

---

### 6.7 `qos_bw_sum` — 0xFCE

Running sum of `bw_class` across active CN Contract holders on the selected domain.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | SUM | RO | 0 | Sum of `bw_class` for admitted CN Contracts on the selected domain |

Analogous to `mse_bw_sum` (§5.5), scoped to the selected domain.

---

### 6.8 `qos_status` — 0xFCF

Result code from the last QoS operation on this hart.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:8 | *reserved* | WIRI | 0 | — |
| 7:0 | CODE | RO | 0 | Last QoS operation result code (0 = success; Chapter 11 for codes) |

Updated in parallel with the `rd` result of every QoS instruction. Diagnostic;
`rd` is the primary error channel.

---

### 6.9 `qos_violation` — 0x7CD

CN slot guarantee missed for the selected domain (sticky).

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:1 | *reserved* | WIRI | 0 | — |
| 0 | VIOL | W1C | 0 | 1 = CN slot guarantee missed on the selected domain; write 1 to clear |

Analogous to `mse_violation` (§5.7), scoped to the selected domain.
`qos_violation_en` (§6.10) controls the associated interrupt.

---

### 6.10 `qos_violation_en` — 0x7CE

Interrupt enable for `qos_violation` on the selected domain.

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:1 | *reserved* | WIRI | 0 | — |
| 0 | EN | RW | 0 | 1 = raise platform interrupt when `qos_violation.VIOL` becomes 1 for the selected domain |

Level-triggered; remains asserted while `VIOL = 1` on the selected domain.
Interrupt routing is implementation-defined.

---

## 7. Illegal access behavior

| Condition | Outcome |
|-----------|---------|
| Any CE Suite CSR access from privilege below M-mode | *illegal instruction* (subject to P2 S-mode relaxations) |
| Write to any CE Suite RO CSR (0xFC0–0xFCF, 0xFD1–0xFD2) | *illegal instruction* (RISC-V privilege spec §4.1) |
| Write to a reserved field in an RW CSR | Ignored (WIRI) |
| Domain-scoped CSR access with invalid domain in `qos_domain_sel` | *illegal instruction* |
| Access to `cme_seal_key` from S-mode or below | *illegal instruction* (M-mode-only restriction applies even after P2 relaxations) |
| Any CE Suite CSR access when CE is disabled (charter §3.7) | Reads return 0; writes are silently ignored |

---

## 8. Address summary

### 8.1 M-mode RW CSRs (0x7C0–0x7CE)

| Address | Name | Extension | Access | Scope |
|---------|------|-----------|--------|-------|
| 0x7C0 | `cme_ec_table_base` | CME | WARL | Per-hart |
| 0x7C1 | `cme_next_free` | CME | WARL | Per-hart |
| 0x7C2 | `cme_dma_addr` | CME | WARL | Per-hart |
| 0x7C3 | `cme_seal_key` | CME | WARL (M-only) | Per-hart |
| 0x7C4 | `cpe_violation` | CPE | W1C | Per-hart |
| 0x7C5 | `cpe_violation_en` | CPE | RW | Per-hart |
| 0x7C6 | `mse_slot_ratio` | MSE | WARL | Per-hart |
| 0x7C7 | `mse_bw_cap` | MSE | WARL | Per-hart |
| 0x7C8 | `mse_violation` | MSE | W1C | Per-hart |
| 0x7C9 | `mse_violation_en` | MSE | RW | Per-hart |
| 0x7CA | `qos_domain_sel` | QoS | WARL | Per-hart |
| 0x7CB | `qos_slot_ratio` | QoS | WARL | Domain-scoped |
| 0x7CC | `qos_bw_cap` | QoS | WARL | Domain-scoped |
| 0x7CD | `qos_violation` | QoS | W1C | Domain-scoped |
| 0x7CE | `qos_violation_en` | QoS | RW | Domain-scoped |

### 8.2 M-mode RO CSRs (0xFC0–0xFCF, 0xFD1–0xFD2)

| Address | Name | Extension | Reset |
|---------|------|-----------|-------|
| 0xFC0 | `current_ecid` | CME | 0 |
| 0xFC1 | `cme_del_cap` | CME | impl |
| 0xFC2 | `cme_bank_count` | CME | impl |
| 0xFC3 | `cme_status` | CME | 0 |
| 0xFC4 | `cme_reg_mask` | CME | 0 |
| 0xFC5 | `cpe_caps` | CPE | impl |
| 0xFC6 | `cpe_status` | CPE | 0 |
| 0xFC7 | `mse_slot_ns` | MSE | impl |
| 0xFC8 | `mse_max_nesting` | MSE | impl |
| 0xFC9 | `mse_bw_sum` | MSE | 0 |
| 0xFCA | `mse_status` | MSE | 0 |
| 0xFCB | `qos_domain_count` | QoS | impl |
| 0xFCC | `qos_domain_base` | QoS | impl |
| 0xFCD | `qos_max_nesting` | QoS | impl |
| 0xFCE | `qos_bw_sum` | QoS | 0 |
| 0xFCF | `qos_status` | QoS | 0 |
| *(0xFD0)* | *(`ce_present` — Chapter 16)* | *CE substrate* | *impl* |
| 0xFD1 | `current_ecid_level` | CME | 0 |
| 0xFD2 | `current_ecid_parent` | CME | 0 |

---

*End of Chapter 13.*

[Next: Chapter 14 — CE Suite Privilege Model](ch14-privilege-model.md)
