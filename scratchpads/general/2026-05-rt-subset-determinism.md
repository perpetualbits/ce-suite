<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# RT-subset determinism — the 1–2 cycle claim, properly scoped

**Status:** Scratchpad — non-normative. Parked architectural insight from
D6 discussion.
**Source:** Raised by the architect during D6 (TLB behavior on SATP
change) discussion in chat on 2026-05-29. Captured to prevent loss to
chat history.
**Related work items:** D6 (TLB on SATP change). Possibly affects
charter §1, ch04 (microarchitecture), and the eventual
proposal-readiness gap audit (PUB5).
**Disposition policy:** See `scratchpads/README.md`. This note is
expected to be promoted to a D-series work item once developed, or
absorbed into the D6 resolution if the connection is sufficiently
tight.

---

## The insight

The charter's §1 "1–2 cycle context switches" claim is in tension with
the realities of cross-address-space switching: a real cross-address-
space `ec.ob` incurs TLB refill cost regardless of whether the auto-
invalidate happens inside `ec.ob` (per D6 Option A) or as a separate
software-issued `sfence.vma` (per D6 Option B). The claim cannot be
universally true.

The architect's observation: 1–2 cycle switching may be **impossible
in general** but **achievable for a defined subset of execution
contexts** — specifically, real-time ECs that are *designed* to avoid
the costs that prevent sub-cycle switching.

## What an RT-subset EC could be

A context flagged or configured as RT-eligible could be required to:

- **Share its address space with other RT ECs in the same group**, so
  cross-RT-EC switches are same-SATP and require no TLB flush.
- **Hold reserved cache partitions via CPE**, so cache state survives
  switches and there is no cold-start latency.
- **Hold a reserved memory bandwidth Contract via MSE**, so the first
  post-switch memory access is not delayed by another EC's traffic.
- **Hold a reserved I/O Contract via QoS**, same reasoning at the NoC
  and DMA level.
- **Hold a permanently-resident bank**, so the EC's context is not
  spilled to RAM via `ec.im` between switches; the bank is always live.
- **Pre-pin TLB entries** for the RT working set, so the first memory
  access after switch-in does not page-walk.

For an EC satisfying these constraints, the 1–2 cycle figure becomes
defensible: the only architectural state that changes on switch is the
register file (and PC), which is exactly the state `ec.ob` restores
from the bank in 1–2 cycles. Everything else is either unchanged
(same SATP, same cache lines, same TLB entries) or pre-reserved (CPE
partition, MSE contract, QoS contract).

## Why this matters

This is the architectural framing that makes the charter's headline
claim honest and verifiable. Without it, the claim is either:
  - mildly misleading (true for the instruction commit, false for the
    workload-level latency), or
  - aspirational (would be true if everything else cooperated, but
    nothing in the spec enforces cooperation).

With the RT-subset framing, the claim becomes:
  - "1–2 cycle context switches for RT-subset ECs (defined by the
    constraints above)"
  - and "fast but workload-dependent for general-purpose ECs".

Both claims are true. The safety-certification narrative (ASIL D /
DO-178C / FDA Class III) targets exactly the RT-subset case, so the
strong claim covers the use case the spec is most valuable for.

## What needs developing

This insight is currently an architectural sketch, not a specification.
Open questions before it can become a work item:

1. **Discovery / declaration.** How does the OS tell hardware "this EC
   is RT-eligible"? A bit in `EC[e]`? A CSR? A discovery profile (in
   Appendix B)? The current Appendix B has profiles (CE-Embedded /
   MinimalRT / RT / Full) — does "RT-eligible EC" belong there or is
   it orthogonal?

2. **Enforcement.** What happens if an RT-flagged EC attempts a
   cross-SATP switch (e.g. the OS schedules it across address spaces
   incorrectly)? Trap? Best-effort fallback to general-case latency?

3. **Discoverability of the guarantee.** Can software verify, at
   schedule time, that an EC's RT constraints are satisfied — that
   it has its CPE partition, MSE contract, QoS contract, resident
   bank, pinned TLB entries?

4. **Interaction with D6.** If D6 lands on auto-flush (Option A or
   C), the RT-subset by definition never triggers a flush (same-SATP
   switches only). If D6 lands on software-fence (Option B), the RT-
   subset by definition never needs the fence. Either way the
   subset is consistent. But the discovery/enforcement story changes.

5. **WCET tooling.** RT-subset ECs are exactly the population for
   which WCET tools need to compute switching cost. The subset
   framing gives WCET tools a clean lower bound; without the framing,
   they must assume worst-case cross-address-space cost.

## Disposition

Park here until the D6 design-decision session is run. The eventual
D6 resolution should explicitly reference this scratchpad and decide
whether to develop the RT-subset framing as a follow-on work item
(potentially a new D-series item or an Appendix B / Chapter 14 / new
chapter extension), or to defer it to ratification/TG-stage
refinement alongside D6.1 / D6.2 / D6.3.

---

*End of note.*
