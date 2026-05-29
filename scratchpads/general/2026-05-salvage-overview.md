<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Salvage overview — 27-chat summary

**Status:** Scratchpad — non-normative. Salvage material under
review.
**Source:** Distilled from 27 ChatGPT design-discussion chats
conducted between July 2025 and May 2026, summarized in a
review session on 2026-05-29.
**Cluster discussion:** Cross-cutting; reference for all clusters
**Disposition policy:** Items here exit the scratchpad via one
of three routes — promoted to a `docs/work-items.md` entry,
archived to `docs/future-directions.md`, or rejected with a
one-line note. See `scratchpads/README.md` for the lifecycle.

---

Here is a short summary of all 27 chats in your CE suite ChatGPT project, ordered by last activity (newest first), with hardware-deep-dive chats flagged with **⚙️ HW**.

---

**1. CE suite development** — May 26, 2026
You shared the GitHub repo with ChatGPT for a cross-check against project documents. ChatGPT identified version drift between README and charter, CPE chapter still using old operand style, ec.ir semantics ambiguity, and generated a long "repair brief" for Claude to act on critically. Contains a salvage list of future ideas (interrupts, NUMA, migration, compression, etc.). Mostly a meta/coordination chat — useful for the repair brief and the future ideas list.

**2. Register bank distribution** — Dec 14, 2025 ⚙️ HW
Deep hardware discussion on distributing context bank SRAM near execution units (vector unit, interrupt controller). Covers Vector Local Store (VLS) design: managed scratchpad with per-ECID slot eviction, spill/fill state machine (IDLE → EVICTING → WARMING → RESIDENT_PARTIAL → RESIDENT), bypass-on-miss for best-effort ECIDs, pinned slots for RT. Also covers wiring and power savings from localization (shorter wires, fewer crossbars, reduced L1 pollution). **Highly relevant for hardware implementation.**

**3. Shrink project instructions** — Nov 28, 2025
Administrative chat: compressing the project charter/axiom document to fit ChatGPT's 8000-char project instructions limit. The compressed axiom charter itself is the artifact. No hardware design content.

**4. Project baseline update** — Nov 28, 2025
Alignment session for Chapter 5 (Linux integration) to the ECID-first axioms. ChatGPT produced a full replacement for Chapter 5 including struct execution_context, EC table initialization, ECID allocation, context switch flow (ec.ib/ec.ob), bank lifecycle, and interaction with CPE/MSE/QoS. Also a side note about an annotation UI project idea. Good Linux integration reference, but architecture is superseded.

**5. Cache partition instruction design** — Aug 12, 2025 ⚙️ HW
Design of CPE instruction operands. Started with a very rich rs1/rs2 bitfield covering all cache types (WAY, COLOR, COS, REGION, RESV), then you refined scope to per-hart private caches only (L1I/L1D/L2-private, no L3 in v1). Final design: LEVEL_SEL (Auto/L1/L2), COUPLE_L1L2 flag, MODE (WAY_MASK or PERCENT), INLINE bit, LOCK_EN, inline rs2 bitfields per mode, out-of-line CPD struct. Status codes defined. Chat ends with ChatGPT writing Chapter 7 (CPE Instruction Set Reference) in canvas. **Important for CPE hardware/instruction design.**

**6. One-hot register switching** — Aug 12, 2025 ⚙️ HW
Feasibility investigation of one-hot bitline bank selection for the CME register file. You proposed one-hot select lines; ChatGPT confirmed it works up to ~128 banks at GHz, with only a 6-to-64 decoder (≈100–200 transistors) on the hot path. Integration into the CME microarchitecture: global select lines fan out to all bit cells, pass-gates connect live register bits to bank bits, 1-cycle select. Includes inconsistency survey across chapters (operand conventions, mask widths, vector bank sizing). **Key hardware feasibility result.**

**7. Hardware context banks design** — Aug 10, 2025 ⚙️ HW
CME hardware design session: terminology explained (wordlines, bitlines, pass-gates, one-hot), Option A profile (impressive, full feature), checklist for physical design (SRAM placement, lane granularity, mask-aware copy engine, clock gating), transistor/area calculator for CE banks. Results: 90 KB total SRAM ≈ 1.5–6.6% area overhead depending on core size — single-digit %. ChatGPT noticed cross-chapter operand inconsistencies (pointer-based vs ECID-based). **Important for area estimates and design checklist.**

**8. Chapter 0 security advice** — Aug 10, 2025
Security analysis of CME: rogue VM issuing ec.ob on arbitrary ECIDs. Proposed fix explored opaque EHandle (MAC-based auth tag + generation counter) for O(1) authorization. Rights mask per resource class, sticky No-Delegate fuses. You pushed back toward simpler range-checking; discussion led to the Parent_ECID_Cached field in ECID struct. Also: should Groups and ECIDs be merged? (Decided to keep separate in next chat.) Foundational security architecture.

**9. Chapter 0 advice** — Aug 10, 2025
Three-part session: (1) Security/authorization model finalized — Parent_ECID_Cached field for O(1) ec.ob/ec.om check, no LCETs or CAM walks needed. You discovered the solution yourself: ECIDs just know their real bank number; parent checks via up-pointer. (2) Groups vs ECIDs debate resolved: keep distinct — Groups are resource containers, ECIDs are runnables. (3) Draft paragraph replacements for Chapter 0 §0.2 (ECID), §0.3 (Group), §0.7 (Delegation Rules) written. **Core architectural decisions — foundational.**

**10. MSE vs Networking QoS** — Aug 9, 2025
Clarification of how Contracts (MSE/QoS) work: global enforcement via chip-wide arbiters, per-hart contract index indirection, shared binding of multiple ECIDs, delegation and splitting. Chapter 0 revised "Contract Axioms" drafted. ec.ig return value clarified (returns group ID). Mostly spec/axiom alignment, not hardware implementation.

**11. ECID specout** — Aug 6, 2025
Two topics: (1) CE suite as a hardware IP library — feasibility confirmed, recommended module boundaries (Context Bank Module, Contract/Metadata Table, ECID Table, Arbitration FSMs, Privileged Control/CSR Interface, Debug Interface, Optional VMT Module). (2) You shared your FPGA board specs (Xilinx Artix-7 XC7A200T, 215K logic cells, 1.6 MB BRAM, 1 GB DDR3). ChatGPT confirmed it's more than capable for CE prototyping. Good IP partitioning reference.

**12. MSE feasibility discussion** — Aug 4, 2025
Pool-in-pool (nested pools) for MSE: why Pools ≠ Groups (pools for shared quota, groups for ownership/delegation), multi-hart pool enforcement at the memory arbiter, formal data structure for PoolEntry and ECResourceProfile, pool tree diagram. Also early MSE instruction naming brainstorm (ms.ic, ms.oc, ms.in, etc.) and the instruction naming convention origin (ec{i,o}{b,m,s,g,t,v}). MSE architecture reference.

**13. Tree construction methods** — Aug 3, 2025
Early session on MSE instruction/CSR drafts (mse.setcf, mse.getcs, etc. — pre-naming-convention era). You introduced the 4-letter naming convention. Discussion of group/bank axioms. Relatively early and superseded by later chats.

**14. Tree of truths for CE** — Jul 31, 2025
CE "tree of truths" document: axiomatic root nodes for EC as fundamental unit, ECID hardware recognition, all resource bindings referencing ECID, ECS in software, banks/groups serving ECs. Mermaid diagram. Side note: how to view Markdown/Mermaid (GitHub, Obsidian, Typora). Foundational axioms, but early version.

**15. RVA24 Developments and Focus** — Jul 31, 2025 ⚙️ HW
Context switching scenarios and optimizations: preloading R register before switch for near-zero latency, cselect/csave/crestore flow. Interrupt during time-slice handling: S→B[i] spill may be incomplete, proposed S→R move or role-flip. Expanded Scenario Matrix document created covering: kernel↔user, hypervisor↔VM, nested VMs, NMI, bank exhaustion fallback. **Key for understanding CME fast-path context switch flows.**

**16. Context Management Design** — Jul 31, 2025
Instruction naming convention finalized: ec{i,o}{b,m,s,g,t,v}. Discussion of operand semantics for ec.s (save) — rd returns allocated bank ID, hardware picks next free bank; exception on exhaustion. Variants for sealed (ec.z.s/ec.z.l), DMA (ec.d.s/ec.d.l), preload (ec.p.l), flush (ec.p.s). CME Extension Proposal rewritten with new naming and appendices (Verilog summary, transition matrix, use cases by scale, future-proofing). This is where the instruction set crystallized (though now renamed to ec.ib/ec.ob etc.).

**17. CME Extension Processor Design** — Jul 31, 2025 ⚙️ HW
Full CME Technical Specification written. Covers: Linux interrupt handling without CME (hardware trap → asm prologue → C ISR → full save if needed → mret), and where CME fits (only needed for full user-task save when preempting). Corner cases: bank exhaustion, power management/sleep, debug/single-step, I-cache coherence, SMP boot/hot-plug, nested hypercalls. CME-aware vs non-CME-aware OS coexistence. **Comprehensive spec document — valuable reference.**

**18. Speak to you** — Jul 31, 2025
CSR renaming to match ec.{i,o}{b,m,s,g,t,v} scheme: csr.ec.b.count, csr.ec.b.next, csr.ec.r.status, csr.ec.g.map, csr.ec.m.addr, csr.ec.v.key, etc. The CME "Main Spec" document updated with short-form instruction names. Streaming instructions ecis/ecos introduced as optional (background incremental context streaming to memory for live migration/checkpointing). Mostly naming/spec cleanup.

**19. CME Bank Group Structure** — Jul 31, 2025 ⚙️ HW
In-depth group/bank mechanism design: per-bank group stack (up to 4 levels deep), flattened for O(1) access, CAM lookup for group-banked lookup, security/isolation guarantees. CME instruction set reference card (full programmer-facing table). Python CME simulator prototype (ContextBank, Hart, VM, CMEController classes). Git project scaffold. Kernel integration analysis. Exception/revocation protocol. **Hardware group mechanism + simulator = good salvage material.**

**20. FPGA Board Design Feasibility** — Jul 31, 2025 ⚙️ HW
Security and architecture deep-dive: cache coherence after 1-cycle bank switch (cold cache miss problem), TLB invalidation (sfence.vma must be triggered on SATP switch), timing side channels (bank allocation timing as covert channel, low risk), S/R staging vs direct mux (confirmed S/R is industry standard: ARM Cortex-M, SPARC windows, IBM z, x86 shadow registers). Area numbers for Apple M1 scale: CME S+R ≈ 0.25–0.5 mm², context SRAM ≈ 0.8 mm², total ≈ 1–2% of core. Proposal section on TLB invalidation and cache partitioning integration written. **Important for hardware validation and security analysis.**

**21. Context Management for Risc-V** — Jul 31, 2025
CME scope, ecosystem integration: CME vs PMP/CLIC/H-Extension/cache partitioning responsibilities. CME deliberately does only register state; other extensions handle memory protection, interrupt routing, cache partitioning. Integration hooks discussed. Why real-time matters beyond embedded: audio/video studio, gaming, servers, cloud. The "CME in the RISC-V Ecosystem" section drafted. Foundational positioning document.

**22. RISC-V Hard Real-Time Extensions** — Jul 31, 2025
MSE memory scheduling: fractal/hierarchical RAM access slicing (recursive time-division multiplexing), predictive/hint-based scheduling via MMU and prefetch unit cooperation, interrupt preemption of memory blocks, topology-agnostic (works for regular RAM and hypercube/mesh). Prefetch/hint instructions classified as CPE (caching) future work. Future directions section drafted. Interesting architectural idea for MSE.

**23. Software FPGA Feasibility** — Jul 31, 2025
Brief tangent: is a software FPGA feasible? Yes for simulation/education (Verilator, Icarus, Migen), not for real-time. ChatGPT explained feasibility, limitations, tools. Short and off-topic for CE hardware.

**24. Hypercube Chiplet Architecture Advantages** — Jul 31, 2025
Hexagonal chiplet tile architecture: hex vs rectangular layout (hex has 6 neighbors = better routing, fewer crossovers, more uniform), triangle subdivision within hex tiles, hex-tile design toolkit document (EDA changes needed: hex standard cells, non-Manhattan P&R, hex interposers, edge-aligned PHYs, partition-aware scheduler in Linux). Includes BOM for one hex tile and Linux roadmap for CME + hex-partition support. Visionary architectural exploration — not core CE suite.

**25. Context Bank Schematic** — Jul 31, 2025 ⚙️ HW
Full CE suite recap: CME (fast context switch, 1-cycle S/R, context SRAM banks), CPE (cache way/set partitioning for RT isolation), QoS (IO/DMA arbitration), MBW/MSE (DRAM bandwidth arbitration). Industry comparison: CME vs SPARC windows, ARM banked regs, x86 shadow, IBM z. S/R staging confirmed as industry best practice. Additional tricks discussed: speculative preload into R, dirty/valid bits per register, on-chip compression, per-context power gating, content-addressable pointer/tag for banks. **Good high-level recap and CME competitive analysis.**

**26. RISC-V vector unit spec** — Jul 31, 2025 ⚙️ HW
Vector unit design: composable multiplier (fusing 8-bit operands into 32-bit), predicate masking for vectorized if/else, bandwidth-bound vs latency-bound workloads, pipelined fused multiplier diagram. Discussion of ChatGPT workflow management for large projects (Projects feature, Canvas, Git, session summaries). The vector design content is early and likely superseded by RVV work. Workflow tips still useful.

**27. Vector unit design critique** — Jul 31, 2025
CE suite readiness for RISC-V International submission: community process (working groups, RFC/white paper, iterate publicly), when to share (once core concepts are coherent, no need to be complete), how (isa-dev list, GitHub issue on riscv-isa-manual, seek collaborators). Acknowledgment that AI assistance is fine as long as human rigour is applied. Encouragement to engage early and collaboratively. Meta/process — not hardware content.

---

**Summary of which chats are richest for hardware implementation ideas:**

The chats with the most concrete hardware logic content are **#2, #5, #6, #7, #15, #17, #19, #20, and #25**. These cover: bank SRAM and slot state machines, one-hot bitline selection, physical design checklist, CPE instruction operand encoding, context switch fast-path flows, the full CME technical spec, group/bank security mechanisms, TLB/cache coherence on switch, area estimates, and competitive analysis against ARM/SPARC/IBM. If you're targeting hardware implementation depth, those are the chats to mine first.
