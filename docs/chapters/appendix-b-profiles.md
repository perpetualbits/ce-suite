<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Appendix B — CE Suite Capability Profiles

**Status:** Normative.
**Scope:** This appendix defines the standard CE Suite capability profiles — named
tiers of implementation capability. A profile is a stable, human-readable mapping
from existing discoverable parameters to a certified capability level. No new hardware
is required; profiles are a naming convention over parameters that are already readable
from `ce_present` (Chapter 16) and the capability CSRs in Chapter 13.

---

## B.1 Purpose

The `ce_present` CSR (0xFD0) and the capability CSRs (`cme_del_cap`, `cme_bank_count`,
etc.) let software probe the exact capabilities of a CE implementation. For most
software, this fine-grained probing is necessary and correct.

For two groups of users, probing individual parameters is inconvenient:

1. **Certification bodies.** Safety-certification standards (ISO 26262, DO-178C,
   IEC 61508) require a stable capability declaration that can be traced through a
   system from hardware to software. "This SoC supports CE-RT" is a traceable claim;
   "this SoC has CME=1, CPE=1, MSE=1, D≥2, NV≥4" expresses the same thing but
   requires per-parameter tracing against the hardware data sheet.

2. **Firmware and OS integration code.** Boot code that configures CE can branch on a
   profile name once, rather than re-implementing the full parameter-combination check
   in every driver or configuration layer.

Profiles address both needs. Each profile is a named, stable capability tier defined as
an explicit set of constraints on the existing discoverable parameters. Profiles do not
introduce new instructions, new CSRs, or new hardware behavior.

---

## B.2 Definitions

A **profile** is a named set of constraints on CE Suite implementation parameters. An
implementation **conforms to** a profile if and only if all constraints in that profile's
definition are simultaneously satisfied. An implementation may conform to zero or more
standard profiles.

A **profile declaration** is an optional firmware-issued advertisement (§B.5) stating
that the implementation conforms to a specific profile. The authoritative capability
information is always the raw CSR values; a profile declaration is a convenience derived
from those values. If a profile declaration and the raw CSR values disagree, the raw CSR
values are authoritative and firmware must be corrected.

---

## B.3 Standard profiles

Four standard profiles are defined, covering the primary deployment tiers of CE Suite
implementations, from deeply embedded microcontrollers to full cloud and server
configurations.

| Profile name | Target class | Required extensions | Min D | Min NV banks | Min VMT banks |
|---|---|---|---|---|---|
| `CE-Embedded`  | Microcontrollers, bare-metal RT | CME only | 0 | 1 | 0 (required absent) |
| `CE-MinimalRT` | Embedded RTOS, single-chip RT | CME, CPE | ≥ 1 | ≥ 2 | unconstrained |
| `CE-RT`        | Multi-partition RT, mixed-criticality | CME, CPE, MSE | ≥ 2 | ≥ 4 | unconstrained |
| `CE-Full`      | Cloud, server, nested virtualization | CME, CPE, MSE, QoS | 3 | ≥ 8 | ≥ 1 |

Each profile is defined completely by the constraints in its §B.3.x entry. A field listed
as "unconstrained" may take any value; the implementation need not satisfy any particular
minimum for that field to conform to the profile.

### B.3.1 CE-Embedded

**Target class.** Microcontrollers, deeply embedded bare-metal real-time systems, RISC-V
E-extension cores.

**Constraints:**

| Parameter | Source CSR | Constraint |
|---|---|---|
| `ce_present.CME` | 0xFD0 bit 0 | = 1 |
| `ce_present.CPE` | 0xFD0 bit 1 | = 0 |
| `ce_present.MSE` | 0xFD0 bit 2 | = 0 |
| `ce_present.QoS` | 0xFD0 bit 3 | = 0 |
| `cme_del_cap.D`  | 0xFC1 bits 1:0 | = 0 |
| `cme_bank_count.NV` | 0xFC2 bits 7:0 | ≥ 1 |
| `cme_bank_count.VMT` | 0xFC2 bits 15:8 | = 0 |

**Rationale.** `D = 0` means delegation is not possible — a single privileged mode manages
all ECIDs. This matches bare-metal embedded systems that have no concept of a guest OS or
hypervisor. CPE, MSE, and QoS are explicitly excluded to define a minimal hardware target
that can be implemented for a few hundred gates. A single NV bank permits fast-path context
switching between interrupt handlers and the foreground task without any higher-level
software stack. `VMT = 0` removes the requirement for vector/matrix register file save
and restore, keeping implementation cost minimal.

### B.3.2 CE-MinimalRT

**Target class.** Embedded real-time systems, single-chip RTOS, industrial controllers.
Supports one level of delegation: a kernel may delegate resources to application tasks.

**Constraints:**

| Parameter | Source CSR | Constraint |
|---|---|---|
| `ce_present.CME` | 0xFD0 bit 0 | = 1 |
| `ce_present.CPE` | 0xFD0 bit 1 | = 1 |
| `cme_del_cap.D`  | 0xFC1 bits 1:0 | ≥ 1 |
| `cme_bank_count.NV` | 0xFC2 bits 7:0 | ≥ 2 |

**Rationale.** `CPE = 1` is the minimum additional ingredient for deterministic real-time
behavior: cache-partition isolation prevents best-effort tasks from evicting hot cache lines
belonging to real-time tasks. Without CPE, a task's WCET is not independently provable
under co-location. `D ≥ 1` allows the kernel (L0) to delegate banks and CPE contracts to
individual tasks (L1). Two NV banks are the minimum to execute a fast-path context switch
while keeping one bank holding the incoming context's state.

### B.3.3 CE-RT

**Target class.** Multi-partition real-time systems, embedded Linux co-running with a
real-time partition, automotive domain controllers, mixed-criticality SoCs.

**Constraints:**

| Parameter | Source CSR | Constraint |
|---|---|---|
| `ce_present.CME` | 0xFD0 bit 0 | = 1 |
| `ce_present.CPE` | 0xFD0 bit 1 | = 1 |
| `ce_present.MSE` | 0xFD0 bit 2 | = 1 |
| `cme_del_cap.D`  | 0xFC1 bits 1:0 | ≥ 2 |
| `cme_bank_count.NV` | 0xFC2 bits 7:0 | ≥ 4 |

**Rationale.** `MSE = 1` closes the last gap in deterministic WCET: cache partitioning
bounds cache interference, but DRAM access latency under contention from other harts or
DMA masters is unbounded without MSE arbitration. Together, CPE + MSE give a provable
end-to-end WCET bound. `D ≥ 2` supports a three-level hierarchy: host kernel (L0),
a hypervisor or partition manager (L1), and task-level ECIDs (L2). Four NV banks provide
headroom for simultaneous hardware residency of a real-time partition, a best-effort OS
partition, an interrupt handler, and an idle context.

### B.3.4 CE-Full

**Target class.** Cloud and server platforms, systems requiring nested virtualization,
DO-178C / ASIL-D certification targets.

**Constraints:**

| Parameter | Source CSR | Constraint |
|---|---|---|
| `ce_present.CME` | 0xFD0 bit 0 | = 1 |
| `ce_present.CPE` | 0xFD0 bit 1 | = 1 |
| `ce_present.MSE` | 0xFD0 bit 2 | = 1 |
| `ce_present.QoS` | 0xFD0 bit 3 | = 1 |
| `cme_del_cap.D`  | 0xFC1 bits 1:0 | = 3 |
| `cme_bank_count.NV` | 0xFC2 bits 7:0 | ≥ 8 |
| `cme_bank_count.VMT` | 0xFC2 bits 15:8 | ≥ 1 |

**Rationale.** `QoS = 1` and `D = 3` together enable the full four-level isolation
hierarchy: host kernel (L0) → hypervisor (L1) → nested hypervisor (L2) → guest (L3),
each with independently bounded DRAM and I/O latency. Eight NV banks accommodate a
realistic cloud workload with several VMs, a hypervisor, management software, and
interrupt handlers all holding state simultaneously in hardware. One VMT bank ensures
at least one context can use hardware-accelerated vector and matrix register save/restore,
which is required for ML inference workloads co-located with real-time partitions.

---

## B.4 Profile conformance check

Software that needs to determine whether the running implementation satisfies a named
profile reads the required CSRs and compares against the profile's constraint table. The
following C pseudocode shows the conformance check for all four profiles.

The CE-absent trap-handler probe required before reading `ce_present` is described in
Chapter 16 §4.1. The code below assumes CE is confirmed present and the CSRs have already
been read into the variables shown.

```c
/* CE Suite capability CSR values, read during M-mode boot. */
static uint32_t ce_present;       /* CSR 0xFD0 */
static uint32_t cme_del_cap;      /* CSR 0xFC1 */
static uint32_t cme_bank_count;   /* CSR 0xFC2 */

#define CME_BIT  (1u << 0)
#define CPE_BIT  (1u << 1)
#define MSE_BIT  (1u << 2)
#define QOS_BIT  (1u << 3)

static inline unsigned d_cap(void)    { return cme_del_cap & 0x3u; }
static inline unsigned nv_banks(void) { return cme_bank_count & 0xFFu; }
static inline unsigned vmt_banks(void){ return (cme_bank_count >> 8) & 0xFFu; }

bool ce_conforms_embedded(void) {
    return (ce_present & CME_BIT) &&
           !(ce_present & (CPE_BIT | MSE_BIT | QOS_BIT)) &&
           d_cap()     == 0 &&
           nv_banks()  >= 1 &&
           vmt_banks() == 0;
}

bool ce_conforms_minimal_rt(void) {
    return (ce_present & (CME_BIT | CPE_BIT)) == (CME_BIT | CPE_BIT) &&
           d_cap()    >= 1 &&
           nv_banks() >= 2;
}

bool ce_conforms_rt(void) {
    return (ce_present & (CME_BIT | CPE_BIT | MSE_BIT)) ==
                         (CME_BIT | CPE_BIT | MSE_BIT)  &&
           d_cap()    >= 2 &&
           nv_banks() >= 4;
}

bool ce_conforms_full(void) {
    return (ce_present & (CME_BIT | CPE_BIT | MSE_BIT | QOS_BIT)) ==
                         (CME_BIT | CPE_BIT | MSE_BIT | QOS_BIT)  &&
           d_cap()     == 3 &&
           nv_banks()  >= 8 &&
           vmt_banks() >= 1;
}
```

### B.4.1 Profile precedence and the CE-Embedded branch

CE-Full, CE-RT, and CE-MinimalRT form a nested sequence: every CE-Full implementation
satisfies CE-RT; every CE-RT implementation satisfies CE-MinimalRT. Firmware should
advertise the highest profile in this sequence that the implementation satisfies.

CE-Embedded is in a separate branch. It requires D = 0 and CPE = 0, both of which
conflict with CE-MinimalRT (D ≥ 1, CPE = 1). No implementation can simultaneously
conform to CE-Embedded and any of the other three profiles. The capability space has the
following structure:

```
CE-Full
  └─ CE-RT
       └─ CE-MinimalRT

CE-Embedded   (independent branch: D = 0, CPE = 0)
```

An implementation with all four extensions and D = 3 conforms to CE-Full, not to
CE-Embedded.

---

## B.5 Device-tree advertisement

Firmware that has confirmed the implementation conforms to a named profile should
advertise the profile name in the device tree using the `ce,profile` string property
on the relevant hart node. This property is optional; software must not assume its
presence and must fall back to reading the raw CSRs if the property is absent.

```
cpus {
    cpu@0 {
        compatible = "riscv";
        riscv,isa = "rv64imafdc_xce";
        ce,profile = "CE-Full";
    };
};
```

**Multi-hart systems.** In practice all harts in a CE-capable system implement the same
profile, but software must not assume this. If `ce,profile` is present, it may be
read per-hart.

**Consistency requirement.** The value of `ce,profile` must be consistent with the raw
CSR values on the hart. If the raw CSRs do not satisfy the constraints of the advertised
profile, firmware is incorrect; software must fall back to raw-CSR probing. Software that
detects a disagreement between `ce,profile` and the raw CSRs should log the inconsistency
and ignore the profile property — the same principle as `riscv,isa` vs. `ce_present` in
Chapter 16 §5.

**No ISA string profile names.** Profile conformance is not expressed in the `riscv,isa`
ISA string. The ISA string carries individual extension names (`Xce`, `Xcecme`, etc.) as
defined in Chapter 16 §2; those names convey extension presence but not delegation depth
or bank counts. Profile names require CSR-value constraints that the ISA string format
cannot express.

---

## B.6 Governance and vendor profiles

The four standard profiles in §B.3 are defined by the CE Suite specification. Changes
to the standard profile set require a revision to this appendix, a changelog entry, and
a version bump.

**Vendor profiles.** A vendor may define non-standard profiles not covered by this
specification. Vendor profile names must use the prefix `V-` followed by a short ASCII
vendor identifier (chosen by the vendor; not registered by this spec), a hyphen, and a
descriptive name. Example: `V-AcmeCorp-SecureRT`. The CE Suite specification does not
define the constraints or semantics of vendor profiles; software that encounters an
unrecognized profile name must fall back to raw-CSR probing.

**Composition.** Composing standard profiles (e.g., `CE-MinimalRT + Vault`) is not
defined in v1. Software requiring a specific combination of a named profile and additional
capabilities (such as vault support via `ec.iv`/`ec.ov`) should use the standard profile
conformance check and then probe the additional capability separately. Composition rules
are deferred to a future version.

---

## B.7 Relationship to other chapters

**Chapter 16 (Discovery).** Establishes the hardware interface for CE Suite capability
probing: `ce_present` (§3) and the per-extension capability CSRs (§3.1). Profiles
(this appendix) are a convenience naming layer above that interface. Always probe
`ce_present` first (Chapter 16 §4.1); profiles are consulted after the raw capability
values are known.

**Chapter 13 (CSR Reference).** Defines the bit layouts of `cme_del_cap` (0xFC1) and
`cme_bank_count` (0xFC2) used in the constraint tables (§B.3.1–§B.3.4).

**Charter §5.1.** The architectural maximum D ≤ 3 is what makes the CE-Full profile's
`D = 3` constraint both meaningful and final: no implementation can exceed D = 3, so
CE-Full's delegation depth is the global maximum.

---

*End of Appendix B.*
