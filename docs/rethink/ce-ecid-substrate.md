<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# The ECID Substrate — Core Data Structure and Operation

> *Provisional chapter (foundational; sits before the instruction-set reference and the
> resource extensions). Documents the single in-chip structure on which ECIDs, Groups,
> Banks, and Contracts all rest.*

## 1. Purpose and scope

The CE Suite is a RISC-V extension that adds in-chip structures for **sub-10-cycle
context switching** under **hard-realtime** constraints, designed so that
virtualization, containerization, and other execution-context isolation can keep those
guarantees across nesting levels.

This chapter defines the **core data structure** — the per-hart ECID array and the
parallel resource arrays — and the rules by which every higher-level operation
(context switch, delegation, reclamation, teardown, sealing, migration) acts on it.
The design target for the structure is simple: the **fast path is O(1)** in silicon,
and the **slow path is at most O(N log N)** and never on the realtime-critical path.

The structure is deliberately minimal. Everything is **fixed-width records** linked by
**single up-pointers**. There are no variable-length per-record tables, no required
contiguity, and no structure that fragments.

---

## 2. The substrate at a glance

Four object classes rest on one structural idea — *the owned thing points at its
owner*.

| Object | What it is | Where it lives |
|---|---|---|
| **ECID** | Execution Context IDentifier; a handle for one runnable context | a record in the per-hart **ECID array** |
| **Bank** | register-file-sized SRAM holding saved architectural state | a record in the per-hart **Bank array**, with an owner up-pointer |
| **Contract** | a divisible guarantee (memory bandwidth, cache, I/O) | per-hart **Contract array(s)**, with an owner up-pointer |
| **Group** | everything a given ECID owns | backward half is a *view* over the arrays; forward half (vnum→slot) is a hart-local cache, built while the parent runs, never in memory (see §6) |

An **ECID** can be bound to any kind of context: a kernel thread, a user process, an
interrupt service routine, a secure enclave, a bare-metal routine, a vCPU, a whole VM.
The structure is OS-agnostic; Linux is used only for examples.

Everything in this chapter is **per-hart**. Under SMT each sibling *is* a hart, so each
sibling has its own complete set of arrays. No CE structure is shared between harts;
sharing happens only through RAM (§10).

---

## 3. The ECID array

The ECID array is a flat, fixed-width table indexed by a physical **slot** number. An
implementation supports up to `2^k` slots (`k` typically 8 to 12). Each record has
**three baseline fields**, plus one optional field:

| Field | Width (typical) | Meaning |
|---|---|---|
| `ecs` | XLEN ptr | Pointer to the **ECS** (Execution Context State) in RAM. **Null = the slot is free.** |
| `owner` | n bits | Up-pointer to the owning ECID (the parent). `n` = ECID-index width. |
| `vnum` | n bits | This ECID's number **in its owner's universe** (see §5). `vnum = 0` means "self/root". |
| `gen` *(optional)* | few bits | Generation counter; incremented on free. See §3.2. |

So the baseline record is `{ ecs, owner, vnum }`. Because correct hardware is the sole
writer of these arrays, software cannot corrupt them; `gen` is therefore **not required
for integrity** and is omitted from the baseline. It earns its place only if a context
may present a *remembered* handle that could outlive a teardown-and-reuse of its slot
(stale-handle disambiguation, §3.2) — a few bits if adopted, zero otherwise.

The historical two-row drawing used during design maps directly: the top row was `ecs`,
the bottom row was `owner`.

**Open question — what kind of address is `ecs`?** Chip designers will need to know
whether the ECS pointer is a *physical* address or a *virtual* one (i.e. interpreted
before or after page-table translation). This is unresolved. A physical pointer is simplest
for hardware to dereference (no translation, no fault path) but ties the ECS to a fixed
physical location; a virtual pointer is more flexible for the OS but pulls page-table
translation onto the ECS-access path. The choice also bounds the pointer's width (§8.1).
Marked OPEN in §14.

### 3.1 Free slots

A slot is **free if and only if `ecs == null`**. This unifies two ideas that looked
separate during design: the "everything initially owned by root" picture and a
free-list. A free slot nominally carries `owner = 0`, i.e. it sits in root's pool,
available for allocation; it simply has no ECS bound yet. Allocation (`ec.ir`) binds an
ECS and assigns `owner` and `vnum`; freeing clears `ecs` (and bumps `gen` if present).

### 3.2 Reuse hygiene and the generation counter (optional)

**Anything reused is zeroed by hardware.** When a slot, a bank, or a contract is freed and
later handed to a different context, the hardware clears it before the new owner can see
it — no stale register values, page-table pointers, or vector state leak from the previous
occupant. The same principle covers work that was *in flight*: if an interrupt handler's
ECID is changed while an interrupt for the old handler is still pending, that pending
interrupt is cancelled rather than delivered to whatever now occupies the slot. Reuse never
exposes a predecessor's state or redirects its unfinished work. This is a hardware
guarantee, not something software must arrange.

Because hardware is the only writer of these arrays and it scrubs on reuse, **software
cannot corrupt them**, and no generation counter is needed to protect *integrity*. The one
case a counter would address is a *stale handle*: a context holds a token for some ECID,
that ECID is torn down, its slot is reused, and the remembered token now names a different
live context. With zeroing on reuse this is already softened — a token naming a freed slot
finds it empty and traps, rather than silently hitting a wrong live context — but a token
that survives long enough to name the slot's *next* occupant could still mislead. If
`ec.ob` only ever takes a freshly-issued token (never a remembered one that can outlive a
teardown), no counter is needed and the record stays `{ ecs, owner, vnum }`. If tokens can
be retained across teardown, a few-bit `gen`, incremented on free and compared on use,
rejects the stale one. Baseline: omitted.

The free list may be implicit (scan for `ecs == null`; slow-path, acceptable) or an
explicit list threaded through the free slots. Either is an implementation choice.

### 3.3 Initial state (CE switched on by firmware)

At boot the machine is in M-mode; firmware switches CE on. Slot 0 is the **root**; all
other slots are free.

```
 slot | ecs        | owner | vnum
------+------------+-------+------
   0  | kernel ECS |   0   |  0      root: owns itself, vnum 0
   1  |   null     |   0   |  -      free (ecs null)
   2  |   null     |   0   |  -      free
  ... |   null     |   0   |  -      free
 N-1  |   null     |   0   |  -      free
```

Root (slot 0) points to itself (`owner[0] = 0`) and is never wasted: its `ecs` is a live
RAM pointer to the kernel's (or firmware's) own ECS — a natural anchor for, e.g., a
`kexec`-style handover.

---

## 4. Ownership and the tree

`owner[X]` is the slot of the ECID that owns `X`. These up-pointers form an ownership
**forest rooted at slot 0**. This single pointer answers every *upward* question in
O(1) or bounded O(1):

- **"Who owns me?"** — read `owner[X]`. One load.
- **"Is X inside Y's domain?"** (containment / isolation) — walk `owner` from `X`
  upward; if `Y` is reached, `X` is inside `Y`. The walk is bounded by the maximum
  nesting depth **D**, and `0 ≤ D ≤ 3`, so it is at most three hops — O(1).

### 4.1 Levels and depth

Ownership nests up to **D** levels deep. The roles below are one common reading, but the
levels are *generic nesting*, not fixed to virtualization. L0 can equally be a plain
operating system, with its processes, threads, and interrupt handlers as L1; an L1 VM
kernel's processes and threads then sit at L2; and an L2 VM kernel's processes and threads
at L3. So "level" just counts how deeply a context is nested, whatever each layer happens
to be.

| Level | One typical role | Equally valid |
|---|---|---|
| L0 | firmware / bare hypervisor | a plain OS kernel |
| L1 | a VM, or a nested hypervisor | processes/threads/interrupts under an L0 kernel |
| L2 | a guest OS / kernel | processes/threads under an L1 VM kernel |
| L3 | the deepest contexts | processes/threads under an L2 VM kernel |

`D` is chosen per implementation: a microcontroller may set `D = 0`; a datacenter part
may set `D = 3`; laptops and phones sit in between. The nesting need not be a
general-purpose OS stack — it serves Kubernetes, a flight computer, a game console, or
any layered isolation scheme equally. A `D = 3` laptop with plenty of RAM is genuinely
useful: a developer could run a full hypervisor (say, a new Proxmox build) at L1, a guest
OS at L2, and that guest's containers at L3, every layer hardware-accelerated. The same
capability lets a hyperscaler offer virtualized, hardware-accelerated hypervisor clusters
to tenants.

The bound `D ≤ 3` is what makes upward operations O(1): no walk through the structure is
ever longer than the depth, and the depth is a small constant.

---

## 5. Virtualized numbering (the level-agnostic principle)

Every ECID is the **root of its own universe**. It sees **itself as 0** and numbers what
it owns **1, 2, 3, …**. A context never observes absolute slot numbers, its parent, or
its siblings — only its own virtualized namespace and its hart number.

This is what lets the **same OS image run unchanged at any level**: a kernel always
believes it is "0" with children "1..n", whether it is installed at L0, L1, L2, or L3.
It is the identity analogue of the bandwidth telescoping used by the memory-scheduling
extension — each level works in its own normalized world, and hardware bridges to the
absolute representation.

The `vnum` field stores each ECID's number in its **owner's** universe, fixed at
allocation. Two structural consequences follow:

- **"Nobody gives away themselves."** `vnum = 0` is reserved for self and can never be
  the operand of a delegation. Self-reference — and therefore a cycle — is structurally
  impossible; no runtime check is required.
- **To create a tenant you must own at least two ECIDs beyond yourself** — one to *be*
  the tenant root and at least one more to hand it.

### 5.1 Worked tree

To talk about an ECID without confusion, we use a **path**: a list of vnums from the root
down, written `/a/b/c`. The root is `/`. Its child with vnum 1 is `/1`. That child's own
child with vnum 2 is `/1/2`, and so on. The path is what each level *sees*; the absolute
slot is the hardware's private business. A path's length is also the ECID's level: `/1/2`
is at L2.

Starting from the initial state, root creates two children and gives each some children
of its own; then one child is made a tenant and receives children under it. The final
array (slot is implied by position; only `owner` and `vnum` are stored):

```
 slot | owner | vnum | path   | role
------+-------+------+--------+----------------------------------
   0  |   0   |  0   | /      | root (L0)
   1  |   0   |  1   | /1     | nested hypervisor (L1)
   2  |   1   |  1   | /1/1   | a context under /1 (L2)
   5  |   1   |  2   | /1/2   | a guest kernel (L2) — a tenant
   7  |   5   |  1   | /1/2/1 | context under kernel /1/2 (L3)
   9  |   5   |  2   | /1/2/2 | context under kernel /1/2 (L3)
   3  |   0   |  2   | /2     | a VM (L1)
   4  |   3   |  1   | /2/1   | context in VM /2 (L2)
   6  |   3   |  2   | /2/2   | context in VM /2 (L2)
   8  |   3   |  3   | /2/3   | context in VM /2 (L2)
   a  |   3   |  4   | /2/4   | context in VM /2 (L2)
```

As a tree (each node labelled by its path):

```
/  (root, slot 0)
├─ /1            (slot 1)  nested hypervisor
│  ├─ /1/1       (slot 2)
│  └─ /1/2       (slot 5)  guest kernel — a tenant
│     ├─ /1/2/1  (slot 7)
│     └─ /1/2/2  (slot 9)
└─ /2            (slot 3)  a VM
   ├─ /2/1  /2/2  /2/3  /2/4   (slots 4, 6, 8, a)
```

The deepest path `/1/2/1` has length 3 — exactly the `D = 3` limit. The kernel at slot 5
knows itself as `/1/2`'s local root, sees its two children as vnum 1 and vnum 2, and
neither knows nor can name the absolute slots 7 and 9.

### 5.2 The handover: turning a vnum into a slot

When a kernel switches to one of its threads, it asks in its own terms: *"switch to my
vnum 2."* The hardware, though, stores everything by absolute slot. So something must turn
**"vnum 2 of the running kernel"** into **"slot 9."** This is the handover, and getting it
right is what the whole structure rests on.

**Why the array alone cannot answer it.** Each record stores `owner` and `vnum`. That lets
you ask, of a slot you already have, *"what is your vnum?"* — one read. But the kernel's
question is the reverse: *"which slot has vnum 2 under me?"* The array is not arranged to
answer that; you would have to look through every record asking "is it you?" — a scan. A
scan is fine for slow reconfiguration, but a context switch must take a couple of cycles,
so a scan is not allowed here.

**The sort that would work — and why we must not do it to the array.** Suppose we sorted
the array by `owner` first and `vnum` second. Then every owner's children would sit
together in one block, ordered by vnum, and "owner 5's vnum 2" would be easy to find. The
catch is fatal: **the slot number *is* the position in the array.** Sorting moves records,
so it changes every ECID's absolute number — slot 9 might become slot 6 — and every
up-pointer and every stored reference would break. Identity is position, so the array can
never be reordered.

**So we sort a copy of the keys, not the array.** We keep a separate small structure that
maps `(owner, vnum) → slot`, built and kept in order as children are inserted, while the
real array's positions — the identities — stay put. That separate structure is the
**forward index**. It is the same object seen three ways: a parent's list of its children's
slots; "vnum points to a slot"; and the sort keys lifted out into their own table. The
array faces *backward* (slot → its vnum, free); the forward index faces *forward*
(vnum → slot, what the switch needs).

**Where the forward index lives: only in hardware.** A parent needs its forward index
*only while it is running* — only a running kernel issues "switch to my vnum 2." So the
index is a **hart-local cache**, held in a small "current children" register, and it is
**never written to addressable memory** — not to the ECS, not anywhere the OS, a DMA
engine, or a debugger could read it. Writing a slot number to RAM would re-expose exactly
the identifiers this section works to hide. Instead the index is *built* in the hart as the
parent creates its children, and simply *dropped* when the parent leaves the hart, to be
*regenerated* when it runs again (§5.3). A context with no children carries no index —
there is nothing to resolve.

**The kernel stays slot-blind end to end.** The kernel holds only ECS addresses. It reads
a child's `vnum` from that child's ECS, issues "switch to vnum 2," and the hardware's
forward index maps vnum 2 → slot 9. The kernel never sees, stores, or can guess an absolute
slot. This is what defeats the attack of a guest trying to name its way into the
hypervisor: there is no slot number for it to name, and none ever reaches memory.

### 5.3 When the forward index is built — and why it never needs rebuilding

The index is not assembled at switch-in by scanning; it is **built incrementally by the
ownership instructions themselves**, because those are executed *by the parent while it is
the running context*. A kernel allocates and delegates its own children, so it is current
on the hart at that moment, and each entry can be written straight into the hart's current
children register as it is created:

- **`ec.ir`** (allocate a child) adds one `vnum → slot` entry to the running parent's index.
- **`ec.it`** (delegate unused ECIDs to a tenant) populates the tenant's index (and removes
  those entries from the giver's).
- **`ec.ot`** (tear a tenant down) removes the entries for the children that cease to exist.

There is no separate "load" or "rebuild" step and no save-to-memory step: the index comes
into being as a side effect of a parent building its own children, lives in the hart while
the parent runs, and is dropped when the parent is switched out. When the parent runs again
its children are unchanged, so the same mapping is simply rebuilt from the array
(`owner == me`) as part of swapping it in — a slow-path scan, which is acceptable because
switching *into* a scheduler is not the nanosecond-critical event; switching *among* its
already-loaded children is, and during that the index is already resident.

Two invariants make this safe across changes at any level:

1. A parent's index references only its **direct children**, and is changed only by **that
   parent's own** `ec.ir`/`ec.it`/`ec.ot` (while it runs) or by its parent tearing it down.
   A sibling's or a descendant's activity can never invalidate it.
2. **Vnums are stable for life.** Removing a child leaves a *gap*; survivors are never
   renumbered. So every surviving `vnum → slot` entry stays correct across any change
   anywhere in the tree.

### 5.4 Worked walk: changes at several levels

Absolute slots are capital letters (`A, B, …`, never seen by software); a context's view
of its children is `1, 2, 3 …` (vnums; `0` = self); a forward index is written
`{1→X, 2→Y}`. Root `A` is L0; it owns a guest kernel `B` (L1); `B` owns threads.

```
E0  boot — only root exists
    array:  A:(owner=A, vnum=0)
    A.index: { }

E1  A runs ec.ir -> creates guest kernel B
    array:  A:(A,0)  B:(A,1)
    A.index: { 1->B }                A knows its child as "1", not "B"

E2  A runs ec.ob 1 -> switch into B  (A.index says 1->B, load slot B)
    B is now current; the hart's current-children register is B's (empty)
    B.index: { }

E3  B runs ec.ir twice -> threads C, D
    array:  A:(A,0)  B:(A,1)  C:(B,1)  D:(B,2)
    B.index: { 1->C, 2->D }          B sees its threads as 1 and 2

E4  B runs ec.ob 1 / ec.ob 2 -> fast-path switching among C and D
    nothing changes the index; B is just using { 1->C, 2->D }

E5  change at B's level — B runs ec.ir -> thread E
    array adds:  E:(B,3)
    B.index: { 1->C, 2->D, 3->E }    only B's index changed; A's untouched

E6  change at A's level — switch out to A, A runs ec.ir -> second guest F
    (while A was swapped out in E3-E5, A.index = {1->B} stayed valid:
     B was changing B's own children, never A's)
    array adds:  F:(A,2)
    A.index: { 1->B, 2->F }

E7  grandparent acts — A runs ec.ot on its child 1 (B)
    recursively removes B and everything under it (B, C, D, E), zeroed
    array now:  A:(A,0)  F:(A,2)
    A.index: { 2->F }                entry 1->B removed by A itself
    B.index: gone with B             nothing else ever referenced C/D/E,
                                     so there is nothing to clean up

E8  F keeps vnum 2 — it is NOT renumbered to "1" because B left.
    A.index has a gap at 1; that is fine. A vnum, once assigned, is stable
    for the life of that child; removing a sibling never shifts survivors.
```

The teardown in E7 is local precisely because of the up-pointer structure: the only index
that referenced `C/D/E` was `B`'s, and it died with `B`. The vnum stability in E8 is what
keeps every surviving mapping intact through changes at any level — the same reason the
array itself is never reordered (§5.2).

---

## 6. What a Group is: a backward view plus a forward index

A **Group** is "everything an ECID owns." It is **not** a stored, variable-length
structure. It is the *set of all records whose up-pointer is X*, read across the arrays:

```
Group(5) = { ECIDs with owner == 5 }  ∪  { Banks with owner == 5 }  ∪  { Contracts with owner == 5 }
         = { ECID 7, ECID 9, ... whatever banks/contracts 5 holds }
```

Nothing stores "5 owns {7,9}" *as a membership list*; it is *implied* by `owner[7] = 5`
and `owner[9] = 5`. This is why child ECIDs need no separate group array for the
*backward* question (who owns me, who is inside me) — their membership is already their
up-pointer in the ECID array. The other owned resources — banks and contracts — are
**parallel fixed-width arrays following the identical pattern**: each record carries an
`owner` up-pointer to the ECID that holds it. (The bank array's owner pointer already
exists in the instruction-set reference as the bank ownership check.)

The one thing a Group has beyond the backward view is the **forward index** of §5.2–§5.3 —
the parent's `vnum → slot` map used to switch into a child by its vnum. That is the forward
half of a Group. It is **not** stored in the array, the bank, or the ECS: it is a
**hart-local cache**, built by the parent's own ownership instructions while it runs, and
never written to addressable memory (§5.3). So a Group has two halves: the backward half is
a free view over up-pointers, and the forward half is a hart-resident table that exists only
while the parent runs. Only parents that switch among children have one.

So the substrate is **three** parallel fixed-width arrays (ECID, Bank, Contract), every
relationship a single up-pointer, every Group's backward half a view over them, and every
Group's forward half a small table carried with its parent's saved state.

---

## 7. The directions the structure answers

The structure answers questions in three ways, each matched to its cost budget:

| Question | Mechanism | Cost | Path |
|---|---|---|---|
| who owns me? is X inside Y? | the `owner` up-pointer | O(1), ≤3 hops | fast |
| switch to my vnum k → which slot? | the parent's forward index (§5.2–5.3), a hart-local cache | O(1) indexed read | fast |
| list my children/banks; enumerate a Group | scan the arrays for `owner == self` | O(N) | slow |

The split that keeps the structure cheap: the fast path needs only two things, and both
are O(1). The **upward** question is answered by the up-pointer in the array — free, no
storage beyond the pointer. The **vnum → slot** question is answered by the small forward
index that the running parent built in the hart as it created its children (§5.3) — present
only for parents, held only while running, never in memory. Only *enumeration* (listing a
Group, walking children for delegation or teardown) needs a scan, and that arises only in
slow-path reconfiguration, where O(N) is within budget. So the array stores the backward
fact in every record (`owner`, `vnum`); the forward index is a hart-local cache regenerated
per parent; and nothing else is needed.

---

## 8. Banks

A **Bank** is register-file-sized SRAM holding a saved architectural context, organized
in a fixed layout (GPR, FPR, CSR, SATP, PC, control fields each at a fixed offset). Banks
are the medium of the fast path: saving to / restoring from a bank is the 1–9 cycle
operation that makes sub-10-cycle switching possible. There are two kinds:

| Kind | Holds | Size (example) | Count (example) |
|---|---|---|---|
| **non-VMT** | GPR, FPR, CSR, SATP, PC, control | < 1 KB → rounded to **1 KB** (RV64) | ~32 per hart (laptop); more on servers |
| **VMT** | Vector / Matrix / Tensor register state | **4 KB** for 1024-bit vregs; scales with width | fewer, e.g. **8** per hart — SRAM is scarce |

VMT is forward-looking: matrix and tensor instructions are expected to reuse the vector
registers, so one bank kind covers all three. RVV's large vector state is a primary
motivation for CE — it is exactly the state whose save/restore most needs hardware
acceleration.

Each bank record carries an `owner` up-pointer to its current holding ECID. Software does
not address a bank by number (§9.3): a context simply *has* a bank or does not. An ECID
with no bank stores a "no bank" sentinel and uses the RAM path (§10) instead.

**An interrupt handler can be its own banked ECID.** On a conventional design, taking an
interrupt traps into the kernel, which spills registers and sets up the handler — the
handler is "the kernel wearing a different hat," not a context of its own. CE lets you
instead give an interrupt handler its *own* ECID with its *own* pre-loaded bank, so taking
the interrupt is a single `ec.ob` into that bank rather than a trap-and-spill sequence.
That is a direct latency win for hard-realtime sources — a radar-return handler, an audio
interrupt — and it is *optional*: whether an ISR is the kernel or its own banked ECID is a
design choice CE makes available, not a fact the OS must commit to in advance. (Under
SMP/SMT the kernel is resident on every hart and entered concurrently; each hart has its
own banks, and the kernel handles its own concurrency in software exactly as it does
today. CE changes the speed of entry and exit, not the concurrency model.)

### 8.1 ECID-array sizing and the choice of n

Let **n** be the ECID-index width, so the array holds `2^n` records and both `owner` and
`vnum` are n bits. With an XLEN-bit ECS pointer, one record is `(XLEN + 2n)` bits and the
whole per-hart array is `(XLEN + 2n) · 2^n` bits.

```
per-hart ECID array  (record = ECS_ptr + owner(n) + vnum(n))
  n   records   RV32/rec   RV64/rec   RV32 total   RV64 total
  8       256       48 b       80 b      1.5 KB       2.5 KB
  9       512       50 b       82 b      3.1 KB       5.1 KB
 10      1024       52 b       84 b      6.5 KB      10.5 KB
 11      2048       54 b       86 b     13.5 KB      21.5 KB
 12      4096       56 b       88 b       28 KB        44 KB
```

The decisive figure is not per-hart but **per-hart × hart count**, because the array is
replicated in every hart (every SMT sibling and every core):

```
RV64 total scaled by hart count
  n     1 hart     8 harts    32 harts    128 harts
  8     2.5 KB      20 KB       80 KB       320 KB
 10    10.5 KB      84 KB      336 KB      1.31 MB
 12      44 KB     352 KB      1.38 MB      5.5 MB
```

Read against on-die SRAM (an L1 is ~32–64 KB per core; an L2 slice ~256 KB–1 MB per
core), and remembering this sits **on top of** the bank SRAM (~64 KB/hart, the part that
actually buys the fast path):

- **n = 8 (256 ECIDs/hart)** is the choice for any SRAM-scarce implementation —
  microcontrollers, embedded, realtime, phones, laptops. At 2.5 KB/hart it is smaller
  than one L1 way and negligible even at 128 harts. The array need only hold a hart's
  *working set*; colder contexts live in RAM and stream in via `ec.om`. **Recommended
  default.**
- **n = 10 (1024 ECIDs/hart)** is the graceful step up — and a better "next rung" than
  n = 12. It costs 4× the n = 8 footprint for 4× the capacity (10.5 KB/hart, 336 KB
  across 32 harts) and stays comfortably sub-L1. Use it when a midrange part — a phone or
  laptop running a containerized stack with many live threads — finds 256 resident
  contexts tight, without paying the n = 12 jump into L1-sized-per-hart territory.
- **n = 12 (4096 ECIDs/hart)** is the ceiling, and only for a large server that has
  *measured* a need for thousands of resident contexts per hart: 44 KB/hart is already
  L1-sized per hart, and a 32-hart machine spends ~1.4 MB on ECID arrays alone.

Beyond n = 12 a flat array stops making sense — the footprint grows as `2^n` while the
populated fraction shrinks — so the practical range is **8 to 12**. A namespace larger
than that would call for a sparse structure (e.g. a radix tree that pays only for live
ECIDs) rather than a bigger flat array, which is a different data structure and out of
scope here.

A note on capacity in practice: today few systems run anywhere near 1024 contexts on a
single hart — that many usually means a runaway fork. But the premise of CE is that
context switching becomes *dramatically* cheaper, and cheap switching tends to invite far
more, finer-grained contexts (lightweight threads, fibers, per-request contexts). So the
"who needs 1024?" intuition may not hold for long; sizing n with a little headroom above
today's norms is reasonable.

A note on the ECS-pointer width: "RV64" does not force a 64-bit pointer field. RVA23
defines several virtual-address widths (Sv39, Sv48, Sv57), and an implementation need only
store as many bits as its address space uses — an Sv39 part needs ~39, not 64. Whether the
ECS pointer is a physical or a virtual address (see §3 / §10 open items) also affects the
width. The sizing math above uses XLEN as an upper bound; a real part may store fewer
pointer bits and shrink the record accordingly.

**Packed vs. aligned records — the catch with intermediate n.** The per-record figures
above assume *tight bit-packing*: n = 10 yields an 84-bit RV64 record. If the
implementation instead **aligns** fields or records to a byte/word boundary (often
desirable for the SRAM array and the decode path), the record rounds up — e.g. to 96
bits — and n = 9, 10, 11 all pad to the same physical width as n = 12. In that case the
intermediate values stop being distinct operating points and n = 12's larger namespace
becomes effectively free relative to them. So an intermediate n is a genuine, cheaper
operating point **only if records are packed tightly**; under record alignment, choose
between n = 8 and n = 12 directly.

**Choose n together with maximum fanout, not in isolation.** The usable capacity is
bounded by the tree shape `fanout^D` (D ≤ 3), not by raw `2^n`. With a max fanout of 16,
the logical tree tops out at 16³ = 4096 positions, so at n = 8 the 256 slots bind first
while at n = 12 the fanout binds first; n = 10's 1024 slots pair naturally with a fanout
of ~10 at D = 3. The slot width n and the maximum fanout (open item, §14) are the two
halves of "what this part actually supports" and should be picked as a pair.

Note what the table also shows about the design itself: even at n = 12 the two n-bit
fields add only 24 bits to an 88-bit record — **the ECS pointer dominates**. The
ownership/numbering machinery is nearly free; shrinking the namespace (n) saves far more
SRAM than trimming any bookkeeping field could.

### 8.2 Physical cost against shipping silicon

The figures below put CE's cost in context using real parts (mid-2026). They are
back-of-envelope — 6T SRAM cells at 6 transistors/bit, control/tag/ECC overhead ignored
(add ~20–40% to bank SRAM) — but the conclusion is insensitive to the soft assumptions.

**Per-hart CE cost.** With n = 10 (1024 ECIDs), 32 non-VMT banks of 1 KB, and 8 VMT banks
sized to the vector width:

| Component | VLEN 256 (e.g. SpacemiT X100) | VLEN 1024 |
|---|---|---|
| ECID array (n = 10) | 10.5 KB / 0.52 M tr | 10.5 KB / 0.52 M tr |
| 32 × 1 KB non-VMT banks | 32 KB / 1.57 M tr | 32 KB / 1.57 M tr |
| 8 × VMT banks | 8 KB / 0.39 M tr | 32 KB / 1.57 M tr |
| **CE per hart** | **50.5 KB / 2.5 M tr** | **74.5 KB / 3.7 M tr** |

The ECID array — the structure this chapter is about — is the *cheap* part: ~0.5 M
transistors, ~14–20% of CE's footprint. The banks dominate, and within them the cost is
**vector register storage**, which scales with VLEN. This is the design thesis made
physical: CE spends SRAM precisely on the architectural state (especially vector state)
that is expensive to save and restore, and that expense tracks the vector unit the core
already paid for.

**Measured anchors (published / disclosed):**

- *SpacemiT X100* (the K3's application core): a 4-issue out-of-order RVA23 core, single
  thread per core, single-core performance positioned near Arm Cortex-A76; **256-bit**
  vector registers (32 × 256 b). The K3 integrates 8 X100 cores with a shared ~8–10 MB
  L2. (The K3's 1024-bit RVV lives in its separate A100 AI cores, not the X100.)
- *SiFive U84*: ~**0.28 mm² per core at 7 nm** (OoO, ~A72-class, no vector); a quad-core
  cluster with 2 MB L2 is ~2.63 mm². The nearest *published* RISC-V core-area data point.
- *AMD Ryzen 9 9955HX / HX3D*: **16.63 B transistors**, TSMC 4 nm, 16 cores / 32 threads,
  64 MB L3 (the 3D part stacks an extra ~64 MB cache on a separate die).

**CE as a fraction of an X100-class hart.** Estimating an A76-class RISC-V core with a
256-bit vector unit at 150–500 M transistors (lean to heavy):

| X100 core estimate | CE (2.5 M tr) as % of core |
|---|---|
| ~150 M tr (lean, A72/SiFive-like) | ~1.7 % |
| ~300 M tr (mid) | ~0.8 % |
| ~500 M tr (heavy, full A76 + vector) | ~0.5 % |

So the **entire** CE suite — banks included — costs roughly **0.5–1.7 % of a hart**; the
ECID array alone is ~0.1–0.3 %. The instruction-set side reinforces this: RVA23's
mandatory set (RV64I + M, A, F, D, C, bit-manip, V, H) is a few hundred instructions
versus x86-64's thousands, so an X100 spends its transistors on the vector unit and the
out-of-order engine, not on decode — and those are exactly the structures CE's banks
shadow. CE's cost therefore stays a fixed small fraction of whatever the core already
spent on architectural state.

**Budget comparison.** Stripping ~4 B transistors of cache from the 9955HX leaves ~12.5 B
for cores + uncore. A Zen 5 core is far heavier than an X100 (wider, higher-clocked, full
AVX-512, deep speculation), so the same transistor budget holds on the order of **30–50
X100-class harts** versus 16 Zen 5 cores — and **CE on all of them adds under 1 %**
(~125 M transistors across 50 harts, less than 4 % of the L3 cache alone). The
context-switch machinery does not move the hart count; the core-width decision does.

**Takeaway.** The expensive resource was never the ECID structure. It is the vector
register banks — and even those are dwarfed by the core and the cache. Whatever is chosen
for n, bank counts, or core width, the CE substrate is a sub-1 % area tax on a realtime
RISC-V hart, and it is cheapest exactly where it matters least (narrow-vector embedded
parts) and grows only on wide-vector cores, which are also where fast vector
context-switching is most valuable.

---

## 9. Operations on the structure

The instruction families act on the structure as follows. (Full encodings and operand
formats are in the instruction-set reference; this section maps each to its structural
effect and cost.) All CE instructions are privileged. The mnemonic form is
`<class>.<dir><target>`, where `<class>` names the object operated on (`ec` an ECID,
`bk` a bank), `<dir>` is `i` (in/save/acquire) or `o` (out/restore/release), and
`<target>` names where it goes (`b` bank, `m` memory/ECS, `v` vault, `e` an ECID,
`t` a tenant).

### 9.1 Saving and restoring context state

These move a context's architectural state on and off the hart. Two go via a bank (the
fast path); two go via the ECS in RAM (for contexts that have no bank).

- **`ec.ib`** (in bank): save the running context's architectural state into its bank.
  Maskable (which register groups to save); a dirty-group bitmap allows lazy saving.
  Always succeeds or traps. **Fast path, 1–3 cycles.**
- **`ec.ob`** (out of bank): restore a target context's state from its bank. The target
  is verified by a single up-pointer check (`owner[target] == current`, or an ancestry
  walk bounded by `D`). If the PC is in the mask, control transfers to the restored
  context (the switch). **Fast path, 1–3 cycles.**
- **`ec.im`** (in memory): save the running context's architectural state **directly to
  its ECS in RAM**, by DMA — not via a bank. This is the save path for a context that has
  no bank. Fast in practice, but **not** realtime-bounded (it is a DMA transfer, not a
  fixed-cycle bank copy).
- **`ec.om`** (out of memory): restore a context's architectural state **directly from its
  ECS in RAM**, by DMA. The fill counterpart to `ec.im`; the restore path for a bankless
  context, and a building block of migration.

`ec.im` / `ec.om` move hart state straight to and from RAM; they are *not* "copy a bank to
RAM." A banked context that merely wants its bank spilled would use `ec.ib` then an
ordinary copy — no dedicated instruction is needed for that. `ec.im` / `ec.om` exist
precisely so a *bankless* context can be saved and restored at all, which a two-step
bank sequence could not do (it has no bank). These are save/restore operations, not
reconfiguration.

### 9.2 ECID ownership: allocation and delegation (slow path)

These reshape the ownership tree. All are slow-path reconfiguration, bounded by
**≤ O(N log N)**, never realtime-critical.

- **`ec.ir`** (allocate an ECID): take a free slot (`ecs == null`), bind an ECS, set its
  `owner` and `vnum`. Returns a handle to the owner. There is no separate `ec.or`:
  an ECID is not "deallocated" on its own — it is returned to its owner by tearing down
  the tenant that holds it (`ec.ot`), which is the single return path.
- **`ec.it`** (into tenant): make a child you own into a *tenant* — a local root that may
  itself own and re-delegate. Only **unused (free) ECIDs** may then be handed to that
  tenant for it to populate; you never push an already-populated subtree into a tenant.
  (Delegating live, occupied contexts across an ownership boundary is a security hazard;
  forbidding it removes the hazard entirely.) Requires that you own at least two ECIDs
  beyond yourself — one to be the tenant root, at least one to give it.
- **`ec.ot`** (out of tenant): recursively tear a tenant down — return every ECID, bank,
  and contract under it to you, and zero them on the way out (§3.2). **Always succeeds**,
  even if the tenant or a VM beneath it has crashed. Bounded by the subtree size
  (depth ≤ D). `ec.ot` does *not* coordinate with anything still running inside the
  tenant: orderly shutdown of whatever lives under it is the OS/hypervisor programmer's
  responsibility *before* calling `ec.ot`. The instruction simply reclaims and scrubs.
  (Because `ec.ot` already destroys a whole subtree unconditionally, no separate
  "forced destroy" instruction is needed.)

### 9.3 Banks: delegation and reclamation (slow path)

A bank is owned via the same up-pointer pattern; giving one is repointing that pointer.
Reclamation, by deliberate design, is **only on teardown** — never from a running ECID
(see below).

- **`bk.ie`** (bank into ECID): give a free bank to a child ECID — repoint a bank's
  `owner` to that child. You do **not** name a specific bank; the hardware takes the first
  free one of the requested type (non-VMT or VMT). How many free banks of each type you
  hold is readable from a CSR — that count is all you need to decide whether you can give.
  A child with ≥ 1 bank can use it for its own state; with ≥ 2 it can run its own `bk.ie`
  to a grandchild.
- **`bk.iv`** (bank into vault): seal a bank under hardware encryption.
- **`bk.ov`** (bank out of vault): unseal a sealed bank for a secure enclave (§11).
  (These were written `ec.iv` / `ec.ov` in earlier drafts; the object operated on is a
  *bank*, so the class letters are `bk`.)

**The "own bank" rule.** Any ECID that holds banks must use one for **itself**. The reason
is the whole point of CE: a scheduler cannot guarantee sub-10-cycle switching to the
realtime work beneath it (an interrupt handler, a radar-tracking thread, a DAW audio
thread) unless it can save and restore *its own* state through a bank. So when CE is
enabled the **root ECID has its own bank**, and the same holds at every level: to hand
banks to a child so that child can sub-delegate, one of those banks must be the child's
own. Giving each realtime child exactly one bank, for its own use, is the common case.

**Reclamation is only on teardown — there is no standalone `bk.oe`.** A running ECID never
gives a bank back: it is *running on* that bank, and surrendering it would be like pulling
a register file out of a live core. Banks return to the parent only when their holder ends
— cleanly via `ec.ot`, or violently when its subtree is torn down — at which point the
teardown sweep (§9.4) reclaims **all** of the holder's banks at once and zeroes them
(§3.2). This mirrors real systems: you cannot hot-remove a CPU's parts from a running VM;
you power it down, and the resources return. Reclamation is therefore *by owner*
(destroy the holder, sweep its group), never *by bank*.

**A consequence: software never names a bank.** Giving is "a free one" (by CSR count);
reclaiming is "sweep a destroyed owner's group." Neither operation addresses a specific
bank by number. So although banks are virtualized in the same spirit as ECIDs in
principle, in the baseline ISA a bank has **no software-visible handle** — its number, if
any, lives only inside the hardware. The 0-vs-1 numbering question is therefore moot for
banks: there is nothing for software to count.

### 9.4 Why reclamation and teardown are clean

Because ownership is always "the owned thing points at its current owner," tearing down a
whole subtree is a depth-bounded walk that returns every owned record — ECIDs, banks,
contracts — to the parent and zeroes it. A parent reclaims everything inside its subtree
in O(1) per item by destroying the holders, and can **never** touch anything outside it —
the containment check enforces this structurally. There is no live, by-name revocation of
a bank from a running ECID; reclamation happens only as part of destroying the holder.

---

## 10. Multi-hart operation

The arrays are per-hart, but real workloads span harts. The model rests on one split:

- The hardware **slot** number is **hart-local** — slot 7 on one hart is unrelated to
  slot 7 on another.
- The **durable, global identity** of a context is its **ECS in RAM** (the `ecs`
  pointer), together with the owner's virtual name for it. This is the migration anchor.

A scheduler refers to its placed contexts by the coordinate **(hart number, virtualized
ECID number)** and stores that in the ECS records it keeps. The hardware on each hart
holds the full local tree; software sees only its own universe.

### 10.1 Why the fast path stays local

Whoever runs on a hart got there because its **entire chain of schedulers ran on that
hart to switch it in**. Therefore the running context's full ancestor chain to root is
always co-resident on the hart. The up-pointer ancestry check on `ec.ob` walks only these
on-hart pointers — never RAM — so it stays O(1). Root (L0) is resident on **every** hart.

### 10.2 The same context across harts

A context that spans harts (e.g. the kernel of a multi-vCPU VM) has **one ECID slot per
hart it touches**, all sharing **one ECS in RAM**. The virtualized number is
hart-independent (a stable name); the absolute slots need not agree across harts. A
containment check is computed locally on each hart and yields the same logical answer.

The picture stores no forward pointers *in the array itself*. The backward facts
(`owner`, `vnum`) live in each record; the only other stored links are the `ecs` pointers
into RAM. The forward index a parent uses to switch to a child by vnum (§5.2–5.3) is not in
the array, the bank, or the ECS — it is a hart-local cache, rebuilt on whichever hart the
parent runs. So "K's child by vnum 1" is resolved on hart A from the index K built while
running on A, and independently on hart B from the index K built while running on B; each
hart's index maps the same vnum to that hart's local slot. Enumerating K's children for
reconfiguration (not switching) is still a slow-path scan for `owner=K`.

```
        HART A                              HART B
  kernel K is slot 5                  kernel K is slot 12

  slot 7:  owner=5, vnum=1            slot 30: owner=12, vnum=1
  slot 9:  owner=5, vnum=2            slot 31: owner=12, vnum=2
            │                                   │
            │ owner up-pointers                 │ owner up-pointers
            ▼                                    ▼
  slot 5:  ecs ──────────────► ECS_K in RAM ◄────────────── slot 12: ecs
```

On hart A, K's first child is whichever record has `owner=5, vnum=1` (here slot 7); on
hart B the same logical child is `owner=12, vnum=1` (here slot 30). The absolute slots
differ and need not agree; the up-pointers are local; the shared `ecs` is what unifies
the two harts' views of the same kernel.

### 10.3 Migration

Moving a context from one hart to another reuses the existing instructions:

1. Source hart: `ec.im` spills the running context's state to its ECS in RAM (or, if it
   has a bank, `ec.ib` then a copy); free the slot (bump `gen` if used).
2. Destination hart: `ec.ir` allocates a fresh slot; `ec.om` fills it from the ECS.

**Banks never travel; state travels through RAM; identity is the ECS.** This is why
per-hart banks are a feature, not a limitation. Hard-realtime contexts are typically
**pinned** (their hart number is fixed); best-effort contexts migrate freely.

### 10.4 What an ECS contains, and how the hardware finds its parts

The ECS (Execution Context State) is the RAM home of a context. A real OS does not keep
architectural state in one neat block — Linux scatters it: user registers in a `pt_regs`
frame at the top of the task's kernel stack, callee-saved registers in a separate
`thread_struct`, and vector state behind a *pointer* to a separately allocated,
VLEN-sized buffer. The layout also differs by context kind (kernel thread, user task,
interrupt frame). So CE cannot assume one fixed memory layout and blindly copy it.

The resolution is not "one block *or* a pointer list" — it is **both at once**, because
the split is forced by physics, not taste. Fixed-size scalar state (GPR, scalar FP, the
handful of CSRs, SATP, PC, control) can sit in a contiguous block; variable-size vector
state *cannot* be inlined in a fixed record (its size depends on VLEN, §8), so it must be
reached by a pointer-and-length. The ECS is therefore a small **fixed descriptor** that
*contains* pointers to the variable parts:

```
ECS descriptor (fixed; what ec.im / ec.om read):
  [hart#, vnum]          ← optional software-convenience mirror (see below)
  scalar block           ← GPR, scalar FP, CSRs, SATP, PC, control
  vmt_ptr, vmt_len       ← pointer + length of the variable VMT buffer
```

**Two modes, selected per instruction by an operand bit.** `ec.im` / `ec.om` carry a mode
bit (in `rs1`/`rs2`) choosing how the scalar part is interpreted:

- **Descriptor mode** (the non-negotiable baseline): the scalar entries are themselves
  `(pointer, length)` pairs into the OS's existing scattered structures. Hardware chases
  each pointer. This lets a largely-unmodified kernel adopt CE by handing CE the addresses
  of structures it already maintains.
- **Flat mode**: the scalar block *is* the contiguous state at known offsets; no chasing.
  This is the fully-ported path — and it is just descriptor mode where the kernel has
  arranged its structures to be contiguous in the standard order, so the descriptor
  degenerates into "one block." A new OS would be born in flat mode; a ported Linux could
  reach it by a remapping of where it keeps these structures.

The VMT buffer is reached by `vmt_ptr` + `vmt_len` in **both** modes — flat mode flattens
only the *scalar* part; the vector buffer is always behind a pointer because VLEN forces
it. Stated plainly so no one expects a single blob that includes the vectors.

**Mode pairing is the OS's responsibility.** `ec.im` and `ec.om` for the same context must
use the same mode, exactly as an OS must not free a stack it is still using. The hardware
does not track mode per context (that would add bookkeeping for no safety gain). What the
hardware *does* guarantee is containment: every pointer a descriptor follows is
dereferenced under the **running context's own memory mapping**, so a malformed or
mismatched descriptor can corrupt only that context's own memory — it can never reach
across an isolation boundary into a parent or sibling. Memory safety (the page tables /
SATP already in force) is the wall. A mode mismatch is a self-inflicted wound, not an
escape.

**`[hart#, vnum]` is authoritative in the ECID array, not the ECS.** The tuple already
exists for free: `vnum` is a stored field in the array record, and `hart#` is implied by
*which* hart's array the record lives in — nothing to store. A context "uses CE" exactly
when it has an array record, and then it has `[hart#, vnum]` by construction. The ECS may
*mirror* the tuple as a convenience for software that holds an ECS pointer and wants the
name without a hardware lookup, but that copy is not the source of truth. (A process that
uses no CE at all has no array record and therefore no tuple — which is correct: nothing
forces every process under a CE-aware OS to be a CE context.)

**The forward index is never in the ECS — never in addressable memory at all.** A parent's
`vnum → slot` map (§5.2) is CE-private hardware state, held in the hart's "current
children" register while the parent runs. It is built incrementally by the parent's own
ownership instructions (§5.3) and is **not** written to RAM on swap-out: putting a slot
number in memory would re-expose the very identifiers the design keeps invisible (§5.2),
where a compromised kernel, a DMA engine, or a debugger could read them. So the forward
index lives only in hardware; it is regenerated, not reloaded, when a parent runs again
(§5.3). It is CE's own data and is untouched by the flat/descriptor mode bit, which governs
only OS-owned scalar state.

The remaining open choices — whether the ECS pointer and the descriptor pointers are
physical or virtual addresses — are in §14.

---

## 11. Viewpoints and the need-to-know model

The structure enforces a strict "each role knows only what it needs." The **per-hart CE
hardware is the trusted base** — the *trusted computing base* (TCB), meaning the part that
must be correct for isolation to hold; if it is sound, a bug anywhere else cannot break
isolation. It holds the full local tree precisely so it can enforce minimal knowledge on
everyone else.

| Role | Must know | Must NOT know | Span |
|---|---|---|---|
| Per-hart CE hardware (TCB) | full local arrays, `current` | anything on other harts | one hart |
| M-mode firmware / platform | hardware caps, topology; CE on/off; sets up root | guest contents (policy) | system |
| L0/L1/L2 scheduler (software) | `(hart#, vnum)` of ECs in its own universe; their ECS | absolute slots, its parent, siblings, inside delegated tenants | its universe |
| Shared arbiters (mem/cache/IO) | *flattened* resource-class numbers of loaded ECs | the ownership tree, identities | system, cross-hart |
| Migration / mover (a parent) | source + dest `(hart#, vnum)` of the one EC; its ECS | sealed contents, siblings | two harts, via RAM only |
| Secure enclave | its own contents | — (its owner cannot read it) | one EC |
| Debug module | everything | **must be gated** from live sealed contents | system |

### 11.1 Isolation invariants (defined by absence)

The properties most worth verifying are negative — a test suite that exercises only the
positive paths will pass while the system is broken:

1. **Sibling ↔ sibling**: a context cannot name, switch to, inspect, or affect a sibling
   under the same parent.
2. **Upward opacity**: a context cannot learn its absolute slot, its parent's identity,
   or anything at `vnum 0` other than "self".
3. **Cross-hart software**: a context on one hart observes nothing of another hart's
   arrays; the only shared channel is RAM.
4. **Delegation boundary**: after a subtree is delegated to a tenant, the parent's other
   children cannot reach into it except through the chain.

---

## 12. Secure enclaves — the one inverted edge

A secure enclave is simply an ECID whose bank is **sealed** (`bk.iv`). It is the one
place where the normal parent→child relationship is **inverted**: the owner retains
control of the enclave's **existence** (it can schedule and force-destroy it) but
**cannot read its contents**. Every other edge in the tree keeps the usual "an owner can
inspect what it owns"; this one edge revokes inspection while keeping lifecycle control.
This matches the established confidential-computing model (and the RISC-V CoVE
direction), in which the host manages a confidential guest's lifecycle and resources but
cannot see its data.

Sealing alone (properties: confidentiality, integrity, sealing) is necessary but not
sufficient for certification against hardware-DRM / confidential-computing schemes; those
also require **attestation** (proving to a remote party what code runs on a genuine
hardware root of trust) and a **measured-boot root of trust**. A CE attestation primitive
or firmware role is required in addition to `bk.iv` / `bk.ov`. **Debug** is reconciled
with certifiability by gating it at this edge only — lifecycle-fused lockout,
scrub-on-attach, or authenticated debug — so debug sees everything *except* live sealed
contents. Migration of a sealed context must spill the *sealed* form and is deferred
until specified.

---

## 13. Invariants (summary)

- Ownership is always encoded **child → parent** by a single up-pointer.
- Root is slot 0 and points to itself.
- A slot is **free iff `ecs == null`**. Anything reused is zeroed by hardware (§3.2).
- Every context is **0 in its own universe**; `vnum = 0` is self and is never delegable.
  ECID children are numbered from 1. Banks carry no software-visible handle (§9.3): they
  are given as "a free one" and reclaimed only by destroying their owner.
- Any ECID that holds banks **uses one for itself** — a banked scheduler needs its own
  bank to guarantee sub-10-cycle switching to the realtime work beneath it. With CE
  enabled, root has its own bank; the rule holds at every level.
- Bank reclamation is **only on teardown** — a running ECID never surrenders a bank, just
  as a running CPU cannot give back its register file. No standalone `bk.oe`.
- Nesting depth `0 ≤ L ≤ D ≤ 3`, making all upward walks O(1).
- Fast path (`ec.ib`, `ec.ob`) is O(1), 1–3 cycles: an up-pointer ownership check plus, for
  switching to a child by vnum, one read of the parent's forward index — a hart-local cache.
  The bankless RAM path (`ec.im`, `ec.om`) is fast but not realtime-bounded.
- Slow path (allocation, delegation, teardown, enumeration) may scan: ≤ O(N log N).
- A **Group** has two halves: a backward view (records pointing at an owner — free) and a
  forward index (a parent's `vnum → slot` map — a hart-local cache, built while the parent
  runs, never written to memory).
- The forward index and the `[hart#, vnum]` tuple are **CE-private**: the index never
  reaches addressable memory, and `[hart#, vnum]` is authoritative in the array (vnum is
  stored, hart is implied by which array). The ECS may mirror the tuple for software only.
- Identity is the **ECS in RAM**; slot numbers are hart-local; banks never migrate.
- Optional generation counters make freed-and-reused slots safe against stale *remembered*
  references; not needed for integrity, since hardware is the arrays' only writer.

---

## 14. Open questions / decisions pending

Resolved during this design pass (recorded here so they are not reopened by accident):
the `ec.ob` target is named by **vnum**, translated by the parent's forward index (§5.2),
so software never handles an absolute slot; the tenant family delegates **unused ECIDs
only**, never a populated subtree (§9.2); banks are given by **`bk.ie`** ("a free one", by
CSR count) and sealed via **`bk.iv` / `bk.ov`**; bank reclamation is **only on teardown**
— there is no standalone `bk.oe`, because a running ECID never surrenders a bank (§9.3);
ECID children are numbered **from 1** (0 = self), and banks carry **no software-visible
handle** at all (so their numbering base is moot); a separate forced-destroy
instruction was dropped because `ec.ot` already tears down a subtree (§9.2); the **ECS is a
fixed descriptor containing pointers to the variable parts**, with a per-instruction
**flat/descriptor mode bit** whose pairing is the OS's responsibility and whose worst
failure is self-corruption, never escape (§10.4); **`[hart#, vnum]` is authoritative in the
ECID array** (vnum stored, hart implied), optionally mirrored in the ECS for software; and
the **forward index is a hart-local cache, never written to memory**, built by the parent's
own ownership instructions and regenerated when it runs (§5.3, §10.4).

Still open:

- **ECS pointer / descriptor pointers: physical or virtual addresses?** Determines the
  dereference path and the pointer width (§3, §8.1, §10.4). A physical address is simplest
  and most deterministic for hardware; a virtual one is more flexible for the OS but pulls
  page-table translation onto the (non-realtime) `ec.im` / `ec.om` path.
- **`vnum` width / maximum fanout** per owner — sets the practical branching factor and,
  with `D`, defines what "supports N ECIDs" means for an implementation (a more honest
  capacity statement than a flat `2^k`). Choose together with `n` (§8.1). Also sets the
  size of the hart's current-children register that holds the forward index.
- **Free-list representation**: implicit scan for `ecs == null` vs. an explicit threaded
  list through free slots.
- **Attestation primitive / firmware role**: quote format and what it measures (§12).
- **Debug gating mechanism**: lifecycle fuse, scrub-on-attach, authenticated debug, or a
  combination (§12).

### 14.1 Numbering base (decided)

ECID children are numbered **1, 2, 3, …**, with `vnum = 0` reserved for self. This is the
natural human convention (no one calls their first child 0), it gives one unambiguous
number line per universe (0 always means "me"), and it makes "you cannot delegate
yourself" fall out for free — 0 is simply never a valid delegate operand. The only cost is
one subtraction if a forward index is stored zero-based internally, which is invisible to
software.

Banks (and, by the same reasoning, contracts) are different: they have no "self" entry to
reserve, and — as established in §9.3 — software never names a bank at all (giving is "a
free one" by CSR count; reclaiming is sweeping a destroyed owner's group). A thing software
never addresses needs no numbering convention, so the 0-vs-1 question does not arise for
banks. Any internal index is the hardware's private business. Banks are virtualized in the
same *spirit* as ECIDs should a future need ever surface a handle, but the baseline ISA
exposes none.

---

*End of chapter.*
