<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# ASID/VMID empirical insight — why "require ASID" is wrong but "use it where present" is right

**Status:** Scratchpad — non-normative. Parked architectural insight
from the D6 follow-up discussion.
**Source:** Raised by the architect during D6 follow-up discussion in
chat on 2026-05-29. Captured to prevent loss to chat history.
**Related work items:** D6.1 (exact scope of TLB invalidation on
`ec.ob` SATP change). Also bears on D6.2 (H-extension analogues).
**Disposition policy:** See `scratchpads/README.md`. This note is
expected to be absorbed into D6.1's resolution, or referenced from
it, when D6.1 is eventually decided.

---

## The insight

The earlier framing of D6.1 assumed a four-quadrant population:
implementations could have ASIDs or not, and could have many or few
address-space switches, giving four cases that needed to be handled
defensively. In particular, the case "no ASIDs + many address-space
switches" appeared to need careful handling because Scope 2 (ASID-aware
flush) would degrade to Scope 1 (full flush) on every switch, which is
exactly the cost the rule's loose wording was trying to avoid.

The architect's observation: **that case is essentially empty in
practice.** The chips that don't honor ASIDs are precisely the chips
that don't do many address-space switches. The chips that do many
address-space switches all honor ASIDs because the alternative is
performance-uncompetitive.

## Why the missing-ASID + frequent-switching case doesn't occur

The argument walks through the actual deployment landscape:

**Bare-metal real-time systems.** Often no MMU at all, or MMU disabled.
Physical addressing throughout. SATP is zero or irrelevant. No TLB to
flush. Context switching means changing register sets, not changing
translation. The D6 question doesn't arise.

**Small RTOS deployments (Zephyr, FreeRTOS, similar).** Typically run
all tasks in a single address space, possibly with MPU-based protection
rather than MMU-based translation. SATP either fixed or absent.
Address-space switches are zero or near-zero per second. Whether the
chip honors ASIDs doesn't matter because the question doesn't arise.

**Mid-tier RTOS with virtual memory (VxWorks, INTEGRITY, QNX,
real-time Linux variants).** These DO use full virtual memory with
multiple address spaces. But they run on chips designed to support
Linux-class workloads, which essentially always honor ASIDs because
the performance penalty otherwise is too large for the workloads these
chips target.

**Application processors (Linux desktops, servers, mobile).**
Frequent address-space switching is the bread and butter of the
workload. Every modern application-class RISC-V chip honors ASIDs.
Empirically: every RVA22-class and RVA23-class chip honors a non-zero
number of ASID bits.

The population that would be hurt by "Scope 2 degrading to Scope 1
when ASIDs aren't honored" is therefore not just rare — it's
architecturally implausible. Chips designed for high context-switch
rates have ASIDs because they were designed for high context-switch
rates. Chips without ASIDs are operating in a regime where the
degradation doesn't matter.

## Why "require ASIDs" is still wrong

Even though the missing-ASID + frequent-switching case is empty, making
ASID support a CE Suite conformance requirement would still be wrong:

1. **It breaks the opt-in philosophy.** CE Suite's design ethos
   throughout is that any privilege level can ignore CE without
   modification, and firmware can disable CE entirely. Requiring a
   particular hardware feature for CE conformance contradicts this — a
   chip implementing CE would be forced to also implement ASID decoding
   even if it has no use case for it.

2. **It excludes legitimate embedded deployments.** A microcontroller-
   class chip with a small MMU but no ASID decoding might still want to
   advertise CE support for QoS or the safety-critical context-switch
   determinism, without paying for ASID hardware it doesn't otherwise
   need.

3. **It's redundant with the empirical reality.** The chips that need
   ASIDs already have them. Mandating what's already true adds
   complexity to the spec without changing actual deployments.

## Why VMIDs follow the same logic

D6.2 is structurally identical. VMIDs are part of the H-extension.
Chips that ship H honor VMIDs because hypervisor workloads make
unbounded TLB flush cost intolerable. Chips that don't ship H don't
have `vsatp` or `hgatp` at all — so `ec.ob`'s bit 6 (or any future
mask bit covering them) doesn't restore them, and the TLB question
doesn't arise.

Requiring H for CE Suite would be even worse than requiring ASIDs: it
would exclude essentially the entire embedded segment where CE Suite's
safety-critical and real-time value propositions are strongest. RVA23
mandates H; RVA22 doesn't; most current embedded RISC-V chips don't
have H at all.

## Proposed D6.1 resolution form

Given the empirical picture, D6.1 can lean more aggressively toward
the optimized form than a defensive reading would have allowed:

> The TLB invalidation on `ec.ob` with SATP change SHOULD be
> ASID-aware on implementations that honor ASIDs (i.e., decode any
> non-zero number of ASID bits in SATP). Implementations that do not
> honor ASIDs MUST perform an invalidation correct for un-tagged TLBs
> (i.e., flush all translations from the affected supervisor or
> guest-supervisor mode). Software does not need to determine which
> form is in use; correctness is guaranteed in either case.

The companion D6.2 wording for the H-extension cases:

> When `ec.ob` restores `vsatp` (under the H-extension), the analogous
> rule applies using `hfence.vvma`. When it restores `hgatp`, the
> analogous rule applies using `hfence.gvma`. Where the implementation
> honors VMIDs, the SHOULD/MUST pattern from the SATP rule applies.
> Implementations without the H-extension do not implement these
> registers; the rule is vacuous in that case.

## Optional discovery bit

A bit in `cme_caps` indicating whether the implementation uses
ASID-aware flushing could be added for software that wants to bound
worst-case switch latency analytically (e.g., a WCET analyzer for
safety-critical scheduling). This is an optional addition; portable
software does not need it because correctness is guaranteed
regardless of which form is used. It would be a small E-series
enhancement, not a D-series decision.

## Relationship to the RT-subset framing

The companion scratchpad `2026-05-rt-subset-determinism.md` proposes
that the "1–2 cycle" claim is fully defensible for a defined RT-subset
of ECs with specific constraints (same-SATP, CPE-reserved, etc.).

The ASID-availability question could be one of the constraints on the
RT-subset: "an RT-subset EC must run on an implementation that honors
at least N ASID bits." This makes the requirement live on the *EC*
rather than on the *implementation as a whole*. An implementation that
doesn't honor ASIDs can still implement CE Suite — it just can't host
RT-subset ECs. Everything else continues to work.

This integration is clean and worth considering when both D6.1 and the
RT-subset framing are eventually resolved.

## Disposition

Park here until D6.1 is resolved. The D6.1 resolution should reference
this scratchpad and decide whether to adopt the proposed wording (or a
refinement of it). The optional `cme_caps` discovery bit and the
RT-subset integration are separate decisions that may be made at the
same time or deferred further.

---

*End of note.*
