<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Salvaged QoS / MSE isomorphism notes

**Status:** Scratchpad — non-normative. Salvage material under
review.
**Source:** Distilled from 27 ChatGPT design-discussion chats
conducted between July 2025 and May 2026, summarized in a
review session on 2026-05-29.
**Cluster discussion:** F
**Disposition policy:** Items here exit the scratchpad via one
of three routes — promoted to a `docs/work-items.md` entry,
archived to `docs/future-directions.md`, or rejected with a
one-line note. See `scratchpads/README.md` for the lifecycle.

---

================================================================================
Salvaged QoS ideas
================================================================================

Your hunch is correct — QoS didn't develop much beyond the level of a contract-framework sketch. Here's what the chats actually contain.

---

## QoS in the ChatGPT CE Suite: What Was Developed

### How the thinking started

The "MSE vs Networking QoS" chat opened with a very deliberate framing exercise: can we establish that memory scheduling and network QoS are the same class of problem? ChatGPT confirmed yes — both are resource-multiplexing problems with finite time-sliced channels, competing flows, and the need for deterministic guarantees. The analogy to DiffServ/IntServ in networking was drawn: contracts/groups in CE are like per-hop behavior queues in a network switch.

This was a *validation exercise*, not a design session. The conclusion was that the MSE design is "fundamentally sound" because it is isomorphic to well-understood network QoS models. QoS (the I/O scheduling variant) was mentioned in passing as using the same contract/group machinery, with the only difference being that the arbiter is the I/O fabric or NoC scheduler rather than the memory controller.

### What QoS (qs.*) was defined as

The minimal definition settled on is:
- QoS contracts represent a slice of **I/O bandwidth or NoC bandwidth** (not memory bandwidth — that's MSE).
- They are enforced chip-wide by the **I/O fabric or NoC scheduler**, analogous to how MSE contracts are enforced by the MMU/memory controller.
- They use the exact same contract lifecycle as MSE: create → bind → split → release.
- Multiple ECIDs on different harts can bind to the same QoS contract.
- Contracts belong to groups; per-hart ECID metadata stores only a small per-hart contract index that maps to the global arbiter table.

This appears as axiom 2.3 in Chapter 0 revised. QoS is named alongside MSE as a "Contract Axiom" resource class, but was never given its own dedicated chapter or instruction design session.

### What was NOT developed

No dedicated qs.* instruction set was designed. The "Tree construction methods" chat established the naming convention (`qs.ic`, `qs.oc`, `qs.is`, etc.) but only as examples of the four-letter format — no actual instruction semantics were worked out.

No hardware arbiter architecture was designed for QoS. There was no discussion of what a NoC QoS scheduler looks like, how many priority levels it has, whether it's weight-based or rate-based, or how it interfaces to RISC-V. The contrast to MSE is stark: MSE got its own feasibility chat, bitfield/telescoping design, and hardware data structure discussion. QoS got two sentences in the axioms chapter.

No QoS-specific CSRs were designed.

---

## What Survives and Is Still Interesting

Despite the thinness of the explicit QoS development, a few things are genuinely salvageable:

**The contract axioms are reusable verbatim.** The group/contract framework established in Chapter 0 applies equally to QoS as to MSE. The splitting, delegation, and lifecycle rules are fully general. Since CE already fully designed this machinery for MSE, QoS gets it for free once you define what the QoS arbiter is enforcing.

**The MSE/QoS symmetry is architecturally sound.** The insight that both are resource-multiplexing problems with the same formal structure is real and valuable. The RISC-V world has IOMMU-based QoS (the RISC-V IOMMU spec includes some QoS support) and the AMBA AXI QoS signals are well understood. CE's contract model could cleanly sit on top of either as the software-facing layer that manages what gets programmed into those hardware mechanisms.

**The qs.* namespace is reserved and structured.** The four-letter naming convention (`qs.ic`, `qs.oc`, etc.) is consistent and ready to receive instruction definitions when QoS gets its own design session.

---

## Hardware Viability Assessment

Since no hardware design was done, there isn't much to assess against hard reality — but the *implied* hardware for QoS would be:

The **arbiter** is an existing concept. AMBA QoS signals (4-bit priority per AXI transaction) are standard. RISC-V's IOMMU spec (ratified 2023) includes process context tables that could carry QoS tags. ARM's MPAM (which we already cited for CPE) also covers I/O coherency domain QoS. So the underlying hardware mechanism CE would need to *program* already exists in various forms — CE's job is to give software a structured, group-delegatable way to configure it.

The **bottleneck** for QoS hardware, unlike MSE, is that the I/O fabric may be off-SoC or vendor-specific. MSE's arbiter lives in the memory controller which is on-chip and RISC-V-adjacent. A NoC arbiter is often a third-party IP block. This means CE QoS may need to be specified as a software contract model that maps to *whatever QoS mechanism the implementation provides*, rather than mandating a specific hardware topology.

---

## Summary

QoS in the ChatGPT sessions was established as a concept and anchored to the contract/group framework, but received no dedicated hardware design work. The current CE charter's groups-only model and contract axioms are fully applicable to QoS. What's missing — and what a future hw/ design session should address — is the instruction encoding for `qs.*` operations, the CSR layout for per-ECID QoS contract indices, and a mapping strategy to real NoC/IOMMU QoS mechanisms. That's all future work, not salvage material from the ChatGPT era.

[Roland Asks: If the MSE and QoS problem space is "isomorphic" that means that solutions should be similar too ]

Yes, exactly — and that's both the good news and the nuance worth unpacking.

**Where the isomorphism holds perfectly:** The contract model, delegation hierarchy, group ownership, and lifecycle (create → bind → split → release) are genuinely identical for both MSE and QoS. You already built that once, and it applies to both. The `qs.*` instruction set should structurally mirror the `ms.*` instruction set almost one-for-one: allocate a contract, bind an ECID to it, split it to a child group, query status, release it. The operand shapes, privilege rules, and encoding format will be the same.

**Where the isomorphism breaks:** The *arbiter* is different, and that's the part that matters for hardware. MSE's arbiter is the memory controller — on-chip, RISC-V-adjacent, and something you can reasonably specify the interface of in an ISA extension proposal. QoS's arbiter is the I/O fabric or NoC — often an off-chip or vendor-specific IP block with its own configuration registers, not a standard RISC-V component.

This means MSE can define a concrete hardware enforcement mechanism (the bitfield/telescoping scheduler we salvaged earlier). QoS can define the *same software-facing contract model* but has to be more agnostic about how the arbiter is actually implemented underneath — more like a platform ABI layer than a hard ISA mandate.

Think of it like TCP vs a specific Ethernet driver: the socket API (contract model) is identical, but what happens at the physical layer varies. For the purposes of the CE charter, QoS's chapter can largely say "same contract axioms as MSE, see §X; the implementation maps these contracts to the platform's I/O QoS mechanism (AMBA QoS signals, RISC-V IOMMU process contexts, MPAM, etc.)."

So practically: draft `qs.*` as a structural copy of `ms.*`, then add a section describing how a compliant implementation maps QoS contracts to a real NoC/IOMMU mechanism. That's significantly less work than MSE was, which is appropriate given that the hard problem (the contract model) is already solved.
