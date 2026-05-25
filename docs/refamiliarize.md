# CE Suite — Refamiliarize

**Purpose:** This document is what you read first when you come back to this
project after any break, planned or unplanned. It is *not* the architecture —
that lives in the Project Instructions (the charter) and Chapter 0. This
document is the on-ramp: it reminds you where you are, what you decided, and
what's next.

**Read order when coming back:**

1. This document (10–15 minutes). Gets your intuitions back.
2. The Project Instructions / Axiom Charter (20–30 minutes). The normative spine.
3. Chapter 0 — Fundamental Structure (20 minutes). The detailed model.

Only then start editing chapters.

---

## Part A — Where we are

### A.1 The project in one paragraph

The **CE Suite** is a set of five RISC-V extensions you've been designing
since (roughly) 2024, aimed at making RISC-V credible for hard real-time and
certifiable systems (ASIL D, DO-178C, FDA Class III). The core idea is to
move scheduling and resource management from non-deterministic software into
dedicated hardware, so that Worst-Case Execution Time becomes *provable*
rather than empirical. The five extensions compose: CME handles 1-cycle
context switches, CPE partitions caches, MSE arbitrates DRAM deterministically,
QoS does the same for I/O, and the ECID/Group substrate is the identity and
ownership layer that ties the other four together.

### A.2 The five extensions in one sentence each

- **CME — Context Management Extension.** Hardware-resident context banks
  per hart make context switches take 1–9 cycles instead of hundreds.
- **CPE — Cache Partitioning Extension.** Per-hart L1 and L2-private cache
  is sliced per ECID so noisy neighbors can't evict your hot lines.
- **MSE — Memory Scheduling Extension.** DRAM access is arbitrated by
  alternating best-effort and contract time slots, so RT contexts get
  bounded latency guarantees.
- **QoS — I/O Quality-of-Service Extension.** The same arbitration philosophy
  applied to the NoC, DMA, and peripheral interconnect.
- **ECID + Group/Contract substrate.** The shared identity and ownership
  layer that all four hang off. Not numbered as a sixth extension; it's the
  foundation defined in Chapter 0.

### A.3 Chapter status (as of v0.8 of the charter)

| Chapter | State | Next action |
|---|---|---|
| **Charter** (Project Instructions) | v0.8 — current | — |
| **Chapter 0** (Fundamental Structure) | Done — aligned to charter v0.8; `ec.oe` throughout | — |
| **Chapter 1** (Execution Context Model) | Done — ECID-first gateway chapter | — |
| **Chapter 2** (CME Instruction Set Reference) | Done — ECID operands, `ec.oe`, mnemonic scheme, per-extension subsets | — |
| **Chapter 3** (Bank/Group/Delegation Semantics) | Done — GroupID=ECID, reversal trick, delegation invariants | — |
| **Chapter 4** (HW Microarchitecture) | Done — EC[e] SRAM residency, radix-tree lookup path | — |
| **Chapter 5** (Linux Kernel Integration) | Done — pointer idioms framed as Linux conventions, not architectural | — |
| **Chapter 6** (CME Usage Examples) | Done — ECID-first operands, mnemonic scheme | — |
| **Chapter 7** (CPE Instruction Set Reference) | Done — `cp.ir`/`cp.or`; 16-bit ECID field confirmed; CPE subset `{r}` declared | — |
| **Chapter 8** (MSE) | Not drafted; rich material in `101-mse-scratchpad.md` and `102-mse-scratchpad2.md` | Write from scratch using the Contract model + alternating BE/contract slot scheme |
| **Chapter 9** (QoS) | Not drafted | Write after MSE; reuse arbitration philosophy |
| **Appendix A** (ECID) | Not converted | Convert scratchpad to proper appendix with radix tree algorithms and diagrams |

### A.4 What's been *decided* (locked in v0.7)

If a chapter you're reading contradicts any of these, the chapter is wrong:

1. **ECID = 16 bits**, hart-local, never global.
2. **`ecs_ptr` at offset 0** of `EC[e]`. Always.
3. **GroupID = ECID number.** No separate Group ID space.
4. **D ≤ 3.** Implementations may pick smaller (1, 2, or 3); zero means
   no delegation; D = 3 is the maximum allowed.
5. **No pools.** Anywhere. Resource scheduling uses Contracts directly.
6. **`ec.oe` is the forced-destroy instruction.** `ec.or` and `ec.od` are
   retired. The trailing `e`=existence: "take this EC out of existence."
7. **Generation counters** in `EC[e]` for ABA safety on slot reuse.
8. **No ECID migration across harts** — kernel rebinds, reusing ECS.
9. **ECID allocation via radix tree** with prefix ownership and per-prefix
   quotas. Kernel-side data structure; the architectural view is `EC[e]`.
10. **Instruction naming** is `{ec, cp, ms, qs}.{i, o}{target}` with target
    letters `b m s g t v e r`. No exceptions without a charter change.
11. **CE is opt-in.** Firmware can disable CE entirely. Any privilege level
    can ignore CE even when enabled.

### A.5 What's *open* (parked in §8 of the charter)

These are real questions you have not yet decided. They do not block work
on the rest of the spec. If a writing session tries to "resolve" one of
these, stop — that's a charter-level change.

1. NUMA-aware Contract assignment.
2. Whether a Contract can span multiple resource classes.
3. The software slow-path when hardware Contract slots are exhausted.
4. Cross-hart ECS sharing during migration handover.
5. UCS (Unified Context Structure) — kernel-side abstraction, not
   architectural; may become an optional appendix.
6. Secure Vault key derivation, attestation, rotation.
7. The CE-disable CSR name, bit layout, reset defaults, per-extension
   granularity.

### A.6 What's *next* (the suggested work order)

1. Read the charter; read Chapter 0; read this document. Don't edit yet.
2. **Refactor Chapter 1** to be the gateway. It's the chapter every reader
   sees first; getting it right pays compound interest.
3. **Refactor Chapter 2** to use ECID operands and add `ec.od`. This is
   where the most concrete drift happened in the past.
4. **Consolidate Chapter 0.** Pick one of the three drafts as the base
   (recommended: `Chapter0-fundamental-structure.md`), align it strictly
   with charter v0.7, retire the others.
5. **Then Chapter 3** (delegation), **Chapter 4** (microarch — use REVISED),
   **Chapter 5** (Linux), **Chapter 6** (examples). In that order.
6. **Then Appendix A** as a real document.
7. **Then write MSE** as its own chapter from the scratchpads.
8. **Then QoS** from the MSE template.
9. **Then Usage Examples chapters** for each extension (CME, CPE, MSE, QoS) — one
   session per chapter, after all instruction-set and semantics chapters are stable.
   Chapter 6 covers CME examples; equivalent chapters for CPE, MSE, and QoS do not
   yet exist.

Roughly: charter → Chapter 0 → Chapter 1 → instruction-reference chapters
→ semantics chapters → microarch → kernel → examples → appendix → MSE → QoS.

### A.7 Where things live

```
.
├── project_instructions.md          # the charter (this is the comb)
├── refamiliarize.md                  # this document
├── working_notes_for_authors.md     # workflow rules (not yet written)
└── sketches/
    ├── Chapter0-fundamentals/
    │   ├── Chapter0-fundamental-structure.md    # use this one as base
    │   ├── Chapter0-half-correct.md             # obsolete (has Pools)
    │   └── Chapter0-also-half-correct.md        # obsolete (v0.5 transitional)
    ├── Chapter1-Execution_Context_Model.md      # pre-ECID; refactor
    ├── Chapter2-CME_Instruction_Set_Reference.md  # uses pointers; refactor
    ├── Chapter3-Bank_Group_and_Delegation_Semantics.md  # 6-bit groups; refactor
    ├── Chapter4-Hardware_Microarchitecture_Overview-REVISED.md  # keep this one
    ├── Chapter4-Hardware_Microarchitecture_Overview.md          # obsolete
    ├── Chapter5-Linux_Kernel_Integration.md     # pointer-based; refactor
    ├── Chapter6-CME_Usage_Examples.md           # mostly fine, refresh
    ├── Chapter7-CPE_Instruction_Set_Reference.md  # nearly aligned
    ├── AppendixA-ECID.md            # scratchpad; convert to real appendix
    ├── 101-mse-scratchpad.md        # MSE design material
    ├── 102-mse-scratchpad2.md       # MSE BE/contract slot scheme
    ├── UCS.md                       # exploratory note; charter §8.6
    ├── CE-tree-of-truths.md         # axiom sketch; predates charter
    ├── Rewrite-Plan.md              # the old plan; superseded by charter §7.3
    ├── cme-instruction-reference-card   # quick reference; needs update
    └── working_with_chatgpt.md      # workflow lessons; merge into companion doc
```

---

## Part B — Concepts at a glance

This is the glossary from the charter, expanded with one paragraph of *why*
per concept. The point is to get your intuitions back, not just your
definitions.

### B.1 EC — Execution Context

The unit of computation the OS scheduler dispatches: a thread, a process,
a vCPU, a container task, an interrupt handler, a secure enclave. CE
treats all of these uniformly. *Why uniformly?* Because the hardware
machinery for saving register state, partitioning cache, and arbitrating
DRAM is the same regardless of what *kind* of scheduled work is running.
Treating them all as ECs lets the hardware story stay simple while the OS
keeps its higher-level distinctions.

### B.2 ECID — Execution Context Identifier

A hart-local, 16-bit, hardware-managed token. *Why hart-local?* Because
making ECIDs global would force cross-hart synchronization on every
context switch, which destroys the per-hart latency story. The system-
wide identity of a running EC is therefore the tuple `(hart_id, ECID)`,
but no hardware mechanism uses that tuple as a key — only software does.

*Why opaque to user code?* Because if software could read or write its
own ECID, it could forge access to other contexts' resources. Opacity is
the mechanism that turns ECID into an unforgeable capability.

*Why 16 bits?* 8 was too few once you have tenants owning prefix subtrees.
32 is wasteful when only the *currently runnable* ECIDs cost hardware
resources. 16 gives 65,536 per hart, which is far more than will ever
be simultaneously hart-bound.

### B.3 `current_ecid`

The ECID of whatever's running right now on a hart. Held in a CSR. *Why
a CSR?* Because every CME instruction that operates on "me" needs to
look up its own ECID in 1 cycle; a CSR is the only structure that
gives that latency. When you read about an instruction "consulting
`current_ecid` implicitly," that's the CSR being read.

### B.4 `EC[e]` — the EC array

Per-hart, conceptually an array of `EC_entry` structs indexed by ECID
number. `EC[e]` is the canonical descriptor of ECID `e`: it holds the
ECS pointer, generation counter, delegation level, parent ECID, and
whatever else the implementation chooses to cache.

*Why model it as an array?* Because the architectural lookup is then
`base + e * stride` — a single addition, computable in the same cycle
as the instruction issuing the lookup. The actual storage may be
hierarchical (SRAM cache of active entries, RAM-resident for the rest)
but the architectural view stays simple.

### B.5 ECS — Execution Context Structure

A RAM-resident structure with the *saved* register state, *metadata*,
*pointers to banks*, *contract descriptors*, and OS bookkeeping. Reached
via `EC[e].ecs_ptr` (at offset 0).

*Why have both `EC[e]` and ECS?* Because they serve different speeds.
`EC[e]` is small, fast, can live in SRAM, and holds just enough for the
hardware fast path. ECS is bigger, lives in RAM, and holds everything
needed for spill/fill, migration, and OS-level bookkeeping. The
fast-path `ec.ib`/`ec.ob` instructions touch only `EC[e]` and banks;
the DMA-path `ec.im`/`ec.om` touches ECS.

### B.6 Group

The inventory of resources owned by one ECID. *Every ECID has exactly
one Group; GroupID = ECID number.* The Group holds (or rather, is
reverse-referenced by) Banks, Contracts, and child ECIDs.

*Why "reverse-referenced"?* This is the **reversal trick**, the core
hardware-enforcement idea of the whole design. Resources carry up-
pointers to their owning Group; Groups don't maintain downward member
lists. When the hardware needs to check "does this hart's current ECID
own this bank?" it looks at the bank's up-pointer and compares — O(1).
If the Group held a member list, the hardware would have to search it —
O(N). The reversal makes hardware enforcement constant-time.

*Why GroupID = ECID?* Because every ECID has exactly one Group; carrying
a separate GroupID space would just add an indirection with no
information gain.

*Why does a child Group appear to its child ECID as Group 0?* Because
the child shouldn't be able to see, infer, or guess host-level Group
identifiers. Each delegation level renumbers its world to start at 0.
This is the same trick Linux namespaces use for PIDs in containers.

### B.7 Bank

A hardware register-state container. Non-VMT banks are 1 KB on RV64
(holding GPRs, FPRs, selected CSRs, SATP, CP) and 512 B on RV32. VMT
banks hold vector/matrix/tensor register files and scale with the
implementation's vector width.

*Why bother having dedicated hardware banks at all?* Because saving
and restoring register state to RAM takes hundreds of cycles. With
banks, the entire save/restore happens via on-chip SRAM with wide
buses and a staging-bank arrangement, getting you down to 1–9 cycles.
This is the foundation of the "1-cycle context switch" claim.

*Why non-VMT and VMT separately?* Because VMT banks are an order of
magnitude bigger than non-VMT banks (4 KB+ vs 1 KB), and a typical
workload may need many non-VMT banks but few VMT banks. Separating
them lets the implementation size each pool appropriately.

*Why does a bank store its Group ID rather than its ECID?* It's the
same thing (GroupID = ECID), but the convention is "Group ID" because
that's the abstraction level — resources belong to Groups, and Groups
happen to be 1:1 with ECIDs.

### B.8 Contract

A slice of a global, multiplexed resource. MSE Contracts hold memory
bandwidth/latency budgets; QoS Contracts hold I/O budgets; CPE
Contracts hold cache ways or percentages. A Contract has *exactly one*
owning Group at any time. Contracts can be split into child Contracts
that are strict subsets of the parent.

*Why Contracts and not Pools?* This was the big simplification. Pools
were an intermediate layer between ECIDs and Contracts — but in
practice every Pool always pointed to exactly one Contract, so the
Pool was redundant. Removing Pools cost nothing and clarified the model.

*Why "atomic admission"?* Because if you split a Contract and the
chip-global resource manager can't honor the split, you must end up
with the same state as if you hadn't tried. Half-applied splits are
a worse failure mode than outright rejection. So the arbitration is
atomic: succeed-and-commit, or fail-and-no-change.

*Why bound Contract trees by D?* Because every level of Contract
delegation corresponds to a virt level (L0 host → L1 hypervisor → L2
nested hypervisor → L3 guest), and four levels is already more than
real cloud nesting ever needs.

### B.9 Delegation level L and the cap D

Every ECID has a delegation level `L`, between 0 and the implementation's
cap `D` (where D ≤ 3). If `L < D`, that ECID may create child ECIDs and
delegate Banks and Contracts to them. If `L = D`, it can still bind
resources for itself but can't delegate further.

*Why have a cap at all?* Because unbounded delegation chains make
forced revocation a tree walk of unbounded depth. Bounding D to 3
makes the walk O(log N) with a tiny constant. *Why specifically 3?*
Because the realistic virt depth in any production system is at most
L0 → L1 → L2 → L3 (host → hypervisor → nested hypervisor → guest).
Deeper than that is theory, not engineering.

### B.10 Generation counter

A small counter in each `EC[e]` slot, incremented every time the slot
is reused. Software that holds a reference to a `(hart_id, ECID, generation)`
triple can detect that the ECID it was tracking has been freed and
reallocated — the generation no longer matches.

*Why bother?* Classical ABA problem. Imagine the kernel queues a
delivery to ECID 42, then ECID 42 dies, then a brand new context gets
ECID 42 (because slot reuse is allowed). Without a generation counter,
the queued delivery would go to the wrong target. With one, the
mismatch is detectable.

### B.11 The radix tree

The kernel-side data structure that backs ECID allocation. Each tree
node represents an ECID prefix owned by a tenant or privileged context;
allocations within a prefix don't need global coordination; forced
revocation of a whole tenant is a subtree walk.

*Why a radix tree?* Three reasons. First, scalability: tenants own
subtrees, so there's no global ECID allocator. Second, isolation:
a tenant can never touch ECIDs outside its prefix. Third, fast
revocation: killing a tenant means walking its subtree and reclaiming
every resource — O(log N) on average.

*Why isn't the radix tree in the architectural model?* Because it's
a kernel-side structure, not hardware. The hardware sees `EC[e]`, an
array. The kernel-side radix tree happens to populate that array, but
hardware doesn't traverse the tree itself.

### B.12 Disable / ignore

CE is opt-in at every level. Firmware can disable CE entirely (then all
CE CSRs read zero and all CE instructions trap as illegal). Any
privilege level can ignore CE even when it's enabled (run a stock
non-CE kernel). When CE is enabled, M-mode firmware creates the first
ECID at boot and hands it to the kernel; the kernel may use it, delegate
further, or ignore it.

*Why this matters:* For testing. If you suspect CE is involved in a
kernel bug, boot with CE off and see if the bug persists. This kind of
"can I make the new feature go away" property is critical for adoption.
A new RISC-V extension that can't be disabled won't get into shipping
systems.

---

## Part C — Things to remember when you come back

These are not technical decisions. They are habits.

### C.1 The comb is the comb

When in doubt, the Project Instructions win. If you find yourself reading
a chapter that contradicts the charter, the chapter is wrong, not the
charter. Don't try to argue with the charter mid-chapter-edit — flag it,
finish what you were doing, then go through a separate "charter revision"
pass.

### C.2 One chapter per session

This is in `working_with_chatgpt.md` and it applies equally to working
with me. Working on multiple chapters at once is how chapters quietly
corrupt each other. Do one chapter, commit, end the session, start fresh.

### C.3 Don't let me sweep

"Let me harmonize the terminology across all chapters in one pass" is
the operation that has historically broken everything. It's tempting
because it sounds efficient. It is not. Do it chapter by chapter, with
the charter in front of each one, committing between each one.

### C.4 Use git

If you're not using git, your next ChatGPT-style disaster is
unrecoverable. With git, "this session corrupted three files" is
`git reset --hard`. Without git, it's "I have lost weeks of work."
This is the single most important workflow lesson from the previous
hiatus.

### C.5 Open items stay open

If a writing session tries to resolve an item in §8 of the charter,
stop. Charter-level changes get their own session, their own version
bump, their own changelog entry. They do not happen as a side effect
of editing a chapter.

### C.6 You knew more than you remember

The earlier `working_with_chatgpt.md` document said something true:
"If ChatGPT starts to 'go bad' (confusion, forgetting, errors), stop
and reset with a new chat or session." Same applies to me. If you find
yourself doubting the conversation, end the session and start a fresh
one with this document, the charter, and Chapter 0 as the opening
context. You won't lose progress; you'll regain clarity.

---

*End of Refamiliarize.*
