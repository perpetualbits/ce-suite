# Chapter 9 — MSE: Memory Scheduling Extension

## 1. Overview

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
   represented as Contracts (charter §4.3), owned by ECIDs, splittable to child ECIDs,
   and enforced in O(1) hardware per arbitration cycle. Group caps bound the total
   guaranteed bandwidth any ECID subtree can claim.

MSE is per-system (the memory controller is a shared resource across harts), but all
software interactions are per-hart and ECID-first: MSE instructions take ECID numbers
as operands, never raw pointers or opaque group IDs.

MSE v1 covers main DRAM arbitration only. NoC, DMA, and peripheral interconnect are
handled by QoS (Chapter 11). L1/L2 cache isolation is handled by CPE (Chapter 7).

---

## 2. The BE/Contract Slot Scheme

### 2.1 Alternating slots

The memory controller divides time into fixed-size **slots** (implementation-defined
size, typically one DRAM burst period). Slots alternate between two classes:

```
... | CN | BE | CN | BE | CN | BE | ...
```

- **CN (contract) slots** — served only to ECIDs holding an active MSE Contract whose
  latency class is non-zero. Within a CN slot, the arbitration rule in §7 selects
  which eligible EC is served.
- **BE (best-effort) slots** — available to any EC regardless of Contract status.
  BE slots are never reserved; any requesting EC may use them. They are also the
  landing zone for interrupts (§3).

The default split is 50 % CN / 50 % BE. Implementations may expose a configurable
split ratio via the `mse_slot_ratio` CSR (§6), but the BE fraction must be at least
25 % and the CN fraction at least 25 % to preserve the latency bounds in §3.

### 2.2 Slot size

Slot size is implementation-defined and exposed as a read-only value in `mse_slot_ns`
(nanoseconds per slot). Software uses this value to convert Contract latency classes
into wall-clock latency bounds. Slot sizes are typically 64–256 ns on current DRAM
technology.

### 2.3 Steady-state bandwidth

In steady state with N active Contract holders each claiming one CN slot per pair:

- Each Contract holder receives ≥ 50 % of its guaranteed minimum over any window of
  two consecutive slots.
- BE traffic fills all slots not consumed by Contract holders, so total bus utilization
  approaches 100 % under load.

---

## 3. Interrupt Accommodation and Latency Bounds

### 3.1 Interrupts absorb into BE slots

When an interrupt fires, its handler executes as a new EC on the interrupted hart.
If that handler needs DRAM access, it competes in the next available BE slot. Because
BE slots occur at least every other slot, the maximum additional memory-access latency
imposed on an interrupt handler is **one slot** beyond whatever DRAM latency is already
in flight.

CN slots are never preempted by an interrupt. This is what keeps Contract holders'
bandwidth guarantees intact under interrupt load.

### 3.2 Nested interrupts and the nesting cap K

Interrupt nesting extends the worst-case latency for CN slots. MSE defines a
parameter **K** — the maximum hardware-tolerated interrupt nesting depth — exposed via
the read-only CSR `mse_max_nesting`. The value K is independent of the ECID
delegation depth cap D (charter §5.1); they are unrelated parameters.

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

### 3.3 Practical values

| K | Worst-case CN latency | Notes |
|---|---|---|
| 0 | 1 × slot | No interrupt nesting permitted |
| 1 | 2 × slot | NMI only (typical Linux) |
| 2 | 3 × slot | NMI + one preemptible IRQ level |
| 3 | 4 × slot | Deepest nesting CE supports |

K = 1 is the recommended default. K > 3 voids the latency guarantee for CN slots
and is not permitted by MSE v1.

---

## 4. MSE Contracts

MSE Contracts are instances of the general Contract model (charter §4.3). This section
specifies the MSE-specific parameters each Contract carries.

### 4.1 Contract parameters

Each MSE Contract holds two fields set by the privileged actor that creates it:

| Field | Width | Meaning |
|---|---|---|
| `bw_class` | 4 bits | Minimum bandwidth class: how many CN slots per window the holder is guaranteed. 0 = best-effort only. |
| `lat_class` | 4 bits | Latency class: priority within CN slot arbitration. Lower value = higher priority. 0 = best-effort only. |

Both fields are zero for best-effort ECIDs. An ECID with both fields non-zero is a
**Contract holder**; it participates in CN slot arbitration.

`bw_class` and `lat_class` are carried in the bank's CP field (chapter 0 §0.6) and
loaded atomically by `ec.ob` on context switch. The memory controller reads these
fields from per-hart registers, not from RAM, during arbitration.

### 4.2 Group bandwidth cap

The privileged actor that creates an ECID may set a **group bandwidth cap** on it:
a ceiling on the total `bw_class` sum across all ECIDs in that ECID's delegation
subtree. The cap is stored in `EC[e]` (implementation-defined field) and checked in
O(1) on every `ms.ir` call.

Hardware enforces:

```
sum(bw_class, subtree(e)) ≤ bw_cap(e)
```

A child cannot claim more guaranteed bandwidth than the parent has delegated. This
is the mechanism that prevents a tenant VM from over-committing global memory
resources.

### 4.3 Hierarchical splitting

A privileged actor may split an MSE Contract into a parent Contract and one or more
child Contracts (charter §4.3.2). Each child's `bw_class` must be ≤ the parent's
`bw_class` minus what the parent retains. The sum of all children's `bw_class` values
must never exceed the parent's `bw_class`.

Splitting is performed via `ms.it` (§5.3) and is **atomic**: if the hardware
admission check fails, no state is changed (charter §4.3.3).

### 4.4 Dissolution

When an ECID's Contract is revoked (via `ms.or` or `ec.oe`), the Contract dissolves
and its `bw_class` is returned to the parent ECID's cap headroom. If the ECID has
child Contracts, those are revoked first, recursively (charter §4.3.4). This is
always O(log N) via the radix tree and always succeeds — even for zombie or hostile
ECIDs.

---

## 5. MSE Instructions

All MSE instructions are privileged. They follow the naming scheme
`ms.{i,o}{target}` (charter §6.1). MSE uses the subset `{r, t}`:

| Letter | Target / kind |
|---|---|
| `r` | resource (memory Contract) |
| `t` | tenant (child Contract delegation) |

**ECID-first operands.** Any MSE instruction targeting a context other than the
current one takes an ECID number as its primary operand — never a pointer, never an
opaque group ID (charter §6.2).

---

### `ms.ir` — Assign a memory Contract to an ECID

* **Syntax**: `ms.ir rd, rs1, rs2`
  * `rd`: 0 on success; error code on failure.
  * `rs1`: Target ECID.
  * `rs2`: Contract parameters. Inline form (bit `[XLEN-1]` = 0): bits 3:0 =
    `bw_class`, bits 7:4 = `lat_class`, bits `[XLEN-2]`:8 reserved (must be zero).
    Pointer form (bit `[XLEN-1]` = 1): bits `[XLEN-2]`:0 are a pointer to an
    `MSE_Contract_Params` struct (see below).
* **Pointer form struct:**
```c
struct MSE_Contract_Params {
    uint8_t  bw_class;    /* bandwidth class (0 = best-effort) */
    uint8_t  lat_class;   /* latency class (0 = best-effort) */
    uint16_t reserved;    /* must be zero */
};
```
* **Semantics**:
  1. Checks that `rs1` is a valid, allocated ECID on this hart.
  2. Checks that `bw_class(rs2) + existing_sum(subtree(parent(rs1))) ≤ bw_cap(parent(rs1))`.
     If not, returns `MSE_ERR_CAP_EXCEEDED` in `rd`; no state changes.
  3. Sets `EC[rs1].bw_class` and `EC[rs1].lat_class`.
  4. Updates the running bandwidth sum for all ancestor groups up to the root.
  5. The change takes effect on the next `ec.ob` that loads ECID `rs1`. If ECID
     `rs1` is currently running on this hart, the new Contract parameters are
     applied immediately to the per-hart memory controller registers; the new
     class values take effect at the next CN slot boundary.
* **Cycles**: 1–4 (O(1) cap check; ancestor sum update is bounded by D ≤ 3).

---

### `ms.or` — Revoke the memory Contract from an ECID

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

* **Syntax**: `ms.it rd, rs1, rs2`
  * `rd`: 0 on success; error code on failure.
  * `rs1`: Parent ECID — the source whose Contract is being split.
  * `rs2`: Delegation descriptor. Inline form (bit `[XLEN-1]` = 0):

  | Bits | Field | Meaning |
  |---|---|---|
  | 15:0 | `child_ecid` | Child ECID to receive the split Contract |
  | 19:16 | `child_bw_class` | Bandwidth class to delegate (0 = inherit parent's full class) |
  | 23:20 | `child_lat_class` | Latency class to delegate (0 = inherit parent's full class) |
  | `[XLEN-2]`:24 | — | Reserved; must be zero |
  | `[XLEN-1]` | `ptr` | 1 = pointer form; bits `[XLEN-2]`:0 point to `MSE_Delegation_Params` |

  Pointer form struct:
```c
struct MSE_Delegation_Params {
    uint16_t child_ecid;       /* child ECID to receive the split Contract */
    uint8_t  child_bw_class;   /* bandwidth class to delegate (0 = inherit parent's) */
    uint8_t  child_lat_class;  /* latency class to delegate (0 = inherit parent's) */
    uint32_t reserved;         /* must be zero */
};
```

  `child_ecid` must satisfy `EC[child_ecid].delegation_L < D`.

* **Semantics**:
  1. Verifies `child_ecid` is a child of `rs1` in the delegation tree.
  2. Performs the split: transfers `child_bw_class` and `child_lat_class` to the
     child; if both are 0, the child inherits the parent's full class.
  3. Admission check: `bw_class(child) + existing_sum(subtree(rs1)) ≤ bw_cap(rs1)`.
     If the check fails, returns `MSE_ERR_CAP_EXCEEDED`; no state changes.
  4. Updates running sums atomically.
* **Cycles**: 1–8 (log of delegation depth).

---

### `ms.ot` — Revoke a child Contract back to the parent

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

## 6. MSE CSRs

| CSR | Access | Purpose |
|---|---|---|
| `mse_slot_ratio` | RW (privileged) | CN/BE slot split. Bits 7:0 = CN fraction (0–255, where 128 = 50 %). Implementations may restrict to a set of legal values. |
| `mse_slot_ns` | RO | Slot size in nanoseconds (implementation-defined). |
| `mse_max_nesting` | RO | Maximum interrupt nesting depth K supported by this implementation. |
| `mse_bw_cap` | RW (privileged) | Per-hart register holding the bandwidth cap for the currently loaded ECID's group. Updated by `ms.ir` / `ms.it` / `ms.ot`. |
| `mse_bw_sum` | RO | Running sum of `bw_class` across all active Contract holders on this hart. |
| `mse_status` | RO | Result code from the last MSE operation on this hart. |
| `mse_violation` | RO (sticky) | Set when a Contract holder does not receive its guaranteed CN slot in the expected window. Cleared by writing 1. Raises an interrupt if `mse_violation_en` is set. |
| `mse_violation_en` | RW (privileged) | Enable interrupt on `mse_violation`. |

---

## 7. Arbitration

### 7.1 Per-access arbitration (CN slots)

Within each CN slot, the memory controller selects one requesting EC using the
following rule, executed in O(1) hardware:

1. Collect all harts with a pending DRAM request and a non-zero `lat_class`.
2. Select the hart with the **lowest `lat_class` value** (highest priority).
3. Ties broken by round-robin among tied harts.
4. Grant that hart a burst of size proportional to its `bw_class` (implementation
   maps `bw_class` to a burst length, typically 1–16 cache lines).

Best-effort requests (zero `lat_class`) are not eligible in CN slots; they wait for
the next BE slot.

### 7.2 Per-access arbitration (BE slots)

All harts with a pending request are eligible. Arbitration is round-robin. Burst size
is implementation-defined (typically one cache line per BE slot).

### 7.3 Admission control

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

### 7.4 Group caps

Group caps (§4.2) are enforced on every `ms.ir` and `ms.it` call as described there.
No runtime per-access group check is needed: once admitted, the per-hart registers
already encode the correct class bits.

---

## 8. Scheduling Window

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

## 9. Interaction with CME and CPE

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

## 10. Error Codes

| Code | Value | Meaning |
|---|---|---|
| `MSE_OK` | 0 | Success |
| `MSE_ERR_INVALID_ECID` | 1 | `rs1` is unallocated or generation-mismatched |
| `MSE_ERR_NOT_CHILD` | 2 | `rs2` is not a child of `rs1` in the delegation tree |
| `MSE_ERR_CAP_EXCEEDED` | 3 | Request would exceed group bandwidth cap |
| `MSE_ERR_SYSTEM_FULL` | 4 | Global CN budget exhausted; no room for new Contract |
| `MSE_ERR_PRIVILEGE` | 5 | Caller does not have permission to modify this ECID's Contract |

All error codes are returned in `rd` or in `mse_status`. Silent failure is prohibited
(charter §6.6).

---

## 11. Instruction Encoding

All CE Suite instructions share the same R-type format and custom-0 opcode
(`0001011`). See Chapter 3 §10.1–§10.2 for the bitfield diagram and the
funct3 extension-selector table.

**MSE uses funct3 = `010`.**

### 11.1 MSE instruction encoding (funct3 = `010`)

| funct7      | Mnemonic | rd field | rs1 field    | rs2 field                 |
|-------------|----------|----------|--------------|---------------------------|
| `0000000`   | `ms.ir`  | result   | target ECID  | contract parameters       |
| `0000001`   | `ms.or`  | result   | target ECID  | `00000`                   |
| `0000010`   | `ms.it`  | result   | parent ECID  | delegation descriptor     |
| `0000011`   | `ms.ot`  | result   | child ECID   | `00000`                   |

funct7 values `0000100`–`1111111` (4–127) are reserved for future MSE instructions.

`ms.or` and `ms.ot` carry no `rs2` operand; the rs2 field is encoded as `00000` (x0).

### 11.2 Encoding examples

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

## 12. Out of Scope for v1

- **NoC, DMA, and peripheral arbitration.** Covered by QoS (Chapter 11).
- **NUMA-aware Contract assignment.** Multi-socket NUMA semantics for MSE Contracts
  are an open item (charter §8.1).
- **Multi-resource Contracts.** Whether a single Contract can span memory and I/O
  is open (charter §8.2).
- **Software-overflow Contracts.** When hardware Contract slots are exhausted, the
  slow-path software fallback is not yet specified (charter §8.3).
- **Cross-hart ECS sharing during migration.** Open item (charter §8.4).

---

**Next:** Chapter 10 — MSE Usage Examples
