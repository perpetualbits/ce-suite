<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Chapter 9 — MSE: Memory Scheduling Extension

## 9.1 Overview

The **Memory Scheduling Extension (MSE)** provides hardware-enforced deterministic
DRAM arbitration for shared SoCs. Its purpose is to make Worst-Case Execution Time
for memory-bound workloads *provable* rather than empirical — a prerequisite for
ASIL D, DO-178C, and FDA Class III certification.

MSE achieves this through two coordinated mechanisms:

1. **BE/Contract slot alternation.** Time at the memory controller is divided into
   alternating best-effort (BE) and contract (CN) slots. CN slots are reserved for
   ECIDs holding MSE Contracts; BE slots are available to all ECIDs opportunistically
   and can be preempted by interrupts. This gives hard latency and bandwidth bounds to
   Contract holders without starving best-effort traffic.

2. **Hierarchical Contract model.** Memory bandwidth and latency guarantees are
   represented as Contracts, owned by ECIDs, splittable to child ECIDs,
   and enforced in O(1) hardware per arbitration cycle. Group caps bound the total
   guaranteed bandwidth any ECID subtree can claim.

MSE is per-system (the memory controller is a shared resource across harts), but all
software interactions are per-hart and ECID-first: MSE instructions take ECID numbers
as operands, never raw pointers or opaque group IDs.

MSE v1 covers main DRAM arbitration only. NoC, DMA, and peripheral interconnect are
handled by QoS (Chapter 11). L1/L2 cache isolation is handled by CPE (Chapter 7).

---

## 9.2 The BE/Contract Slot Scheme

### 9.2.1 Alternating slots

The memory controller divides time into fixed-size **slots** (implementation-defined
size, typically one DRAM burst period). Slots alternate between two classes:

```
... | CN | BE | CN | BE | CN | BE | ...
```

- **CN (contract) slots** — served only to ECIDs holding an active MSE Contract whose
  latency class is non-zero. Within a CN slot, the arbitration rule in §9.7 selects
  which eligible EC is served.
- **BE (best-effort) slots** — available to any EC regardless of Contract status.
  BE slots are never reserved; any requesting EC may use them. They are also the
  landing zone for interrupts (§9.3).

The default split is 50 % CN / 50 % BE. Implementations may expose a configurable
split ratio via the `mse_slot_ratio` CSR (§9.6), but the BE fraction must be at least
25 % and the CN fraction at least 25 % to preserve the latency bounds in §9.3.

### 9.2.2 Slot size

Slot size is implementation-defined and exposed as a read-only value in `mse_slot_ns`
(nanoseconds per slot). Software uses this value to convert Contract latency classes
into wall-clock latency bounds. Slot sizes are typically 64–256 ns on current DRAM
technology.

### 9.2.3 Steady-state bandwidth

In steady state with N active Contract holders each claiming one CN slot per pair:

- Each Contract holder receives ≥ 50 % of its guaranteed minimum over any window of
  two consecutive slots.
- BE traffic fills all slots not consumed by Contract holders, so total bus utilization
  approaches 100 % under load.

### 9.2.4 Dithered slot scheduling and bounded gap

The slot pattern within a window must satisfy `mse_slot_ratio.CN_FRAC` over the
window's slot count. In addition, the maximum gap between consecutive CN slots is
bounded by ⌈256 / CN_FRAC⌉ slots, and the maximum gap between consecutive BE slots is
similarly bounded.

This bounded-gap property is required to preserve the worst-case CN latency guarantee
under interrupt nesting: a Contract holder waiting for its next CN slot waits at most
one gap period regardless of `CN_FRAC` value, which ensures the (K+1) × slot_size
latency bound in §9.3.2 remains valid across the full range of `CN_FRAC` settings.

Implementations satisfy this property by any mechanism. The spec specifies the
guarantee (bounded gap), not the mechanism.

**Example.** With `CN_FRAC = 192` (75% CN, 25% BE), the maximum CN gap is
⌈256/192⌉ = 2. The repeating 4-slot pattern CCCB... satisfies this: every 4 slots
holds exactly 3 CN and 1 BE, and the longest gap between two CN slots is 1 (one BE
slot separating them). A Contract holder waiting for its next CN slot waits at most 1
additional slot period. By contrast, placing all 192 CN slots contiguously would
create a 64-slot gap for BE traffic — 64 times the bounded-gap worst case.

---

## 9.3 Interrupt Accommodation and Latency Bounds

### 9.3.1 Interrupts absorb into BE slots

When an interrupt fires, its handler executes as a new EC on the interrupted hart.
If that handler needs DRAM access, it competes in the next available BE slot. Because
BE slots occur at least every other slot, the maximum additional memory-access latency
imposed on an interrupt handler is **one slot** beyond whatever DRAM latency is already
in flight.

CN slots are never preempted by an interrupt. This is what keeps Contract holders'
bandwidth guarantees intact under interrupt load.

### 9.3.2 Nested interrupts and the nesting cap K

Interrupt nesting extends the worst-case latency for CN slots. MSE defines a
parameter **K** — the maximum hardware-tolerated interrupt nesting depth — exposed via
the read-only CSR `mse_max_nesting`. The value K is independent of the ECID
delegation depth cap D; they are unrelated parameters.

Under worst-case nesting of depth K, CN slots are delayed but not skipped:

```
IN₁ | CN | IN₂ | CN | ... | INₖ | CN | BE | CN | BE | ...
```

After all K interrupt handlers complete, the alternation phase is corrected by
adjusting the next BE slot; no drift accumulates across windows.

**Maximum latency for a CN slot** under nesting depth K:

```
latency_max = (K + 1) × slot_size
```

**Contract bandwidth** remains at the configured CN fraction regardless of K.

### 9.3.3 Practical values

| K | Worst-case CN latency | Notes |
|---|---|---|
| 0 | 1 × slot | No interrupt nesting permitted |
| 1 | 2 × slot | NMI only (typical Linux) |
| 2 | 3 × slot | NMI + one preemptible IRQ level |
| 3 | 4 × slot | Deepest nesting CE supports |

K = 1 is the recommended default. K > 3 voids the latency guarantee for CN slots
and is not permitted by MSE v1.

---

## 9.4 MSE Contracts

MSE Contracts are instances of the general Contract model (Chapter 0 §0.7). This section
specifies the MSE-specific parameters each Contract carries.

### 9.4.1 Contract parameters

Per Chapter 0 §0.7.0, an MSE Contract is identified by
`(owning_ECID, MSE)` and consists of the parameters below stored in the bank's
CP field plus admission-control state in implementation-defined per-controller SRAM.

Each MSE Contract holds two fields set by the privileged actor that creates it:

| Field | Architectural width | Meaning |
|---|---|---|
| `bw_class` | 8 bits max | Guaranteed minimum CN slots per window, on the pre-flattened 0–255 absolute scale (see §9.4.5). 0 = best-effort only. |
| `lat_class` | 8 bits max | Priority within CN slot arbitration. Lower value = higher priority. 0 = best-effort only. |

Both fields have a maximum architectural width of 8 bits. Implementations may decode
fewer bits and advertise the actual decoded width via the `mse_caps` CSR (Chapter 13).
The minimum supported decoded width is 4 bits per field for meaningful MSE support.
Software discovers the actual decoded widths by reading `mse_caps`.

Both fields are zero for best-effort ECIDs. An ECID with both fields non-zero is a
**Contract holder**; it participates in CN slot arbitration.

`bw_class` and `lat_class` are carried in the bank's CP field (Chapter 0 §0.6) and
loaded atomically by `ec.ob` on context switch. The memory controller reads these
fields from per-hart registers, not from RAM, during arbitration.

### 9.4.2 Group bandwidth cap

The privileged actor that creates an ECID may set a **group bandwidth cap** on it:
a ceiling on the total pre-flattened `bw_class` sum across all ECIDs in that ECID's
delegation subtree. The cap is stored in `EC[e]` (implementation-defined field) and
checked in O(1) on every `ms.ir` and `ms.it` call.

Hardware enforces the cap on pre-flattened absolute values:

```
sum(pre-flattened bw_class, subtree(e)) ≤ bw_cap(e)
```

where all values are on the 0–255 absolute scale.

A child cannot claim more guaranteed bandwidth than the parent has delegated. This is
the mechanism that prevents a tenant VM from over-committing global memory resources.

Round-down rounding during telescoping (§9.4.3) typically creates a small residual
within each group — the sum of children's pre-flattened values is less than the
parent's due to rounding. This residual is not lost: it flows via the multi-tier
over-budget overflow or BE fallthrough in §9.7.1.

### 9.4.3 Hierarchical splitting and telescoping

A privileged actor may split an MSE Contract into a parent Contract and one or more
child Contracts via `ms.it` (§9.5). Splitting is **atomic**: if the hardware admission
check fails, no state is changed.

**Telescoping.** When delegating, the parent specifies the child's bandwidth share as
a value on the parent's local precision scale. The hardware computes the child's
pre-flattened bandwidth by multiplying the parent's pre-flattened value by the child's
fraction, rounded down:

```
child_pre_flattened = floor(parent_pre_flattened × (child_bw_class / parent_scale))
```

where `parent_scale` is the parent's local precision range (e.g., 256 for 8-bit
precision). The result is stored as the child's pre-flattened value. The parent may
optionally specify the child's local precision (1–8 bits) in the delegation descriptor
(§9.5 `ms.it`); if omitted, the child uses the parent's precision.

**Cap enforcement.** The sum of all children's pre-flattened `bw_class` values must
not exceed the parent's pre-flattened `bw_class` (§9.4.2). Round-down guarantees this
invariant holds even at the extreme, since `floor(x) ≤ x` always.

**Example.** A hypervisor holds pre-flattened `bw_class = 76`. It delegates to three
VMs at 50%, 25%, and 12% of its slice:

- VM-A: floor(76 × 50/100) = 38
- VM-B: floor(76 × 25/100) = 19
- VM-C: floor(76 × 12/100) = floor(9.12) = 9

Sum of children = 66. Residual = 76 − 66 = 10, available for over-budget overflow via
§9.7.1 tier 2.

### 9.4.4 Dissolution

When an ECID's Contract is revoked (via `ms.or` or `ec.oe`), the Contract dissolves
and its pre-flattened `bw_class` is returned to the parent ECID's cap headroom. If
the ECID has child Contracts, those are revoked first, recursively. This is always
O(log N) via the radix tree and always succeeds — even for zombie or hostile ECIDs.

### 9.4.5 Pre-flattening

The hardware maintains the **pre-flattened `bw_class`** in the leaf Contract: the
absolute bandwidth value on the 0–255 scale computed once at delegation time (§9.4.3).
Arbitration reads this value in O(1) with no runtime multiplication.

When a parent Contract is reconfigured (its pre-flattened bandwidth changes via a
privileged operation), all descendant Contracts in its subtree are recomputed. The
recomputation must complete before the next arbitration cycle that involves any
affected Contract holder. Implementations may briefly stall arbitration on affected
harts during recomputation; non-affected harts continue unaffected.

The `mse_absolute_bw` CSR (specified in Chapter 13) allows software to read the
running EC's effective pre-flattened `bw_class` — the value the memory controller uses
in arbitration. This is useful for monitoring, admission-control accounting, and
debugging.

---

## 9.5 MSE Instructions

All MSE instructions are privileged. They follow the naming scheme
`ms.{i,o}{target}`. MSE uses the subset `{r, t}`:

| Letter | Target / kind |
|---|---|
| `r` | resource (memory Contract) |
| `t` | tenant (child Contract delegation) |

**ECID-first operands.** Any MSE instruction targeting a context other than the
current one takes an ECID number as its primary operand — never a pointer, never an
opaque group ID.

> **Memory ordering.** MSE Contract instructions operate on per-hart hardware
> registers and SRAM; they carry no implicit memory fence. Cross-hart coordination
> during EC migration requires explicit `FENCE` instructions. See Chapter 17.

---

### `ms.ir` — Assign a memory Contract to an ECID

> `ms.ir` = memory scheduling into resource (`ms` = MSE, `i` = into/assign, `r` = resource)

* **Syntax**: `ms.ir rd, rs1, rs2`
  * `rd`: 0 on success; error code on failure.
  * `rs1`: Target ECID.
  * `rs2`: Contract parameters. Inline form (bit `[XLEN-1]` = 0): bits 7:0 =
    `bw_class`, bits 15:8 = `lat_class`, bits `[XLEN-2]`:16 reserved (must be zero).
    Pointer form (bit `[XLEN-1]` = 1): bits `[XLEN-2]`:0 are a pointer to an
    `MSE_Contract_Params` struct (see below).
* **Pointer form struct:**
```c
struct MSE_Contract_Params {
    uint8_t  bw_class;    /* pre-flattened bandwidth class, 0–255 (0 = best-effort) */
    uint8_t  lat_class;   /* latency class, 0–255 (0 = best-effort) */
    uint16_t reserved;    /* must be zero */
};
```
* **Semantics**:
  1. Checks that `rs1` is a valid, allocated ECID on this hart.
  2. Checks that `bw_class(rs2) + existing_sum(subtree(parent(rs1))) ≤ bw_cap(parent(rs1))`
     (all values on 0–255 absolute scale). If not, returns `MSE_ERR_CAP_EXCEEDED` in
     `rd`; no state changes.
  3. Sets `EC[rs1].bw_class` and `EC[rs1].lat_class` to the supplied values (stored as
     pre-flattened absolute values on the 0–255 scale).
  4. Updates the running pre-flattened bandwidth sum for all ancestor groups up to the
     root.
  5. The change takes effect on the next `ec.ob` that loads ECID `rs1`. If ECID
     `rs1` is currently running on this hart, the new Contract parameters are
     applied immediately to the per-hart memory controller registers; the new
     class values take effect at the next CN slot boundary.
* **Cycles**: 1–4 (O(1) cap check; ancestor sum update is bounded by D ≤ 3).

---

### `ms.or` — Revoke the memory Contract from an ECID

> `ms.or` = memory scheduling out of resource (`ms` = MSE, `o` = out of/revoke, `r` = resource)

* **Syntax**: `ms.or rd, rs1`
  * `rd`: 0 on success; error code on failure.
  * `rs1`: Target ECID.
* **Semantics**:
  1. Sets `EC[rs1].bw_class = 0` and `EC[rs1].lat_class = 0`.
  2. Updates running bandwidth sums for ancestor groups.
  3. The change takes effect on the next `ec.ob` that loads ECID `rs1`. If ECID `rs1`
     is currently running on this hart, the change is applied immediately to the
     per-hart memory controller registers.
* **Note**: Revoking a Contract does not destroy the ECID. Use `ec.oe` to destroy
  the ECID and all its resources (including any Contract) atomically.
* **Cycles**: 1–4.

---

### `ms.it` — Delegate a child Contract to a child ECID

> `ms.it` = memory scheduling into tenant (`ms` = MSE, `i` = into/delegate, `t` = tenant/child ECID)

* **Syntax**: `ms.it rd, rs1, rs2`
  * `rd`: 0 on success; error code on failure.
  * `rs1`: Parent ECID — the source whose Contract is being split.
  * `rs2`: Delegation descriptor. Inline form (bit `[XLEN-1]` = 0):

  | Bits | Field | Meaning |
  |---|---|---|
  | 15:0 | `child_ecid` | Child ECID to receive the split Contract |
  | 23:16 | `child_bw_class` | Bandwidth class to delegate on parent's precision scale (0 = inherit parent's full class) |
  | 31:24 | `child_lat_class` | Latency class to delegate (0 = inherit parent's full class). On RV32, only bits 30:24 (7 bits); values 128–255 require pointer form. |
  | 35:32 *(RV64 only)* | `child_precision` | Child's local precision in bits (1–8). 0 = use parent's precision unchanged. |
  | `[XLEN-2]`:36 | — | Reserved; must be zero. On RV32, no bits are available here. |
  | `[XLEN-1]` | `ptr` | 1 = pointer form; bits `[XLEN-2]`:0 point to `MSE_Delegation_Params` |

  Pointer form struct:
```c
struct MSE_Delegation_Params {
    uint16_t child_ecid;       /* child ECID to receive the split Contract */
    uint8_t  child_bw_class;   /* bandwidth class on parent's precision scale (0 = inherit) */
    uint8_t  child_lat_class;  /* latency class to delegate (0 = inherit parent's) */
    uint8_t  child_precision;  /* child's local precision 1–8 bits; 0 = use parent's unchanged */
    uint8_t  reserved1;        /* must be zero */
    uint16_t reserved2;        /* must be zero */
};
```

  `child_ecid` must satisfy `EC[child_ecid].delegation_L < D`.

* **Semantics**:
  1. Verifies `child_ecid` is a child of `rs1` in the delegation tree.
  2. Computes the child's pre-flattened bandwidth:
     `floor(parent_pre_flattened × (child_bw_class / parent_scale))`. If
     `child_bw_class` = 0, the child inherits the parent's full pre-flattened value.
     If `child_precision` is non-zero, sets the child's local precision accordingly;
     otherwise the child uses the parent's precision.
  3. Admission check: `pre_flattened(child) + existing_sum(subtree(rs1)) ≤ bw_cap(rs1)`
     (all values on 0–255 absolute scale). If the check fails, returns
     `MSE_ERR_CAP_EXCEEDED`; no state changes.
  4. Updates running pre-flattened sums atomically.
* **Cycles**: 1–8 (log of delegation depth).

---

### `ms.ot` — Revoke a child Contract back to the parent

> `ms.ot` = memory scheduling out of tenant (`ms` = MSE, `o` = out of/revoke, `t` = tenant/child ECID)

* **Syntax**: `ms.ot rd, rs1`
  * `rs1`: Child ECID whose Contract is being revoked.
  * `rd`: 0 on success; error code on failure.
* **Semantics**:
  1. Sets `EC[rs1].bw_class = 0` and `EC[rs1].lat_class = 0`.
  2. Returns the revoked `bw_class` to the parent's cap headroom.
  3. If `rs1` itself has child Contracts, those are revoked first (recursive, bounded
     by D ≤ 3). Always succeeds; cannot be stalled by a hostile context.
* **Cycles**: 1–8 (proportional to subtree depth, bounded by D).

---

## 9.6 MSE CSRs

| CSR | Access | Purpose |
|---|---|---|
| `mse_slot_ratio` | RW (privileged) | CN/BE slot split. Bits 7:0 = CN fraction (0–255, where 128 = 50 %). Implementations may restrict to a set of legal values. |
| `mse_slot_ns` | RO | Slot size in nanoseconds (implementation-defined). |
| `mse_max_nesting` | RO | Maximum interrupt nesting depth K supported by this implementation. |
| `mse_bw_cap` | RW (privileged) | Per-hart register holding the pre-flattened bandwidth cap for the currently loaded ECID's group. Updated by `ms.ir` / `ms.it` / `ms.ot`. |
| `mse_bw_sum` | RO | Running sum of pre-flattened `bw_class` across all active Contract holders on this hart. |
| `mse_absolute_bw` | RO | Pre-flattened `bw_class` of the currently running EC on this hart — the value the memory controller uses in arbitration. Useful for monitoring and debugging. Full specification in Chapter 13. |
| `mse_caps` | RO | Capability register advertising the implementation's decoded field widths for `bw_class` and `lat_class`, and other MSE parameters. Full specification in Chapter 13. |
| `mse_status` | RO | Result code from the last MSE operation on this hart. |
| `mse_violation` | RO (sticky) | Set when a Contract holder does not receive its guaranteed CN slot in the expected window. Cleared by writing 1. Raises an interrupt if `mse_violation_en` is set. |
| `mse_violation_en` | RW (privileged) | Enable interrupt on `mse_violation`. |

---

## 9.7 Arbitration

### 9.7.1 Per-access arbitration (CN slots) — multi-tier policy

Within each CN slot, the memory controller selects the winning Contract holder using
the following three-tier rule, executed in O(1) hardware:

**Tier 1 — Within-budget Contract holders.** A Contract holder is *within budget* when
it has consumed fewer than its guaranteed `bw_class` slots in the current window.
Among all within-budget harts with a pending DRAM request, the hart with the lowest
`lat_class` value wins (lower = higher priority). Ties are broken by round-robin: each
hart's most-recent grant time is tracked; among equally-prioritized contenders the
least-recently-served hart wins.

**Tier 2 — Over-budget Contract holders.** If no within-budget Contract holder
requests memory in this CN slot, Contract holders that have already consumed their
full `bw_class` guaranteed slots but still want memory compete. Selection follows the
same rule: lowest `lat_class` wins, round-robin tie-break.

**Tier 3 — Best-effort fallthrough.** If no Contract holder of any tier requests
memory in this CN slot, the slot becomes available to best-effort traffic. BE harts
compete by round-robin.

A BE slot (from the `mse_slot_ratio` alternation) is always available to best-effort
traffic independently of the CN slot policy.

The tier ordering guarantees three properties:
- Every Contract holder receives at least its promised `bw_class` slots per window
  (tier 1 serves within-budget holders before over-budget demands).
- Idle Contract bandwidth does not go to waste (tiers 2 and 3 absorb it).
- BE traffic always has a path to memory via dedicated BE slots plus CN fallthrough.

Best-effort requests (zero `lat_class`) are never eligible in CN slots; they wait for
the next BE slot.

**Worked example.** Window = 256 slots. `CN_FRAC = 128` (50/50), giving 128 CN and
128 BE slots per window (dithered per §9.2.4). Three active Contracts, all requesting
memory throughout the window:

| EC | `bw_class` | `lat_class` | Budget |
|---|---|---|---|
| EC-A | 8 | 1 *(highest priority)* | 8 slots |
| EC-B | 4 | 3 | 4 slots |
| EC-C | 16 | 5 | 16 slots |

**CN slots 1–8:** EC-A, EC-B, EC-C all within budget. EC-A has `lat_class = 1`
(lowest) and wins all 8 slots. EC-A is now at budget.

**CN slots 9–12:** EC-B and EC-C within budget; EC-A over-budget. EC-B wins
(`lat_class = 3 < 5`). EC-B is now at budget.

**CN slots 13–28:** Only EC-C within budget. EC-C wins all 16 slots. EC-C is now at
budget. Within-budget phase complete: 8 + 4 + 16 = 28 CN slots used.

**CN slots 29–128:** All Contracts over-budget (tier 2). EC-A has `lat_class = 1`
(highest priority among over-budget holders) and wins all 100 remaining CN slots.

Final tally: EC-A = 8 (guaranteed) + 100 (over-budget) = 108 total CN slots. EC-B = 4.
EC-C = 16. All three received their guaranteed minimum; no CN slot was unused.

### 9.7.2 Per-access arbitration (BE slots)

All harts with a pending request are eligible. Arbitration is round-robin. Burst size
is implementation-defined (typically one cache line per BE slot).

### 9.7.3 Admission control

Admission control prevents over-commitment of the CN slot budget. The hardware
maintains a running sum of `bw_class` across all active Contract holders (visible in
`mse_bw_sum`). On every `ms.ir` or `ms.it` call, hardware checks:

```
new_sum = mse_bw_sum + requested_bw_class
new_sum ≤ mse_total_cn_budget
```

where `mse_total_cn_budget` is a fixed constant derived from the slot ratio and
implementation capacity. If the check fails, the instruction returns
`MSE_ERR_SYSTEM_FULL` and no state changes.

This check is O(1): a single addition and comparison.

### 9.7.4 Group caps

Group caps (§9.4.2) are enforced on every `ms.ir` and `ms.it` call as described there.
No runtime per-access group check is needed: once admitted, the per-hart registers
already encode the correct class bits.

---

## 9.8 Scheduling Window

MSE operates with a rolling **scheduling window** — a period over which bandwidth
guarantees are measured. The window length is implementation-defined and exposed in
`mse_window_slots` (number of slots per window).

At the end of each window:

- Running per-EC and per-group bandwidth counters reset.
- Any EC that did not consume its full guaranteed CN slots in the previous window
  does **not** carry those slots forward (no accumulation). This prevents burst
  attacks where an EC saves up credit and then floods the bus.
- The memory controller logs a `mse_violation` for any Contract holder that was
  eligible but did not receive its full `bw_class` worth of CN slots in the window.

Window length is a trade-off: shorter windows catch violations faster but impose more
reset overhead; longer windows smooth out bursty workloads. Typical values are
16–256 slots.

---

## 9.9 Interaction with CME and CPE

**CME.** On every `ec.ob` (context restore), CME atomically loads the new EC's full
bank state, which includes the `bw_class` and `lat_class` fields in the CP slot (see
chapter 0 §0.6). The memory controller reads these from per-hart registers; the switch
is therefore instantaneous from the memory controller's perspective — no separate MSE
reconfiguration instruction is needed on a normal context switch.

**CPE.** Cache partitioning (chapter 7) and MSE are complementary:

- CPE guarantees that an EC's L1/L2-private cache lines are not evicted by other ECs.
  When an EC's working set fits in its cache partition, all its memory accesses are
  served from cache and MSE slots are irrelevant for that EC.
- MSE governs uncached accesses and accesses that miss the cache partition. The
  combination — CPE for cache isolation, MSE for DRAM determinism — gives end-to-end
  bounded memory latency for real-time workloads.

An EC with both a CPE cache partition and an MSE Contract has:

- 1-cycle cache access latency (CPE guarantee, for cached data)
- ≤ (K + 1) × slot_size DRAM access latency (MSE guarantee, for uncached data)

---

## 9.10 Error Codes

| Code | Value | Meaning |
|---|---|---|
| `MSE_OK` | 0 | Success |
| `MSE_ERR_INVALID_ECID` | 1 | `rs1` is unallocated or generation-mismatched |
| `MSE_ERR_NOT_CHILD` | 2 | `rs2` is not a child of `rs1` in the delegation tree |
| `MSE_ERR_CAP_EXCEEDED` | 3 | Request would exceed group bandwidth cap |
| `MSE_ERR_SYSTEM_FULL` | 4 | Global CN budget exhausted; no room for new Contract |
| `MSE_ERR_PRIVILEGE` | 5 | Caller does not have permission to modify this ECID's Contract |

All error codes are returned in `rd` or in `mse_status`. Silent failure is prohibited
Silent failure is prohibited.

---

## 9.11 Instruction Encoding

All CE Suite instructions share the same R-type format and custom-0 opcode
(`0001011`). See Chapter 3 §3.10.1–§3.10.2 for the bitfield diagram and the
funct3 extension-selector table.

**MSE uses funct3 = `010`.**

### 9.11.1 MSE instruction encoding (funct3 = `010`)

| funct7      | Mnemonic | rd field | rs1 field    | rs2 field                 |
|-------------|----------|----------|--------------|---------------------------|
| `0000000`   | `ms.ir`  | result   | target ECID  | contract parameters       |
| `0000001`   | `ms.or`  | result   | target ECID  | `00000`                   |
| `0000010`   | `ms.it`  | result   | parent ECID  | delegation descriptor     |
| `0000011`   | `ms.ot`  | result   | child ECID   | `00000`                   |

funct7 values `0000100`–`1111111` (4–127) are reserved for future MSE instructions.

`ms.or` and `ms.ot` carry no `rs2` operand; the rs2 field is encoded as `00000` (x0).

### 9.11.2 Encoding examples

`ms.ir a0, a1, a2` — assign memory Contract (parameters in a2) to ECID in a1,
result in a0 (a0=x10=`01010`, a1=x11=`01011`, a2=x12=`01100`):

```
 31      25  24    20  19    15 14  12 11     7 6      0
┌─────────┬────────┬────────┬──────┬────────┬─────────┐
│ 0000000 │ 01100  │ 01011  │ 010  │ 01010  │ 0001011 │
└─────────┴────────┴────────┴──────┴────────┴─────────┘
  ms.ir      rs2=a2   rs1=a1   MSE    rd=a0   custom-0
```

`ms.or a0, a1` — revoke memory Contract from ECID in a1, result in a0:

```
 31      25  24    20  19    15 14  12 11     7 6      0
┌─────────┬────────┬────────┬──────┬────────┬─────────┐
│ 0000001 │ 00000  │ 01011  │ 010  │ 01010  │ 0001011 │
└─────────┴────────┴────────┴──────┴────────┴─────────┘
  ms.or      rs2=x0   rs1=a1   MSE    rd=a0   custom-0
```

---

## 9.12 Out of Scope for v1

- **NoC, DMA, and peripheral arbitration.** Covered by QoS (Chapter 11).
- **NUMA-aware Contract assignment.** Multi-socket NUMA semantics for MSE Contracts
  are deferred to a future revision.
- **Multi-resource Contracts.** Whether a single Contract can span memory and I/O
  is deferred to a future revision.
- **Software-overflow Contracts.** When hardware MSE Contract slots are exhausted,
  `ms.ir`/`ms.it` return `MSE_ERR_SYSTEM_FULL` (4). The slow-path response is
  implementation-defined for v1.0: software may deny the request, queue the
  Contract, or use another strategy. Richer slow-path semantics are deferred.
- **Cross-hart ECS sharing during migration.** Deferred to a future revision.

---

## 9.13 Worked Example: Telescoping Delegation and Multi-Tier Arbitration

This section shows the complete MSE flow for a hypervisor managing three virtual
machines: bandwidth allocation via telescoping delegation, arbitration across a
scheduling window, and the interplay of guaranteed minimum and over-budget consumption.
The scenario is representative of a L=1 hypervisor in a mixed-criticality system.

### 9.13.1 Setup

The system has 256-slot windows with `CN_FRAC = 128` (50/50 CN/BE split), dithered
per §9.2.4, giving 128 CN and 128 BE slots per window. The root ECID (L=0) holds
`bw_class = 255` (full system bandwidth). Firmware delegates a 30% slice to a
hypervisor ECID (hyp_ecid, L=1) and the hypervisor creates three guest ECIDs (L=2).

**Step 1.** Hypervisor claims its bandwidth via `ms.ir`. A 30% share of 256 =
floor(76.8) = 76 (round-down).

```asm
# Inline ms.ir: bits 7:0 = bw_class = 76, bits 15:8 = lat_class = 2
li   a2, ((2 << 8) | 76)      # 0x0240
ms.ir a0, hyp_ecid, a2         # a0 = 0 on success
```

Hypervisor's pre-flattened `bw_class` = 76.

**Step 2.** Hypervisor delegates to three VMs via `ms.it`.

| VM | Requested fraction | Pre-flattened `bw_class` | `lat_class` |
|---|---|---|---|
| VM-A (high priority) | 50% of 76 | floor(38.0) = 38 | 1 |
| VM-B (medium priority) | 25% of 76 | floor(19.0) = 19 | 5 |
| VM-C (low priority) | 12% of 76 | floor(9.12) = 9 | 10 |

Residual in hypervisor: 76 − (38 + 19 + 9) = 10 units, available for over-budget
overflow to the hypervisor's subtree.

```asm
# Delegate to VM-A: child_bw_class = 38, child_lat_class = 1
# Inline ms.it: bits 15:0 = child_ecid, 23:16 = child_bw_class, 31:24 = child_lat_class
li   t0, vm_a_ecid
ori  t0, t0, (38 << 16)        # child_bw_class = 38
ori  t0, t0, (1 << 24)         # child_lat_class = 1
ms.it a0, hyp_ecid, t0

# Delegate to VM-B: child_bw_class = 19, child_lat_class = 5
li   t0, vm_b_ecid
ori  t0, t0, (19 << 16)
ori  t0, t0, (5 << 24)
ms.it a0, hyp_ecid, t0

# Delegate to VM-C: child_bw_class = 9, child_lat_class = 10
li   t0, vm_c_ecid
ori  t0, t0, (9 << 16)
ori  t0, t0, (10 << 24)
ms.it a0, hyp_ecid, t0
```

### 9.13.2 A typical scheduling window (all VMs active)

All three VMs are requesting memory throughout the window (128 CN slots available).

**Within-budget phase (tier 1):**

- CN slots 1–38: VM-A wins all (`lat_class = 1` lowest). VM-A budget exhausted.
- CN slots 39–57: VM-B wins all (`lat_class = 5` next lowest). VM-B budget exhausted.
- CN slots 58–66: VM-C wins all (`lat_class = 10`). VM-C budget exhausted.
- Total within-budget consumption: 38 + 19 + 9 = 66 CN slots.

**Over-budget phase (tier 2):**

- CN slots 67–128: All three VMs over-budget. VM-A has `lat_class = 1` (highest
  priority) and wins all 62 remaining CN slots.

**Final tally:**

| VM | Guaranteed | Received | Guarantee met? |
|---|---|---|---|
| VM-A | 38 | 38 + 62 = 100 | ✓ |
| VM-B | 19 | 19 | ✓ |
| VM-C | 9 | 9 | ✓ |

All VMs received their guaranteed minimum. VM-A's high `lat_class` priority caused it
to absorb the over-budget bandwidth. VM-B and VM-C were unharmed — the tier 1 rule
served their budgets first.

### 9.13.3 A window where VM-A is idle

If VM-A makes no DRAM requests in a window, tier 1 finds no requester for VM-A's 38
budget slots. Those CN slots fall to tier 2 (VM-B and VM-C compete; VM-B wins by
`lat_class`) or tier 3 (BE fallthrough if neither VM-B nor VM-C wants more). No slot
goes unused.

This illustrates the guaranteed-minimum-but-no-waste property: unused budget flows
usefully to other Contract holders or best-effort traffic rather than being discarded.

---

[Next: Chapter 10 — MSE Usage Examples](ch10-mse-usage-examples.md)
