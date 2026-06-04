<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite — Axioms

> **What this is.** A compact, hopefully-irreducible set of statements from which the
> principles document (*why*) and the substrate specification (*what*) can be re-derived.
> The intent is that you check a proposed change against ~25 short axioms instead of
> re-reading two long documents. If a change contradicts an axiom, it is wrong (or the
> axiom is wrong and must be changed deliberately — never silently).
>
> **How to read it.** Axioms are grouped: **Purpose** (P-axioms, the root and what it
> forces), **Structure** (S-axioms, always true of the data at rest), **Operation**
> (O-axioms, true of every instruction), and **Method** (M-axioms, how the work is done
> and judged). Each axiom is one sentence; a short gloss follows only where needed. Where
> an axiom is *derived from* others, that is noted — a derived statement is a theorem, not
> an axiom, and is listed separately at the end as a check.
>
> **Authority.** The Purpose axioms outrank all others (the priority rule). When axioms
> appear to conflict, a Purpose axiom wins; among non-Purpose axioms, the one closer to the
> root wins. This document is subordinate to the principles document's §0 root statement;
> if they ever disagree, §0 governs.

---

## Purpose axioms (P)

**P-1 (Root).** CE makes worst-case execution bounds *enforceable* — kept even when
something would otherwise take what was promised.

**P-2 (Resource non-interference — the realtime guarantee).** A resource *granted* to a
context is honored against every *competing demand*: a greedy sibling, the **grantor's own
appetite** (a parent's own work must not implicitly erode what it granted a child), and the
machine's own physics. The parent is the grantor, not a resource adversary; its own use
cannot silently claw back a grant (though it may *explicitly* revoke — see P-2c).

**P-2b (Isolation — the security guarantee).** A context cannot reach *outside its own
domain*: it cannot touch a sibling or reach up to an ancestor. A **parent is privileged**,
not an adversary — it may terminate, revoke, tear down, and read or alter its child's memory,
because it carved out that space; that is authority, not breach. Confidentiality *from* the
parent exists only where opted into (the enclave inversion, O-13).

**P-2c (Scope limit — enforce partitions, do not invent capacity).** CE guarantees a grant
is honored, not that the set of grants is *feasible*. An under-resourced grantor, or a hart
whose tasks sum to more than it can do, will break — predictably, bounded to the right
victim, but it breaks. Preventing overload and misconfiguration is the user / OS-designer /
sysadmin's responsibility (measurement, tooling, admission tests); CE cannot do it by magic.
The own-bank rule (S-12) is the hardware *hook* that lets a grantor be adequately
provisioned; using it correctly is software's job.

**P-2d (Work-conserving; guaranteed, not reserved).** A grant guarantees *availability on
demand*, not a fenced-off reservation that idles when unused. Capacity a grant-holder does
not currently use — including a realtime slice finished early — flows automatically to
best-effort work; nothing is wasted. A grant-holder reclaims its share within its contracted
latency (the slack-filler must be preemptible within that bound), so filling the slack never
weakens any guarantee. Think *solids and gas*: contracted ECs (with a contract or a bank)
are solids with guaranteed, reclaimable shares; best-effort ECs (without) are gas that fills
every gap and compresses out of the way the instant a solid expands. A **configurable
best-effort floor**, settable **per level within each grantor's own slice**, guarantees
best-effort *progress over a declared accounting window* — but it never creates an
unpreemptible claim *inside* a realtime reclaim window. (So best-effort is load-bearing, not
leftover — the slack that lets realtime absorb transient bursts, e.g. a long interrupt,
without missing a deadline — yet it is never a stone in the realtime shoe.) The gas/solid
model nests.

**P-2e (Fitting constraint — guarantees must compose).** *Axiom:* for a grant to be
subdivided (P-3, P-4), every child grant must be **no tighter in latency than its parent's
bound** and must consume **only a bounded fraction of the parent's allocable bandwidth**;
and the *set* of child grants must pass admission — the sum of child guarantees, the
parent's own overhead, and the configured best-effort floor must fit within the parent's
grant. (The per-child shape rule alone does **not** prove the set fits; set feasibility is
admission, which is software's responsibility — P-2c.)

*Default hard-realtime profile:* the fitting constraint is realized by a halving/doubling
rule — a child's latency bound is **at least double** its parent's and its bandwidth
guarantee **at most half** of the parent's remaining allocable grant. This self-similar
halving is the default law behind both MSE arbitration and scheduling, and it is why depth is
bounded: three halvings reach about ⅛ bandwidth and 8× latency, near the limit of a useful
realtime guarantee — hence `D ≤ 3`. Other profiles may use a different fitting function if
they prove the same non-interference and composability properties; the *fitting constraint*
is the axiom, the *halving rule* is the first required profile.

**P-3 (Nesting is intrinsic).** "Enforceable" means both guarantees hold all the way down a
nesting of execution contexts, to a depth `D` fixed in advance (`0 ≤ L ≤ D ≤ 3`); a
guarantee that cannot be subdivided-and-still-enforced is not enforceable.

**P-4 (Composability).** A promise made at one level can be subdivided and handed to a
child and remain a real, hardware-kept promise at every lower level.

**P-5 (Admissible-then-minimal).** Designs are first filtered to those that keep P-1…P-4
(the admissible floor); only among those does minimality/elegance choose. Purpose never
yields to taste; if more mechanism is needed to keep the guarantee, take the *least*
mechanism that still keeps it.

**P-6 (RVA23 is the trusted base).** CE composes with RVA23 (memory protection, the H
extension, CLIC, …) and inherits its hardware isolation as trusted; CE adds structure and
nesting, not new walls. Trusting that base is trusting silicon, not trusting any software
layer above it.

**P-7 (Buildability obligation).** Every contract CE specifies must have at least one
exhibited realization (precedent, written solution, emulator, FPGA). The bar is
credibility; the aim is a running witness. No air castles.

---

## Structure axioms (S) — always true of the data at rest

**S-1 (Per-hart).** Every CE structure — the ECID array, banks, contracts, the forward
index — is per-hart. Nothing CE-resident is shared between harts; cross-hart sharing is
only through RAM, as ordinary data.

**S-2 (Record).** The ECID array is a flat fixed-width table; a record is `{ ecs, owner,
vnum }` (plus an optional `gen`). The **slot** index is the absolute ECID and is never
stored — it is the position.

**S-3 (Free ⇔ null).** A slot is free if and only if `ecs == null`.

**S-4 (Up-pointer ownership).** Ownership is encoded child → parent by the single `owner`
up-pointer. The forest is rooted at slot 0; root owns itself (`owner[0]=0`, `vnum 0`).

**S-5 (One ECS per ECID).** Every ECID in use has exactly one ECS; distinct ECIDs never
share an ECS. Since an ECS belongs to a `[hart#, vnum]`, ECIDs on different harts cannot
share one. The ECS is the state of *one context on one hart* — not a cross-hart identity.

**S-6 (Self is 0; children from 1).** In its own universe every context is `vnum 0`
(self); its children are numbered `1, 2, 3 …`. `vnum 0` is never a delegable operand.

**S-7 (Vnum stable for life).** A vnum, once assigned, never changes while the child lives;
removing a sibling leaves a gap and never renumbers survivors. (Hence the array is never
reordered: position is identity.)

**S-8 (Bounded depth).** No ownership chain is longer than `D ≤ 3`, so every upward walk is
O(1).

**S-9 (Identity tuple is authoritative in the array).** A context's identity `[hart#,
vnum]` lives in the array — `vnum` stored, `hart#` implied by which hart's array holds the
record. The ECS may mirror it for software convenience only; the array is the source of
truth.

**S-10 (Group is a view + a private index).** A Group is not a stored object. Its *backward*
half (who/what an owner owns) is a view recovered from up-pointers. Its *forward* half (the
`vnum → slot` map) is a hart-local cache, built while the owner runs and **never written to
addressable memory**.

**S-11 (Banks).** A bank is register-file-sized SRAM holding one context's architectural
state in a fixed layout; it carries an `owner` up-pointer; software never names a bank by a
handle (banks are given as "a free one" and reclaimed only on teardown).

**S-12 (Own-bank rule).** Any ECID that holds banks uses one for itself; a banked scheduler
needs its own bank to keep the sub-10-cycle guarantee. With CE enabled, root has a bank, at
every level.

**S-13 (Sizing is bounded).** The slot-index width `n` is small (typically 8…12); capacity
is `2^n` per hart, and the practical limit is `fanout^D`, not raw `2^n`. The ECS pointer
need only be as wide as the address space in use (Sv39/48/57), not necessarily XLEN.

**S-14 (O(1) bank binding).** For every banked ECID, hardware can locate its scalar and VMT
bank bindings in O(1); software never observes or names those bindings. (How — CE-private
slot metadata, a bounded associative lookup, etc. — is the substrate chapter's choice; the
axiom states only the O(1) property and the slot-blindness, which T-4 relies on.)

---

## Operation axioms (O) — true of every instruction

**O-1 (Two paths).** Only `ec.ib` / `ec.ob` belong to the sub-10-cycle switch path. Other
operations may have specified finite bounds (useful to admission math) and may scan, but
must never be *required* on an admitted fast path; none is realtime-critical in the
sub-10-cycle sense.

**O-2 (Fast path touches only up-pointer + bank + forward index).** A switch verifies the
target with a one-hop ownership check (`owner[target] == current`) and resolves a vnum with
one read of the hart-local forward index. No scan, no memory chase, no indirection on the
fast path.

**O-3 (Software is slot-blind).** No software ever sees, stores, or can guess an absolute
slot. It names targets by vnum; the hardware translates. A slot number never reaches
addressable memory.

**O-4 (Level-agnostic — CE forces no per-level code).** A context operates only in its own
universe (self 0, children 1…n) and knows only its hart number; nothing CE does leaks
absolute identity, parent identity, or sibling existence, so **CE never forces a context to
differ by level** — the same CE-aware logic runs unmodified at any level. (A full unmodified
*OS image* additionally requires the platform to virtualize privilege state, CSRs, traps,
timers, and interrupts — RVA23's job, P-6 — not CE's. O-4 is a claim about CE's contribution,
not the whole stack.)

**O-5 (Ownership instructions build the forward index).** `ec.ir` (allocate child),
`ec.it` (delegate unused ECIDs to a tenant), and `ec.ot` (tear a tenant down) are the only
things that change ownership; they run while the parent is current and maintain its forward
index incrementally. There is no save-to-memory and no rebuild-by-scan on the fast path
(a scan may regenerate the index on swap-in, which is slow path).

**O-6 (Delegate only the unused).** Only free/unused ECIDs may be handed to a tenant; a
populated subtree is never delegated across an ownership boundary.

**O-7 (Teardown is the only return path, and always succeeds).** Resources return to a
parent only by destroying the holder: `ec.ot` recursively reclaims a tenant's whole subtree
— ECIDs, banks, contracts — and always succeeds, even on a crashed or hostile subtree.
There is no live, by-name revocation of a bank from a running ECID, and no separate
forced-destroy instruction.

**O-8 (Reuse is scrubbed).** Anything reused — a slot, a bank, a contract — is zeroed by
hardware before a new owner can see it; work in flight to a reassigned context (e.g. a
pending interrupt to a changed handler) is cancelled, not delivered.

**O-9 (Containment is structural).** Every cross-context action is checked against the
up-pointer tree (and RVA23's mappings): a context can act only within its own subtree and
can never reach a sibling, an ancestor, or outside its domain. The check is what makes
isolation (P-2b) true, not policy or trust. (A parent reaching *down* into its own child is
not a cross-domain action — it is authority, P-2b.)

**O-10 (Save/restore has a bank path and a RAM path).** `ec.ib`/`ec.ob` move state via a
bank (fast); `ec.im`/`ec.om` move state directly to/from the ECS in RAM by DMA (for
bankless contexts) — fast in practice but not realtime-bounded.

**O-11 (ECS is a descriptor with pointers; mode is OS-chosen).** The ECS is a fixed
descriptor whose scalar part is read either flat (contiguous) or via a descriptor of
pointers into the OS's own structures, selected per-instruction; the variable-size vector
buffer is always reached by pointer+length. Mode pairing is the OS's responsibility. Every
descriptor dereference occurs **only through the running context's own protection domain** —
translated by its permitted mappings, or validated against memory pinned to that ECID — so a
malformed or mismatched descriptor can reach only the offending context's own memory and can
never cross a boundary. That protection rule is what backs the claim, not trust in the OS.

**O-12 (Opt-in).** CE is adopted per-context. A context that uses CE has an ECID array
record (hence a `[hart#, vnum]`); a context that does not has neither. A machine with CE
off behaves as an ordinary RISC-V machine.

**O-13 (One inverted edge).** A sealed bank (`bk.iv` / `bk.ov`) makes a secure enclave: the
owner keeps lifecycle control (schedule, force-destroy) but cannot read contents. This is
the single deliberate inversion of "an owner can inspect what it owns."

---

## Method axioms (M) — how the work is done and judged

**M-1 (Match reality).** Reject abstractions that do not map to silicon or to how real
hardware and operating systems behave; ground decisions in physical and systems reality.

**M-2 (One mechanism, reused).** Prefer one general mechanism over special cases until a
special case is provably more economical; reuse aids understanding and hardware reuse.

**M-3 (Specify the contract, not the gates).** CE defines instructions and enforceable
bounds; the microarchitecture is the implementer's freedom (banks may be register sets,
etc.) so long as the instruction set and the guarantees are identical.

**M-4 (Honesty about scope and cost).** State plainly what is proven vs. estimated vs.
open; label assumptions; a behavioural model proves logic and invariants, not RTL
correctness or timing.

**M-5 (Derivable, not decreed).** A piece of the design is not done until it is obvious why
it had to be that way; aim for each element to feel forced by the axioms above. *(Least
certain; flagged in the principles document as an inference.)*

---

## Derived theorems (checks, not axioms)

These follow from the axioms and should *not* be stated independently; they are listed so a
reader can verify the axiom set is generative.

- **T-1 (No fragmentation crisis).** From S-2, S-3, S-4, S-7: ownership needs no
  contiguity, so slot reuse never fragments and identities never move.
- **T-2 (Modularity).** From P-2/P-2b + P-3 + P-5 + S-1: the core (ECID+CME) is the
  enforceable switch and cannot be omitted; each of MSE/CPE/QOS subdues one *flavour of
  physics* and is omitted when that physics is absent; `D` is a dial. Isolation
  (sibling/child-can't-reach-out) lives in the core with P-6's RVA23; the parent's downward
  authority is not constrained.
- **T-3 (Banks cost, structure is nearly free).** From S-2, S-11, S-13: the ECID record is
  dominated by the ECS pointer; the bank SRAM (especially VMT) dominates CE's area; the
  bookkeeping is a rounding error.
- **T-4 (Fast path is O(1)).** From O-2 + S-8 + S-10 + S-14: ownership check ≤ D hops, vnum
  resolution one indexed read, bank binding located in O(1), no scan — so the switch is
  constant-time.
- **T-5 (A workload spanning harts is many contexts).** From S-1 + S-5 + S-9: no shared
  ECS, so a multi-vCPU VM is N ECIDs / N ECSs; the cross-hart "one thing" is an OS software
  abstraction, not a CE object.
- **T-6 (A grant survives the grantor's own demand).** From P-2 + P-6 + O-9: a parent
  *configures* and may *explicitly* revoke a child's resources (its authority), but its own
  workload cannot *implicitly* erode a grant it has made — the arbiter/contracts honor the
  partition regardless of the grantor's appetite, provided the grantor is itself adequately
  provisioned (P-2c).
- **T-7 (Hard-realtime *and* work-conserving — no wasted capacity).** From P-2 + P-2c +
  P-2d: a CE system can be both hard-realtime and work-conserving — unused contracted
  capacity is temporarily usable by best-effort ECs, reclaimable within the grant-holder's
  contracted latency. *Debt:* like P-2e, this is a claim the MSE/CPE/QOS chapters must
  *discharge* with a concrete arbitration mechanism — in particular a proof of the reclaim
  latency bound when a slack-filler is mid-operation (e.g. an in-flight DMA burst that cannot
  be un-issued). Until then T-7 is a promise, not a settled result.

---

## Using the axiom set

- To vet a change: find the axiom(s) it touches. If it contradicts a Purpose axiom, reject
  it. If it contradicts a Structure/Operation axiom, either the change is wrong or the axiom
  must be revised *deliberately* (and then the documents updated to match).
- A change that satisfies all internal tests of the model but violates an axiom is drift.
- If a "theorem" stops following from the axioms, the axiom set has a gap — fix the axioms,
  not the theorem.
- Keep this list short. If it grows past ~30, some entries are probably theorems in
  disguise; demote them.
