# Chapter 9 — QoS: I/O Quality-of-Service Extension

## 1. Overview

The **I/O Quality-of-Service Extension (QoS)** applies the same arbitration philosophy
as MSE (Chapter 8) to the on-chip I/O fabric: the Network-on-Chip (NoC), DMA engines,
and peripheral interconnect. Its purpose is to make Worst-Case Execution Time for
I/O-bound workloads *provable* — the same guarantee MSE provides for DRAM access.

QoS achieves this through two coordinated mechanisms:

1. **BE/Contract slot alternation.** Time on each I/O fabric domain is divided into
   alternating best-effort (BE) and contract (CN) slots. CN slots are reserved for
   ECIDs holding QoS Contracts; BE slots are available to all ECIDs opportunistically.
   This gives hard latency and bandwidth bounds to Contract holders without starving
   best-effort traffic.

2. **Hierarchical Contract model.** I/O bandwidth and latency guarantees are represented
   as Contracts (charter §4.3), owned by ECIDs, splittable to child ECIDs, and enforced
   in O(1) hardware per arbitration cycle.

QoS is per-system (the I/O fabric is a shared resource), but all software interactions
are per-hart and ECID-first: QoS instructions take ECID numbers as operands, never raw
pointers or opaque identifiers.

**Relationship to MSE.** MSE governs DRAM arbitration (Chapter 8); QoS governs I/O
fabric arbitration (this chapter). The two are complementary: a DMA transfer exercises
both — QoS on the I/O side, MSE on the DRAM side. Neither subsumes the other.

**What QoS does not cover:**

- DRAM arbitration — MSE (Chapter 8).
- L1/L2 cache isolation — CPE (Chapter 7).
- Multi-resource Contracts spanning memory and I/O — open item (charter §8.2).
- Software slow-path when hardware Contract slots are exhausted — open item (charter §8.3).

---

## 2. Fabric Domains

Unlike MSE, which governs a single DRAM controller, QoS governs **multiple heterogeneous
fabric domains** within the same SoC. Each domain is an independent arbitration point
with its own bandwidth capacity, slot timescale, and CN budget.

### 2.1 Domain classes

| Domain class | Examples | Typical slot timescale |
|---|---|---|
| **NoC** | On-chip mesh, ring, or crossbar fabric | 1–20 ns (flit period or arbitration window) |
| **DMA** | DMA engines, IOMMU-mapped transfer channels | 100 ns – 10 µs (transfer credit unit) |
| **Peripheral** | APB, AHB, AXI peripheral bus segments | 10–200 ns (bus transaction period) |

### 2.2 Domain identifier (`domain_id`)

Each fabric domain visible to QoS software has an implementation-assigned
**`domain_id`**: an integer of implementation-defined width, exposed via the
`qos_domain_count` CSR (§6). Domain IDs are stable across boots for a given
implementation; they are not architectural constants.

Software discovers available domains and their properties by reading the domain
descriptor array (§6.1). A `domain_id` that does not correspond to a domain present
in the implementation is invalid; instructions that reference it return
`QOS_ERR_INVALID_DOMAIN`.

### 2.3 Per-domain isolation

Admission control, CN budgets, scheduling windows, and violation tracking are all
**per-domain**. Exhausting the CN budget on the NoC domain does not block assignment
of a DMA Contract. This is a deliberate consequence of keeping Contracts single-domain
(charter §8.2 multi-resource Contracts are out of scope).

---

## 3. The BE/Contract Slot Scheme

### 3.1 Alternating slots

Each fabric domain independently divides its arbitration time into alternating slots:

```
... | CN | BE | CN | BE | CN | BE | ...
```

- **CN (contract) slots** — served only to ECIDs holding an active QoS Contract on
  this domain whose `lat_class` is non-zero. The arbitration rule in §8 selects which
  eligible EC is served.
- **BE (best-effort) slots** — available to any EC regardless of Contract status.
  DMA channels not bound to a Contract also compete in BE slots.

The default split is 50 % CN / 50 % BE. Each domain exposes a `qos_slot_ratio` CSR
field (§6); the BE fraction must be at least 25 % and the CN fraction at least 25 %
to preserve the latency bounds in §4.

### 3.2 Slot size

Slot size is implementation-defined and per-domain. Each domain's slot size is exposed
as a read-only value via the domain descriptor array (§6.1) in nanoseconds. Software
uses this value to convert Contract latency classes into wall-clock latency bounds.

Typical values:

| Domain class | Typical slot size |
|---|---|
| NoC | 2–20 ns |
| DMA | 200 ns – 2 µs |
| Peripheral | 20–200 ns |

### 3.3 Steady-state bandwidth

In steady state with N active Contract holders each claiming one CN slot per pair on
a given domain:

- Each Contract holder receives ≥ 50 % of its guaranteed minimum over any window of
  two consecutive slots on that domain.
- BE traffic fills all slots not consumed by Contract holders, so total fabric
  utilization approaches 100 % under load.

---

## 4. Interrupt Accommodation and Latency Bounds

### 4.1 Interrupts absorb into BE slots

When an interrupt fires, its handler executes as a new EC. If that handler performs
I/O (acknowledging a peripheral, draining a FIFO, initiating a DMA), those accesses
compete in the next available BE slot on the relevant domain. Because BE slots occur
at least every other slot, the maximum additional I/O latency imposed on an interrupt
handler is **one slot** on that domain beyond whatever access is already in flight.

CN slots are never preempted by an interrupt. This keeps Contract holders' bandwidth
guarantees intact under interrupt load.

### 4.2 Nested interrupts and the nesting cap K

Interrupt nesting extends the worst-case latency for CN slots. QoS defines a
parameter **K** — the maximum hardware-tolerated interrupt nesting depth — exposed
via the read-only CSR `qos_max_nesting`. K is per-system (not per-domain) and is the
same parameter as `mse_max_nesting`; implementations that support both MSE and QoS
expose a single K that satisfies both extensions simultaneously.

Under worst-case nesting of depth K, CN slots are delayed but not skipped. After all K
interrupt handlers complete, the alternation phase is corrected; no drift accumulates
across windows.

**Maximum latency for a CN slot** on a given domain under nesting depth K:

```
latency_max = (K + 1) × slot_size(domain)
```

**Contract bandwidth** remains at the configured CN fraction regardless of K.

### 4.3 Practical values

| K | Worst-case CN latency | Notes |
|---|---|---|
| 0 | 1 × slot | No interrupt nesting permitted |
| 1 | 2 × slot | NMI only (typical) |
| 2 | 3 × slot | NMI + one preemptible IRQ level |
| 3 | 4 × slot | Deepest nesting CE supports |

K = 1 is the recommended default. K > 3 voids the latency guarantee for CN slots
and is not permitted by QoS v1.

---

## 5. QoS Contracts

QoS Contracts are instances of the general Contract model (charter §4.3). This section
specifies the QoS-specific parameters each Contract carries.

### 5.1 Contract parameters

Each QoS Contract holds three fields set by the privileged actor that creates it:

| Field | Width | Meaning |
|---|---|---|
| `bw_class` | 4 bits | Minimum I/O bandwidth class: how many CN slots per window on this domain the holder is guaranteed. 0 = best-effort only. |
| `lat_class` | 4 bits | Latency class: priority within CN slot arbitration on this domain. Lower value = higher priority. 0 = best-effort only. |
| `domain_id` | impl-defined | Which I/O fabric domain this Contract governs. |

Both `bw_class` and `lat_class` are zero for best-effort ECIDs. An ECID with both
fields non-zero is a **Contract holder** on the specified domain; it participates in
CN slot arbitration for that domain.

An ECID may hold at most one QoS Contract per domain. Holding a Contract on the NoC
domain does not prevent holding a separate Contract on a DMA domain.

`bw_class` and `lat_class` are carried in the bank's CP field (chapter 0 §0.6) per
domain and loaded atomically by `ec.ob` on context switch. The I/O fabric controller
reads these fields from per-hart registers, not from RAM, during arbitration.

### 5.2 Group bandwidth cap

The privileged actor that creates an ECID may set a **group bandwidth cap** on it:
a ceiling on the total `bw_class` sum across all ECIDs in that ECID's delegation
subtree for a given domain. The cap is stored in `EC[e]` (implementation-defined
field, indexed by `domain_id`) and checked in O(1) on every `qs.ir` call.

Hardware enforces, per domain:

```
sum(bw_class, subtree(e), domain) ≤ bw_cap(e, domain)
```

A child cannot claim more guaranteed I/O bandwidth than the parent has delegated.

### 5.3 Hierarchical splitting

A privileged actor may split a QoS Contract into a parent Contract and one or more
child Contracts (charter §4.3.3). Each child's `bw_class` must be ≤ the parent's
`bw_class` minus what the parent retains. The sum of all children's `bw_class` values
must never exceed the parent's. Splitting is performed via `qs.it` (§7.3) and is
**atomic**: if the hardware admission check fails, no state is changed.

### 5.4 Dissolution

When an ECID's Contract is revoked (via `qs.or` or `ec.oe`), the Contract dissolves
and its `bw_class` is returned to the parent ECID's cap headroom for that domain.
If the ECID has child Contracts on the same domain, those are revoked first,
recursively (charter §4.3.5). Dissolution always succeeds — even for zombie or hostile
ECIDs — and is O(log N) via the radix tree.

### 5.5 DMA attribution

DMA engines generate fabric traffic that is not CPU-pipeline-initiated. QoS handles
this through **DMA channel binding**: when a privileged actor calls `qs.ir` with a
`domain_id` identifying a DMA channel, the call binds that ECID to the named DMA
channel. From that point forward, all DMA transactions on that channel are arbitrated
using the ECID's `bw_class` and `lat_class` parameters. The DMA controller reads
per-channel registers (loaded at bind time) during transfer arbitration.

If a DMA channel is not bound to any ECID, its transactions compete in BE slots only.
A DMA channel may be bound to at most one ECID at a time; attempting to bind an
already-bound channel returns `QOS_ERR_DOMAIN_BUSY`. Binding is revoked by `qs.or`
or `ec.oe`.

---

## 6. QoS CSRs

QoS CSRs are **domain-scoped**: a domain selector register (`qos_domain_sel`)
determines which domain's registers are visible to subsequent CSR reads and writes.
This allows a single architectural register name per function regardless of how many
domains the implementation supports. Implementations with a fixed, small number of
domains may expose them as flat CSR sets with domain-suffixed names; the domain-selector
model is the architectural baseline.

### 6.1 Domain descriptor array

A read-only memory-mapped array, base address in `qos_domain_base`, with one
descriptor per domain. Each descriptor holds:

| Field | Width | Meaning |
|---|---|---|
| `domain_id` | impl-defined | Identifier for this domain |
| `domain_class` | 2 bits | 0 = NoC, 1 = DMA, 2 = Peripheral |
| `slot_ns` | 16 bits | Slot size in nanoseconds |
| `total_cn_budget` | 8 bits | Total CN slot capacity (sum of all `bw_class` values the system can admit on this domain) |
| `max_ecids` | 16 bits | Maximum number of simultaneous Contract holders on this domain |

Software reads this array at boot to enumerate available I/O fabric domains.

### 6.2 Domain-scoped CSRs

| CSR | Access | Purpose |
|---|---|---|
| `qos_domain_count` | RO | Number of I/O fabric domains present |
| `qos_domain_base` | RO | Base address of the domain descriptor array |
| `qos_domain_sel` | RW (privileged) | Domain selector: set before accessing domain-scoped CSRs |
| `qos_slot_ratio` | RW (privileged) | CN/BE slot split for the selected domain. Bits 7:0 = CN fraction (0–255, where 128 = 50 %). Implementations may restrict to a set of legal values. |
| `qos_max_nesting` | RO | Maximum interrupt nesting depth K (system-wide) |
| `qos_bw_cap` | RW (privileged) | Per-hart bandwidth cap for the currently loaded ECID's group on the selected domain |
| `qos_bw_sum` | RO | Running sum of `bw_class` across all active Contract holders on the selected domain |
| `qos_status` | RO | Result code from the last QoS operation on this hart |
| `qos_violation` | RO (sticky) | Set when a Contract holder on the selected domain does not receive its guaranteed CN slot in the expected window. Cleared by writing 1. |
| `qos_violation_en` | RW (privileged) | Enable interrupt on `qos_violation` for the selected domain |

---

## 7. QoS Instructions

All QoS instructions are privileged. They follow the naming scheme
`qs.{i,o}{target}` (charter §6.1). QoS uses the subset `{r, t}`:

| Letter | Target / kind |
|---|---|
| `r` | resource (I/O Contract) |
| `t` | tenant (child Contract delegation) |

**ECID-first operands.** Any QoS instruction targeting a context other than the
current one takes an ECID number as its primary operand — never a pointer, never an
opaque domain handle (charter §6.2).

---

### `qs.ir` — Assign an I/O Contract to an ECID

* **Syntax**: `qs.ir rd, rs1, rs2`
  * `rs1`: Target ECID.
  * `rs2`: Contract parameters — `bw_class` (bits 3:0), `lat_class` (bits 7:4), and
    `domain_id` (bits 23:8), packed into `rs2`; or a pointer to a `QOS_Contract_Params`
    struct if bit 63 of `rs2` is set.
  * `rd`: 0 on success; error code on failure.
* **Semantics**:
  1. Checks that `rs1` is a valid, allocated ECID on this hart.
  2. Checks that `domain_id` is valid.
  3. Checks that ECID `rs1` does not already hold a Contract on this domain; if it
     does, returns `QOS_ERR_ALREADY_BOUND`.
  4. Checks `bw_class(rs2) + existing_sum(subtree(parent(rs1)), domain) ≤ bw_cap(parent(rs1), domain)`.
     If not, returns `QOS_ERR_CAP_EXCEEDED`; no state changes.
  5. Checks `qos_bw_sum + bw_class(rs2) ≤ total_cn_budget(domain)`.
     If not, returns `QOS_ERR_SYSTEM_FULL`; no state changes.
  6. Sets `EC[rs1].bw_class[domain]` and `EC[rs1].lat_class[domain]`.
  7. If `domain_id` identifies a DMA channel, binds the DMA channel to ECID `rs1`.
  8. Updates the running bandwidth sum for all ancestor groups on this domain, up to
     the root.
  9. The change takes effect on the next `ec.ob` that loads ECID `rs1`.
* **Cycles**: 1–4 (O(1) cap check; ancestor sum update bounded by D ≤ 3).

---

### `qs.or` — Revoke the I/O Contract from an ECID

* **Syntax**: `qs.or rd, rs1`
  * `rs1`: Target ECID. The domain is inferred from the Contract currently held by `rs1`.
    If `rs1` holds Contracts on multiple domains, the `domain_id` must be specified in
    the low bits of `rd` on input (bits 15:0), with bit 16 set as a selector flag; if
    bit 16 is clear, all domains are revoked.
  * `rd`: 0 on success; error code on failure.
* **Semantics**:
  1. Sets `EC[rs1].bw_class[domain] = 0` and `EC[rs1].lat_class[domain] = 0` for the
     specified domain(s).
  2. Releases any DMA channel binding for those domains.
  3. Updates running bandwidth sums for ancestor groups.
  4. If ECID `rs1` is currently running on this hart, the change is applied immediately
     to the per-hart I/O fabric registers.
  5. If revoking all domains, child Contracts on each domain are revoked first,
     recursively (bounded by D ≤ 3).
* **Note**: Revoking a Contract does not destroy the ECID. Use `ec.oe` to destroy the
  ECID and all its resources (including all QoS Contracts on all domains) atomically.
* **Cycles**: 1–8 (proportional to domain count × subtree depth).

---

### `qs.it` — Delegate a child I/O Contract to a child ECID

* **Syntax**: `qs.it rd, rs1, rs2`
  * `rs1`: Parent ECID — the source whose Contract is being split.
  * `rs2`: Child ECID — the recipient; must satisfy `EC[rs2].delegation_L < D`. The
    `domain_id` and child `bw_class` share the same encoding as `qs.ir`'s `rs2`.
  * `rd`: 0 on success; error code on failure.
* **Semantics**:
  1. Verifies `rs2` is a child of `rs1` in the delegation tree.
  2. Verifies `rs1` holds a Contract on the specified domain.
  3. Performs the split: transfers a portion of `rs1`'s `bw_class` on the domain to
     `rs2`. The portion is encoded in `rs2` (bits 3:0 of `bw_class` field); if zero,
     the child inherits the parent's full class (useful when the parent relinquishes
     its own participation).
  4. Admission check: `bw_class(child) + existing_sum(subtree(rs1), domain) ≤ bw_cap(rs1, domain)`.
     If the check fails, returns `QOS_ERR_CAP_EXCEEDED`; no state changes.
  5. Updates running sums atomically.
* **Cycles**: 1–8 (log of delegation depth).

---

### `qs.ot` — Revoke a child I/O Contract back to the parent

* **Syntax**: `qs.ot rd, rs1`
  * `rs1`: Child ECID whose Contract is being revoked. Domain inferred from `rs1`'s
    current Contract binding; multiple-domain semantics same as `qs.or`.
  * `rd`: 0 on success; error code on failure.
* **Semantics**:
  1. Sets `EC[rs1].bw_class[domain] = 0` and `EC[rs1].lat_class[domain] = 0`.
  2. Returns the revoked `bw_class` to the parent's cap headroom for that domain.
  3. Releases any DMA channel binding.
  4. If `rs1` itself has child Contracts on this domain, those are revoked first
     (recursive, bounded by D ≤ 3). Always succeeds; cannot be stalled by a hostile
     context.
* **Cycles**: 1–8 (proportional to subtree depth, bounded by D).

---

## 8. Arbitration

### 8.1 Per-access arbitration (CN slots)

Within each CN slot on a given domain, the fabric arbiter selects one requesting EC
using the following rule, executed in O(1) hardware:

1. Collect all requesters (harts or DMA channels) with a pending I/O request on this
   domain and a non-zero `lat_class`.
2. Select the requester with the **lowest `lat_class` value** (highest priority).
3. Ties broken by round-robin among tied requesters.
4. Grant that requester a burst of size proportional to its `bw_class` (implementation
   maps `bw_class` to a burst length appropriate for the domain type).

Best-effort requesters (`lat_class = 0`) are not eligible in CN slots; they wait for
the next BE slot.

### 8.2 Per-access arbitration (BE slots)

All requesters with a pending request on this domain are eligible. Arbitration is
round-robin. Burst size is implementation-defined.

### 8.3 Admission control

Each domain independently prevents over-commitment of its CN slot budget. On every
`qs.ir` or `qs.it` call, hardware checks:

```
new_sum = qos_bw_sum(domain) + requested_bw_class
new_sum ≤ total_cn_budget(domain)
```

If the check fails, the instruction returns `QOS_ERR_SYSTEM_FULL` and no state changes.
This check is O(1): a single addition and comparison, per domain.

### 8.4 Group caps

Group caps (§5.2) are enforced on every `qs.ir` and `qs.it` call as described there.
No runtime per-access group check is needed: once admitted, the per-hart or per-channel
registers already encode the correct class bits.

---

## 9. Scheduling Window

QoS operates with a rolling **scheduling window** per domain — a period over which
bandwidth guarantees are measured. The window length is implementation-defined and
exposed in the domain descriptor array (§6.1) as `window_slots` per domain.

At the end of each window:

- Running per-EC and per-group bandwidth counters reset for that domain.
- Any EC that did not consume its full guaranteed CN slots in the previous window does
  **not** carry those slots forward (no accumulation). This prevents burst attacks where
  an EC saves up credit and floods the fabric.
- The fabric controller logs a `qos_violation` for any Contract holder on this domain
  that was eligible but did not receive its full `bw_class` worth of CN slots in the
  window.

Window length is a trade-off: shorter windows catch violations faster; longer windows
smooth bursty workloads. Typical values are 16–256 slots per domain.

---

## 10. Interaction with CME, CPE, and MSE

**CME.** On every `ec.ob` (context restore), CME atomically loads the new EC's full
bank state. The CP field in the bank (chapter 0 §0.6) carries the QoS Contract
parameters for each domain alongside the MSE parameters. The I/O fabric controllers
read per-hart registers; no separate QoS reconfiguration instruction is needed on a
normal context switch. For DMA channels, the per-channel registers are updated whenever
a `qs.ir` or `qs.or` call is issued, not on every `ec.ob`.

**CPE.** Cache partitioning (chapter 7) and QoS are complementary. CPE reduces
compulsory I/O traffic by keeping an EC's working set in its cache partition, which
reduces the load the EC places on the I/O fabric. An EC with both a CPE partition and
QoS Contracts has bounded latency on both the cache miss path (CPE) and the I/O path
(QoS).

**MSE.** The key pairing: a DMA transfer exercises two separate Contract chains
simultaneously — a QoS Contract on the I/O fabric side and an MSE Contract on the DRAM
side. An EC that initiates DMA needs both Contracts for end-to-end deterministic
behavior:

```
EC initiates DMA write to DRAM:
  qs Contract (DMA domain)  →  fabric arbitration  →  DMA engine
  ms Contract               →  memory controller   →  DRAM
```

Neither Contract governs the other's resource. Assigning only one is valid but yields
determinism only on that one resource leg.

A complete latency bound for a DMA-writing EC with both Contracts:

```
latency_max(end-to-end) = (K + 1) × qos_slot_ns(DMA domain)   // I/O side
                        + (K + 1) × mse_slot_ns                // DRAM side
```

---

## 11. Error Codes

| Code | Value | Meaning |
|---|---|---|
| `QOS_OK` | 0 | Success |
| `QOS_ERR_INVALID_ECID` | 1 | `rs1` is unallocated or generation-mismatched |
| `QOS_ERR_NOT_CHILD` | 2 | `rs2` is not a child of `rs1` in the delegation tree |
| `QOS_ERR_CAP_EXCEEDED` | 3 | Request would exceed group bandwidth cap on this domain |
| `QOS_ERR_SYSTEM_FULL` | 4 | Global CN budget for this domain exhausted; no room for new Contract |
| `QOS_ERR_PRIVILEGE` | 5 | Caller does not have permission to modify this ECID's Contract |
| `QOS_ERR_INVALID_DOMAIN` | 6 | `domain_id` does not correspond to a domain present on this implementation |
| `QOS_ERR_ALREADY_BOUND` | 7 | ECID already holds a Contract on this domain; revoke it first |
| `QOS_ERR_DOMAIN_BUSY` | 8 | DMA channel is already bound to another ECID |

All error codes are returned in `rd` or in `qos_status`. Silent failure is prohibited
(charter §6.6).

---

## 12. Out of Scope for v1

- **DRAM arbitration.** Covered by MSE (Chapter 8).
- **L1/L2 cache isolation.** Covered by CPE (Chapter 7).
- **Multi-resource Contracts.** Whether a single Contract can span multiple I/O domains
  or span I/O and memory is open (charter §8.2).
- **Software-overflow Contracts.** When hardware Contract slots on a domain are
  exhausted, the slow-path software fallback is not yet specified (charter §8.3).
- **Multi-socket / NUMA I/O fabric.** By analogy with MSE's NUMA open item, QoS
  Contract semantics across multiple NoC domains in a multi-socket system are not
  yet specified.

---

**Next:** Appendix A — ECID: Radix Tree, Allocation, and Forced-Destruction Algorithms
