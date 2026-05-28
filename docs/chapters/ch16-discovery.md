<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Chapter 16 — CE Suite Discovery Mechanism

**Status:** Normative.

This chapter defines how software detects the presence of CE Suite
extensions and determines which sub-extensions are implemented. It introduces a
single top-level capability CSR (`ce_present`, 0xFD0) and specifies the provisional
ISA string names used to advertise CE Suite in firmware and tooling.

---

## 1. What software needs to know

Before using any CE Suite extension, software must establish three things:

1. **Is CE Suite present and enabled?** An absent implementation has no CE CSRs;
   a present but firmware-disabled implementation reads all CE CSRs as 0. Both
   cases mean "do not use CE."
2. **Which sub-extensions are implemented?** A hart may implement CME alone, or
   any subset of the four extensions.
3. **What are the implementation parameters?** Number of banks, cache ways, DRAM
   slot duration, and so on — these are covered by the per-extension capability
   CSRs in Chapter 13 and do not require new definitions here.

This chapter covers items 1 and 2. Item 3 uses the existing CSRs from Chapter 13.

---

## 2. ISA string extension names

RISC-V extension names beginning with `X` denote non-standard (custom) extensions.
The following names are proposed for CE Suite:

| Name | Sub-extension |
|------|---------------|
| `Xce` | CE Suite umbrella — all four sub-extensions implemented |
| `Xcecme` | CME (Context Management Extension) only |
| `Xcecpe` | CPE (Cache Partitioning Extension) only |
| `Xcemse` | MSE (Memory Scheduling Extension) only |
| `Xceqos` | QoS (I/O Quality-of-Service Extension) only |

**Umbrella vs. individual names.** An implementation that provides all four
sub-extensions advertises `Xce`. A partial implementation advertises only the
names for the sub-extensions it provides — an implementation with CME and CPE
but not MSE or QoS advertises `Xcecme Xcecpe`, not `Xce`. Software that checks
for a specific sub-extension name need not also check `Xce`; a conforming
firmware that advertises `Xce` implicitly includes all four individual names.
In implementation terms: `Xce` ↔ (`Xcecme` ∧ `Xcecpe` ∧ `Xcemse` ∧ `Xceqos`).

**Ratification note.** The `X` prefix is appropriate at proposal stage. If CE
Suite is ratified as a RISC-V standard extension, the names will be replaced with
registered standard names (likely with a `Z` prefix) assigned by RISC-V
International. All names in this chapter are provisional.

**Where these names appear.** In the RISC-V device tree, the ISA string for
each hart is carried in the `riscv,isa` DT property (DT spec §3.8). A hart
implementing full CE Suite includes `xce` (lowercased per DT convention) in that
string. Toolchain feature detection, OS kernel ISA-extension infrastructure (such
as `RISC-V_ISA_EXT_*` in Linux), and configuration management tools use these
names to gate CE-aware code paths.

---

## 3. `ce_present` — 0xFD0

A single read-only CSR provides a per-hart summary of which CE sub-extensions
are implemented.

**Address:** 0xFD0 — M-mode read-only (custom). This is the first available
slot after the 16-CSR M-mode RO block defined in Chapter 13 (0xFC0–0xFCF).

| Bits | Field | Access | Reset | Description |
|------|-------|--------|-------|-------------|
| XLEN-1:5 | *reserved* | WIRI | 0 | — |
| 4 | HEXT | RO | impl | 1 = `hcme_ctrl` (0x6C0) is implemented; H-extension CE integration present |
| 3 | QOS | RO | impl | 1 = QoS (I/O Quality-of-Service Extension) is implemented |
| 2 | MSE | RO | impl | 1 = MSE (Memory Scheduling Extension) is implemented |
| 1 | CPE | RO | impl | 1 = CPE (Cache Partitioning Extension) is implemented |
| 0 | CME | RO | impl | 1 = CME (Context Management Extension) is implemented |

**Per-hart.** Like all CE Suite CSRs, `ce_present` is per-hart. In practice all
harts in a system will report the same bit pattern, but software must not assume
this without reading the CSR on each hart.

**CE-disabled behavior.** When an extension's enable bit in `ce_ctrl` (0x7D0)
is 0, that extension's CSRs read as 0 — including the relevant bits of
`ce_present`. When all four extension bits are 0, `ce_present` reads as 0
entirely, consistent with Chapter 13 §2. This is intentional: `ce_present = 0`
is the correct answer to "is CE available?" when CE is disabled. No
software-visible distinction exists between CE absent and CE disabled.

**CE-absent behavior.** When the hardware does not implement CE at all, address
0xFD0 is unimplemented and access traps as an illegal instruction (RISC-V
privilege spec §4.1). Software must install a trap handler when probing this
CSR (§4).

**HEXT bit.** `HEXT = 1` means the H-extension CE integration described in
Chapter 14 §14.8 is present. This implies: the H extension is implemented
(`misa.H = 1`), CME is implemented (`CME = 1`), and `hcme_ctrl` (0x6C0) is a
valid CSR. A hypervisor can probe `ce_present.HEXT` as a single check rather
than reading both `misa` and `ce_present.CME`.

### 3.1 Relationship to per-extension capability CSRs

`ce_present` establishes which sub-extensions are present. The per-extension
capability CSRs in Chapter 13 provide detailed implementation parameters. They
should only be consulted when the corresponding `ce_present` bit is 1.

| `ce_present` bit | Per-extension capability CSRs to consult |
|------------------|------------------------------------------|
| `CME = 1` | `cme_del_cap` (0xFC1) — delegation depth cap D |
| `CME = 1` | `cme_bank_count` (0xFC2) — NV and VMT bank counts |
| `CPE = 1` | `cpe_caps` (0xFC5) — cache levels, way counts, delegation support |
| `MSE = 1` | `mse_slot_ns` (0xFC7) — slot duration in nanoseconds |
| `MSE = 1` | `mse_max_nesting` (0xFC8) — interrupt nesting depth |
| `QOS = 1` | `qos_domain_count` (0xFCB) — number of I/O QoS domains |
| `QOS = 1` | `qos_domain_base` (0xFCC) — domain descriptor array base |

Reading a per-extension capability CSR when the corresponding sub-extension is
absent (`ce_present` bit = 0) returns 0. This is consistent with "not present":
`qos_domain_count = 0` means no domains available; `cpe_caps = 0` means no cache
partitioning capability; and so on.

**Capability profiles.** After reading `ce_present` and the per-extension capability
CSRs, software may optionally determine which named implementation profile the hart
satisfies by consulting Appendix B (Capability Profiles). Profiles are a convenience
naming layer — a stable mapping from the raw CSR values to named tiers such as
`CE-Embedded`, `CE-MinimalRT`, `CE-RT`, and `CE-Full`. The raw CSR values are always
authoritative; Appendix B provides the conformance-check criteria and the device-tree
advertisement mechanism for profiles.

---

## 4. Software probe sequence

### 4.1 M-mode boot probe

M-mode firmware probes CE Suite presence during early boot, before enabling CE
for any lower privilege level. The probe uses a minimal trap handler because
hardware that does not implement CE at all will raise an illegal-instruction
exception on the `ce_present` read.

```asm
    # Step 1: Install a trap handler that sets a0 = 0 and advances past the
    #         faulting instruction.  Catches "illegal instruction" from
    #         ce_present (0xFD0) on CE-absent hardware.
    la    t0, ce_probe_trap
    csrw  mtvec, t0

    # Step 2: Attempt to read ce_present.
    #   CE absent  → illegal instruction → ce_probe_trap fires, a0 = 0
    #   CE disabled → reads 0 normally, no trap
    #   CE enabled  → reads non-zero, no trap
    csrr  a0, 0xFD0
    j     ce_probe_done

ce_probe_trap:
    li    a0, 0
    csrr  t0, mepc
    addi  t0, t0, 4             # advance past the faulting csrr (4 bytes, non-compressed)
    csrw  mepc, t0
    mret

ce_probe_done:
    # Restore normal mtvec before proceeding.
    # a0 = 0 : CE not present or CE disabled — do not use CE.
    # a0 ≠ 0 : CE present and enabled; bits [4:0] identify sub-extensions.
    beqz  a0, no_ce

    andi  t0, a0, 0x1           # t0 ≠ 0 : CME present
    andi  t1, a0, 0x2           # t1 ≠ 0 : CPE present
    andi  t2, a0, 0x4           # t2 ≠ 0 : MSE present
    andi  t3, a0, 0x8           # t3 ≠ 0 : QoS present
    andi  t4, a0, 0x10          # t4 ≠ 0 : H-extension CE integration present
```

After confirming `CME = 1`, firmware proceeds to read the capability CSRs from
§3.1, set up the EC table, allocate the root ECID, and enable lower-privilege
CE access per Chapter 14 §14.9.

### 4.2 S-mode probe (firmware-published value)

`ce_present` (0xFD0) is M-mode read-only; S-mode access traps (Chapter 13 §13.7
and Chapter 14 §14.6). M-mode firmware publishes the CSR value in a shared memory
region at boot, alongside the other capability CSR values described in Chapter 14
§14.9:

```asm
    # M-mode boot sequence (extend the publication step):
    csrr  t0, 0xFD0             # read ce_present
    sw    t0, fw_caps + CE_PRESENT_OFFSET(x0)

    # S-mode at runtime:
    lw    t0, fw_caps + CE_PRESENT_OFFSET(x0)
    # t0 holds the same value and bit interpretation as the raw CSR.
```

The `fw_caps` base address and the offset constant are communicated to S-mode via
the device tree or an equivalent platform-defined mechanism.

When the device tree `riscv,isa` property is authoritative and trusted, S-mode
may alternatively infer CE presence from the ISA string (§5) without relying on a
firmware-published table. Both mechanisms must agree; the CSR is the authoritative
source; the ISA string is a derived advertisement.

---

## 5. Device-tree advertisement

Firmware implements CE Suite should populate the `riscv,isa` DT property for
each hart to include the appropriate extension names from §2.

**Full CE Suite (all four sub-extensions):**

```
riscv,isa = "rv64imafdc_xce"
```

**CME and CPE only (no MSE or QoS):**

```
riscv,isa = "rv64imafdc_xcecme_xcecpe"
```

The Linux kernel CE Suite driver, if one is contributed, would parse these names
from `riscv,isa` and set corresponding bits in the `RISC-V_ISA_EXT_*` bitmap,
analogous to other multi-letter extensions (`Zba`, `Zbb`, etc.).

**Consistency requirement.** The ISA string and `ce_present` must report
consistent information. If `ce_present.CPE = 0`, the ISA string must not contain
`Xcecpe` or `Xce`. If the two disagree, the hardware CSR is authoritative and the
device-tree string is incorrect; firmware must be fixed. Software that detects a
disagreement should log the inconsistency and fall back to the CSR value.

---

## 6. Address summary

| Address | Name | Extension | Access | Notes |
|---------|------|-----------|--------|-------|
| 0xFD0 | `ce_present` | CE substrate | RO (M-mode) | First available slot after ch13's 0xFC0–0xFCF block |

This is the only CSR introduced by this chapter. All per-extension capability CSRs are
defined in Chapter 13.

---

## 7. Where to go next

**Chapter 13** (CSR reference) defines all 31 CE Suite CSRs, including the
per-extension capability CSRs consulted after `ce_present` confirms extension
presence (§3.1 above).

**Chapter 14** (privilege model) specifies `cme_priv_ctl` (§14.4.1). M-mode must
not set `S_EN = 1` before verifying `ce_present.CME = 1`; enabling CE for S-mode
on CE-absent hardware has no effect (the instruction set does not exist), but the
sequence is logically incorrect and should be guarded.

**Chapter 15** (trap table) covers the illegal-instruction trap that `ce_present`
access raises on CE-absent hardware (§15.2.1, universal trap conditions).

**Appendix B** (Capability Profiles) defines the named implementation profiles
(`CE-Embedded`, `CE-MinimalRT`, `CE-RT`, `CE-Full`) as a convenience naming layer
over the `ce_present` bits and capability CSR values established by this chapter.

**Chapter 19** (Ratified-extension interoperability) specifies how CE-aware software
coexists with RVA23 mandatory state — which extension-specific CSRs (H, Sha, Ssaia,
Sstc, and others) belong in the bank CSR slot, and how CE's privilege controls
interact with `Smstateen`/`Ssstateen` gates.

[Next: Chapter 17 — Memory Ordering Guarantees](ch17-memory-ordering.md)

---

*End of Chapter 16.*
