# The CE Logical Core — A Plain-Language Design Document

*A complete, jargon-explained description of the Context Engine (CE) logical core
as settled in the design loop. Written for a reader who has not seen the
specification. Every technical term is introduced before it is used. Nothing in
the underlying design has been simplified away — only the wording is plain.*

*Status: this describes the converged logical core. The design loop's five exit
criteria are met; the set below includes the divisibility principle as a tenet
(the final deliberate addition). It is a synthesis for reading and sharing, not the
normative specification itself — the specification (charter and chapters) is being
rewritten from this core.*

---

## 1. What CE is, and what this document covers

**CE (Context Engine)** is a hardware feature for a CPU. Its job is to let many
independent "execution contexts" — think of them as isolated workloads: an
operating system, the virtual machines it hosts, the programs inside those, and so
on — share one processor safely, each owning a slice of the machine's resources,
without any one of them being able to see or steal another's.

CE is built as a small set of CPU instructions and a few hardware tables. The
hard part is not the instructions; it is getting the **logical model** exactly
right — what an identity *is*, who can own what, who can hand resources to whom,
and what a workload is allowed to observe. If that model is even slightly wrong,
every document describing the chip has to be rewritten when it is fixed. So the
model was settled first, on its own, in a "laboratory" separate from the formal
specification. That separation — settle the logic in the lab, then port finished
results into the specification as deliberate decisions — is called **the firewall**.
This document is the plain-language output of that lab work.

The design is expressed as two layers:

- **Tenets** — a short list of non-negotiable principles. Changing one is a
  deliberate, dated act.
- **Invariants** — concrete rules that every operation must keep true and every
  hardware configuration must satisfy. They are the tenets made precise and
  operational.

Sections 4 and 5 give all of them in plain language. First, the vocabulary and the
model.

---

## 2. Vocabulary (every term used later)

- **Hart** — one hardware execution thread: the smallest thing the CPU schedules.
  A simple core is one hart. A core with "simultaneous multithreading" (SMT) — two
  threads sharing one core's silicon — is **two harts**. CE treats each hart as
  independent.
- **Execution context** — an isolated workload (an OS, a virtual machine, a
  program). It is a software idea; CE gives it a hardware identity and the tools to
  own resources.
- **ECID (Execution Context IDentifier)** — the hardware **identity** of a context.
  It is a small number that indexes a per-hart hardware table. It is *not* a memory
  pointer — you cannot use it to reach into memory; it only names a slot. The same
  ECID number on a different hart is a completely different identity.
- **EC table / EC entry** — the per-hart hardware table of context slots. Each
  entry holds the fast-to-access state for one context (including a pointer back to
  its parent). The information needed for a fast context switch lives here.
- **ECS (Execution Context Structure)** — *optional* extra metadata that an
  operating system may attach to a context (for its own bookkeeping). A context can
  exist and own resources with **no ECS**. But it cannot actually be *run* until an
  ECS is attached. An ECS can also exist with no ECID, purely as a software object.
- **Bank** — a unit of saved register/working state that belongs to a context. A
  Bank is an **exclusive** resource: it is owned whole, by exactly one context.
- **Group** — the set of everything one context owns (its Banks, its Contracts, its
  child contexts). "Group" is an abstract idea; in hardware it is realized only by
  the **up-pointers** that owned things carry back to their owner. A Group's ID is
  simply the owner's ECID.
- **Up-pointer** — a link from an owned object back to its owner. Ownership is
  always represented *upward*. Up-pointers are the single source of truth about who
  owns what.
- **Contract** — a reserved slice of a **divisible** resource. Where a Bank is owned
  whole, a Contract is a guaranteed *share* of something that can be split — memory
  bandwidth, cache space, I/O bandwidth. Many contexts can each hold a
  non-overlapping Contract carved from the same underlying resource.
- **Exclusive vs divisible resource** — an **exclusive** resource (a Bank, a child
  identity) is owned whole by one owner. A **divisible** resource (bandwidth, cache)
  is split into non-overlapping slices, each slice (a Contract) owned exclusively by
  its holder. This distinction is fundamental and is now a tenet (section 4).
- **Delegation** — handing some of your resources to a **child** context you create.
  A context can carve off Banks and Contracts and give them to children, which can
  delegate further, forming a tree.
- **Delegation tree / level / L0–L3** — the parent–child structure. The **root** is
  the top context on a hart (its level is **L0**). Each child is one level deeper
  (L1, L2, …). CE bounds the depth at a small number, **D** (typically D = 3), so the
  tree is always shallow.
- **Root** — the top context of a hart's tree. Its "parent" is itself — a deliberate
  self-reference used only as the stopping point when walking up the tree. It is a
  sentinel, not a real delegation.
- **VMT (and VMT vs non-VMT Banks)** — VMT Banks are a special class of Bank tied to
  virtual-machine memory translation. The model treats VMT and non-VMT Banks
  alike for ownership and numbering; the distinction matters only to specific
  hardware features.
- **Local view / rebasing** — the principle that each context sees its own resources
  numbered *from its own zero*, as if it were the only thing in existence. It cannot
  see the parent's or the physical numbering. Software written for one position in
  the tree runs unchanged at any other position, because everything is presented in
  its own local terms.
- **Stored-global value** — the true, machine-wide value a piece of hardware keeps
  internally (for example, the absolute size of a bandwidth share). Software never
  sees this directly.
- **Formula 2** — the conversion hardware applies, at the moment software reads a
  value, to turn a stored-global value into the reader's **local view**. Concretely,
  a child reading its bandwidth share gets `floor(child_share × 256 ÷ parent_share)`
  — its share as a fraction (on a 0–255 scale) of its parent's share. The child sees
  only this fraction; it never sees the underlying stored-global numbers, so it
  cannot work out the parent's absolute amount or anything machine-wide.
- **Telescoping** — composing local views across several delegation levels at once
  (a multi-level version of the local-view conversion). Used by memory bandwidth;
  deliberately *not* used for I/O bandwidth in the first version (see section 6).
- **Pinned** — a context is "pinned" when it holds a live arrangement that cannot be
  saved as plain bytes (see tenet 10), so it cannot be moved without loss.
- **The four extensions** — CE has four optional capability areas:
  - **CME** — the core context-management feature: identities, Banks, delegation,
    destruction. Always present.
  - **CPE** — cache partitioning: dividing cache space among contexts. Per-core.
  - **MSE** — memory-bandwidth scheduling: dividing memory bandwidth. Machine-wide.
  - **QoS** — I/O-bandwidth quality-of-service: dividing I/O and interconnect
    bandwidth. Machine-wide. (Its details are deferred — section 6.)
- **The operations** — CE has 24 instructions. Their names follow a pattern: a
  two-letter prefix for the area (`ec` = CME, `cp` = CPE, `ms` = MSE, `qs` = QoS) and
  a short suffix for the action. Section 7 lists what they cost; the ones referenced
  by name below are: `ec.ib`/`ec.ob` (save/restore a context — the actual context
  switch), `ec.ir` (create a child), `ec.it` (delegate a Bank), `ec.ot` (revoke from
  a child), `ec.oe` (force-destroy a context and everything under it), `ec.im`/
  `ec.om` (spill/fill a Bank to and from memory), and `ec.iv`/`ec.ov` (seal/unseal a
  Bank under encryption — the "vault").

---

## 3. The model in one picture

Put together, the model is:

A **hart** runs one context at a time, identified by its **ECID**. Each context is
a node in a **tree**: the **root** (L0) is the top; it creates **children**, which
create grandchildren, down to a small fixed depth. Each context owns a **Group** of
things — **Banks** (whole, exclusive units of state), **Contracts** (non-overlapping
slices of divisible resources like bandwidth and cache), and its **child contexts**.
Ownership is recorded by **up-pointers** from each owned thing to its owner; those
up-pointers are the only truth about ownership.

A parent **delegates** resources downward to children, but in doing so it never lets
a child see anything beyond the child's own slice: every child gets a **local view**,
numbered from its own zero, with the machine-wide reality hidden behind hardware
conversion. A child cannot name, observe, or infer anything about its parent,
siblings, or the machine as a whole — and it cannot turn any partial guess into
authority it was not given.

Identity, compute, and per-core resources (Banks, cache) are **per-hart**. Bandwidth
(memory and I/O) is **machine-wide**, arbitrated across all harts at once. Cleaning
up is strict and complete: a slot is freed only after everything under it is fully
torn down and scrubbed, so a reused slot never carries a previous owner's leftovers.

The rest of the document makes each of these claims precise.

---

## 4. The tenets (the non-negotiable principles)

These are the fixed principles the whole design answers to. They are grouped here by
theme; the numbering is the design's own.

**Identity**

1. An **ECID is an identity, not a pointer.** It names a slot in the per-hart table
   and can never be used to reach into memory.
2. **Identity and metadata are separate things.** The ECID (identity) and the ECS
   (optional OS metadata) are distinct. A context can exist and own resources with no
   ECS; it just cannot be *run* until one is attached. An ECS can also exist with no
   ECID. The state needed for a fast context switch lives in the context's table
   entry, never hidden behind the ECS.
3. **Identity is tied to its hart.** A context is the pair *(hart, ECID)*. The same
   ECID number on another hart is a different identity, and an identity never moves
   between harts on its own.

**Ownership and the tree**

4. **Everything owned has exactly one owner, recorded upward.** Every Bank, Contract,
   and child has one owning Group (whose ID is the owner's ECID), realized by a single
   up-pointer to that owner.
5. **Up-pointers are the truth.** Any convenience list pointing "downward" is just an
   accelerator; if it ever disagrees with the up-pointers, the up-pointers win, and
   acting on the wrong one is made impossible.
6. **The ownership structure is a tree (acyclic), except the root points to itself.**
   Following up-pointers always leads up to the root and stops there; no context can
   become its own ancestor. The root's self-pointer is only a stopping marker, not a
   real link.
7. **One root per hart.** Each hart's tree has exactly one root (level 0, ECID 0)
   whose parent is itself. Every other context's parent sits strictly higher up.

**Divisible resources** *(the principle elevated to a tenet in the final step)*

12. **A resource is either owned whole or shared in non-overlapping slices.** Some
    resources are **exclusive** — owned entirely by one context (a Bank, a child
    identity). Others are **divisible** — bandwidth, cache — and are shared by carving
    them into **Contracts**: separate, non-overlapping slices, each one exclusively
    owned by its holder, the slices never adding up to more than the parent had. This
    split between "owned whole" and "shared in slices" is fundamental to how CME, CPE,
    and MSE (and, later, QoS) all work.

**Visibility and authority**

8. **A child sees only its own virtualized view.** It cannot observe or infer its
   host, its siblings, or the machine as a whole — and even a partial guess (for
   instance from timing) must never be convertible into authority it was not granted.
9. **Authority comes only from delegation.** You cannot gain authority over a
   resource by guessing, writing, or replaying an identifier — only by being handed it
   by someone who holds it.

**Movement and cost**

10. **Some state can be saved as bytes; some cannot.** A Bank's contents can be
    saved and restored (spilled and filled). But live arrangements with shared
    hardware — cache reservations, bandwidth Contracts, interrupt routing, timers,
    whether they are per-hart or machine-wide — have no byte form; they must be
    re-established wherever the context lands, and that may fail. State with no
    saveable form cannot be moved without loss. (A context holding such state is
    "pinned.")
11. **The fast path never scans.** The instructions on the time-critical path run in
    constant time; slower management operations may do bounded work, but nothing ever
    does an unbounded search on a time-critical path.

---

## 5. The invariants (the rules always kept true)

These are the tenets made precise: properties every operation must preserve and
every hardware configuration must satisfy. They are grouped as in the design. Each is
restated in plain language; the security ones also state *how* the hardware keeps
them true.

**Identity and structure**

- **D.1** Each hart has exactly one current context at any instant. SMT siblings are
  separate harts that may share the physical table and Bank storage but never share a
  "current context" pointer.
- **D.2** A context's identity slot and its optional metadata structure are different
  objects; neither is ever the other.
- **D.3** An instruction's operand never carries a raw physical slot number — software
  only ever sees numbers virtualized within its own Group. At the root (L0), the local
  numbering happens to coincide with the physical table.

**Ownership**

- **D.4** Every ownable thing (Bank, Contract, child) has exactly one owning Group,
  realized by a single up-pointer.
- **D.5** Nothing has two owners, and nothing live is unowned.
- **D.6** Ownership is recovered by following up-pointers; any disagreeing downward
  index yields to them.

**The delegation tree**

- **D.7** Exactly one root per hart, whose parent is itself; every other context's
  parent is strictly higher; no non-root context is its own ancestor; walking upward
  always terminates at the root's self-loop.
- **D.8** A child's level is its parent's level plus one, bounded by the maximum depth
  D; a context at the deepest level has no children.
- **D.9** Two contexts where neither is an ancestor of the other never both own the
  same *exclusive* thing. They *may* each own separate, non-overlapping slices of one
  *divisible* resource (bandwidth, cache), each slice exclusively its owner's.

**Authority and visibility** *(security rules — stated as prohibitions, each with the
mechanism that enforces it)*

- **D.10** Authority is never gained by guessing, writing, or replaying an
  identifier — only by delegation from a holder.
- **D.11** A child cannot observe or infer its host, siblings, or machine-wide
  topology — not via allocation results, not via operand values; and no partial guess
  can be escalated into authority.
  *How:* a child sees its resources only in its own local view. The operands it
  supplies and the allocation results it gets back are local-namespace numbers (a
  local index or a count), never a machine-wide slot number. When it reads a bandwidth
  share, hardware gives it a *fraction* (via Formula 2), computed from stored-global
  numbers — its own and its parent's — that the child never sees; so the child sees
  only the resulting fraction and cannot recover those numbers or any machine-wide
  total.
- **D.12** A context can name only resources within its own Group/subtree. It cannot
  name itself as something to delete, nor name its parent or siblings.
  *How:* operands are interpreted in the caller's own local namespace; names outside
  it either cannot be expressed at all, or, if expressible but out of range, cause a
  trap rather than reaching anything else; "self" is the reserved local base ("self =
  0") and simply is not a nameable target for delegation or deletion.

**Lifecycle (creation, destruction, cleanup)**

- **D.13** A slot returns to "free" only after a complete, synchronous teardown — all
  its children, Banks, Contracts, and inbound routes resolved. No lazy reuse.
  *How:* an inbound route is fully cleared before the slot frees. Interrupt routes
  follow a fixed order — clear the mask, clear the pending bit (discarding any latched
  interrupt), clear the routing entry, then free. I/O-bandwidth and timer routes
  follow the same "resolve before free" rule with their own steps (they have no
  mask/pending bits). And the force-destroy instruction (`ec.oe`) reclaims a whole
  subtree by walking up-pointers — revoking Contracts, freeing Banks, marking the
  subtree free — before any slot can be reused. With the scrub (next), no later owner
  ever sees an earlier owner's state.
- **D.14** On freeing or before reuse, a resource's contents are scrubbed (by whatever
  bulk hardware mechanism fits — cache invalidate, way-flush, a zeroing engine), so no
  successor sees a predecessor's leftovers.
- **D.15** Teardown returns a freed child's resources to its parent, never anywhere
  outside the parent's subtree.

  *On forced destruction:* "resolved" does not require the victim's cooperation. The
  force-destroy instruction always succeeds — the hardware itself reclaims the whole
  subtree. If the software built on top (nested hypervisors, VMs) breaks as a result,
  that is the operator's problem, not a CE failure: CE supplies clean teardown tools
  but does not prevent misuse.

**Cost**

- **D.16** Every operation is classified by cost, with nothing left unclassified: the
  fast path is constant-time and never scans; slower paths are bounded and proportional
  to the work actually done, never worse than a near-linear ceiling.

**Runnability, movement, divisible resources**

- **D.17** A context may own resources while not yet runnable (no metadata attached);
  it can be made runnable (dispatched) only once metadata is attached.
- **D.18** Only register/Bank state can be saved and restored as bytes. Live
  arrangements with shared hardware — cache reservations, bandwidth guarantees,
  interrupt routing, timers — cannot be saved as bytes; they must be re-established on
  arrival, which may fail. This is exactly why "pinned" exists.
- **D.19** A divisible resource may be split among children: each child's slice is a
  strict subset of the parent's, and the children's slices never sum to more than the
  parent held. Granting or splitting is all-or-nothing and atomic at the scope of
  whatever arbitrates the resource — machine-wide for bandwidth, per-core for cache —
  succeeding wholly or changing nothing.

**Local view and confidentiality** *(the two added in the final completeness step)*

- **D.20** Every level sees its delegated resources — identity ranges, both kinds of
  Bank, and contract scales — renumbered into its own local namespace starting from a
  local base, and cannot see the parent or physical numbering. The mechanism may
  differ per resource (up-pointers, per-Group renumbering, the Formula-2 bandwidth
  readback), but the property is the same everywhere. (This is the positive,
  operational form of D.11 for the numbering channel.)
- **D.21** A Bank sealed by the vault instruction holds its contents only as
  ciphertext at rest; the plaintext can be reached only by an unseal in the most
  privileged mode. No ordinary operation exposes sealed plaintext: a restore refuses a
  sealed Bank (it must be unsealed first), and spill/fill move only the ciphertext.
  (Managing the keys — derivation, rotation, attestation — is a separate, deferred
  matter; this rule covers only the confidentiality.)

---

## 6. What CE deliberately is *not* (scope boundaries)

Knowing what a design refuses to do is as important as what it does. The design draws
four firm lines.

- **No migration.** Moving a context across harts, hypervisors, or levels is an
  operating-system operation, assembled from CE's primitives (allocate, save/restore,
  free, change ownership). CE itself has no "migrate" idea. Because some live state has
  no saveable form (tenet 10 / D.18), the OS may find a context "pinned" — but that is
  the OS *observing* CE state, not a CE feature. This dissolves the hard "cross-level
  migration" question rather than answering it: there is nothing in CE to permit or
  forbid.
- **No guarantee of a *workable* amount of resource.** CE guarantees structure — one
  owner, clean teardown, no leakage — but it does **not** promise that a context keeps
  enough cache or bandwidth to function after giving slices away. Arranging a workable
  split is the programmer's or OS's job. CE's only structural guarantee here is that a
  context holding children can never give *itself* away, so a subtree always stays
  reachable from above.
- **I/O-bandwidth (QoS) details are out of the frozen core.** QoS is structurally the
  same problem as memory bandwidth and will reuse the same mechanism, but its full
  chapter-level details are deliberately downstream work, to be finished after the core
  is frozen and the specification is rewritten. The core only commits to being
  *compatible* with it (D.19/D.20 describe the shape it must take). Notably, the first
  version of QoS is single-level — it does **not** telescope across multiple delegation
  levels — because multi-level I/O sharing only matters in narrow cases (virtual
  machines with direct hardware I/O).
- **No "generation counters."** An earlier design carried a counter on each slot to
  detect stale references to a reused slot. The design loop removed it: with strict,
  complete teardown before any reuse (D.13) plus scrubbing (D.14), and with the rule
  that software never supplies a raw slot number (D.3/D.10), the hazard the counter
  guarded against is closed by construction. The specific case that motivated keeping
  it — a reused interrupt slot — is handled instead by the ordered teardown in D.13
  (clear mask, clear pending, clear routing, then free).

---

## 7. What things cost

Performance correctness was checked by classifying **every** one of the 24
instructions into a cost tier. The model has two cost shapes: a **fast path** (constant
time, never scans) and a **slow path** (bounded, proportional to the work done, never
worse than a near-linear ceiling). Because the delegation tree is capped at a small
depth (D ≤ 3), even the "proportional to subtree" operations are only a handful of
cycles in practice.

- **The actual context switch is the only thing on the truly fast path:** saving the
  current context (`ec.ib`) and restoring the next (`ec.ob`), each a few cycles. These
  never touch the optional metadata.
- **Management operations** — assigning/releasing a Bank, delegating a Bank,
  creating a child, revoking from a child, creating/returning a Contract — are a few
  cycles each, bounded by the shallow depth. Creating or splitting a Contract is where
  the all-or-nothing, machine-wide admission of D.19 is enforced.
- **Force-destroying** a context and its subtree always succeeds and is proportional to
  the subtree size (bounded by the depth cap).
- **Spilling/filling** a Bank to and from memory is the one genuinely many-cycle
  operation, and it is kept off the context-switch path.
- **Sealing/unsealing** a Bank (the vault) is limited by the encryption engine and is
  also off the fast path.

The verdict: nothing is unbounded, and nothing on a time-critical path scans.

---

## 8. Configurations (profiles)

Not every chip needs every feature. The design defines four standard **profiles** —
named bundles of which extensions are present and how deep delegation can go — without
adding any new hardware:

- **CE-Embedded** — CME only, no delegation (depth 0), no VM memory tables. For
  microcontrollers.
- **CE-MinimalRT** — CME + CPE (cache partitioning), shallow delegation. For embedded
  real-time systems.
- **CE-RT** — CME + CPE + MSE (memory bandwidth), deeper delegation. For
  mixed-criticality and embedded Linux.
- **CE-Full** — all four extensions, full depth, VM memory tables. For cloud, servers,
  and the highest safety levels.

The larger profiles contain the smaller ones (Full ⊇ RT ⊇ MinimalRT); Embedded is a
separate branch (no delegation, no cache partitioning). Every invariant holds in every
profile — in the smaller ones, the rules about delegation and divisible resources are
simply satisfied trivially, because those features are absent.

---

## 9. Key decisions and why they were made

- **Hardware picks the slot, not software.** When a context asks for a new child or a
  resource slot, the hardware chooses which slot and returns it; software cannot demand
  a particular one. This is what makes "software never sees a raw number" (D.3) and "no
  authority by guessing" (D.10) hold in practice.
- **SMT siblings are just independent harts.** Two threads on one core are two harts
  that happen to share silicon; isolation between them is the default. CE state is
  per-hart, so SMT needs no special logical machinery — the physical table they share
  must enforce per-hart isolation, which is a microarchitecture matter.
- **One uniform local-view rule (D.20) instead of per-feature rules.** Identity
  ranges, both kinds of Bank, and bandwidth scales are *all* renumbered into each
  level's local namespace. This single rule is what lets software run unchanged at any
  delegation level, and the chip's self-protection mechanism depends on it.
- **The vault is a confidentiality guarantee (D.21), not just an instruction.** Sealed
  Banks stay encrypted at rest and can only be unsealed in the most privileged mode;
  ordinary operations cannot expose their plaintext. (Key management is a separate,
  later concern.)
- **Self-preservation is structural, not a resource promise.** A context cannot
  delegate itself away — so subtrees stay reachable — but CE does not promise anyone
  keeps a workable amount of resource. That is software's responsibility.

---

## 10. How the design was checked

The design loop declared itself finished only against five explicit exit conditions:

1. **The tenets are fixed and self-consistent.**
2. **The invariants are enumerated, internally non-contradictory, preserved by every
   operation, and satisfied by every profile.**
3. **Every operation's cost is classified**, with a constant-time fast path and a
   bounded slow path, none exceeding a near-linear ceiling.
4. **A stress battery runs clean** — the model was pushed through three demanding
   scenarios: mapping onto a real OS, deep nesting (levels 0 through 3), and a
   multi-hart "cluster" with shared memory and I/O — and held up for every settled
   resource class.
5. **Two consecutive red-team passes produce no change.** The tenets and invariants
   were attacked repeatedly from different angles — first for internal contradictions,
   then for completeness (does the model rely on anything not written down?), then for
   whether every principle and rule has a counterpart. The freeze is only declared
   after two clean passes in a row.

The red-team did real work. It found and corrected: a tenet that wrongly called
machine-wide bandwidth "per-hart"; an invariant that wrongly called all divisible
resources "machine-wide" (cache is per-core); two over-broad explanations (a bandwidth
readback described as depending only on the child's own state when it also uses the
parent's; an interrupt-only teardown order described as applying to all route types); a
loose use of the word "acyclic" given the root's self-loop; a **load-bearing invariant
that had been cited everywhere but never actually written into the list** (the uniform
local-view rule, D.20); and a confidentiality property that the vault instructions
enforced but no rule captured (D.21). Each was fixed deliberately. Only after the
corrected, completed set survived consecutive clean passes was the design considered
converged.

---

## 11. What is settled, and what comes next

**Settled (this core):** the identities, ownership and delegation model; the per-hart
versus machine-wide split; the uniform local-view rule; clean teardown and scrubbing;
the vault confidentiality guarantee; the cost shape; the four profiles; and the twelve
tenets and twenty-one invariants above.

**Still to come (downstream of the freeze):** rewriting the formal specification (the
charter and chapter 0) *from* this frozen core, then propagating the changes through
the remaining chapters; finishing the I/O-bandwidth (QoS) chapters, which reuse the
memory-bandwidth mechanism and were deliberately kept out of the core freeze; and
routine bookkeeping updates to the project's tracking documents.

---

*This document is a faithful plain-language synthesis of the converged CE logical
core. The authoritative source remains the specification being rewritten from it; where
this document and the specification ever differ, the specification governs.*
