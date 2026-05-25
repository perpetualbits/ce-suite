# Chapter 1 — Execution Context Model

## 1.1 Why this architecture exists

Modern SoCs run mixed workloads: real-time motor controllers, safety monitors,
hypervisors, and general-purpose operating systems, often on the same die. The
problem is that none of these workloads can give the others hard guarantees.
Context switches take hundreds of cycles because register state must be
flushed to RAM. Cache lines belonging to a latency-sensitive task get evicted
by a batch job. DRAM arbitration is first-come-first-served, so worst-case
memory latency is unbounded in the presence of even one greedy neighbor.

The CE Suite addresses this at the hardware level. It is a set of five
coordinated RISC-V extensions:

- **CME** (Context Management Extension) — hardware-resident register-state
  containers per hart; 1–9 cycle context save/restore.
- **CPE** (Cache Partitioning Extension) — per-ECID partitioning of L1 and
  L2-private caches, so one context cannot evict another's hot lines.
- **MSE** (Memory Scheduling Extension) — deterministic DRAM arbitration with
  alternating best-effort and contract time slots; per-context bandwidth and
  latency classes.
- **QoS** (I/O Quality-of-Service Extension) — the same arbitration philosophy
  applied to the NoC, DMA, and peripheral interconnect.
- **The ECID and Group/Contract substrate** — the identity and ownership layer
  that all four extensions hang off. Not a separately-numbered extension; it is
  the shared foundation defined in Chapter 0 and explained in this chapter.

Together the goal is provable Worst-Case Execution Time and certifiability at
ASIL D / DO-178C / FDA Class III levels, at an estimated 5–15% transistor
overhead per core.

This chapter is the conceptual introduction. It explains what each core object
is and why the design is shaped the way it is. Byte-level layouts are in
Chapter 0. Instruction definitions are in Chapter 2.

---

## 1.2 Execution Contexts

An **Execution Context (EC)** is any schedulable unit the OS dispatcher
handles: a thread, a process, a vCPU, a containerized task, an interrupt
handler, a secure enclave. CE treats all of these uniformly, because the
hardware machinery for saving register state, partitioning cache, and
arbitrating DRAM is the same regardless of what kind of work is running.
Uniform treatment keeps the hardware story simple while allowing the OS to
maintain whatever higher-level distinctions it needs.

---

## 1.3 The Execution Context Identifier (ECID)

Every EC running on a hart is assigned an **Execution Context Identifier
(ECID)**. The ECID is the token the hardware uses to enforce ownership,
track resources, and drive the fast context-switch path.

Four properties define what an ECID is:

**Hart-local.** An ECID is meaningful only on the hart that issued it. The
system-wide identity of a running EC is the tuple `(hart_id, ECID)`, but no
hardware mechanism uses that tuple as a key — it is a software convention.
Making ECIDs global would force cross-hart synchronization on every context
switch, which would destroy the per-hart latency story.

**Opaque to user code.** A process cannot read or write its own ECID. The OS
may know it; the EC running as that ECID cannot. Opacity is what turns the
ECID into an unforgeable capability: a user process that cannot observe its
own ECID cannot forge a reference to another context's resources.

**Privileged creation only.** Only M-mode firmware, an S-mode kernel, or an
HS-mode hypervisor may create or destroy ECIDs. When CE is enabled at boot,
M-mode firmware creates the first ECID and hands it to the kernel. The kernel
may use it, delegate from it, or ignore CE entirely. User mode never creates
or destroys ECIDs.

**16-bit width, per hart.** ECID numbers are 16 bits, giving 65,536 ECIDs per
hart. This is not the same as a process identifier. A PID names a long-lived
OS abstraction that may be suspended, blocked on I/O, or checkpointed to disk.
An ECID names a context *currently bound to a specific hart*. Most OS-level
tasks at most moments are not hart-bound; a task acquires an ECID at dispatch
and releases it when switched out. The OS multiplexes many PIDs through a
small number of ECIDs, the same way it multiplexes many PIDs through a small
number of harts. On a 256-hart server, 16 bits per hart × 256 harts gives
16 million simultaneously hart-bound contexts — well past anything a real
operating system runs concurrently.

**No migration across harts.** When the scheduler moves an EC from one hart to
another, the kernel does not move the ECID. It unbinds the ECID on the source
hart, allocates a fresh ECID on the destination hart, and reuses the same
in-memory execution context structure. Migration is rebinding, not literal
ECID movement.

**Generation counters and ABA safety.** When an ECID slot is freed and later
reallocated, its generation counter is incremented. Software that holds a
reference to a `(hart_id, ECID, generation)` triple can detect that the ECID
it was tracking has been freed and a new context has taken the slot. Without
generation counters, a queued delivery to ECID 42 could silently reach a
brand-new context that happened to be assigned number 42 after the original
was destroyed.

---

## 1.4 The EC Array: `EC[e]`

Each hart has a conceptual array `EC[0..E_max]` indexed by ECID number. `EC[e]`
is the canonical hardware descriptor for ECID `e` on that hart. It holds, at
minimum, a pointer to the Execution Context Structure in RAM, the generation
counter, the delegation level, and the parent ECID.

The pointer to the Execution Context Structure is **always at offset 0** of
`EC[e]`. This constraint means the most common hardware operation — fetching the
ECS pointer for a given ECID — is a single load from a base address plus a
stride:

```text
entry_addr(e) = cme_ec_table_base + e * stride
ecs_ptr(e)    = *(entry_addr(e))        // offset 0
```

Why model it as an array? Because the lookup then reduces to a single addition,
computable in the same cycle as the instruction issuing it. The physical storage
may be hierarchical — a small SRAM holding the currently active entries, backed
by a RAM-resident table for the rest — but the architectural view stays flat.
The fast-path instructions (`ec.ib`, `ec.ob`) touch only SRAM-resident entries;
the DMA-path instructions (`ec.im`, `ec.om`) may walk the RAM-resident table.

The full structure of `EC[e]` and the `cme_ec_table_base` CSR are defined in
Chapter 0, §0.2 and §0.3.

---

## 1.5 The Execution Context Structure (ECS)

The **Execution Context Structure (ECS)** is a RAM-resident data structure
reachable via `EC[e].ecs_ptr`. It holds the saved register state for contexts
not currently in a bank, metadata (privilege level, flags, scheduling
information), pointers to banks, contract descriptors, and OS bookkeeping
fields.

Why have both `EC[e]` and ECS? Because they serve different speeds. `EC[e]`
is small — on the order of tens of bytes — and can live in SRAM. A context
switch on the fast path touches `EC[e]` and the banks directly without ever
reading ECS. ECS is larger and lives in RAM; it is read during the slower DMA
path, during migration, and for OS-level bookkeeping. Keeping them separate
lets the fast path stay fast.

The ECS layout is a kernel software convention. The CME instruction set takes
ECID numbers as operands, not pointers to ECS or any other structure. Chapter 5
describes how Linux represents ECS as `struct execution_context` and how that
address is stored in `EC[e].ecs_ptr`, but this is a Linux convention, not an
architectural requirement.

---

## 1.6 Groups

Every ECID `e` has exactly one **Group**, and the Group's identifier equals
the ECID number: **GroupID = ECID**. The Group is the ECID's inventory of
resources — the Banks, Contracts, and child ECIDs that belong to it.

The Groups do not maintain explicit downward membership lists. Instead,
resources carry **up-pointers** to their owning Group. When hardware needs to
check "does the currently running ECID own this bank?" it reads the bank's
up-pointer and compares it to `current_ecid`. That is one load and one
comparison: O(1). If Groups held member lists, the hardware would have to
search them: O(N). The reversal — resources point up, Groups do not point down
— makes ownership enforcement constant-time.

Why GroupID = ECID? Every ECID has exactly one Group; a separate Group ID space
would add an indirection with no information gain.

When an ECID delegates resources to a child ECID, the child receives its own
Group. From the child's perspective, its Group appears as Group 0. The child
cannot observe the host-level GroupID. This is the same isolation trick Linux
namespaces use for PIDs inside containers: each delegation level renumbers its
world to start at zero.

---

## 1.7 Banks

A **Bank** is a hardware register-state container. There are two kinds:

**Non-VMT banks** hold general-purpose registers, floating-point registers,
selected CSRs, the supervisor address translation register (SATP), and cache
partition configuration (CP). On RV64 a non-VMT bank is 1 KB; on RV32, 512 B.
The exact field layout is in Chapter 0, §0.4.

**VMT banks** hold vector, matrix, and tensor register files. Their size scales
with the implementation's vector width and is typically much larger than a
non-VMT bank. VMT banks are fewer in number than non-VMT banks for exactly
this reason.

Why have dedicated hardware banks at all? Because saving and restoring register
state to RAM takes hundreds of cycles. With banks, the entire save/restore
happens via on-chip SRAM over wide parallel buses, getting the operation down
to 1–9 cycles. That is the foundation of CME's fast context-switch claim.

Every Bank stores the GroupID of the Group it belongs to (equivalently, the
ECID number of its owner). Banks are never shared between ECIDs simultaneously.
The fast context-switch path (`ec.ib`, `ec.ob`) touches only banks and
`current_ecid`; ECS is not involved.

---

## 1.8 Contracts

A **Contract** is a slice of a global, multiplexed resource:

- **MSE Contracts** allocate memory bandwidth and latency guarantees.
- **QoS Contracts** allocate I/O and NoC bandwidth and latency guarantees.
- **CPE Contracts** allocate cache ways or a fraction of cache capacity.

Three properties define how Contracts work:

**Single ownership.** A Contract has exactly one owning Group at any moment.
Ownership can be transferred, but not duplicated. This is what makes guarantees
binding: if bandwidth is allocated, no other context can use it.

**Hierarchical splitting.** A privileged actor may split a Contract into child
Contracts. Each child is a strict subset of its parent; the sum of all children
never exceeds the parent's allocation. A cloud provider can hold a top-level
Contract, carve off a sub-Contract for a tenant, and the tenant can carve off
further sub-Contracts for its VMs.

**Atomic admission.** Splitting or binding a Contract requires chip-global
hardware arbitration that succeeds or fails atomically. On failure, no state
is changed. Half-applied splits are a worse failure mode than outright
rejection — atomic semantics prevent them.

Why Contracts and not Pools? Earlier drafts placed a Pool layer between ECIDs
and Contracts. Every Pool always pointed to exactly one Contract, making the
Pool redundant. Removing Pools collapsed the model without losing anything.

---

## 1.9 Delegation

Every ECID has a **delegation level** `L`, stored in `EC[e]`. The
implementation exposes a cap `D` (at most 3) via a read-only CSR:

- **`L < D`**: this ECID may create child ECIDs and delegate Banks and
  Contracts to them.
- **`L = D`**: this ECID may bind resources for its own use but may not
  delegate further.

The cap D ≤ 3 is not arbitrary. It matches the realistic depth of nested
virtualization: L0 host kernel → L1 hypervisor → L2 nested hypervisor → L3
guest. Deeper nesting exists in theory but not in production. Bounding D to 3
also bounds the worst-case depth of a forced revocation tree walk.

Forced revocation — destroying an ECID and all its descendants, reclaiming all
their resources — must always succeed. A destroyed EC cannot stall its own
reclamation. The instruction `ec.oe` provides this guarantee; its semantics are
defined in Chapter 2.

ECID allocation uses a kernel-side radix tree that provides prefix ownership
and per-prefix quotas. The architectural view of ECIDs is still `EC[e]`; the
radix tree is a kernel data structure that populates it. The allocation and
forced-revocation algorithms are in Appendix A.

---

## 1.10 CE is opt-in

CE imposes no obligation on software.

**Firmware disable.** The BIOS or M-mode firmware may disable CE entirely.
When CE is disabled, all CE CSRs read as zero (or the implementation-defined
"unimplemented" pattern) and all CE instructions trap as illegal. The system
behaves as a standard RISC-V system. This is essential for isolating kernel
bugs: if a bug is suspected to involve CE, boot with CE off and check whether
it persists.

**Privileged ignore.** Even when CE is enabled, any privilege level may choose
to ignore it. An OS or hypervisor may run an entirely conventional kernel and
userspace without issuing any CE instructions. The hardware enforces no
obligation to use CE.

**Boot sequence.** When CE is enabled, M-mode firmware creates the first ECID
and passes it to the kernel. The kernel may use it, delegate from it, or ignore
it. All are conforming behaviors.

This opt-in property applies uniformly across all five extensions: CME, CPE,
MSE, QoS, and the ECID substrate.

---

## 1.11 Where to go next

**Chapter 0** contains the normative byte-level layouts: the `EC[e]` entry
structure, the Bank field layouts for RV32 and RV64, the Context Restore Mask
encoding, and the ECS header. Read Chapter 0 before working with instruction
semantics.

**Chapter 2** defines the CME instruction set: `ec.ib`, `ec.ob`, `ec.im`,
`ec.om`, `ec.oe`, and the rest. Instruction operands are ECID numbers and
masks; the encoding follows Chapter 0 §0.9.

**Appendix A** contains the radix-tree data structure and the ECID allocation,
delegation, and forced-destruction algorithms.
