<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite — Underlying Design Principles

> **Purpose of this document.** This is the *compass* for the CE Suite: the principles
> that the concrete decisions in the substrate specification keep pointing back to. It
> exists so that future work — by the author, by collaborators, or by an AI assistant that
> has no memory and no intuition of its own — can be checked against intent, not just
> against internal consistency. When a proposed change "passes all the tests" but still
> feels wrong, this document is where to find out why.
>
> **How it is organised.** Principles are split into two groups: those the author
> **stated outright** during design, and those an assistant **inferred** from the pattern
> of decisions. The inferred ones are explicitly marked as such; they are candidates for
> the author to confirm, correct, or discard, not settled doctrine.
>
> **Status of the gaps.** Two things this document does *not* yet pin down are recorded at
> the end: the priority order when principles collide, and the single root statement above
> them all. Those are the author's to supply; until then they are marked OPEN.

---

## 0. The root (resolved)

> Arrived at by Socratic dialogue between the author and an assistant; the author supplied
> every load-bearing word. This section outranks everything below it (per §D).

### The root statement — why CE exists

**CE exists to make worst-case execution bounds *enforceable* — kept even when something
would otherwise take what was promised — and to keep them enforceable down a nesting of
execution contexts, to a depth fixed in advance, so that a realtime promise can be
subdivided and handed down and remain a real, hardware-kept promise at every level.**

Unpacking the load-bearing words, in the author's own emphasis:

- **Enforceable** is the heart — not merely *known* and not merely *bounded*, but *kept*
  even when something would otherwise take what was promised. Today's systems often have
  small *average* costs but no *enforceable worst case*, so a noisy neighbour, a cache
  eviction, or an interrupt storm blows the deadline. EDF (Earliest Deadline First) can, in
  principle, meet every deadline *given known, bounded, composable worst-case costs*; real
  systems fail because they cannot supply those costs for context switching, wakeup,
  cache/memory interference, interrupts, and device service. CE turns those hidden variable
  costs into explicit hardware contracts.

Enforceability resolves into **two distinct guarantees**, which must not be conflated:

- **Resource non-interference (the realtime guarantee).** A resource *granted* to a context
  is honored against every *competing demand*: a greedy sibling, the **grantor's own
  appetite** (a parent running its own work must not implicitly erode what it promised a
  child), and the machine's own physics. The parent is *not* a resource adversary — it is
  the grantor; the guarantee is that its own use cannot silently claw back the grant. (A
  parent may still *explicitly* revoke or tear down a child; that is its authority, below.)

- **Isolation (the security guarantee).** A context cannot reach *outside its own domain* —
  it cannot touch a sibling or reach up to an ancestor. This defends against a sibling
  reaching sideways and an unruly child reaching up. The **parent is privileged, not an
  adversary**: a hypervisor (or a Kubernetes-like manager, or a non-OS system such as a
  medical device or radar controller) legitimately rules its child — it may terminate,
  revoke, tear down, and even read or alter the child's memory, because it carved out that
  address space. That is expected and correct. Confidentiality *from* the parent exists only
  where deliberately opted into (the secure-enclave inversion), never as the general rule.

- **Scope limit — CE enforces partitions; it does not invent capacity.** CE guarantees that
  a grant is honored, not that the set of grants is *feasible*. If a grantor is itself
  under-resourced, or if the tasks on a hart sum to more than it can do (five tasks needing
  1.5 µs of work per 1 µs will break, necessarily), something gives — predictably, and bounded
  to the right victim, but it gives. Preventing overload and misconfiguration is the
  responsibility of the user / OS designer / sysadmin, supported by measurement and tooling
  and by admission tests; it is not something CE can do by magic. The own-bank rule is the
  hardware *hook* that lets a grantor be adequately provisioned (a banked scheduler must
  hold its own bank); using it correctly is software's job.

- **Guaranteed, not reserved — nothing is wasted.** A grant guarantees *availability on
  demand*, not a fenced-off reservation. Capacity a grant-holder is not using — including a
  realtime slice that finishes early — flows automatically to best-effort work, and the
  grant-holder reclaims it within its contracted latency. *Solids and gas*: contracted ECs
  are solids with guaranteed, reclaimable shares; best-effort ECs are gas filling every gap
  and compressing out of the way the instant a solid expands. A configurable best-effort
  *floor*, set per level within each grantor's slice, keeps best-effort progressing. This
  makes best-effort load-bearing, not leftover — it is the slack that lets realtime absorb a
  transient burst (a long interrupt) without missing a deadline.

- **Fractal fit — guarantees shrink with depth so they compose.** Each level deeper, a
  child's realtime latency bound is *at least* double and its bandwidth guarantee *at most*
  half its parent's (a fitting constraint, not a fixed ratio). This self-similar halving is
  the one law behind both memory arbitration (MSE) and scheduling, and it is why depth is
  bounded: three halvings reach ⅛ bandwidth / 8× latency, about the useful limit — hence
  `D ≤ 3`.

- **Enforceable inherently contains nesting.** "Enforceable" already implies "holds all the
  way down," to a depth fixed in the contract structure in advance. A guarantee that cannot
  be subdivided-and-still-enforced is not fully enforceable, because the layer below it
  inherits a hollow promise. So *realtime that nests* is not a second goal bolted on; it is
  what enforceability means here.

### The priority rule (resolves the old "priority order" gap)

The principles do not form a ranked list. They form **two layers**:

1. **Admissible floor.** The root statement and the principles it *forces* (see §A′) define
   which designs are even considered. Nothing below the floor — nothing that weakens the
   enforceable, nesting, all-three guarantee — is ever on the table.
2. **Minimal among the admissible.** Only *within* the set of designs that clear the floor
   do the engineering-taste principles (minimalism, one-mechanism, etc.) choose between
   options.

So purpose-forced principles and taste principles **never actually collide**: they act on
different things. The forced ones decide *what is admissible*; the taste ones decide *which
admissible option to pick*. The author's own resolution of "P1 vs P7" is exactly this — if
more complexity is needed to keep the guarantee, choose *the next minimum option that still
satisfies it*, not a cheaper option that doesn't. (Banks exist for this reason; see P13.)

### Which principles the root *forces* (§A′)

Forced by the root (the admissible floor): **P1** (realtime is master — an enforceable
worst-case bound *is* the realtime guarantee), **P2** (the fast-path wall — you cannot bound
what you cannot switch in bounded time), **P3** (structural security — *isolation*: a context
cannot reach outside its domain; this is the security guarantee, distinct from resource
non-interference), **P5** (level agnosticism + nesting — "remain a promise at every level,
handed down"), **P8**'s physical-resource arbitration (the realtime guarantee's defence
against the machine's own physics, which forces the bandwidth/cache/latency contracts),
**P14** (composition with RVA23, which is in the TCB — the walls CE's structure stands on),
and **P15** (modularity — forced by the platform's range and shaped by the guarantee's
cut-lines).

Not forced by the root — these are *how* CE is built well, and yield to the forced ones when
they conflict: **P4** (need-to-know — a security technique that follows mostly from P5),
**P7** (minimalism), **P9** (generality), **P10** (child→parent up-pointer — a chosen
technique that *made* things possible), and **P11** (touch reality).

### P13 — Specify the contract, not the implementation; and owe an existence proof

CE defines **instructions and enforceable bounds**, and deliberately leaves the
microarchitecture free. "Banks" are an *abstraction*: an implementer may realize them as
switchable register sets or otherwise, as long as the instruction set and the guarantees
are identical. This is what lets P11 (must be buildable, FPGA-able) coexist with P1 (hard
guarantees): CE guarantees the *contract*, not the *gates*.

The freedom has a matching obligation. For every contract CE specifies, the author must be
able to **exhibit at least one concrete realization** — by precedent (others have built the
piece), by a written-out solution, better by a QEMU emulator, and best by an FPGA
realization integrated into an existing reusable RISC-V design. The two halves are one coin:
abstract the mechanism away, *and* owe a witness that the mechanism can exist. No air
castles.

The strength of that obligation: **the bar is credibility; the aim is correctness by
construction.** Today, a precedent or a written solution clears the bar — it lets the design
be *defended* to a skeptic, against the foreseeable criticism that "this is impossible." The
*aim*, not yet reached, is that every contract has a built, running witness (emulator → FPGA
→ integration), at which point the contract is not merely defensible but demonstrated. The
gap between bar and aim is the project's work plan, not a thing to hide.

### P14 — CE composes with RVA23; RVA23 is in CE's trusted computing base (FORCED)

CE is not self-sufficient and does not reinvent isolation. It *presupposes and reuses* the
existing RVA23 mechanisms — memory protection (PMP/PMA), the H (hypervisor) extension and
its two-stage translation, CLIC for interrupts, and so on — and lays the ECID structure
*on top* of them to make their guarantees enforceable and nesting. The
walls are RVA23's; CE provides the structure and the nesting.

Therefore **RVA23 is part of CE's trusted computing base**: CE's enforceability is only as
strong as RVA23's, and a weakness in RVA23 isolation is inherited by CE. This is acceptable
and is the standard confidential-computing trust boundary, because trusting RVA23 isolation
is **trusting silicon, not trusting any software layer above it**. A parent legitimately
*configures* its children's boundaries (it carves out their address spaces, sets PMP and
stage-2 tables) — that is its authority. What hardware *enforces* is that, once configured,
those boundaries cannot be crossed: a child cannot reach outside its space, and one child
cannot reach into a sibling's, because the enforcement is silicon the running contexts
cannot subvert. So isolation holds even against a compromised *child*; the parent is trusted
to configure correctly (and confidentiality *from* the parent is the separate, opt-in
enclave inversion). CE thus trusts the CPU vendor, exactly as every TEE design does.

### P15 — Modularity, forced from two directions (FORCED)

CE must scale across the whole RISC-V range — microcontroller to hyperscale server — because
*RISC-V itself does*, and a RISC-V extension inherits that obligation. So CE must be
modular. But the *seams* along which it may be cut are not a matter of taste; they are
dictated by the root statement. The structure is three layers:

- **Below CE — RVA23** (P14): the raw isolation primitives CE assumes.
- **The CE core — ECID + CME**: lays the structure that makes RVA23's primitives enforceable
  and nesting. This is the **floor** — it *is* the enforceable bounded
  switch, so it can never be omitted. ECID alone is not useful; ECID + CME is the minimum
  meaningful CE.
- **Optional CE modules — MSE, CPE, QOS**: each subdues *one flavour of physical contention*
  (memory bandwidth/latency, cache, I/O). A module is included exactly when its flavour of
  physics is present on the silicon, and omitted when that contention is simply absent (a
  microcontroller with no shared memory controller and no cache does not face memory/cache
  physics, so it drops MSE and CPE — not as "advanced features" withheld, but because that
  contention is not there to arbitrate).
- **A dial, not a module — the depth `0 ≤ L ≤ D ≤ 3`**: nesting depth is a *parameter* of
  the guarantee itself ("to a depth fixed in advance"), so the implementer sets D rather than
  including or omitting a feature.

So modularity is forced from above (the platform demands range) and shaped from below (the
guarantee dictates the legal cut-lines): the core is the guarantee, each optional module is
the defence against one flavour of physics, and the depth is the guarantee's own parameter.
Isolation (a child or sibling cannot reach out) lives in the core with RVA23; only physics
comes in omittable flavours.

---

## A. Principles stated outright

### P1 — Hard realtime is the master constraint
Sub-10-cycle context switching under hard-realtime guarantees is the reason the project
exists, not one feature among many. Every structural choice is judged first by: *does the
fast path stay O(1)?* If a design would compromise the realtime guarantee, it is wrong,
regardless of other merits.

### P2 — A hard wall between the fast path and everything else
Only `ec.ib` / `ec.ob` are realtime-bounded (1–3 cycles). *Everything* else —
allocation, delegation, teardown, enumeration, migration, the bankless RAM path — is
explicitly permitted to be slow, up to O(N log N), and may scan. The simplicity budget is
spent on reconfiguration precisely so the fast path can be trivially fast. An O(N)
operation off the fast path is not a problem; an indirection *on* it is.

### P3 — Security is structural, not policy
The recurring test is: *could a security researcher break out of a VM with this?* When the
answer is bad (e.g. real slot numbers becoming visible to a guest), it is a hard rejection,
not a tradeoff to be balanced. Isolation must be something the hardware *cannot* violate,
not something software is trusted to respect. Containment is enforced by the structure
(up-pointer checks, slot-blindness, memory mappings), so that a compromised or hostile
guest is contained by construction. The direction matters: isolation stops a context
reaching *outward* — sideways to a sibling, or up to an ancestor. It does *not* constrain a
parent reaching *down* into its own child; that is the parent's legitimate authority (it
carved out the child's space), not a breach. Confidentiality from the parent is a separate,
opt-in thing (the secure-enclave inversion), not part of this baseline isolation.

### P4 — Need to know: software knows only what it needs, never more
A context sees its own universe (`self = 0`, children `1, 2, 3 …`) and its hart number —
nothing else. No absolute slot numbers, no parent identity, no siblings, nothing inside a
delegated tenant. The forward index that maps a vnum to a slot is CE-private and never
reaches addressable memory. *"Everyone can only know what they need to know. Not more, not
less."*

### P5 — Level agnosticism: CE forces no per-level code
CE must never *force* a context to differ by nesting level. A kernel always believes it is
the local root (`0`) with children `1..n`, whatever its actual level; CE leaks no absolute
identity, parent identity, or sibling existence. This forces virtualized numbering. Note the
precise scope: this is a claim about **CE's contribution** — CE never makes you ship
different code per level. A *full* unmodified OS image additionally needs the platform to
virtualize privilege state, CSRs, traps, timers, and interrupts (RVA23's job, P14), which is
not CE's to provide. So "the same image runs at any depth" holds for CE's part of the stack;
the rest is RVA23's.

### P6 — CE is opt-in and must not break what does not use it
A process may use no CE at all; a machine with CE switched off behaves as an ordinary
RISC-V machine. CE is adopted per-context, not imposed. A context that uses CE has an ECID
array record (and therefore a `[hart#, vnum]` identity); a context that does not, has
neither — and that is correct, not a gap.

---

## B. Principles inferred from the pattern of decisions

> These are an assistant's reading of *why* the decisions went the way they did. They are
> consistent with the record but were not stated as principles by the author. Confirm,
> correct, or discard.

### P7 — Minimalism as a tiebreaker (INFERRED)
Refuse to add hardware until it is *proven necessary*, then take the smallest version that
works. Across the design, every proposed new structure (a forward table, a generation
counter, a central index array, an `ec.oe`, a standalone `bk.oe`) was pushed back on until
necessity was demonstrated — and several were dropped. The design should be the *least*
mechanism that satisfies P1–P6.

### P8 — Match physical reality; reject abstractions that do not map to silicon or to how systems actually behave (INFERRED)
Fixed-width records, never variable-length. Banks reclaimed only on teardown, because "you
cannot hot-remove half a register file from a running CPU" (the Proxmox analogy: hot-add a
NIC, never half a vCPU). Decisions are grounded in how real hardware and real operating
systems behave, not in what is elegant on paper.

### P9 — One mechanism, reused; prefer generality over special cases (INFERRED)
The same up-pointer pattern serves ECIDs, banks, and contracts identically. The
contiguous-array scheme is "the degenerate case" of the general one; flat ECS mode is
"descriptor mode collapsed." When two things turn out to be the same mechanism wearing
different hats, that is treated as a sign the design is right, not a coincidence.

### P10 — The owned thing points at its owner: child → parent, always (INFERRED)
The architectural signature of the whole substrate. Ownership, containment, and teardown
all fall out of one up-pointer per record. Inverted exactly once, deliberately and
flagged, for secure enclaves (the owner controls existence but cannot read contents).

### P11 — Honesty about scope and cost (INFERRED; partly about the documents themselves)
Use real numbers (transistor counts, real kernel source, the X100 VLEN correction). State
plainly what is proven vs. estimated vs. open, and label back-of-envelope assumptions as
such. Do not oversell: a behavioural model proves logic and invariants, not RTL
correctness or timing. This governs how the work is presented as much as how it is built.

### P12 — The design should be *derivable*, not *decreed* (INFERRED; least certain)
A piece of the design is not "done" until it is obvious *why it had to be that way*. Each
element should feel forced by the constraints, so that a reviewer re-derives it rather than
taking it on faith. (This may be an assistant reading its own experience of the design
conversation into the author; flagged as the least certain inference.)

---

## C. What this document does NOT yet capture

Both items formerly open here are now **resolved in §0** (the root, the priority rule, and
P13), through the Socratic dialogue:

- **RESOLVED — Priority order when principles collide.** It is not a ranked list but a
  two-layer rule: *admissible floor first* (designs that keep enforceability and nesting),
  *minimal among the admissible second*. Purpose-forced principles and taste principles
  never truly collide; they act on different things. See §0.

- **RESOLVED — The single root statement.** See §0: enforceable worst-case bounds, kept
  even when something would take what was promised, nesting to a fixed depth — resolving
  into two distinct guarantees (resource non-interference, isolation) plus a scope limit
  (CE enforces partitions, it does not invent capacity), so a realtime promise can be handed
  down and stay real at every level.

No principle gaps remain open at the time of writing. New tensions discovered during
implementation should be added here, then resolved into §0 or the principle list.

---

## D. How to use this document

- When reviewing AI-produced (or any) work on CE, read the change against P1–P6 first
  (stated), then P7–P12 (inferred). A change that satisfies the substrate spec's internal
  tests but violates a principle here is drifting, even if it "looks correct."
- When a principle here turns out to be wrong or incomplete, edit it — this document is the
  compass, and a wrong compass is worse than none.
- When the two OPEN items in section C get answered, move them into a new stated-principle
  section at the top; they outrank everything below them.
