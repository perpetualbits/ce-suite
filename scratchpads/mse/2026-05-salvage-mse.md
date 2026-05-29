<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Salvaged MSE telescoping and arbitration model

**Status:** Scratchpad — non-normative. Salvage material under
review.
**Source:** Distilled from 27 ChatGPT design-discussion chats
conducted between July 2025 and May 2026, summarized in a
review session on 2026-05-29.
**Cluster discussion:** D
**Disposition policy:** Items here exit the scratchpad via one
of three routes — promoted to a `docs/work-items.md` entry,
archived to `docs/future-directions.md`, or rejected with a
one-line note. See `scratchpads/README.md` for the lifecycle.

---

================================================================================
Salvaged MSE ideas
================================================================================

Found it. The MSE design is spread across two chats: **"MSE feasibility discussion"** (chat #21, `688b2cf3`) and **"MSE vs Networking QoS"** (chat #19, `68932217`). Here is everything I recovered, reconstructed in full:

---

## The MSE Design — What Was Developed in ChatGPT

### What MSE is and what it does

MSE (Memory Scheduling Extension — later also called MBW, Memory Bandwidth) is a CE suite extension that arbitrates shared RAM access across harts. The core problem: every hart on a chip competes for RAM bandwidth and latency. The OS has the "big picture" of which execution contexts (ECs) are real-time, which are best-effort, and what their guarantees should be. MSE gives the OS a way to express those guarantees to hardware, which then enforces them.

---

### The Stream-of-Opportunities Model

You described memory access as a stream of access *slots* (opportunities): in any given time window (of N cycles), some number of memory access slots are available. Any number of harts may be waiting. The hardware arbiter (living outside the harts, in the memory controller or MMU) decides per slot who gets access and at what granularity. This is the key insight: rather than per-request arbitration with unpredictable latency, you pre-divide the time window into a structured stream of slots.

**Granularity control** is the clever part. The size of each slot (i.e., the granularity of memory access granted per turn) is determined by bitfields in each EC's resource profile. The bitfields encode:
- **Latency bits**: how fine-grained the minimum memory access slot can be (low-latency = small, frequent slots)
- **Bandwidth bits**: how large the maximum memory access block can be per grant (high-bandwidth = large, infrequent slots)

These are a small number of bits (say 4 bits each, representing powers of two in slot sizes), not a continuous value. Fewer bits means coarser control; the hardware can check and enforce them O(1).

---

### The Telescoping / Strip-Bits Mechanism

This is the key invention you're trying to recover. When an L0 OS delegates a pool to an L1 VM (or an L1 VM further delegates to an L2 service), the delegation *strips* bits from the bitfields. Specifically:

- Delegating from a parent pool to a child pool **removes the lowest-latency bit** (doubling the minimum slot size) and **removes the highest-bandwidth bit** (halving the maximum block size)
- This is called "bit shaving" in the scratchpad

**Effect:** Each level of the virtualization hierarchy has a coarser view of memory scheduling. An L0 host can request slots as fine as 1 unit and as large as 16 units. A VM at L1 can only request between 2 and 8 units. A service at L2 between 4 and 4 units (i.e., it can only use one fixed granularity). This is the *telescoping*: the usable range of the bitfield collapses inward at each delegation level.

This telescoping serves two purposes:
1. **Security**: a nested guest can never claim finer latency or more bandwidth than its parent allowed
2. **Simplicity**: the hardware never needs to walk the whole delegation tree at arbitration time — it just checks the EC's own bitfield, which already encodes all the restrictions from all its parents

---

### How Arbitration Works in Hardware (O(1))

The memory arbiter (centralized, outside the harts) maintains a small SRAM/CAM with:

```c
struct PoolEntry {
    PoolID id;
    PoolID parent_pool;       // 0 if top-level
    uint8_t latency_bits;     // Latency cap — with bits already "shaved" from parent
    uint8_t bandwidth_bits;   // Bandwidth cap — with bits already "shaved" from parent
    uint16_t cap;             // Total bandwidth/latency units allowed per window
    uint16_t usage;           // Current usage (updated per slot)
};

struct ECResourceProfile {
    ECID id;
    PoolID pool;       // Which pool this EC draws from
    GroupID group;     // For ownership/delegation
    // latency_bits and bandwidth_bits for this EC, restricted by pool
};
```

On every arbitration slot (wire-speed, O(1)):
1. Check the EC's pool membership (a small field in the active EC's profile — already loaded into a register for the hart's current context)
2. Check `usage + request ≤ cap` for this pool **and** all ancestor pools (in practice a shallow chain ≤ 4 deep, done in parallel)
3. If all pass → grant access and update usage counters up the chain
4. If any cap would be exceeded → deny or defer to the best-effort pool

The OS never needs to touch per-cycle arbitration. It only configures pools at VM creation/teardown, which is an infrequent (ms-scale) event.

---

### Groups vs. Pools — the key architectural distinction

This was a crucial design clarification reached in the chat:

| Feature | Groups | Pools |
|---|---|---|
| Purpose | Ownership, delegation, security | Shared quota enforcement |
| Structure | Hierarchical tree | Flat (can overlap) |
| Membership | One owner per bank/contract | Any EC can be in many pools |
| Cap enforcement | Per group (max aggregate) | Per pool (shared cap) |
| Use case | Virtualization, isolation, VMs | Sharing bandwidth among tenants |

**CME** only needs groups (context banks are exclusively owned). **MSE, CPE, and QoS** need both: groups for ownership/delegation, pools for shared quota enforcement.

---

### Pool-in-Pool (Nested Delegation) Example

```
[System Pool] (cap=16, all bits available)
    |
    +──────────────────────────────────+
    |                                  |
[VM Pool A] (cap=8,               [VM Pool B] (cap=6,
 cannot use top 2 BW bits)         cannot use top 2 BW bits)
    |
    +──────────────────────+
    |                      |
[SvcA1] (cap=4,       [SvcA2] (cap=4,
 also strips bottom    also strips bottom
 2 latency bits)       2 latency bits)
    |
  [ECIDs on any hart]
```

L0 creates System Pool. L1 VM is delegated VM Pool A (caps at 8, loses 2 bandwidth bits). L2 services within VM A are further delegated Service Pools (caps at 4, also lose 2 latency bits — they can only access coarsely). ECIDs point to their assigned pool; hardware enforces the hierarchy without walking the full tree, because each pool's `latency_bits` and `bandwidth_bits` are already pre-restricted by all parents at delegation time.

---

### What's Still Open / What Was Not Finalized

From the scratchpad:
- **No concrete MSE instructions or CSRs were finalized** — the design worked out the policy and hardware enforcement model, but the ISA encoding was deliberately left open
- The exact width of the latency/bandwidth bitfields (how many bits) was not nailed down
- Whether pool membership is enforced in the MMU or in a separate central arbiter block was left as an implementation choice

---

### Assessment for Bringing Back to Claude/Claude Code

The **core ideas that are worth salvaging and formalizing** are:

1. **The bitfield-based contract model** — latency_bits + bandwidth_bits per pool, with O(1) hardware enforcement via token buckets / window accounting. This is solid and maps cleanly to what hardware actually does (compare: Intel RDT/MBA, ARM MPAM).

2. **The telescoping/bit-shaving mechanism** — stripping bits at delegation time is elegant and aligns well with the depth-D delegation model already in the CME charter (D=0..3). Each level strips one bit from each end of the range. This is a novel, clean encoding that's worth keeping.

3. **The pool-in-pool hierarchy** — the formal data structure (`PoolEntry` with `parent_pool`, `latency_bits`, `bandwidth_bits`, `cap`, `usage`) is ready to be turned into RTL. The enforcement algorithm is straightforward.

4. **The O(1) argument** — the scratchpad worked out clearly that per-access arbitration is O(1) in the number of active ECs (not in the total number of ECIDs in the system), because hardware only tracks currently-active ECs. This is a strong, defensible claim.

5. **The stream/slot model** — memory access as a stream of time-window slots that are pre-divided is a clean mental model for the ISA spec chapter on MSE.

What's NOT worth bringing back verbatim: the initial confusion between pools and groups (now resolved in the charter), the rejected approaches (per-hart global bus control), and the fractal/hint-based prefetch idea from the "RISC-V Hard Real-Time Extensions" chat (that was a separate, earlier exploration that got superseded by the contract model).

The scratchpad document (`101-MSE-scratchpad.md`) in the ChatGPT CE suite project is the single best artifact to export — it contains the axioms, rejected approaches, scenarios, timescale/complexity table, and the pool-in-pool diagram and data structure, all in one place.

[Roland then asked: Yes, so the ideas may be salvagable but we don't use pools anymore. Only groups.]

Right — and that's a significant simplification. Here's how I think the MSE ideas map onto the groups-only model:

**What pools did and how groups cover it now:**

Pools were a "flat sharing quota" mechanism — any set of ECs could share a bandwidth cap regardless of ownership. Groups are hierarchical and ownership-based. The current design (charter v0.18) uses groups for *both* ownership/delegation *and* resource accounting. So instead of a separate Pool table, the cap/usage accounting lives on the group itself.

**The ideas that survive cleanly:**

1. **Contracts as resource slices** — The current charter already has this. A contract (MSE/QoS) is a slice of global memory bandwidth/latency, owned by a group, delegatable down the group hierarchy. This replaces what the pool-in-pool was trying to do.

2. **The bitfield/bit-shaving / telescoping mechanism** — This maps directly onto contract delegation. When a group delegates a child contract, it can strip bits from the latency/bandwidth bitfields, so the child contract has a coarser range than the parent. This mechanism is fully portable from pools to contracts-within-groups. The key insight — that each delegation level collapses the usable range inward — is still valid and still elegant.

3. **The stream-of-slots model** — This is independent of pools vs. groups. Memory access as a stream of time-window slots, with hardware arbitrating O(1) per slot based on the active EC's contract profile, still holds. The arbiter just looks up the active EC's bound contract, checks `usage + request ≤ cap`, and enforces at wire speed.

4. **The O(1) hardware enforcement model** — Also still valid. The hardware tracks only active ECs (N of them, where N = number of harts). Each active EC has a pointer to its bound contract (in the group hierarchy). The check is shallow (depth ≤ D, which is at most 3).

**What changes in the translation:**

- Instead of `PoolEntry` + `parent_pool`, the contract table entry has a `parent_contract` pointer (already in the charter's contract axioms — contracts can be split into child contracts)
- Shared binding across multiple ECIDs (which pools provided) is now handled by the contract's shared binding rule in the charter: multiple ECIDs can bind to the same contract
- Pool modes (strict, elastic, priority/fairness) would become contract policy bits

**The key question to re-examine:**

The pool-in-pool's *shared* cap — where unrelated ECs from different groups could all draw from the same quota — is harder with groups-only. In the groups model, a contract is owned by one group. If you want multiple ECIDs from *different* groups to share a bandwidth cap, they need to share a contract owned by a common ancestor group. That's still possible (bind all of them to the same contract), but requires more care in the ownership chain.

Worth explicitly designing: how the MSE instruction set lets the OS bind an ECID to a contract that isn't in its own group but in an ancestor group — and whether that interaction with the charter's "contract binding authority" rule (section 2.4: only the owner ECID of an ECID's parent group can change bindings) creates any friction.

So the salvage work for MSE is essentially: take the bit-shaving telescoping mechanism, the O(1) arbitration model, and the stream-of-slots mental model, and re-express them in terms of contracts-owned-by-groups rather than pools. The math and the hardware model are the same; the ownership wrapper is different.

Would you like me to help draft that re-expression — e.g., as a new MSE section for the hw/ directory or as a prompt for Claude Code to produce an RTL sketch?
