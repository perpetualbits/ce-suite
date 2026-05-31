# CE Core Design-Loop — Session Capture

> ## ▣ ROUND THREE — OPENED 2026-06-01 (repo at charter v0.25)
>
> One-glance orientation for round four. This stamp supersedes the ROUND TWO
> stamp below (kept for history).
>
> **SETTLED THIS ROUND:**
> - **Criterion 4 complete.** The stress battery (Parts J, K, L) runs clean over
>   the frozen core: CME, CPE, MSE, plus invariants D.1–D.20. QoS I/O-fabric is
>   scoped out on the same basis as the round-one-close decision (Part L.5), which
>   is reaffirmed: it is self-contained downstream work that does not gate the loop.
> - **QoS scoped OUT of the design loop** (reaffirmed; see Part L.5). The v0.25
>   charter edit (§4.5.7, QoS local-view readback) stands and is correct; it is a
>   head start on that downstream QoS work, not loop work. QoS chapter propagation
>   (ch00 QoS bullet, ch11, ch13) remains pending as downstream work outside the
>   loop.
> - **Sequencing (architect's decision):** complete the loop (criterion 5) → freeze
>   the core → rewrite the charter and ch00 from the frozen core → propagate to all
>   chapters → fix the QoS chapters last.
>
> **STATE OF THE FIVE CRITERIA:**
> - Criteria 1–3: complete.
> - Criterion 4: **complete** (scoped core; QoS-fabric deferred per Part L.5).
> - Criterion 5: **in progress** — *Pass one (2026-06-01): red-teamed Part C +
>   D.1–D.20. Findings: (1) tenet 10 mislabeled bandwidth contracts as
>   "hart-local" — corrected; (2) D.19 "decided chip-wide" over-generalizes
>   (cache is core-local) — corrected to "atomic at the arbiter's scope"; (3)
>   D.11–D.13 positive operational forms were deferred — added; (4) D.11
>   positive form described Formula-2 readback as "function only of child's
>   subtree" — inaccurate (denominator s(p(e)) is the parent's stored value,
>   outside the child's subtree); corrected; privacy guarantee preserved; (5)
>   D.13 positive form applied interrupt-specific Q.2 order (mask → pending →
>   routing → free) to all routed resources — QoS and timer routes have no
>   mask/pending bits; corrected to scope Q.2 to interrupt routes with a general
>   resolve-before-free rule for the others; (6) tenet 6 "acyclic" was unqualified
>   — loose against the root self-loop (tenet 7 / D.7); tightened to name the
>   sentinel exception. All deliberate dated changes; see Part C and Part D.
>   Zero-change streak remains zero. Next step: a fresh red-team pass over the
>   corrected set.* Both former
>   criterion-5 blockers were resolved in round two: generations (Part Q) and
>   allocator policy F.4(a) (Part P.1).
>
> **ROUND FOUR PICKS UP AT:**
> 1. **Begin criterion 5:** a full red-team pass over tenets (Part C) + invariants
>    (D.1–D.20); zero changes = pass one. A second clean pass = converged → freeze
>    is then a deliberate architect decision with a version bump.
> 2. If a pass produces changes, resolve them and re-run.
>
> **DO FIRST in round four (process):** re-fetch the current repo before asserting
> any repo state — this capture reflects the repo as read 2026-06-01 (charter
> v0.25) and Claude has no memory across sessions.

> ## ▣ ROUND TWO — CLOSED 2026-05-31 (repo at charter v0.24)
>
> One-glance orientation for round three. This stamp supersedes the ROUND ONE
> stamp below (kept for history). Round-two detail lives in Parts M–Q.
>
> **SETTLED THIS ROUND (was open at round-one close):**
> - **Generations — REMOVED** (Part Q). Decision rests on a new normative
>   **teardown rule** (Part Q.2): to free an ISR ECID, software must clear the
>   mask bit → clear the **pending bit** (discard any latched interrupt) → clear
>   the routing entry → free the slot, in that order before reuse. This is D.13
>   applied to interrupt routes. With it, the latched-interrupt window generations
>   guarded is closed, so the counter is removed. Rests on standard base-CLIC
>   pending-bit clearing, which CE already assumes (ch18 §18.0: "no new hardware
>   mechanisms"); the enacting charter session should cite the exact base-CLIC
>   mechanism.
> - **SMT — SETTLED, no logical work** (Part O). Architect framing: siblings are
>   independent harts that share silicon; isolation is default. Repo already agrees
>   (a hart *is* a hardware thread, CE state is per-hart; "SMT" appears nowhere).
>   Physical cache/TLB/bandwidth sharing is a microarch/profile/OS matter, handled
>   by existing CPE/MSE/QoS tools, not the logical core. D.3 already carries it.
> - **Allocator policy (F.4a) — CLOSED** (Part P.1): hardware picks the slot
>   (`ec.ir` returns the number; software cannot request an L value). Matches lab
>   E.2; matches v0.23 `ec.it` count-model.
> - **D.20 (rebasing / local view) — PROMOTED to load-bearing** (Part P.2): charter
>   §6.9 Self-Preservation *depends* on per-level local bank numbering. Invariant
>   list now complete at **D.1–D.20**.
> - **`.md` vs `.adoc` — CLOSED:** the `.md` tree is authoritative; `.adoc` is
>   generated via `make adoc`. No reconciliation ever needed; ignore `.adoc`.
> - **Repo moved in the loop's favor (Part M):** charter v0.23 added a normative
>   **Self-Preservation Invariant** (generalizes round-one reachability); `ec.it`
>   became count-based (confirms hardware-picks); v0.22 shipped MSE local-view
>   (the template for the QoS fix).
>
> **DECIDED, AWAITING THE ARCHITECT'S CHARTER SESSIONS (not loop work):**
> - **Cluster F / QoS local-view** — recommendation drafted
>   (`scratchpads/qos/cluster_f_local_view_recommendation.md`); architect approved
>   its one real choice (borrow MSE storage format, v1 single-level). Awaits a
>   charter session to make normative (charter + ch00 lines ~502/506 + ch11 + ch13).
>   This is the last design-loop blocker on criterion 4 / the freeze.
>   *(Superseded round three: QoS scoped out of loop; criterion 4 complete —
>   see Part L.5 and Round Three stamp above.)*
> - **Generations removal propagation** — decided (Part Q); enacting it is a
>   charter session + per-chapter sessions across ch00, ch03, ch07/09/11, ch05,
>   Appendix A (the F.1 propagation surface).
>
> **STATE OF THE FIVE CRITERIA:** 1–3 complete; 2's invariant list now D.1–D.20;
> 4 survives all three stress slices for CME/CPE/MSE and is blocked only on Cluster
> F's QoS half (now in the architect's hands); 5 (two zero-change passes → freeze)
> cannot begin until 4 closes.
>
> **ROUND THREE PICKS UP AT:**
> 1. Confirm whether the architect has run the Cluster F charter session. If yes,
>    re-run the criterion-4 cluster scenario (Part L.3) against the now-normative
>    QoS local-view → attempt to close criterion 4.
>    *(Superseded round three: criterion 4 confirmed complete on scope-out basis —
>    see Part L.5 and Round Three stamp above; criterion 5 is next.)*
> 2. If criterion 4 closes, **begin criterion 5**: a full red-team pass over tenets
>    (Part C) + invariants (D.1–D.20); zero changes = pass one. A second clean pass
>    = converged → freeze is then a deliberate architect decision with a version bump.
> 3. Otherwise continue any not-yet-enacted propagation (generations) or remaining
>    charter writeups as the architect directs.
>
> **DO FIRST in round three (process):** re-upload / re-load the current repo before
> asserting any repo state — this capture reflects the repo as read 2026-05-31 and
> Claude has no memory across sessions, so round three starts blind to this one.

> ## ▣ ROUND ONE — CLOSED 2026-05-31 *(superseded by the ROUND TWO stamp above; kept for history)*
>
> One-glance orientation for the next session. Detail lives in Parts A–L below.
>
> **SETTLED (criteria 1–3 complete):**
> - **Tenets frozen** (Part C, 11 tenets + migration scope boundary).
> - **Invariants enumerated** (Part D, D.1–D.19; D.20 rebasing/local-view added as
>   candidate to fold in next round).
> - **Cost tiers classified** for all 24 instructions, verified against the repo
>   (Part I): fast critical path is exactly `ec.ib`/`ec.ob`; everything else
>   bounded by D ≤ 3, radix depth, or bank/bandwidth; D.16 holds.
> - **Uniform rebasing decided** (Part L.0): every level sees ECID ranges + all
>   banks (VMT and non-VMT) rebased into its own local namespace.
> - Migration confirmed OS-scope, not CE (Part C boundary).
>
> **EXERCISED & SURVIVING (criterion 4, partial):**
> - OS-mapping (Part J), L0–L3 nesting (Part K), cluster/multi-hart (Part L) stress
>   slices run. Model holds for CME / CPE / MSE.
>
> **BLOCKED (why the round stops here, by design):**
> - Criterion 4 cannot be *declared complete*, so criterion 5 (two zero-change
>   passes → freeze) cannot begin, because the cluster scenario's **QoS I/O-fabric**
>   half depends on **Cluster F**, an open *charter* item (architect's call,
>   dedicated session). The design loop correctly refused to invent QoS-fabric
>   semantics in passing (Part L.3). This is the firewall working, not a stall.
>
> **PARKED (deliberate, for later):**
> - **Generations** — explore removing, or weigh whether consequences force keeping
>   them. Entry point: the sharpened ISR-teardown ordering question (Part J).
> - **SMT detail** — architect deferred to a later dedicated discussion (Parts E.3,
>   K profile-note, L.2).
>
> **ROUND TWO PICKS UP AT (priority order):**
> 1. **Cluster F** — either the architect resolves it in its own charter session,
>    or web-Claude drafts a QoS-fabric local-view *recommendation* (MSE stored-global
>    / Formula-2 mechanism is the template; D.19 + D.20 give the shape) as *input* to
>    that session. This is the blocker; it goes first.
> 2. **Generations** exploration (ISR-teardown window: read ch18's actual teardown
>    sequence first — does it mask source + clear `isr_ecid_slot` atomically before
>    slot reuse?).
> 3. **SMT detail** discussion.
> 4. Smaller verifications: F.4(a) allocator policy (hardware vs software slot
>    selection); confirm `.md` vs `.adoc` authoritative tree (Part L.4) before any
>    porting.
>
> **DO FIRST in round two (process):** re-fetch / re-load the current repo (a fresh
> tarball or the orientation chain) before asserting any repo state — this capture
> reflects the repo as read 2026-05-31 and may be stale by then.

**Type:** Non-normative design-loop laboratory record.
**Belongs with:** `ce_core_logical_structure.md` (the lab document). This is a
capture of one working session between the architect and web-Claude; it is
input to the next revision of the lab document, not a spec edit.
**Status:** Working notes. Nothing here is charter-binding. The lab is slated to
*become* the source from which the charter and the whole CE Suite are eventually
rewritten, so divergence from the current repo is expected and permitted; it is
not a defect to reconcile pass-by-pass (see Part F).

**Verified against the repo this session:** initially the public GitHub mirror
(README → charter **v0.15**, release 2026-05-28; and ch00, the normative formal
data model); then the **full repository tarball** the architect supplied directly
(most current and complete). Criterion-3 verification (Part I) and the divergence
surfaces (Part F) are checked against the tarball: ch03 (CME instructions), ch07/
ch09/ch11 (CPE/MSE/QoS), and Appendix A (ECID allocation). **Not** exhaustively
read this session: the charter prose in full, `docs/working_notes_for_authors.md`,
`docs/work-items.md` (so no work-item numbers are asserted below), ch05 in detail.

---

## Part A — Purpose of the session

The architect's diagnosis: repeated charter redesigns force lengthy propagation
passes through all documentation, because the logical core is not yet exactly
right. The remedy adopted is to settle the logical nucleus in a separate
laboratory document that churns freely, and to port results into the charter
only as deliberate, dedicated decisions. The separation is the firewall.

This session worked the exit condition for the loop (criterion 1) and produced a
frozen tenet list and a candidate invariant list.

---

## Part B — Exit condition for the design loop

The loop is "done" when all five hold. Proposed and agreed in session; the
architect owns this definition.

1. **Tenets frozen and self-consistent.** A short fixed list of non-negotiables
   is written down (Part C) and the lab document is consistent with it. Changing
   a tenet is a deliberate dated act, not drift.
2. **Invariants enumerated.** A list (Part D) that is internally
   non-contradictory, preserved by every algorithm, and satisfied by every
   profile.
3. **Cost shape holds.** Every operation is tier-classified, exhaustively:
   fast path is O(1) or O(D_fixed) and never scans; slow path is bounded
   `≤ O(N log N)`, proportional to work done, with no unbounded scan on a
   realtime path. Each profile's structures fit a declared area budget.
4. **Stress battery runs clean.** The L0–L3, OS-mapping, and cluster-mapping
   scenarios plus the per-pass checklist run with no unresolved item.
5. **Two consecutive zero-change passes.** A red-team pass produces no change to
   the frozen tenets/invariants, and the next pass also produces none. The
   freeze itself is then a deliberate architect decision with a version bump.

Note on criterion 3: the ceiling is `O(N log N)`, not `O(log N)`. Subtree
revocation and teardown are inherently proportional to the state they touch
(`O(S+R)`), which is the floor, not a defect. With delegation/virtualization
levels in `{0,1,2,3}` the depth terms collapse to constants.

---

## Part C — Frozen tenets

The non-negotiable referent for the lab document. Frozen in session.

1. ECID is architectural identity; it indexes the per-hart EC table and is never
   a pointer.
2. ECID (architectural identity) and ECS (optional OS metadata) are distinct
   objects. An ECID may exist and own resources with no ECS bound. An ECID must
   have a bound ECS before it can be made runnable / dispatched. An ECS may
   exist with no ECID, at the OS's discretion — such contexts simply cannot use
   CE features. Fast-path execution state lives in the EC entry, never behind
   the ECS pointer.
3. Identity is hart-local: a context is `(hart, ecid)`; the same ECID on another
   hart is a different identity; identity does not move between harts.
4. Every ownable object has exactly one canonical owner Group, and GroupID =
   ECID. A Group is abstract — membership is realized only by up-pointers from
   owned objects (Banks, Contracts, and child ECIDs) to the owning ECID. The
   child-ECID up-pointer is the parent reference held in the EC entry.
5. Ownership is represented upward; up-pointers are truth. Downward member lists
   are derived accelerators, never canonical, and a disagreeing derived index is
   architecturally impossible to act on (the up-pointer wins).
6. The delegation tree is the transitive closure of up-pointers, and is acyclic
   apart from the root's `parent(root) = root` self-loop — a termination sentinel
   (tenet 7, D.7), not a delegation edge. No ECID other than the root is its own
   ancestor.

   *[Deliberate tenet change 2026-06-01, round three, criterion-5 red-team
   finding. The unqualified "acyclic" sat in tension with the root self-loop that
   tenet 7 / D.7 establish and rely on as an ancestry-walk termination sentinel.
   Tenet 6 now names the sentinel exception explicitly, aligning it with the
   precise machinery already in tenet 7 and D.7. No model change. Architect
   accepted the finding.]*

7. There is exactly one root ECID per hart authority domain (L0, ECID 0), with
   `parent(root) = root` when CE is enabled in hardware. For every non-root ECID,
   parent is strictly higher in the tree; no non-root ECID is its own ancestor.
   Ancestry walks terminate at the root's self-loop.
8. A child sees only its virtualized view; it cannot infer host, sibling, or
   global topology — and even partial inference (e.g. via timing) must not be
   convertible into authority.
9. Authority over a resource cannot be acquired by guessing, writing, or
   replaying an ID — only by delegation from a holder.
10. CE defines a serialization surface: Bank state has architectural
    save/restore via spill/fill; live bindings to shared hardware (cache
    reservations, bandwidth contracts, interrupt routing, timers) — whether
    hart-local or chip-global — have none. State without a serialization cannot
    be moved without loss.

    *[Deliberate tenet change 2026-06-01, round three, criterion-5 pass-1
    red-team finding. Original read "live hart-local bindings (cache/QoS
    contracts, …)" — the "hart-local" qualifier is wrong: MSE and QoS bandwidth
    contracts are chip-global / fabric-wide (see Part L.2, D.18). "QoS
    contracts" as the example also leaned on a frozen extension; replaced with
    the generic "bandwidth contracts." Now aligned with D.18, which already used
    "live arrangements with shared hardware" without the hart-local qualifier.
    Architect accepted the finding.]*
11. The fast path never scans; slow paths may, within the bounded ceiling
    (O(1)/O(D_fixed) fast; `≤ O(N log N)` slow).

**Scope boundary (kept separate from the tenets — states what CE is *not*):**
Migration — cross-hart, cross-hypervisor, cross-level — is an OS operation
composed from CE primitives. CE has no migration concept. An execution context
is a software abstraction facilitated by the ECID and ECS; it is not a thing the
hart can act on as "migrate." CE proper owns only the primitives the OS composes
(allocate, spill/fill, free, ownership update) and enforces its per-operation
invariants on each step. "Pinned / non-migratable" is therefore not a CE
property but the OS observing that some CE state has no serialization. This
boundary dissolves the cross-level question rather than answering it: there is no
cross-level migration in CE to permit or forbid.

---

## Part D — Candidate invariants

Properties every algorithm must preserve and every profile must satisfy. The
security invariants (D.11–D.13) are stated as prohibitions; each now carries a
positive operational form (what the hardware does so the prohibition holds), added
round three (2026-06-01) during the criterion-5 red-team pass. The deferral is
closed.

**Identity & structure**
1. Each hart (hardware execution thread, including each SMT sibling) has exactly
   one current ECID at any instant. SMT siblings on one core are distinct harts
   that may share the physical EC table and Bank storage but never share a
   `current_ecid`.
2. ECID slot (identity) and ECS (metadata) are distinct objects; neither is ever
   the other.
3. An operand never carries a raw physical slot number; software sees only
   virtualized-per-group numbers. L0's namespace coincides with the physical
   table.

**Ownership**
4. Every ownable object (Bank, Contract, child ECID) has exactly one owner
   Group, realized by a single up-pointer to the owning ECID.
5. No object has two owners; no ownable object is unowned while live.
6. Ownership is recoverable by following up-pointers; any downward/derived index
   that disagrees yields to the up-pointers.

**Delegation tree**
7. Exactly one root per hart authority domain, `parent(root)=root`; every
   non-root parent is strictly higher; no non-root ECID is its own ancestor;
   ancestry walks terminate at the root self-loop.
8. A child's level is its parent's + 1, bounded by D; an ECID at level D
   delegates no children.
9. Incomparable ECIDs (neither ancestor of the other) never both own the same
   single exclusive resource object. They may each own separate, non-overlapping
   slices carved from one divisible resource (bandwidth, cache); each slice is
   exclusively its owner's.

**Authority & visibility**
10. Authority is never acquired by guessing, writing, or replaying an ID — only
    by delegation from a holder.
11. A child cannot observe or infer host, sibling, or global topology, including
    via allocation results or operand values; partial inference is not
    escalatable into authority.

    *Positive form:* a child observes its resources only in its own local view,
    and no global quantity is exposed for inference. Operands it supplies and
    allocation results returned to it are local-namespace values — a local index
    or count (hardware-picks, Part P.1), rebased to the child's local base (D.3,
    D.20), never a global slot number. Local-view CSR readbacks (Formula 2)
    present the child's share as a fraction relative to its parent; hardware
    computes this from stored-global values — the child's own and its parent's —
    that the child never sees, so the child observes only the resulting fraction
    and cannot recover those inputs or any global total.

    *[D.11 positive form corrected 2026-06-01, round three, criterion-5 red-team
    finding. Prior wording described the Formula-2 readback as "a function only
    of the child's own subtree state" — inaccurate: Formula 2 is
    r(e) = floor(s(e) × 256 / s(p(e))), where s(p(e)) is the parent's
    stored-global value, which is outside the child's subtree. The privacy
    guarantee is preserved: the child sees only the resulting fraction, never the
    stored-global inputs. Architect accepted the finding.]*

12. A context can name only resources within its own group/subtree entitlement;
    it cannot name self-as-deletable, parent, or siblings.

    *Positive form:* operands are interpreted in the caller's local
    group/subtree namespace; names outside it are not representable in that
    namespace and an out-of-range name traps rather than resolving elsewhere;
    "self" is the reserved local base ("self = 0") and is structurally
    non-nameable as a delegation or deletion target.

**Lifecycle**
13. A slot returns to FREE only after complete synchronous teardown: all child
    ECIDs, Banks, Contracts, and inbound routes (interrupt/QoS/timer) resolved.
    No lazy reuse.

    *Positive form:* every inbound route is fully cleared before the slot frees.
    Interrupt routes follow the fixed order mask → pending → routing → free (Part
    Q.2, which discards any latched interrupt). QoS routes (DMA channel bindings)
    and timer routes follow the same resolve-before-free discipline but with their
    own steps — they have no mask/pending bits. `ec.oe` performs forced reclaim by
    reverse-walking up-pointers — revoking Contracts, freeing Banks, marking the
    subtree FREE — before the slot can be reallocated; with the D.14 scrub, no
    successor observes predecessor state. (This closed the generations ABA window,
    Part Q.)

    *[D.13 positive form corrected 2026-06-01, round three, criterion-5 red-team
    finding. Prior wording applied the interrupt-specific Q.2 order (mask →
    pending → routing → free) to all routed resources; QoS routes (DMA channel
    bindings) and timer routes have no mask/pending bits, so the interrupt order
    does not generalize. Q.2 is now scoped to interrupt routes; the general
    resolve-before-free rule covers QoS and timer routes. Architect accepted the
    finding.]*

    *[Positive forms for D.11–D.13 added 2026-06-01, round three, criterion-5
    red-team pass. Deferral in the preamble above is closed. Each form falls
    directly from mechanisms already in the set: D.3/D.20 and Formula 2 for
    D.11; namespace and trap mechanics for D.12; Part Q.2 teardown order and
    D.14 scrub for D.13. D.11's positive form was subsequently tightened (same
    date, same pass) — see the inline note at D.11 above. D.13's positive form
    was also tightened (same date, same pass) — see the inline note at D.13
    above.]*
14. On free or before reallocation, resource content is scrubbed (by whatever
    bulk hardware mechanism applies — cache-line invalidate, way-flush, zeroing
    engine — not bit-by-bit); no successor owner observes a predecessor's
    leftovers.
15. Teardown returns a freed child's resources to its parent, never outside the
    parent's subtree.

**Forced destruction (`ec.oe`) — clarifies D.13's "resolved".** "Resolved" does
not require cooperative teardown. `ec.oe` on an ECID must *always* succeed: the
hardware itself reclaims the whole subtree — by reverse-walking the tree via
up-pointers, or using the real hardware ECID numbers — revoking all Contracts,
freeing all Banks, and marking the subtree free. A destroyed EC cannot stall its
own reclamation. The hardware's responsibility ends at the architectural reclaim;
what happens to the *software* tower built on those ECIDs (hypervisors, nested
VMs) is not the hardware's concern. Software should attempt an amicable resource
return first, but if that fails, `ec.oe` still succeeds even if the software side
crashes or all dependent VMs die — that is programming or operator error, not a
CE failure. CE supplies the tools to tear down cleanly; it does not prevent
misuse. (The relevant OS-interaction chapters may describe how teardown *should*
be done.) Consistent with ch00 §0.8.

**Cost**
16. Every operation is tier-classified, exhaustively: fast path O(1)/O(D_fixed),
    never scans; slow path bounded `≤ O(N log N)`, proportional to work. Nothing
    unclassified.

**Runnability, serialization, divisible resources**
17. An ECID may be ACTIVE-owning with no ECS bound; it may be dispatched (made
    runnable) only with an ECS bound.
18. Only register/Bank state is architecturally serializable, via spill/fill.
    Live arrangements with shared hardware — cache reservations, bandwidth
    guarantees, interrupt routing, timers — cannot be saved as bytes; they must
    be re-established on the destination, which may fail. CE alone cannot
    recreate them. (This is why "pinned" exists: a context is pinned exactly when
    it holds such an un-saveable arrangement.)
19. A divisible resource (Contract) may be split among child contexts. Each
    child's share is a strict subset of the parent's, and the children's shares
    never sum to more than the parent held. Granting or splitting is all-or-
    nothing and atomic at the arbiter's scope (chip-wide for bandwidth,
    core-local for cache): it either fully succeeds or leaves everything
    unchanged.

    *[Deliberate invariant change 2026-06-01, round three, criterion-5 red-team
    finding. "decided chip-wide" over-generalizes: MSE/QoS bandwidth is
    chip-global but CPE cache is per-hart/core-local (D.9, Part L.2). Corrected
    to "atomic at the arbiter's scope (chip-wide for bandwidth, core-local for
    cache)." Symmetric correction to tenet 10 (which over-narrowed in the other
    direction). Architect accepted the finding.]*

**Scope boundary on resource sufficiency (not an invariant CE enforces).**
CE does not guarantee that any actor retains a *workable* amount of resource
after delegation — e.g. that a kernel keeps enough cache or memory bandwidth for
itself after handing slices to children. Arranging a workable situation is the
programmer's / OS's responsibility. CE's only structural guarantee in this area
is that ECIDs cannot become *unreachable*: an ECID that holds child ECIDs in its
Group cannot give away itself (self is non-delegable, tenet/invariant via "self
= 0"), so authority over a subtree can always be reached from above. Open
question deferred: how this interacts with Linux `kexec` (which replaces the
running kernel) — to be addressed when reached, not now.

---

## Part E — Decisions taken this session (within the lab)

1. **Generations — parked for the next design-loop round (NOT settled).** The
   session explored removing generation counters, replacing ABA/stale-handle
   defense with: hardware picks the slot, the caller never supplies a raw slot
   number, self is virtualized as 0 and non-delegable, and reuse is non-lazy
   (complete synchronous teardown gates return-to-FREE). This shuts the *forging*
   hazard by construction (D.10) and the *ordering* side of reuse via the teardown
   gate — but a *detection* gap remains (F.1). The architect's framing for next
   round: explore options to do without generation counters, or, failing that,
   weigh whether the consequences are severe enough that they must be kept. Until
   then generations stand as in the repo. The other session decisions (E.2, E.6,
   D.13) do **not** depend on this outcome — they hold either way.
2. **Virtualized-per-group namespaces.** Each requester sees its own children
   numbered in its own space; "self = 0" is the context-relative base case, and
   "last-in-row" (rightmost-free) is resolved within the requester's own child
   namespace, leaking nothing. Hardware translation substrate is the up-pointer
   the EC entry already holds; software never sees a raw slot; at L0 virtual and
   physical coincide. Consistent with ch00 §0.5/§0.11 child-renaming.
3. **SMT/hart model.** Each hardware thread is a hart with its own
   `current_ecid`; SMT siblings share the EC table and Bank SRAM but not the
   current pointer. New elaboration; ch00 is silent on SMT. Implies the shared
   table must enforce per-hart isolation between siblings and needs concurrent
   multi-thread access.
4. **ECS optional / runnable-vs-owning split.** An ECID can own resources with
   no ECS (allocated-but-not-runnable); binding an ECS is what makes it runnable.
   Supports delegate-then-bind and grow-after-running. Needs a "none" encoding
   for the ECS pointer and a precise state name. Elaboration; ch00 §0.4 is silent
   on null ecs_ptr.
5. **Explicit root.** Root self-pointer is the documented ancestry-termination
   base case, gated on CE being enabled. Consistent with ch00 §0.8.
6. **Scrub required (independent of the generations question).** On free or
   before reallocation, freed resource content is scrubbed so no successor owner
   sees a predecessor's leftovers (D.14). This addresses *content confidentiality*
   and stands on its own regardless of whether generations are kept — it is a
   different concern from the stale-handle *detection* generations provide. Large
   VMT Banks make scrub timing (eager-on-free vs deferred-before-handover) a real
   profile choice.
7. **Migration exiled to OS scope.** See Part C scope boundary. Consistent in
   spirit with ch00 §0.2 (kernel unbinds/rebinds).

---

## Part F — Intended divergences from the current repo (carried until the rewrite)

The lab is slated to become the source from which the charter and the whole CE
Suite are rewritten, after convergence, in a single deliberate pass. Divergence
from the current repo is therefore expected and permitted; the items below are
not defects to reconcile pass-by-pass. They are the delta the eventual rewrite
will carry.

Two rules still hold, and they are the whole point of the firewall:
- **Flow is one-way and deferred.** Nothing flows from lab to charter until the
  rewrite. No lab item — however settled it feels — leaks into the charter or any
  chapter mid-flight. The failure mode being prevented is not "lab disagrees with
  charter" (that is fine); it is "a half-settled lab idea triggers an early
  propagation pass." The rewrite *is* the one authorized porting session.
- **The rewrite must satisfy what the current ch00 anchors.** Because ch00 is the
  formal data model that ch01–ch19 and both appendices reference, the lab — when
  it eventually supplies the new ch00 — must keep every downstream dependency
  satisfiable. This is folded into criterion 4 (stress battery): "does anything
  in ch01–ch19 depend on something the lab removed?" Generations are the first
  probe (Appendix A's allocator and ch05's Linux triple lean on them).

Recorded divergences (point-in-time against repo as fetched this session):

1. **Generation counters — PARKED for next round; repo keeps them for now.**
   Verified against the full repo this session, generations are woven through:
   ch00 §0.2/§0.3/§0.8; ch03 §3.5 (`ec.ir` and `ec.oe` both increment); ch07
   error table (CPE_ERR on generation mismatch), and almost certainly the ch09/
   ch11 error tables likewise; and Appendix A (the `generation` field in the
   `EC[e]` struct §A.1, the "increment on every reuse" rule §A.2, and the
   allocator algorithm §A.3.2 `EC[new_ecid].generation += 1 // ABA guard; wraps
   modulo 256`). The session explored removing all of this (E.1) but the architect
   has parked the question for the next design-loop round. **Next-round task:**
   find a way to do without generation counters, or, failing that, weigh whether
   the consequences are severe enough that they must be kept. If removal is chosen
   later, the propagation surface is now mapped: ch00, ch03, ch07/09/11 error
   tables, ch05 (the `(hart_id, ECID, generation)` software handle), and Appendix
   A's allocator. Until then, generations stand.

   **The red-team point that must be answered before removal is viable.** The
   repo's stated reason for generations (§A.2) is to stop a
   stale `(hart_id, ECID, generation)` reference from reaching the wrong target
   after a slot is freed and reused. The teardown-gate argument handles *ordering*
   (no reuse before teardown completes) but not *detection*: the privileged
   allocator (kernel/hypervisor) legitimately holds cross-context references and
   is **not** bound by the child-visibility rules (tenets 7–8) that protect
   unprivileged software, so a kernel component can hold an old `(hart, ecid)` and
   address a later occupant of that slot. Generations catch exactly this; removing
   them removes the guard.
   **Candidate answer the next-round probe should test (not adopted):** have the
   OS key durable references on **ECS identity** — the ECS pointer, which the OS
   itself allocates and whose lifetime it controls (tenet 2) — rather than on
   `(hart, ecid)`, which is reusable. Under this option a raw `(hart, ecid)` value
   would be valid only in the immediate hand-back window from `ec.ir` until the OS
   frees it; the architecture would provide no generation guard and not promise
   `(hart, ecid)` stability across a free. This is the most promising direction
   for "do without generations," but it is a real design commitment, not a free
   consequence, and it must be tested against ch05's kernel model before it can be
   called viable. This is the criterion-4 probe started below. Lab open questions
   Q12/Q13 are folded into this next-round task.

2. **ECID width — stale in the lab document; repo is authoritative for now.**
   Current ch00 §0.2 fixes ECID at **16 bits, 65536/hart**. The lab document's
   Section 34 ("12-bit, 4095 max") and open questions Q1/Q2 predate this and
   should be corrected *in the lab* to 16-bit (the session's namespace work
   already assumes 16-bit). This is a lab-doc cleanup, not a divergence the
   rewrite introduces.

3. **L0–L3 role labels — wording drift to normalize in the lab.** Current ch00
   §0.8 labels the levels L0 host kernel / L1 hypervisor / L2 nested hypervisor /
   L3 guest. Lab Sections 7 and 37 use a different framing. Same structure;
   normalize the lab's prose so the eventual rewrite carries one consistent set
   of labels.

4. **Allocator model — lab "rightmost-free in a virtualized namespace" vs repo
   "radix-tree free-list pop, prefix‖index".** Verified: the repo allocates ECIDs
   via a kernel-managed radix tree organized as `prefix‖index` (ch00 §0.2,
   Appendix A), where `ec.ir` pops one ECID from the owning node's free list
   (O(1), §A.3.2) and returns the new child ECID *number* to the parent. Two
   reconciliation points for the rewrite, neither a contradiction:
   (a) *Policy location.* The repo frames allocation policy as kernel software
   layered on the architectural `EC[e]` array; lab E.1/E.2 frames slot selection
   as hardware ("hardware picks the slot"). `ec.ir` being a hardware instruction
   is common ground; what differs is whether the selection *policy* (free-list pop
   vs rightmost-free) is architectural or software. Decide in the rewrite.
   (b) *Number visibility.* `ec.ir` returns a child ECID number to the parent (the
   parent needs it to target `ec.ob` etc.). The repo's `prefix‖index` makes the
   index portion per-prefix (per-group) local, which is broadly compatible with
   the lab's virtualized-per-group namespace (E.2) — but the full 16-bit value is
   hart-global. The rewrite must state precisely what the parent sees (a
   group-local index vs a hart-global `prefix‖index`) and confirm it satisfies
   invariant D.11 (no topology leakage). The lab's "self = 0 / child renaming"
   and the repo's §0.5 child-renaming agree in spirit; the open part is the exact
   number the *parent* (allocator) handles.

---

## Part G — Deferred to later passes (not for now)

For the "per-hart ECID table and up-pointer realization" pass (lab doc §41):
- Child-direction operand translation: an up-pointer resolves child→parent, but
  naming a child is parent→child. The fast path needs O(1) child resolution
  (stable per-context index from the allocator, or a small resident
  child-translation entry). Slow-path to build, O(1) to use.
- Shared-table concurrency and per-sibling isolation under SMT (from E.3),
  including the cross-sibling allocation hazard on rightmost-free.
- The "none" encoding for the ECS pointer and the precise state name for
  allocated-but-not-runnable (from E.4).

For the Banks/Bank-residency pass:
- Scrub timing for large VMT Banks (from E.6).

For OS-interaction chapters (not CE core):
- Realtime OSes using CPE to pin the ECS into hot cache to bound the
  pagetable-walked ECS-pointer dereference (from tenet 2 / ch00 §0.4).
- vCPU scheduling: a vCPU runs on one hart (one hardware thread) at a time; a
  2-way-SMT core runs two vCPUs at once, one per sibling. Different-tenant
  co-residency is the L1TF/MDS side-channel surface; hypervisor "core
  scheduling" (co-schedule only confidentiality-compatible subtrees on one
  core's harts) is the mitigation. CE must leave room for it but does not make
  the policy.

Lab-document edits implied (to apply in a lab-doc revision, not the charter):
- Leave the generation field in place; its removal is parked for next round
  (E.1/F.1). Do not strip it from lab Sections 2/14/19 yet.
- Mark migration Sections 12/13/31 and Part VI conclusions 11–15 as OS-scope.
- Correct Section 34 width and close Q1/Q2 per F.2.

---

## Part I — Criterion 3: cost-tier classification (verified against repo)

All 24 instructions verified against the full repo this session (ch03 §3.1–3.9
timing summary; ch07/09/11 instruction sections and timing tables; ch00 §0.7
admission model). Result: the cost-shape invariant (D.16) holds across the whole
instruction set — nothing is unbounded, nothing on a realtime path scans
unboundedly. Cycle figures are the repo's stated guaranteed cycles.

The repo expresses **three implementation tiers** (banked-SRAM / DMA / vault),
which sit orthogonally on top of our two-tier *cost* model (fast O(1)/O(D_fixed)
vs slow ≤ O(N log N)). The key reconciliation: most management ops are
single-digit cycles **because D ≤ 3 keeps subtrees shallow** — they are
"proportional to subtree size" (slow-path *shape*) but cheap in absolute cycles
(banked *tier*). Both descriptions are true and non-contradictory.

**Critical-path fast (the actual context switch), O(1):**
- `ec.ib` — save current to bank. 1–3 cycles; dirty-save mode skips clean groups.
- `ec.ob` — restore target from bank; atomically loads contract params (MSE/QoS/
  CPE) from the Bank CP field. 1–3 cycles. These two never touch ECS (ch03 §3.1).

**Banked-tier management, O(1) or O(D_fixed), bounded small cycles:**
- `ec.ig` / `ec.og` — assign/release a bank to/from a Group. 1–4 cycles.
  Bank-exhaustion recovery (`ec.ig` → spill victim via `ec.im` → `ec.og` → retry)
  is a defined kernel protocol, not a hardware stall.
- `ec.it` — delegate one bank to a child (one bank per call). 1–4 cycles.
- `ec.ot` — revoke all resources from a child; recursive, returns to parent.
  1–8 cycles, proportional to subtree size (bounded by D ≤ 3).
- `ec.ir` — allocate a child ECID (leaf vs delegating per `rs1`). 1–8 cycles,
  log of radix depth. (Currently increments a generation counter; removal parked,
  F.1.)
- `ec.oe` — forced destroy of ECID + subtree; always succeeds, hardware walks
  depth-first leaves-first bounded by D ≤ 3. O(log N) avg, proportional to
  subtree. (Currently increments generations; removal parked, F.1.)
- `cp/ms/qs.{ir,it}` — create/delegate a Contract. 1–4 cycles; O(1) cap check
  with ancestor-sum update bounded by D ≤ 3; admission is **chip-global atomic**
  (ch00 §0.7.4) — succeeds wholly or changes nothing (this is invariant D.19's
  enforcement point). MSE/QoS enforcement itself is O(1) per arbitration cycle.
- `cp/ms/qs.{or,ot}` — revoke/return a Contract. MSE/QoS comparable to creation;
  Contract dissolution is O(log N) via the radix tree.

**DMA tier, slow path, O(bank_size / bandwidth):**
- `ec.im` / `ec.om` — spill/fill Bank ↔ ECS in RAM. 10–128 cycles (bus-width
  dependent). The only genuinely many-cycle CME ops; explicitly off the
  context-switch path.

**Vault tier, crypto-bound:**
- `ec.iv` / `ec.ov` — seal/unseal a Bank under hardware encryption (M-mode only).
  Cost is crypto-engine-bound; off the fast path.

**CPE invalidation note:** `cp.or`/`cp.ot` carry cache writeback/invalidation
latency (1–16 cycles, proportional to subtree depth) — the CPE instance of
D.18's "live binding cannot be saved as bytes": releasing a cache partition costs
invalidation, it does not serialize.

**Criterion-3 verdict:** every operation is classified; the fast critical path is
exactly `ec.ib`/`ec.ob`; all other ops are bounded by D ≤ 3, radix depth, or
bank/bandwidth, none exceeding the `≤ O(N log N)` ceiling. D.16 is satisfied by
the current instruction set. The two repo-vs-lab deltas that touch this
classification (generations in `ec.ir`/`ec.oe`; allocator policy) are tracked in
F.1/F.4 and do not change any tier.

---

## Part H — Still open (architect's call, not resolved)

- **Generations — parked for the next design-loop round (E.1/F.1).** Explore
  doing without generation counters; failing that, weigh whether the consequences
  are severe enough that they must be kept. The criterion-4 probe below gathers
  evidence for that decision but does not make it.
- Linux `kexec` interaction with the non-delegable-self / reachability guarantee
  (deferred; see Part D scope note).
- Criterion 5 (two consecutive zero-change passes → freeze), after criterion 4
  completes.

Resolved / progressed this session: the SMT/hart model (E.3) carries into the
eventual rewrite as new ch00 material. The invariant list (Part D, D.1–D.20, D.9
tightened, D.20 added) is confirmed complete for criterion 2. Criterion 3 is
complete and verified against the full repo (Part I). Criterion 4 is **complete
for the scoped core** (Parts J/K/L stress slices all survived; QoS I/O-fabric
explicitly scoped out per Part L.5). The `.md` tree is confirmed authoritative
(Part L.5.1).

Criterion 5 (two zero-change passes → freeze) is pending two in-scope
resolutions, both for next round:
1. **Generations** — the sharpened interrupt-teardown question (Part J); gates the
   EC-entry layout. The larger item; settle first.
2. **Allocator policy F.4(a)** — hardware vs software slot selection; minor.

Deferred out of the core entirely (post-rewrite): QoS I/O-fabric / Cluster F
(Part L.5.2). Still parked: SMT detail (architect deferred for later discussion).

---

## Part J — Criterion 4 (in progress): generations / ECS-identity probe vs ch05 + ch18

First slice of the stress battery (the OS-mapping scenario), run to gather
evidence for the parked generations question (E.1/F.1). Verified against the
tarball: ch05 (Linux integration) and ch18 (CLIC interrupt integration). This
probe produces a sharpened question and evidence, not a decision — the decision
stays parked for next round.

**Finding 1 — the common case already keys on ECS identity.** ch05 §5.1.1: the
kernel allocates an ECID with `ec.ir`, writes `EC[e].ecs_ptr`, then **caches the
ecid as a field inside its `struct execution_context`** (`u16 ecid`). On every
switch it loads the ecid *from that struct* and passes it transiently to
`ec.ob`/`ec.im`. The durable handle is the struct (which the kernel owns and
frees on teardown); the bare ecid is only live within a switch sequence. So the
"key durable references on ECS identity" option (F.1 candidate) is **not a new
invention — it is essentially how ch05 already works.** For threads, processes,
and vCPUs, generations are belt-and-suspenders over a discipline that already
holds.

**Finding 2 — the hard case is interrupt/ISR ECIDs.** ch18: each ISR vector gets
a **dedicated ECID stored as a bare number in a per-hart, per-vector hardware
table** (`isr_ecid_slot`), read on every interrupt delivery. This is exactly the
"bare ecid held elsewhere" pattern generations defend. Mitigating factor: the ISR
ECID is **permanent** — allocated once at boot, released only when the interrupt
is unregistered — so it is not subject to rapid alloc/free/reuse churn. The
residual risk is narrow: unregister an ISR (free its ECID) → slot reused → an
in-flight or spurious interrupt for the old vector routes via a stale
`isr_ecid_slot` entry to the new occupant.

**Finding 3 — the current guard is weak anyway.** Per Appendix A §A.3.2 the
generation is **8 bits, wrapping mod 256**. It is a probabilistic detection net,
not a hard guarantee; after 256 reuses it can alias. A clean teardown-ordering
discipline could be *more* robust than a wrapping counter, not less.

**The parked question, now sharpened to one concrete decision point:**
> Can ISR/interrupt-ECID teardown guarantee, atomically before the slot can be
> reused, that (a) the interrupt source is masked and (b) the `isr_ecid_slot`
> routing entry is cleared?
- **If yes:** no stale route can fire; the ch05 ECS-identity discipline covers
  the thread/process/vCPU paths; generations become removable with no detection
  gap. This is the path to "do without generation counters."
- **If no (some window exists):** generations are the only thing catching a
  misrouted interrupt to a reused slot — and the question escalates to whether an
  8-bit wrapping counter is even adequate, or whether the interrupt path needs a
  stronger mechanism than today's generations.

**Severity of a misroute, IF the window exists (conditional — not an established
attack).** This is recorded conditionally because the hazard is only reachable if
interrupt teardown leaves a gap between freeing an ISR ECID and clearing its
`isr_ecid_slot` routing entry; the 1-2-3 teardown order (mask source → clear
routing entry → free slot) closes that gap, and competent interrupt teardown
already follows it (cf. Linux `free_irq`, which disables and synchronizes the
line before releasing anything). So the prior question is whether the consequence
is even reachable, not how bad it is.
- **What it is not:** not arbitrary code injection. Which code runs on an
  interrupt comes from the vector table, not from the target ECID, so a misroute
  does not make the old handler's code execute in the new context, and the bank
  scrub (D.14) means no stale register contents are inherited.
- **What it is:** *misdelivery* — a spurious interrupt delivered to the slot's new
  owner, which may be a different EC across a trust boundary (e.g. a hypervisor or
  another VM). The damage is whatever a context suffers from an unexpected
  interrupt (spurious preemption, violated state assumptions, cross-boundary
  delivery). A correctness/availability problem, possibly a confidentiality/
  integrity one depending on what the receiving OS does with an unexpected
  interrupt — but a misdelivery primitive, not an execute-arbitrary-code
  primitive. Severity is OS-specific and TBD.
- **Next-round verification:** read ch18's actual ISR-ECID teardown sequence and
  confirm whether `isr_ecid_slot` is cleared (and the source masked) atomically
  before the slot can be reused. If the window is closed, this concern dissolves
  entirely. If open, characterize severity then. Do not treat "stale interrupt
  routing → cross-EC compromise" as an established finding until the window is
  shown to exist. (This reasoning is from the ch18 routing model as read this
  session, not from a confirmed teardown sequence.)

**Status of criterion 4:** OS-mapping slice partially exercised (this probe). Not
yet run: the L0–L3 nesting scenario, the cluster-mapping scenario, and the
allocator-reconciliation probe (F.4). Those remain for continued criterion-4
work in this round.

---

## Part K — Criterion 4 (continued): L0–L3 nesting stress test

Ran the nested-virtualization scenario (L0 kernel → L1 hypervisor A/B → L2 guest
VMs → L3 guest threads; Appendix A §A.6.1 tree, lab §37 property list) against the
frozen tenets/invariants and the repo's delegation (A.3/A.4) and forced-destruction
(A.5) algorithms. Result: the model holds under nesting, with one finding that
must be made explicit and one profile-level note.

**Properties that hold:**
- *Sibling isolation (L1 A vs L1 B; L2 A1 vs L2 A2).* Incomparable ECIDs share no
  exclusive resource (D.9). Ownership check is owner-compare or ancestry; A's
  `current_ecid` never matches B's resources and A is not B's ancestor. Reinforced
  structurally by `ecid_delegate_prefix`'s non-overlap precondition (A.3.3):
  delegated prefix ranges are disjoint and alignment-checked. Holds.
- *Revocation reachability and bounds (L0 revokes L1 A; L1 A revokes L2 A1).*
  `ec.oe` always succeeds (A.5.1), post-order subtree walk bounded by D ≤ 3 (≤ 4
  levels, "shallow fast walk"), caller must be parent or privileged ancestor.
  Consistent with D.13 (forced-destroy clarification), D.16 (cost ≤ O(N log N),
  here O(subtree)), and reachability scope note. Holds.
- *Contract conservation on revocation.* `ec.oe` dissolves child Contracts back to
  the parent (A.5.2 step a). Dissolution *returns* resources, so unlike creation it
  cannot be denied — compatible with both the "always succeeds" guarantee and the
  chip-global atomic-admission invariant (D.19), which constrains creation, not
  return. Holds.
- *L3 is a leaf.* D = 3 ⇒ `delegation_L = 3` cannot delegate further (A.4.2 inv 6,
  our D.8). Holds.
- *No bank-topology inference (prop 3, bank half).* `ec.ib` already returns a bank
  slot index that is **0-based within the owning Group** (ch03 §3.1) — i.e. bank
  slots are rebased per-Group, not exposed as physical IDs. The bank side of D.11
  holds, and this is direct repo precedent for per-level rebasing (see finding).

**FINDING — ECID number visibility under nesting (the F.4(b) axis, confirmed
biting at L2/L3).** The open question is what ECID *numbers* a nested level sees
when it allocates. Two readings coexist in the repo and are not reconciled:
- §0.11 (local-view principle) and §0.5 (child renaming: a child sees its Group as
  Group 0, cannot observe parent GroupIDs) imply each level sees a **rebased**
  view — consistent with invariant D.11 and lab E.2.
- Appendix A §A.6.1 shows guest ranges as **raw prefixed** numbers (L2 Guest VM 1 =
  0x1000–0x10FF; threads 0x1011–0x1013). A raw prefix encodes the guest's position
  under its parent — if that is what the guest's own allocator sees, D.11 (no
  topology inference) is **violated**: the guest learns it is nested and roughly
  where.
  Resolution: the §A.6.1 tree is captioned as the **L0 kernel's** prefix view, so
  the raw numbers are the physical/L0 numbering, not necessarily the guest's view.
  The likely-correct and consistency-preserving reading is **rebased** — each level
  sees its delegated ECID range rebased (mirroring how `ec.ib` already rebases bank
  slots per-Group). The spec does not currently **state** this for ECIDs the way
  ch03 §3.1 does for bank slots. **Required for the rewrite:** make ECID-range
  visibility explicit and rebased per level; until then D.11 is only conditionally
  satisfied at L2/L3. This is the same axis as F.4(b), now shown to be a
  correctness requirement under nesting, not just a tidiness preference. The
  bank-slot rebasing precedent (ch03 §3.1) makes it readily resolvable.

**Profile note (not a break).** Forced destruction requires that the target not be
`current_ecid` on any hart; a target running on a remote hart is interrupted and
switched away first (A.5.2 "active-hart preemption", mechanism implementation-
defined). Under the SMT/hart model (E.3, siblings share the EC table), this is a
cross-sibling shootdown, and its latency is the realtime-revocation cost a
realtime profile must bound or forbid. Consistent with the model; flagged as a
profile-level obligation, not a logical defect.

**Status of criterion 4:** OS-mapping slice (Part J) and L0–L3 nesting slice (this
part) exercised. The model survives both, with the ECID-range-visibility finding
(rebased-per-level) added as a rewrite requirement. Not yet run: the cluster-
mapping scenario and the allocator-policy half of F.4(a) (hardware vs software
selection). Those remain for continued criterion-4 work.

---

## Part L — Criterion 4 (continued): cluster-mapping scenario + the rebase rule

### L.0 Decision recorded this session: uniform rebasing

The architect generalized the Part-K finding into a uniform rule:

> Everything a delegation level sees is rebased into that level's own namespace:
> ECID ranges **and** all bank slots — VMT and non-VMT alike. A level operates as
> if its delegated resources were the only ones in existence, starting from a
> local zero/base.

This is consistent with, and generalizes, existing repo mechanisms: ch03 §3.1
(bank slot index 0-based within the owning Group), ch00 §0.11 local-view
principle, and ch09's local-view/stored-global split for MSE. The rewrite states
this as one cross-cutting invariant rather than per-extension prose. Candidate
invariant (to fold into Part D next pass):

> **D.20 (rebasing / local view):** Every delegation level observes its delegated
> resources — ECID ranges, VMT banks, non-VMT banks, and contract scales — rebased
> into its own local namespace beginning at a local base, and cannot observe the
> parent/physical numbering. The realizing mechanism may differ per resource
> (up-pointers, per-Group slot rebasing, MSE stored-global Formula-2 readback) but
> the property is uniform. (This is the positive operational form of D.11 for the
> numbering channel.)

### L.1 IMPORTANT distinction surfaced — two meanings of "cluster"

The cluster-mapping scenario must not conflate two unrelated uses of the word in
this project:

1. **Salvage "clusters"** (work-items.md, refamiliarize.md): editorial groupings
   of related open issues from a source review (Cluster D = MSE telescoping ✓
   resolved; Cluster F = MSE↔QoS isomorphism, **in progress**; Cluster G ✓). These
   are documentation-process artifacts, not a hardware topology.
2. **Hardware multi-hart topology**: multiple harts / cores / sockets and the
   memory+I/O fabric between them — the actual "cluster mapping" the design loop's
   stress battery means.

These are different axes. The stress test below is about meaning (2). But meaning
(1) is directly relevant because **"Cluster F" is an open charter item that
overlaps the design-loop core** (see L.3).

### L.2 Cluster (multi-hart) stress test result

Scenario: the same logical EC tree spread across multiple harts (SMT siblings,
cores, sockets), sharing DRAM and I/O fabric.

- *Identity across harts.* ECID is **hart-local** (ch00 §0.31: "an ECID has meaning
  only on the hart that issued it"); a context is `(hart, ecid)` (tenet 3, D.3).
  The same numeric ECID on two harts is two identities. So spreading a tree across
  harts does not alias identities — consistent, holds. The OS is responsible for
  any cross-hart correspondence (it owns the ECS), which fits migration-is-OS
  (scope boundary) and the ch05 ECS-keyed model (Part J finding 1).
- *Resource scope split — the crux.* CME/CPE resources are **per-hart** (banks,
  EC table, cache ways are hart/core-local). MSE memory bandwidth and QoS I/O
  bandwidth are **chip-global / fabric-wide** — admission is "atomic and
  chip-global" (ch00 §0.7.4, §0.2). So the tree's *identity and compute* resources
  are hart-local while its *bandwidth* resources are arbitrated across all harts at
  once. This split is the real content of the cluster scenario.
- *Does chip-global admission stay O(1)/bounded across many harts?* ch09 enforces
  the cap on **pre-flattened stored-global values** (§9.4.x) so a delegation/
  admission compares against a single stored-global sum, not a walk of every hart's
  tree — i.e. the chip-global check is a bounded arbitration, not an O(harts × N)
  scan. This is the mechanism that keeps D.16 intact at cluster scale. Holds **for
  MSE**.
- *QoS / I/O fabric — NOT yet resolved in the repo.* ch00 lines 502/506 state
  explicitly that the local-view principle for QoS and the CPE↔QoS formalization
  await **"cluster F resolution"**, and work-items.md lists Cluster F as current
  priority with **no code-prompt drafted yet**. So the I/O-fabric half of the
  cluster scenario rests on an item the architect has **not yet decided**. The
  design loop cannot validate it; it can only flag it.

### L.3 Finding — design-loop core depends on an open charter item (Cluster F)

The cluster scenario does not break the model, but it cannot be *completed* because
QoS chip-global behaviour across the I/O fabric is gated on Cluster F, which is an
open charter-level decision (architect's call, dedicated session). This is exactly
the kind of dependency the charter/lab firewall is meant to keep visible rather
than accidentally resolve in passing.

Per process rules (charter changes are their own session; design questions that
are the architect's call are presented, not resolved): the design loop **records**
that its cluster-scenario closure is blocked on Cluster F and does **not** attempt
to settle QoS fabric semantics here. Two clean options for the architect, for a
future session — not to be chosen now:
- (a) Resolve Cluster F first in its own charter session, then complete the
  design-loop cluster scenario against the result; or
- (b) Have the design loop produce a *recommendation* for QoS fabric local-view (by
  analogy to the MSE stored-global mechanism, which already works and is the
  natural template), to feed the Cluster F charter session as input — explicitly
  as a proposal, not a decision.

The MSE stored-global / Formula-2 mechanism is the obvious template for (b): QoS
I/O bandwidth is structurally the same problem as MSE memory bandwidth (a divisible
fabric-wide resource), and D.19 + D.20 already describe the shape the solution must
take. But which path, and the actual QoS semantics, are the architect's to decide.

### L.4 Process flags surfaced (not acted on)

- **`.md` vs `.adoc` dual tree — RESOLVED (round two).** The `.md` tree is
  authoritative; the `.adoc` tree is generated via `make adoc` (in-repo Makefile)
  and is purely downstream. No reconciliation is ever needed; ignore `.adoc`. This
  session (and all loop work) read the authoritative `.md` tree.
- **No work-item numbers asserted.** work-items.md was read only for the Cluster F
  status; no new item numbers are claimed here.

**Status of criterion 4:** OS-mapping (Part J), L0–L3 nesting (Part K), and
cluster/multi-hart (this part) slices exercised. The model survives all three for
the resolved resource classes (CME, CPE, MSE). The cluster scenario is **blocked
from full closure** on the open Cluster F charter item (QoS I/O fabric). Criterion
4 cannot be declared complete — and therefore criterion 5 (two zero-change passes →
freeze) cannot begin — until Cluster F is resolved or an explicit decision is made
to scope QoS-fabric out of the core freeze. *(Resolved — see Part L.5 immediately
below. The scope-out decision was made; criterion 4 is complete. Reaffirmed round
three.)*

---

## Part L.5 — Round-one-close scoping decision: QoS I/O-fabric deferred out of the core freeze (reaffirmed round three)

*This section records the round-one-close decision, reaffirmed by the architect
in round three. The v0.25 charter edit (§4.5.7, QoS local-view readback) stands
and is correct; it is a head start on the downstream QoS work captured here, not
part of the design loop.*

### L.5.1 Authoritative tree (resolves L.4)

The architect confirms: **`docs/chapters/*.md` (chapters + appendices) are
leading.** The `docs/adoc/` tree is *generated* from the `.md` files via a
Makefile; the reference and submission directories are likewise derived. The
design loop and the eventual rewrite operate on the `.md` chapters/appendices
only; generated trees are never edited directly and need no separate
reconciliation. L.4's dual-tree flag is closed.

### L.5.2 QoS I/O-fabric scoped OUT of the core freeze (architect decision)

The architect decides to **explicitly scope the QoS I/O-fabric semantics out of
the core design-loop freeze.** Rationale and sequencing:

- The core is frozen first on what is coherent and proven: identity (tenets/D.1–
  D.8), ownership and delegation (D.4–D.9, D.13–D.15), the hart-local resource
  model, uniform rebasing/local-view (D.20), and the two divisible-resource
  mechanisms already validated — CME/CPE (per-hart) and MSE (chip-global, bounded
  via stored-global pre-flattening).
- QoS I/O-fabric (the Cluster F problem) is **downstream work that consumes the
  frozen core**, not part of it. It is structurally the same divisible-fabric
  problem as MSE and will follow the MSE stored-global / Formula-2 template, but it
  is not required for core coherence.
- **Sequencing:** (1) finish stabilizing the core; (2) use the stabilized core to
  rewrite the charter; (3) *then* resolve QoS I/O-fabric (Cluster F) against the
  rewritten charter. QoS fabric is therefore a post-rewrite activity.

### L.5.3 Effect on the exit criteria

This unblocks criterion 4. Restated core scope for criteria 4–5:

- **In scope for the freeze:** CME (identity, banks, delegation, destruction),
  CPE (cache ways, per-hart), MSE (memory bandwidth, chip-global), and all the
  cross-cutting invariants D.1–D.20.
- **Out of scope for the freeze (deferred to post-rewrite):** QoS I/O-fabric
  chip-global / local-view semantics (Cluster F). The core must remain *compatible
  with* a future QoS-fabric mechanism (D.19/D.20 describe the shape it must take),
  but the freeze does not depend on its resolution.

With QoS-fabric scoped out, the three stress slices (Parts J, K, L) cover the
entire frozen-core surface, and the model survives all three. **Criterion 4 is now
complete** for the scoped core. Two items remain genuinely open inside the scoped
core and must be resolved before the zero-change passes (criterion 5) can run
clean:

1. **Generations** (parked for next round, F.1/Part J) — affects ch00/ch03/
   ch07/09/11/A. Until decided, the EC-entry layout and `ec.ir`/`ec.oe` semantics
   are not final, so a zero-change pass cannot yet be claimed.
2. **Allocator policy F.4(a)** — hardware vs software slot selection; minor, but
   touches Appendix A's allocator and the namespace realization.

### L.5.4 Path to freeze (criterion 5)

Criterion 5 (two consecutive red-team passes with zero changes to tenets/
invariants → architect declares freeze with a version bump) can begin once the two
open in-scope items above are resolved. Order suggested, architect's call:
- Next round: settle generations (the sharpened interrupt-teardown question, Part
  J) — this is the larger of the two and gates the EC-entry layout.
- Then settle allocator policy F.4(a).
- Then run pass 1 and pass 2 of the red-team battery (Parts J/K/L scenarios re-run
  against the then-current tenets/invariants) over the scoped core.
- On two clean passes, the architect freezes and the charter rewrite begins; QoS
  I/O-fabric (Cluster F) follows the rewrite.

**Round status at this capture:** criteria 1–3 complete; criterion 4 complete for
the scoped core (QoS-fabric deferred); criterion 5 pending two in-scope
resolutions (generations, allocator policy). The logical nucleus is coherent and
has survived OS-mapping, deep nesting, and multi-hart stress within its scope.

---

## Part M — ROUND TWO opening: reconciliation against repo at charter v0.24

Round two opened by reloading the repo (tarball, charter **v0.24** — was v0.15 at
round-one close). Before any new design work, this part reconciles round-one
findings against what the repo has done in v0.16–v0.24. **The repo has advanced
substantially on several round-one open items, in some cases independently
reaching the same conclusions this loop did, and generalizing further.** Verified
against the v0.24 charter changelog and §5.4/§6.9, and ch00.

### M.1 Self-Preservation Invariant (charter v0.23/v0.24) — repo has formalized,
and generalized, the reachability/non-delegable-self idea from round one.

Round one (Part D scope note, tenet 7) established: an ECID holding children
cannot give away *itself*, so subtrees stay reachable. The repo v0.23 added a
**normative Self-Preservation Invariant (§5.4)** that is broader: *a non-leaf EC
must retain enough of each resource type to remain operational; no EC may delegate
all of any one resource type to its children* — at every level including L = 0.

Reconciliation:
- This **supersedes and generalizes** the round-one reachability note. Round one
  was about identity reachability (don't orphan the subtree); §5.4 is about
  operational viability (don't strip yourself of banks/contracts you need to run).
  Both are the same instinct — "you can't delegate yourself into nonexistence" —
  with the repo's version covering resources, not just identity.
- The CME enforcement mechanism (**§6.9 Bank-0-unnamed local numbering**: each EC's
  local non-VMT Bank 0 is not nameable for delegation) **is a concrete instance of
  the rebasing rule decided this round** (Part L.0 / candidate D.20). Each EC sees
  its banks in a local namespace starting at local Bank 0, and local Bank 0 is
  structurally retained. So D.20 is not just consistent with the repo — the repo's
  newest normative mechanism *depends* on per-level local bank numbering. This
  strengthens D.20 from "candidate" toward "already load-bearing in the spec."
- **MSE/CPE/QoS carry no architectural floor** (§5.4): self-preservation for
  contracts is software's responsibility, not hardware-enforced. This matches the
  round-one scope note exactly ("arranging a workable situation is the
  programmer's responsibility"; CE only guarantees the structural reachability
  floor). The repo draws the same hardware/software line this loop did.

**Action for the lab:** retire the round-one reachability scope note as
*subsumed by charter §5.4*, and promote D.20 (rebasing/local-view) to reflect that
§6.9 now depends on it. No conflict; the repo moved the loop's direction.

### M.2 `ec.it` is now count-based, not bank-specifier (v0.23 breaking change).

Round-one Part I classified `ec.it` as "delegate one bank to a child (one bank per
call)." **This is now stale.** Under v0.23/v0.24, `ec.it` takes `rs1` = *count* of
non-VMT banks to delegate (hardware picks the highest-numbered local banks, never
local Bank 0); `rd` returns banks remaining; `rs1 = 0` is a no-op; over-range
(`count ≥ K`) traps; VMT banks exempt. `ec.it` joined the success-path-`rd` family.

Reconciliation:
- The Part-I **cost tier is unchanged** (still O(1)/small-cycle banked-tier
  management; delegating N banks is still bounded). D.16 holds.
- The **"hardware picks the bank, not the caller"** property (round-one E.2, the
  no-raw-numbers basis for dropping generations) is now **directly confirmed and
  strengthened** by the repo: hardware chooses *which* banks (highest-numbered
  local), caller only supplies a count. This is repo precedent for the E.2
  allocation philosophy.
- **Lab edit:** correct Part I's `ec.it` line to the count model.

### M.3 Cluster F — STILL the blocker; round-one Part L.3 stands. *(Superseded round three — see Part L.5 and Round Three stamp above.)*

ch00 lines 502/506 are **unchanged** ("the cluster F resolution will formalize
this for QoS"; "when cluster F resolves, QoS will apply the same local-view
principle"). work-items.md still lists Cluster F as current priority, framing
complete, **charter session pending, no code-prompt drafted**. So the round-one
criterion-4 blocker (QoS I/O-fabric local-view undefined) is **not resolved**. The
round-two pickup order from the close stamp holds: Cluster F goes first.

Note (stale-state catch): work-items.md's priority header lists "Cluster F, then
Self-Preservation, then PUB5", but the changelog shows **Self-Preservation already
landed (v0.23/v0.24)**. The work-items priority *header* is stale relative to the
charter changelog. Flag for the architect — not fixed here (work-items is the
architect's tracking doc; editing it is not a design-loop action).

### M.4 MSE local-view (v0.22) confirms the D.20 template for Cluster F.

v0.22 made MSE telescoping fully local-view: software at every level reads
bandwidth on its own 0–255 local scale (`mse_absolute_bw`), hardware converts
stored-global↔local at read time (`floor(stored_global × 256 / parent_stored_global)`).
This is exactly the mechanism round-one Part L.3 proposed as the **template for
resolving QoS fabric local-view** (option b). The repo has now fully normatively
specified it for MSE — so a QoS-fabric recommendation can point to a *shipped,
normative* mechanism, not a sketch. This materially de-risks the Cluster F
recommendation path.

### M.5 Round-two readiness

Reconciliation complete. Net effect of v0.16–v0.24 on the loop: **favorable** —
the repo independently validated the reachability instinct (§5.4), confirmed the
hardware-picks-banks philosophy (`ec.it` count model), and shipped the exact MSE
local-view mechanism that templates the Cluster F fix. Three lab edits implied
(M.1 retire/promote, M.2 `ec.it` correction; both lab-doc, not charter). The
blocker is unchanged: **Cluster F**. Round two proceeds there. *(Superseded
round three: criterion 4 complete on scope-out basis; v0.25 charter §4.5.7 is a
downstream head-start, not loop work; criterion 5 is next.)*

---

## Part N — ROUND TWO: generations question settled (read ch18)

Read ch18 (CLIC integration) end-to-end for the ISR-ECID teardown sequence — the
thing the parked generations question turned on (Part J). Finding, then the
resolution.

### N.1 What ch18 actually specifies

- ISR ECIDs are **permanent**: allocated once at boot via `ec.ir`, stored in a
  per-hart, per-vector `isr_ecid_slot` table (§18.3 lines 64–95). Not created or
  destroyed per interrupt. The slot table holds the **bare ECID number**, read on
  each delivery (prologue line 147).
- Registration is fully specified (§18.3): `ec.ir` → `sh a0, isr_ecid_slot`.
- Linux mapping (§18.10): allocate on `request_irq`, **release on `free_irq`** —
  but ch18 explicitly calls this "a **software convention, not an architectural
  requirement**" (line 357).

### N.2 The decisive gap

**ch18 does NOT specify a deregistration/teardown sequence at all.** There is no
architectural statement that, on freeing an ISR ECID, the `isr_ecid_slot` routing
entry is cleared or the interrupt source masked, nor any ordering of those against
slot reuse. The teardown is left entirely to software convention (`free_irq`).

This means the round-one framing ("can teardown guarantee mask+clear before
reuse?") has no answer *in the current spec* — because the spec doesn't define the
teardown. So the question is not "does the hardware do X" but "**what must the
teardown be required to do**" — which is a design-loop decision, now decidable.

### N.3 Resolution

The hazard (Part J/K) is: free an ISR ECID → slot reused → a late/spurious
interrupt on the old vector routes via a stale `isr_ecid_slot` entry to the new
occupant (misdelivery across a trust boundary; not code injection — vector table
governs which code runs, and D.14 scrub clears register state).

Two ways to close it, and they are not mutually exclusive:

- **(i) Mandate the teardown order architecturally.** Promote the `free_irq`
  convention to a required sequence: to free an ISR ECID, hardware/privileged
  software must, atomically before the slot can return to the free list:
  (1) mask the interrupt source, (2) clear the `isr_ecid_slot` routing entry, then
  (3) free the ECID. This is the design-loop's D.13 (complete synchronous teardown,
  no lazy reuse) applied to the interrupt route as just another inbound reference
  that must be resolved before FREE. If mandated, **no stale route can fire, and
  generations are not needed for this hazard.**
- **(ii) Keep generations as a backstop.** If the teardown order cannot be
  guaranteed atomic on all implementations (e.g. an in-flight interrupt already
  latched in the fabric before masking takes effect), the generation check on
  delivery catches the misroute. But note the 8-bit wrap (Appendix A) — a weak
  backstop.

**Design-loop recommendation (for the architect):** adopt (i) as a normative
teardown requirement — it is the natural and consistent extension of D.13, and it
makes the interrupt route a first-class inbound reference subject to the same
"resolve before FREE" rule already applied to banks, contracts, and child ECIDs.
With (i) in place, **generations become removable for the ISR hazard** — the last
concrete reason this loop found to keep them.

**Residual caveat the architect must weigh (the one thing (i) may not cover):** an
interrupt already *latched in the fabric* before the mask takes effect. If such a
race is possible on a given implementation, either (a) the mask must be defined to
also flush/discard already-latched-but-undelivered interrupts for that vector
before teardown proceeds, or (b) generations stay as the catch for that narrow
window. Whether the fabric can guarantee (a) is an **implementation/microarch
question** (ch04 / ch18 territory), not a pure logical-core question — so it is the
boundary of what the design loop can settle. The loop's position: *if* the mask
can be made to cover latched interrupts, generations are fully removable; *if not*,
generations survive solely as the latched-interrupt backstop and nothing else.

### N.4 Status of the generations question

Moved from "parked, unframed" to "**decidable, one residual microarch question**."
The loop recommends: mandate the (i) teardown order (D.13 applied to interrupt
routes); then generations are removable **unless** the fabric can latch an
interrupt that survives the mask, in which case they persist only as that narrow
backstop. Next concrete step (round three or a microarch pass): confirm against
ch04/ch18 whether interrupt masking can be defined to discard already-latched
interrupts for a vector. That single fact decides generations entirely.

This does not require generations to be removed now; it converts a vague worry into
a precise, bounded, answerable question — which is the design loop's job.

---

## Part O — ROUND TWO: SMT settled (isolation-by-default framing)

Architect's framing decision (this session): **SMT siblings are fully independent
harts that happen to share silicon — isolation is the default, sharing is the
exception.** This resolves the round-one SMT open item (E.3), and it resolves it
by making SMT a non-issue at the logical-core level. Verified against the repo.

### O.1 The repo already takes this position

- charter glossary: "**Hart** — Standard RISC-V hardware thread. CE state is
  **per-hart**." A hardware thread *is* a hart, full stop. An SMT core presents
  multiple harts; each is independent.
- ch00: ECID is "hart-local"; system identity is `(hart_id, ECID)`; "an ECID has
  meaning only on the hart that issued it"; `EC[]` table base is a **per-hart CSR**.
- **The repo says "SMT" / "hyperthread" / "sibling-hart" nowhere** in any chapter
  or the charter. Under the isolation-by-default framing this is *correct*, not a
  gap: there is nothing SMT-specific to say, because CE state is defined per-hart
  and a hyperthread is just a hart.

### O.2 Consequence: the round-one SMT worries dissolve

Round one (E.3, Part K profile-note, Part L.2) raised three SMT concerns under the
assumption that siblings *share* the EC table. Under isolation-by-default, each
hart has its **own** `EC[]` table (the table base is already a per-hart CSR,
ch00), so:

- *Allocation collision between siblings* — gone. Separate tables, separate free
  lists; no shared rightmost-free hazard.
- *One sibling reading/evicting the other's EC entries* — gone at the architectural
  level. Different `(hart_id, ·)` identity space; an ECID on hart A is simply not
  the same identity as the same number on hart B (ch00 hart-local rule, D.3).
- *Cross-sibling shootdown on `ec.oe`* (Part K) — reduces to the **already-specified**
  cross-hart preemption (Appendix A §A.5.2 "active-hart preemption": if the target
  is current on a remote hart, interrupt and switch it away). SMT siblings are just
  "remote harts" that share a core; no new mechanism. The cost is the existing
  cross-hart-IPI cost, which a realtime profile already must bound.

### O.3 What remains — and it is NOT a logical-core concern

The only genuine SMT question left is **physical resource sharing**, which the
isolation-by-default framing deliberately pushes below the logical model:

- SMT siblings share physical caches, TLBs, and memory bandwidth (that is what SMT
  *is*). So two ECIDs on two sibling harts can contend for, and side-channel
  through, shared microarchitectural state — the L1TF/MDS family (round-one Part J,
  vCPU note).
- CE's logical model does not and should not try to prevent this; it is a
  **microarchitecture + profile** matter. CE's contribution is what it already
  provides: CPE (cache partitioning) and MSE/QoS (bandwidth contracts) give
  software the *tools* to partition the shared physical resources between siblings
  when isolation matters; and the hypervisor's **core-scheduling** policy (only
  co-reside confidentiality-compatible subtrees on sibling harts) is an OS policy
  CE must leave expressible but does not itself enforce.

This is exactly the hardware/software line the loop has drawn throughout: CE
guarantees the logical invariants per-hart and supplies partitioning tools;
arranging physical isolation between siblings is the implementer's/OS's job.

### O.4 Status

SMT settled at the logical-core level: **no SMT-specific logical mechanism is
needed**, because a hyperthread is a hart and CE state is per-hart (repo-consistent).
The residual (physical cache/TLB/bandwidth sharing and its side channels) is
explicitly **out of the logical core** — a microarch/profile/OS-policy matter for
which CE already supplies CPE/MSE/QoS as tools. Round-one E.3 and the Part K/L.2
SMT notes are superseded by this part. No invariant change required; D.3
(hart-local identity) already carries it.

---

## Part P — ROUND TWO: two small items closed (allocator policy F.4a; D.20 promotion)

### P.1 Allocator policy (F.4a) — RESOLVED: hardware picks the slot, derives the level

Read ch03 §3.5 (`ec.ir`). The spec is unambiguous:
- `ec.ir rd, rs1` returns the **new child ECID number in `rd`** — i.e. **hardware
  selects the slot**, software does not supply or request a specific ECID. `rs1`
  carries only the leaf/delegating flag (0 = leaf at L=D; 1 = delegating at
  parent_L+1; >1 reserved/illegal).
- Explicit spec note: "The child's delegation level is always **hardware-derived**
  from the parent's level and the leaf flag. **Software cannot request an arbitrary
  `L` value.**"
- Software's only post-allocation role is writing `ecs_ptr` and ECS fields, which
  "are **not instruction operands**" — i.e. metadata, not slot selection.

This confirms the round-one E.2 philosophy ("hardware picks the slot, the caller
never supplies a raw slot number") **as already-normative repo behavior**, and it
aligns with the v0.23 `ec.it` count-model (M.2: hardware picks *which* banks too).
So F.4a(a) — "is selection policy hardware or software?" — is answered: **hardware**.
The kernel manages the radix-tree *bookkeeping* (free lists, prefix nodes per
Appendix A), but the *act of selecting and returning a specific slot* on `ec.ir` is
the hardware instruction's job. No divergence; the lab's E.2 matches the spec.

Remaining nuance (not a blocker): Appendix A's allocator algorithms run in
"the implementation" but are described in kernel-software terms (free-list pop).
The clean statement for the rewrite: *`ec.ir` is a hardware instruction that
selects a slot from the calling context's prefix and returns its (rebased per
D.20) number; the radix-tree structure it draws from is maintained by privileged
software.* This is a wording reconciliation, not a design choice. F.4a closed.

### P.2 D.20 (rebasing / local view) — PROMOTED from candidate to load-bearing

Per M.1, charter v0.23 §6.9 (Bank-0-unnamed local numbering) is a normative
mechanism that **depends on** per-level local bank numbering — i.e. it depends on
D.20. Combined with: ch03 §3.1 (bank slot index 0-based within the owning Group),
ch09 §9.4.6 + charter §4.5.0 (MSE local-view), and the approved QoS local-view
recommendation (Part M/recommendation doc), the rebasing property is now realized
across CME banks, MSE, and (pending charter) QoS. D.20 is therefore promoted:

> **D.20 (rebasing / local view) — LOAD-BEARING.** Every delegation level observes
> its delegated resources — ECID ranges, VMT banks, non-VMT banks, and contract
> scales (MSE/QoS bandwidth, CPE ways) — rebased into its own local namespace
> beginning at a local base, and cannot observe the parent/physical numbering. The
> realizing mechanism differs per resource (radix-prefix rebasing for ECIDs,
> per-Group slot rebasing for banks, stored-global↔local Formula conversion for
> MSE/QoS) but the property is uniform and is depended upon by the Self-Preservation
> mechanism (charter §6.9). This is the positive operational form of D.11 for the
> numbering channel.

The invariant list is now D.1–D.20, all confirmed. (D.17–D.19 from round one;
D.20 here.)

### P.3 Round-two queue status after P

- Cluster F / QoS local-view: recommendation drafted + MSE-machinery approved by
  architect; **awaits architect's charter session** to make normative.
- Generations: reduced to one microarch question (Part N); recommendation =
  mandate teardown order, then removable barring the latched-interrupt window.
- SMT: settled, no logical work (Part O).
- Allocator policy F.4a: **closed** (P.1, hardware-picks confirmed).
- D.20: **promoted to load-bearing** (P.2); invariant list complete at D.1–D.20.
- `.md` vs `.adoc` authoritative tree: still the architect's repo-hygiene call,
  untouched by the loop.

**Gate to criterion 5 (freeze):** the only remaining *design-loop* blocker is
Cluster F's QoS half (criterion-4 cluster scenario, Part L.3), which is now in the
architect's hands via the recommendation. Once Cluster F is made normative and the
generations microarch question is answered, criterion 4 closes and the two
zero-change passes of criterion 5 can begin. *(Superseded round three: criterion 4
is complete on the scope-out basis — QoS scoped out of the loop per Part L.5,
generations resolved per Part Q; criterion 5 is in progress. See the Round Three
stamp above.)*

---

## Part Q — ROUND TWO: teardown rule + generations-removal DECIDED (with ch18 verification)

Two architect decisions this session, recorded together because the second rests
on the first: (1) CE's ISR-ECID teardown **requires clearing the pending bit**, not
just masking; (2) with that rule, generation counters are **removed**. Verified
against ch18 to the extent the repo specifies, with one boundary noted honestly.

### Q.0 Terminology fixed (for future reference in this capture)

- **Mask / enable bit:** a per-source bit in the interrupt controller meaning "am I
  allowed to deliver interrupts from this source." Clearing it stops *future*
  delivery.
- **Pending bit:** a per-source latch (a held flag) meaning "an interrupt from this
  source has fired and is remembered, waiting to be delivered." Set when the source
  fires; stays set until serviced or explicitly written to 0. "Latched in the
  fabric" = this bit is set and held.
- The two are **separate bits.** Masking does not by itself clear pending. A
  pending interrupt set *before* masking can still be delivered later. This gap is
  the entire reason generations existed as a backstop.

### Q.1 What ch18 verifies, and the boundary

- ch18 §18.0: "**CLIC itself has no CE-specific hardware hooks**"; "**No new
  instructions, CSRs, or hardware mechanisms are required.**" CE rides on the
  *base RISC-V CLIC*; the bank swap is software in prologue/epilogue.
- Consequence: the pending bit and its clearing are **base-CLIC functionality**,
  not a CE invention. The RISC-V CLIC (and PLIC/AIA) architecturally expose
  per-source pending bits that privileged software can read and write/clear
  (`clicintip`-class state in CLIC; equivalent in PLIC/AIA). Clearing a pending bit
  is an ordinary, standard operation — not new silicon.
- **Boundary (honest):** ch18 does not itself restate base-CLIC pending-bit
  semantics, and this capture has not quoted the base CLIC spec line-for-line. The
  claim "the CLIC exposes writable pending bits" is standard RISC-V CLIC behavior
  and is the basis CE already builds on per §18.0, but the rewrite/charter session
  should cite the exact base-CLIC pending-clear mechanism when it makes the teardown
  rule normative. Treated here as: **standard capability CE already assumes**, not a
  new requirement on silicon.

### Q.2 DECISION 1 — Teardown rule (normative, to be written in the rewrite)

To free an ISR ECID (deregister an interrupt handler), privileged software MUST
perform, in order, before the ECID slot can return to the free list:

1. **Clear the mask/enable bit** for the source — stop new deliveries.
2. **Clear the pending bit** for the source — discard any already-latched interrupt.
3. **Clear the `isr_ecid_slot` routing entry** for the vector.
4. **Free the ECID** (return the slot to the free list).

This is invariant **D.13 (complete synchronous teardown, no lazy reuse) applied to
the interrupt route**: the routing entry and any latched interrupt are inbound
references that MUST be resolved before FREE, exactly as banks, contracts, and child
ECIDs already are. Step 2 is the step that closes the latched-interrupt window that
generations previously backstopped. Cost: a few register writes at teardown only —
teardown is rare (handlers set up at boot, torn down almost never), so this adds no
per-operation or fast-path cost.

### Q.3 DECISION 2 — Generations removed

With Decision 1 in force, no stray interrupt can survive teardown to reach a reused
slot, and the forging/ordering hazards were already closed (round-one E.1/E.2:
hardware picks the slot, caller supplies no raw number, non-lazy synchronous
teardown). Therefore the generation counter has **no remaining hazard to defend**
and is removed.

**Complexity note (the architect's stated concern, addressed):** removal *reduces*
running complexity. Generations are an always-on cost — a counter field in every
`EC[e]` slot, an increment on every `ec.ir`/`ec.oe`, and a third element in every
`(hart, ecid, generation)` reference. Decision 1 replaces that with a few writes at
the *rare* teardown moment. Complexity moves from constant/per-operation to
rare/per-teardown, and the slot shrinks and the reference triple collapses to
`(hart, ecid)`. Net: less total complexity.

**One-time cost (honest):** removal is cheap at *runtime* but is a real *edit*
job. The `(hart, ecid, generation)` triple and the generation field are woven
through ch00 (§0.2/§0.3/§0.8), ch03 (§3.5 `ec.ir`, §3.6 `ec.oe` — both currently
"increment the generation counter"), ch07/09/11 (error tables: generation-mismatch
codes), ch05 (the software handle), and Appendix A (§A.1 struct field, §A.2 reuse
rule, §A.3.2 allocator `+= 1` ABA guard). This is the propagation surface from
F.1. Enacting removal is a charter-level change → dedicated session, version bump,
changelog, then per-chapter code-Claude sessions each with a propagation check.

### Q.4 Status — generations question CLOSED

Round-one parked item resolved. Both the teardown rule and generations removal are
decided. The only residual is documentary: the charter session that enacts removal
should cite the exact base-CLIC pending-clear mechanism (Q.1 boundary) when writing
Decision 1 normative. The lab's round-one E.1 ("generations removed") is now a
*confirmed architect decision*, not an exploration — capture E.1/F.1 should be read
in light of this Part Q.

Lab/capture reconciliation: E.1 and F.1, previously reframed as "parked," are now
**decided (removed)** per this Part Q. The teardown rule (Decision 1) is new and is
the enabling mechanism that was missing when the question was first parked.
