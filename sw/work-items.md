<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite Linux — Work Items

**Purpose:** Tracks every Linux kernel patch needed for CE Suite support,
from boot-time detection through upstream submission.

**Prerequisite:** CE Suite QEMU Phases 1–10 (`../qemu/work-items.md`) must
be complete before kernel work starts. The QEMU build is the development
and test target throughout.

**Relationship to spec:**
- Context switch: ch03 §3.1 (`ec.ib`/`ec.ob`), ch05 §5.1–§5.4
- ECID allocator: ch00 §0.2, Appendix A
- SMP migration: ch03 §3.2, ch17 §17.5
- Interrupt handling: ch18
- KVM: ch14 §14.8
- SCHED_DEADLINE + MSE: ch05 §5.7
- Power gating: ch04 §4.14

---

## ⚑ Current priority — Phase 1 (SBI interface decision)

L1 is a design decision that blocks everything else. Resolve it before
writing a single line of kernel code.

---

## Phase 1 — Boot interface and detection

### L1 · Resolve: SBI interface for ce_ctrl

**What:** `ce_ctrl` (0x7D0) is M-mode only. Linux (S-mode) cannot write it
directly. Two options:

**Option A — Firmware pre-enables CE Suite.**
Firmware sets `ce_ctrl` before booting Linux (per ch14 §14.9 boot sequence).
Linux reads `ce_present` (0xFD0) to discover what is available. No new SBI
extension needed. Simpler; gives firmware full control over which extensions
are enabled per hart.

**Option B — New SBI extension (`SBI_EXT_CE`).**
Linux calls `sbi_ce_enable(hart_id, extension_mask)` to enable individual CE
extensions. Gives the OS more dynamic control (e.g., enable MSE only when
SCHED_DEADLINE tasks are present). More flexible; requires OpenSBI changes.

**Recommendation:** Start with Option A. It matches the boot sequence in
ch14 §14.9, requires no OpenSBI changes, and can be upgraded to Option B
later if dynamic enable/disable is needed.

**Deliverable:** Decision recorded here and in `sw/README.md`; proceed to L2.

**Status:** ☐

---

### L2 · ISA string parsing for CE Suite names

**What:** Add parsing for `xce`, `xcecme`, `xcecpe`, `xcemse`, `xceqos` in
`arch/riscv/kernel/cpufeature.c` (or the equivalent for the kernel version
being targeted). Add `RISCV_ISA_EXT_CE*` feature bits.

**Files:** `arch/riscv/include/asm/hwcap.h`, `arch/riscv/kernel/cpufeature.c`

**Spec ref:** ch16 §2 (ISA string names)

**Depends on:** L1

**Status:** ☐

---

### L3 · ce_present CSR probing

**What:** At boot (after firmware enables CE Suite per L1), probe `ce_present`
(0xFD0) with a trap handler to distinguish CE-absent from CE-disabled from
CE-present. Set per-CPU feature flags accordingly.

**Files:** `arch/riscv/kernel/cpufeature.c` or `setup.c`

**Spec ref:** ch16 §4.1 (M-mode boot probe sequence — adapt for S-mode)

**Depends on:** L1, L2

**Status:** ☐

---

### L4 · Read and cache capability CSRs

**What:** At boot, read `cme_del_cap` (0xFC1), `cme_bank_count` (0xFC2),
`cpe_caps` (0xFC5), `mse_slot_ns` (0xFC7), `qos_domain_count` (0xFCB). Cache
in per-CPU boot data. These are M-mode RO CSRs that firmware published; Linux
S-mode reads them once and stores them for later use.

**Files:** New `arch/riscv/include/asm/ce.h`, `arch/riscv/kernel/setup.c`

**Spec ref:** ch13 §1, ch14 §14.9 ("publish capability CSRs in shared memory")

**Depends on:** L3

**Status:** ☐

---

## Phase 2 — Task and ECID infrastructure

### L5 · Design decision: ce_context in task_struct

**What:** Decide what CE-related fields live in `task_struct` vs. a separate
`struct ce_context` pointed to from `task_struct`:

```c
struct ce_context {
    u16  ecid;           /* ECID bound on the current hart, or 0 */
    u8   bank_slot;      /* index of the bank currently holding this task */
    void *ecs;           /* ECS in kernel memory (EC[ecid].ecs_ptr) */
    u16  parent_ecid;    /* delegation parent (kernel's root ECID) */
    /* CPE, MSE, QoS Contract descriptors: added in later phases */
};
```

**Deliverable:** Agreed struct layout, added as a stub to `task_struct`
(field pointer, allocated lazily on first CE use). Decision recorded here.

**Spec ref:** ch05 §5.2 (Linux representation of ECS)

**Depends on:** L4

**Status:** ☐

---

### L6 · ECID radix-tree allocator

**What:** Implement the kernel-side ECID radix tree (Appendix A). Key
operations:
- `ecid_alloc(parent_ecid, leaf)` — allocate a child ECID
- `ecid_free(ecid)` — free an ECID and its subtree
- `ecid_set_quota(prefix, max_resourced)` — set per-prefix quota

The allocator is per-hart (ECID numbers are hart-local). Each CPU has its
own allocator rooted at the kernel's ECID for that hart.

**Files:** New `arch/riscv/kernel/ce_ecid.c`, `arch/riscv/include/asm/ce_ecid.h`

**Spec ref:** ch00 §0.2 (ECID allocation), Appendix A (algorithms)

**Depends on:** L5

**Status:** ☐

---

### L7 · ECS allocation and setup

**What:** Allocate an ECS for each CE-enabled task. The ECS is a kernel
memory region whose physical address is written to `EC[ecid].ecs_ptr` via
`cme_ec_table_base + ecid * stride`. Implement:
- `ce_ecs_alloc(task)` — allocate and zero-initialize ECS
- `ce_ecs_free(task)` — free ECS on task exit
- Wire into `copy_process()` and `do_exit()`

**Spec ref:** ch00 §0.4 (ECS), ch05 §5.2

**Depends on:** L6

**Status:** ☐

---

### L8 · Per-CPU kernel ECID (root ECID per hart)

**What:** At boot, each CPU allocates a root ECID (L=0) for the kernel
context. This ECID is the parent of all task ECIDs created on that CPU. It
holds the kernel's own bank (used during interrupt entry, context switch
overhead, etc.).

**Spec ref:** ch05 §5.3, ch14 §14.3

**Depends on:** L6, L7

**Status:** ☐

---

## Phase 3 — Context switch

### L9 · ec.ib / ec.ob in switch_to()

**What:** Replace (or augment) the current GPR/FPR save/restore in
`arch/riscv/kernel/process.c` and `entry.S` with CE bank operations:

```c
/* In __switch_to() */
if (riscv_has_extension_likely(RISCV_ISA_EXT_CECME)) {
    asm volatile("ec.ib x0, %0" :: "r"(CE_FULL_MASK));    /* save prev */
    write_csr(0xFC0_shadow, next->ce.ecid);                 /* conceptual */
    asm volatile("ec.ob x0, %0, %1" :: "r"(next->ce.ecid),
                                       "r"(CE_FULL_MASK)); /* restore next */
} else {
    /* existing software save/restore */
}
```

**Special case:** PC restore. `ec.ob` with the PC bit set jumps immediately;
the context-switch sequence must not set the PC bit for in-kernel switches.
PC is handled by the normal `ret` path.

**Files:** `arch/riscv/kernel/process.c`, `arch/riscv/kernel/entry.S`

**Spec ref:** ch03 §3.1, ch05 §5.4

**Depends on:** L8, QEMU Q13 (ec.ob working)

**Status:** ☐

---

### L10 · FPU and vector state via CE banks

**What:** Currently Linux manages FPU state lazily (`mstatus.FS` bits).
With CE banks, FPR groups are saved/restored as part of `ec.ib`/`ec.ob`
via the mask. This replaces the FPU switch in `fpu.S`.

For vector state (V extension), add `VEC` group (bit 2) to the CE mask
when the task has dirty vector state.

**Files:** `arch/riscv/kernel/fpu.S`, `arch/riscv/kernel/vector.c`

**Spec ref:** ch03 §3.7 (register mask), ch03 §3.1 (dirty-save mode — FPU analogy)

**Depends on:** L9

**Status:** ☐

---

### L11 · Dirty-save mode optimisation

**What:** Use `ec.ib x0, x0` (dirty-save mode, rs1=x0) instead of
`ec.ib x0, FULL_MASK` for interrupt handlers and kernel threads that only
touch GPRs. The dirty-group bitmap automatically limits the save to modified
groups, reducing interrupt latency for GPR-only ISRs.

**Spec ref:** ch03 §3.1 "Dirty-Save Mode", ch18 §18.4.2

**Depends on:** L9, L10

**Status:** ☐

---

## Phase 4 — Trap and exception handling

### L12 · CE_EXC_BANK_FAULT handler (cause 16)

**What:** Add a handler for the new CE exception cause 16
(`CE_EXC_BANK_FAULT`) in `arch/riscv/kernel/traps.c`. This is a hardware
bank SRAM error — non-recoverable. Trigger a kernel panic with CE-specific
diagnostic information from `cme_status`.

**Spec ref:** ch15 §15.3, ch15 §15.5.1

**Depends on:** L9

**Status:** ☐

---

### L13 · Bank exhaustion recovery in the context-switch path

**What:** `ec.ob` can return `CME_ERR_NO_BANK` (2) if the target task's
context was previously spilled and no bank is available to fill it. Handle
this in `__switch_to()`:
1. Select a victim task from the run queue.
2. Spill victim via `ec.im`.
3. Release bank via `ec.og`.
4. Retry `ec.ob` for the target.

This is the slow path; fast path (bank already resident) takes 1–9 cycles.

**Spec ref:** ch03 §3.1 "Bank Exhaustion Recovery", ch05 §5.4.2

**Depends on:** L9

**Status:** ☐

---

## Phase 5 — SMP: per-CPU management and migration

### L14 · Per-CPU ECID binding and unbinding

**What:** When a task is scheduled off a CPU, its ECID is unbound (the bank
remains but is not current). When scheduled onto a different CPU, a new ECID
must be allocated on the destination CPU and the ECS rebound. Implement:
- `ce_task_bind(task, cpu)` — allocate ECID, issue `ec.om` from ECS
- `ce_task_unbind(task, cpu)` — issue `ec.im` to ECS, free ECID

**Spec ref:** ch00 §0.2 "No migration across harts", ch05 §5.5

**Depends on:** L9, L13

**Status:** ☐

---

### L15 · Cross-hart migration fence sequence

**What:** When a task migrates from CPU A to CPU B, the kernel must follow
the normative fence sequence from ch17 §17.5:
1. CPU A: `ec.im` (spill to ECS), `FENCE W,W`, signal CPU B.
2. CPU B: acquire signal, `FENCE R,R`, `ec.om` (fill from ECS), bind ECID.

Integrate with the scheduler's CPU migration path.

**Files:** `arch/riscv/kernel/smpboot.c`, `kernel/sched/core.c`

**Spec ref:** ch17 §17.5

**Depends on:** L14

**Status:** ☐

---

### L16 · CPU hotplug: ec.im on CPU offline

**What:** When a CPU goes offline, all banked tasks on that CPU must be
spilled to their ECS before the CPU stops. Hook into the CPU hotplug
`CPUHP_AP_ONLINE_IDLE` teardown path.

**Spec ref:** ch04 §4.14 (power gating protocol), ch17 §17.3

**Depends on:** L14

**Status:** ☐

---

## Phase 6 — Interrupt handling

### L17 · ISR-EC pattern: per-vector ECID at boot

**What:** Allocate a dedicated ECID and bank for each interrupt vector (or
priority level) at boot, following the interrupt-EC pattern in ch18. Store
the ECID in per-vector data. The IRQ prologue swaps to the ISR bank; the
epilogue swaps back.

**Files:** `arch/riscv/kernel/irq.c`, interrupt controller drivers

**Spec ref:** ch18 §18.2–§18.4

**Depends on:** L8, L9

**Status:** ☐

---

### L18 · IRQ prologue/epilogue: ec.ib / ec.ob

**What:** In the interrupt entry assembly, before calling the C handler:
1. Save preempted ECID in `sscratch` (S-mode equivalent of `mscratch`).
2. `ec.ib x0, x0` — dirty-save mode (GPR-only for most ISRs).
3. `ec.ob x0, isr_ecid, FULL_MASK` — switch to ISR bank.

In epilogue: reverse the sequence. This gives the ISR its own register
state and CPE partition without software save/restore.

**Spec ref:** ch18 §18.4, ch18 §18.10

**Depends on:** L17

**Status:** ☐

---

### L19 · Nested interrupt support

**What:** Each interrupt priority level needs its own ISR ECID and bank.
Verify that the prologue/epilogue is re-entrant across nesting levels
(each level saves the preempted ECID in its own scratch CSR chain).

**Spec ref:** ch18 §18.7

**Depends on:** L18

**Status:** ☐

---

## Phase 7 — KVM integration

### L20 · VM entry: delegate ECID to vCPU

**What:** When KVM creates a vCPU, allocate an L=1 ECID (child of the host's
L=0 ECID on that hart). Assign banks and an MSE/CPE Contract. On VM entry:

```asm
ec.ib  x0, x0               /* save host context */
ec.ob  x0, vm_ecid, FULL    /* restore VM context */
csrw   hcme_ctrl, VS_EN     /* enable CE for this VM (if trusted) */
```

**Files:** `arch/riscv/kvm/vcpu.c`, `arch/riscv/kvm/vmid.c`

**Spec ref:** ch14 §14.8.2

**Depends on:** L9, L8

**Status:** ☐

---

### L21 · VM exit: save vCPU state

**What:** On VM exit, reverse the VM entry sequence: save vCPU CE state,
restore host state. Optionally clear `hcme_ctrl.VS_EN` for untrusted VMs.

**Spec ref:** ch14 §14.8.2

**Depends on:** L20

**Status:** ☐

---

### L22 · Nested virtualisation: L=2 ECID delegation

**What:** A guest hypervisor running in VS-mode may use CE Suite if `VS_EN=1`.
KVM must handle the case where the guest calls `ec.ir` to allocate L=2 ECIDs.
Verify that the delegation cap D prevents runaway nesting.

**Spec ref:** ch14 §14.8.3

**Depends on:** L21

**Status:** ☐

---

## Phase 8 — CPE: cache partitioning

### L23 · CPE: per-task partition assignment

**What:** Add CPE Contract management to `ce_context`. When a task is
assigned to a CPE partition (via cgroup or direct API), call `cp.ir` to
create the Contract and store the descriptor. The Contract is loaded into
hardware on `ec.ob` (the CP field of the bank carries the partition mask).

**Files:** `arch/riscv/kernel/ce_cpe.c` (new)

**Spec ref:** ch07 §7.4–§7.6

**Depends on:** L9

**Status:** ☐

---

### L24 · CPE: cgroup/cpuset integration

**What:** Expose CPE partition assignment through the cgroup `cpuset`
subsystem (or a new `ce` cgroup controller). Tasks in a cgroup share a
CPE partition. Partition is assigned at cgroup creation, released at
cgroup teardown.

**Files:** `kernel/cgroup/cpuset.c` or new `kernel/cgroup/ce.c`

**Spec ref:** ch05 §5.6 (conceptual), ch07

**Depends on:** L23

**Status:** ☐

---

### L25 · CPE: RT-task dedicated partition

**What:** Real-time tasks (`SCHED_FIFO`/`SCHED_RR`/`SCHED_DEADLINE`) should
optionally receive a dedicated CPE partition to prevent cache eviction by
non-RT tasks. Add a scheduler hook that calls `cp.ir` when a task transitions
to a real-time class.

**Spec ref:** ch05 §5.7.6

**Depends on:** L24

**Status:** ☐

---

## Phase 9 — MSE: memory scheduling

### L26 · MSE: per-task Contract lifecycle

**What:** Add MSE Contract management to `ce_context`. `bw_class` and
`lat_class` are stored in the bank's CP field and loaded automatically by
`ec.ob`. Implement:
- `ce_mse_assign(task, bw_class, lat_class)` → calls `ms.ir`
- `ce_mse_revoke(task)` → calls `ms.or`

**Files:** `arch/riscv/kernel/ce_mse.c` (new)

**Spec ref:** ch09 §9.4, ch05 §5.4

**Depends on:** L9

**Status:** ☐

---

### L27 · MSE: SCHED_DEADLINE admission integration

**What:** Two-phase admission at `sched_setattr()` for SCHED_DEADLINE tasks:
1. CPU feasibility check (existing CBS model).
2. DRAM bandwidth check: map `runtime`/`period` + peak bandwidth to
   `bw_class`/`lat_class`, call `ms.ir`, handle `MSE_ERR_SYSTEM_FULL`.

Return `EBUSY` if either phase fails.

**Files:** `kernel/sched/deadline.c`

**Spec ref:** ch05 §5.7.2–§5.7.3

**Depends on:** L26

**Status:** ☐

---

### L28 · MSE: cgroup bandwidth caps

**What:** Parent ECID `bw_cap` field enforces per-cgroup memory bandwidth
limits. When a cgroup is created, allocate a parent ECID and call `ms.ir`
with the cgroup's bandwidth budget. Child task ECIDs inherit as L=1 children.

**Files:** `kernel/cgroup/ce.c` (new or extend from L24)

**Spec ref:** ch05 §5.7.5

**Depends on:** L26, L24

**Status:** ☐

---

## Phase 10 — QoS: I/O quality of service

### L29 · QoS: domain discovery and mapping

**What:** At boot, read `qos_domain_count` (0xFCB) and `qos_domain_base`
(0xFCC). Walk the domain descriptor array to enumerate I/O QoS domains and
their parameters (`slot_ns`, CN budget). Expose via sysfs or DT.

**Spec ref:** ch11 §11.3, ch13 §6.1–§6.2

**Depends on:** L4

**Status:** ☐

---

### L30 · QoS: per-task I/O Contract

**What:** Add QoS Contract management to `ce_context`. When a task is
assigned I/O bandwidth on a given domain, call `qs.ir`. Implement
`ce_qos_assign(task, domain_id, bw_class, lat_class)` and
`ce_qos_revoke(task, domain_id)`.

**Spec ref:** ch11 §11.6–§11.7

**Depends on:** L26 (follows MSE pattern), L29

**Status:** ☐

---

### L31 · QoS: driver integration

**What:** DMA-capable drivers that want bandwidth guarantees call
`ce_qos_assign()` for the relevant domain before starting transfers.
This is driver-specific work; start with a reference driver (e.g., a
synthetic test device) before integrating real peripheral drivers.

**Spec ref:** ch11 §11.10

**Depends on:** L30

**Status:** ☐

---

## Phase 11 — Power management

### L32 · CPU idle: spill all banks before SRAM power-gate

**What:** Hook into `cpuidle` to spill all banked ECIDs on a CPU before
that CPU's CE SRAM can be power-gated. Follow the normative sequence from
ch04 §4.14: `ec.im` for every banked ECID, `FENCE W,W`, then allow power
gate. On wake: `ec.om` for each ECID before the first `ec.ob`.

**Files:** `drivers/cpuidle/cpuidle-riscv-sbi.c` or equivalent

**Spec ref:** ch04 §4.14

**Depends on:** L16

**Status:** ☐

---

## Phase 12 — Reporting and userland interface

### L33 · /proc/cpuinfo CE Suite entries

**What:** Add CE Suite feature reporting to `/proc/cpuinfo`:
- `ce_present` bits (CME/CPE/MSE/QoS)
- `cme_del_cap` (D value)
- `cme_bank_count` (NV and VMT bank counts)
- `mse_slot_ns` (DRAM slot duration)
- `qos_domain_count`

**Files:** `arch/riscv/kernel/setup.c` or `proc.c`

**Depends on:** L4

**Status:** ☐

---

### L34 · Userland CE context API (optional for v1)

**What:** A minimal `prctl`-based or `ioctl`-based interface allowing
userspace to query its own ECID number (from `current_ecid` CSR, readable
in S-mode when `S_EN=1`) and optionally set CPE/MSE/QoS parameters for
real-time userspace threads.

**Spec ref:** ch14 §14.6.2 (S-mode current_ecid access)

**Depends on:** L23, L26, L30

**Status:** ☐

---

## Phase 13 — Testing

### L35 · Kernel selftests: CE Suite

**What:** A test suite under `tools/testing/selftests/riscv/ce/` covering:
- `test_detection.c` — probe `ce_present`, verify feature flags
- `test_context_switch.c` — fork, modify registers, verify isolation
- `test_ecid_alloc.c` — alloc/free ECIDs; verify quota enforcement
- `test_bank_exhaustion.c` — exhaust banks, verify recovery
- `test_migration.c` — pin task to CPU A, migrate to CPU B, verify state
- `test_cpe.c` — assign CPE partition, verify isolation (requires RTL or model)
- `test_mse.c` — SCHED_DEADLINE + MSE admission, EBUSY on over-admit

**Depends on:** Phases 3–11 complete

**Status:** ☐

---

### L36 · Boot CE-unaware distro without regression

**What:** A stock Debian or Fedora RISC-V image must boot unmodified on the
CE Suite QEMU build. CE Suite must be completely invisible to a non-CE kernel.

**Depends on:** L3, Phase 4 complete (trap handler must not fire spuriously)

**Status:** ☐

---

## Phase 14 — Documentation and upstream submission

### L37 · Documentation: arch/riscv/ce-suite.rst

**What:** Add `Documentation/arch/riscv/ce-suite.rst` covering:
- What CE Suite is (one paragraph, pointer to spec)
- How to detect it at runtime (`ce_present`)
- How the context switch works
- The ECID allocation model from Linux's perspective
- How to use CPE/MSE/QoS from kernel code
- Power management protocol
- KVM interaction

**Depends on:** Phases 3–12 complete

**Status:** ☐

---

### L38 · RISC-V Linux coding style compliance

**What:** Run `scripts/checkpatch.pl` on all CE Suite patches. Verify
naming conventions (`riscv_ce_*`, `ce_cme_*`, etc.) follow existing RISC-V
Linux conventions. Verify Kconfig options (`CONFIG_RISCV_CE`, `CONFIG_RISCV_CE_CME`,
etc.) follow the established pattern.

**Depends on:** L37

**Status:** ☐

---

### L39 · Submit patch series to linux-riscv mailing list

**What:** Send the CE Suite patch series to `linux-riscv@lists.infradead.org`
and `linux-kernel@vger.kernel.org`. CC the relevant subsystem maintainers
(scheduler for L27/L28, KVM for L20–L22, cgroup for L24/L28).

Coordinate with P6 (opcode allocation) — the kernel cannot use `custom-0`
indefinitely; a real opcode assignment should be underway before submission.

**Depends on:** L38, P6 (spec: opcode allocation)

**Status:** ☐

---

## Priority order

| # | Item | Phase | Depends on |
|---|------|-------|-----------|
| 1 | **L1** — SBI/firmware decision | 1 | — |
| 2 | **L2** — ISA string parsing | 1 | L1 |
| 3 | **L3** — ce_present probing | 1 | L1, L2 |
| 4 | **L4** — Cache capability CSRs | 1 | L3 |
| 5 | **L5** — ce_context design | 2 | L4 |
| 6 | **L6** — ECID radix-tree allocator | 2 | L5 |
| 7 | **L7** — ECS allocation | 2 | L6 |
| 8 | **L8** — Per-CPU kernel ECID | 2 | L6, L7 |
| 9 | **L9** — ec.ib/ec.ob in switch_to() | 3 | L8, QEMU Q13 |
| 10 | **L10** — FPU/vector via CE banks | 3 | L9 |
| 11 | **L11** — Dirty-save optimisation | 3 | L10 |
| 12 | **L12** — CE_EXC_BANK_FAULT handler | 4 | L9 |
| 13 | **L13** — Bank exhaustion recovery | 4 | L9 |
| 14 | **L14** — Per-CPU ECID bind/unbind | 5 | L9, L13 |
| 15 | **L15** — Cross-hart migration fences | 5 | L14 |
| 16 | **L16** — CPU hotplug: spill on offline | 5 | L14 |
| 17 | **L17** — ISR-EC: per-vector ECID | 6 | L8, L9 |
| 18 | **L18** — IRQ prologue/epilogue | 6 | L17 |
| 19 | **L19** — Nested interrupt support | 6 | L18 |
| 20 | **L36** — Boot CE-unaware distro | 13 | L3, Phase 4 |
| 21 | **L20** — KVM: VM entry | 7 | L9, L8 |
| 22 | **L21** — KVM: VM exit | 7 | L20 |
| 23 | **L22** — KVM: nested virt | 7 | L21 |
| 24 | **L23** — CPE: per-task partition | 8 | L9 |
| 25 | **L24** — CPE: cgroup integration | 8 | L23 |
| 26 | **L25** — CPE: RT-task partition | 8 | L24 |
| 27 | **L26** — MSE: Contract lifecycle | 9 | L9 |
| 28 | **L27** — MSE: SCHED_DEADLINE | 9 | L26 |
| 29 | **L28** — MSE: cgroup bandwidth caps | 9 | L26, L24 |
| 30 | **L29** — QoS: domain discovery | 10 | L4 |
| 31 | **L30** — QoS: per-task Contract | 10 | L26, L29 |
| 32 | **L31** — QoS: driver integration | 10 | L30 |
| 33 | **L32** — cpuidle: spill before power-gate | 11 | L16 |
| 34 | **L33** — /proc/cpuinfo CE entries | 12 | L4 |
| 35 | **L34** — Userland CE API | 12 | L23, L26, L30 |
| 36 | **L35** — Kernel selftests | 13 | Phases 3–11 |
| 37 | **L37** — Documentation | 14 | Phases 3–12 |
| 38 | **L38** — Coding style compliance | 14 | L37 |
| 39 | **L39** — Upstream submission | 14 | L38, P6 |

---

*End of Linux Work Items.*
