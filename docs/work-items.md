# CE Suite — Work Items

**Purpose:** Tracks every known inconsistency, underspecification, and gap in the CE
Suite spec. Items are organized by type and priority. Usage-example chapters must not
be started until all Design Decision (D) and Specification Fix (F) items are resolved.

**Relationship to charter §8:** The charter's §8 lists *architectural* open items —
things not yet decided at the model level. This document lists *specification* work
items — inconsistencies and gaps within the chapters as currently written, plus
detailed design work that follows from locked architectural decisions.

---

## Category D — Design decisions required

These items require an explicit decision before any chapter can be corrected.
Each one is a dedicated session: state the options, decide, record in the charter
or here, then propagate to the affected chapters.

---

### D1 · Error and status reporting policy ✓ RESOLVED (v0.9)

**Decision:** `rd` always for instructions that can fail; use `x0` to discard.
Two exceptions with no `rd`: `ec.ib` (always succeeds or traps) and `ec.oe`
(always succeeds). Status CSRs updated for diagnostics only.

**Propagated to:** charter §6.6, ch00 §0.9–§0.10, ch02 (all affected instructions
+ §12), ch03 §3.5.1, ch05 §2, ch06 (all pseudocode blocks). Ch08 and ch09
were already compliant.

**CPE (ch07):** CPE redesign (F1) is required before D1 can be applied there.
F1 depends on D3. D1 for CPE is deferred to the F1 session.

---

### D2 · `ec.it` resource selection mechanism ✓ RESOLVED (v0.10)

**Decision:** Option 3 — `ec.it` delegates **Banks only**, one per call.
Contract delegation uses per-extension instructions (`ms.it`, `qs.it`, `cp.it`
per D3). The implementation selects which bank from the parent's Group; to
delegate N banks, call `ec.it` N times.

**Propagated to:** charter §4.3 item 7, ch02 §4 (`ec.it` description and §11
relationships table), ch03 §3.4.1 and §3.4.2.

---

### D3 · CPE Contract delegation ✓ RESOLVED (v0.11)

**Decision:** Option 2 — CPE Contracts are delegatable. `cp.it` and `cp.ot` are
required; CPE subset is `{r, t}`. Rationale: a nested hypervisor (L1) holding a
cache-way Contract from L0 must be able to independently allocate sub-partitions
to its guests (L2) without back-channel communication with L0. Making CPE an
exception would break the isolation hierarchy the delegation model exists to provide.

**Propagated to:** charter §4.3 item 7 (placeholder resolved); v0.11 changelog.

**Deferred to F1:** Full `cp.it`/`cp.ot` instruction semantics are specified in
the CPE chapter redesign (F1), which is now fully unblocked (D1 ✓, D3 ✓).

---

### D4 · `qs.or` / `qs.ot` domain selector operand ✓ RESOLVED (v0.12)

**Decision:** Option 1 — `rs2` for domain. `qs.or rd, rs1, rs2` and `qs.ot rd, rs1, rs2`
where rs2 = domain_id; 0 = all domains. Consistent with `qs.ir`; rd-as-input prohibited.

**Propagated to:** charter §6.7 (new section); ch09 (`qs.or`, `qs.ot` syntax corrected).

---

## Category F — Specification fixes

These items can be resolved once the relevant D items are decided, or independently
where no design decision is needed.

---

### F1 · CPE ch07 complete redesign ✓ RESOLVED

**Affects:** ch07.

ch07 rewritten with `rs1` = ECID, `rs2` = partition descriptor; OPC field removed;
QUERY replaced by `cpe_caps` CSR (F9 resolved as part of F1); delegation per D3;
rd-primary per D1. Four instructions: `cp.ir`, `cp.or`, `cp.it`, `cp.ot`.

---

### F2 · `qs.or` and `qs.ot` syntax correction ✓ RESOLVED

**Affects:** ch09.

Fixed as part of D4 resolution. `qs.or rd, rs1, rs2` and `qs.ot rd, rs1, rs2`; rd is
write-only; ch09 updated consistently.

---

### F3 · `ec.ir` rs1 semantics clarification ✓ RESOLVED

**Affects:** ch02 (`ec.ir`).

Fixed in ch02: rs1=0 → leaf child (delegation_L=D, cannot delegate further);
rs1=1 → delegating child (delegation_L=parent_L+1, provided parent_L<D);
rs1>1 → ILLEGAL_FIELD. Hardware always sets child_L = parent_L+1; software only
chooses leaf vs. non-leaf via 0/1.

---

### F4 · `ms.it` rs2 dual-purpose encoding ✓ RESOLVED

**Affects:** ch08 (`ms.it`).

Fixed in ch08: formal bitfield table added — bits 15:0=child_ecid, 19:16=child_bw_class,
23:20=child_lat_class, bit[XLEN-1]=pointer flag; "bit 62" magic removed. Pointer form
points to `MSE_Delegation_Params` struct.

---

### F5 · Charter §6.1 — CME subset list incomplete ✓ RESOLVED

**Affects:** Charter `project_instructions.md` §6.1.

Fixed: CME subset corrected to `{b, m, g, t, r, e, v}`; `s` removed (no ec.is/ec.os
instructions — F6 option 2 chosen). Per-extension subset table added. Charter v0.12.

---

### F6 · `ec.is` / `ec.os` — staging bank instructions absent ✓ RESOLVED

**Affects:** ch02, charter §6.1.

Decision: Option 2 — `s` removed from CME subset. Staging banks are entirely
hardware-managed; no software instruction needed. Charter §6.1 corrected (F5).

---

### F7 · `ec.iv` / `ec.ov` — vault instructions partially defined ✓ RESOLVED (option 1)

**Affects:** ch02 (`ec.iv`, `ec.ov`).

Added explicit "Status — instruction shells only" block in ch02 §6 noting that full
key-derivation, attestation, and sealing-format semantics await resolution of charter
§8.6. Instructions remain in the table; a reader now knows exactly what is and is not
specified.

---

### F8 · Binary encoding for all extensions ✓ RESOLVED

**Affects:** ch02 §10, ch07 §11, ch08 §11, ch09 §12.

**Decision:** Single custom-0 opcode (`0001011`). All 24 CE Suite instructions are
R-type. funct3 selects extension (CME=000, CPE=001, MSE=010, QoS=011). funct7
selects instruction within extension. Unused rd/rs2 fields encoded as `00000`.
All variable-width operands (masks, descriptors, contract params) passed in
registers — no I-type variants needed. Actual opcode assignment subject to
RISC-V International ratification; custom-0 is used for proposal purposes.

**Encoding tables added to:** ch02 §10 (CME, 12 instructions), ch07 §11 (CPE,
4 instructions), ch08 §11 (MSE, 4 instructions), ch09 §12 (QoS, 4 instructions).
Each section includes two worked bit-pattern examples.

---

### F9 · CPE QUERY operation undefined ✓ RESOLVED (as part of F1)

**Affects:** ch07.

QUERY removed. Capability information is now in the `cpe_caps` read-only CSR (ch07 §7).
No software-visible query instruction needed.

---

### F10 · `working_notes_for_authors.md` §5.5 stale ✓ RESOLVED

**Affects:** `docs/working_notes_for_authors.md`.

§5.5 updated: ch08 (MSE) and ch09 (QoS) are normative; scratchpads archived; open
items tracked in work-items.md.

---

## Category G — Gaps requiring new content

Items where the spec is silent and content needs to be created.

---

### G1 · Context switch sequence diagram (ch02 §13 placeholder) ✓ RESOLVED

**Affects:** ch02 §13.

All three ASCII diagrams drawn: (1) fast-path context switch sequence showing Bank[A]/Bank[B]
data flow and `current_ecid` transition, (2) ECID operand lookup via
`cme_ec_table_base + e × stride` with ownership check, (3) `ec.oe` depth-first subtree
walk with generation-counter increments and stale-reference guarantee.
"Placeholder" heading removed.

---

### G2 · Reserved-bit policy for instruction masks ✓ RESOLVED

**Affects:** ch02 §7 (register mask encoding).

Added policy to ch02 §7: non-zero reserved bits return a defined error code (or raise
an illegal-instruction trap); silent ignore prohibited.

---

### G3 · RV32 width audit — "64-bit" assumptions throughout ✓ RESOLVED

**Affects:** ch00 §0.6, ch04 §5–§6. All other chapters already XLEN-aware.

**Audit findings (all chapters checked):**
- ch01–ch03, ch05, ch07–ch12, appendix-a: already use `[XLEN-1]`, `XLEN-wide`,
  and explicit RV32/RV64 labels. No fixes needed.
- ch00 §0.6: RV32 bank FPR row assumed FLEN=32 silently. Fixed: FLEN note added
  with adjusted totals for FLEN=32/64/128.
- ch04 §5–§6: timing table NV row used 1 KB (RV64) without labeling it as such.
  Fixed: split into NV (RV64) and NV (RV32) rows; §6 examples labelled.

---

## Priority order for execution

1. ~~**D1** (error/status policy)~~ — **DONE** (v0.9).
2. ~~**D2** (`ec.it` selection)~~ — **DONE** (v0.10).
3. ~~**D3** (CPE delegation)~~ — **DONE** (v0.11).
4. ~~**D4** (`qs.or` domain selector)~~ — **DONE** (v0.12).
5. ~~**F5** (charter §6.1 CME subset)~~ — **DONE**.
6. ~~**F3** (`ec.ir` clarification)~~ — **DONE**.
7. ~~**F1** (CPE redesign)~~ — **DONE**.
8. ~~**F2** (`qs.or`/`qs.ot` fix)~~ — **DONE** (with D4).
9. ~~**F4** (`ms.it` encoding)~~ — **DONE**.
10. ~~**F6** (`ec.is`/`ec.os`)~~ — **DONE** (option 2: `s` removed).
11. ~~**F7** (`ec.iv`/`ec.ov` incompleteness flag)~~ — **DONE**.
12. ~~**F9** (CPE QUERY)~~ — **DONE** (resolved in F1).
13. ~~**F10** (working notes stale note)~~ — **DONE**.
14. ~~**G2** (reserved-bit policy)~~ — **DONE**.
15. ~~**G1** (diagrams)~~ — **DONE**.
16. ~~**F8** (binary encoding)~~ — **DONE**.
17. ~~**G3** (RV32 width audit)~~ — **DONE**.

---

## Usage example chapters

- ~~Chapter 8 — CPE Usage Examples~~ — **DONE**
- ~~Chapter 10 — MSE Usage Examples~~ — **DONE**
- ~~Chapter 12 — QoS Usage Examples~~ — **DONE**

---

## Category P — Proposal-readiness gaps

These items are required to make the CE Suite a submittable RISC-V ISA extension
proposal. They are independent of the D/F/G work above (which fixed internal
consistency); these fill gaps between the spec as written and what RISC-V
International expects for ratification.

---

### P1 · CSR chapter — addresses, bit-fields, access control ✓ RESOLVED

**Affects:** `docs/chapters/ch13-csr-reference.md` (new chapter).

31 CSRs specified across CME (9), CPE (4), MSE (8), QoS (10). Each entry
includes: provisional address, bit-field table with access type (RO/RW/WARL/W1C)
and reset value, semantics, and illegal-access behavior. Two provisional address
ranges used: 0x7C0–0x7CE (M-mode RW custom) and 0xFC0–0xFCF (M-mode RO custom).

New CSR names introduced: `cme_del_cap` (delegation depth cap D, previously
unnamed), `cme_status.VMT_RDY` bit (VMT-ready flag, previously unnamed in ch04).
`cpe_caps` bit layout promoted from informative (ch07 §7) to normative (ch13 §4.1).

**Blocks unblocked:** P2 (privilege model) and P4 (discovery) may now proceed.

---

### P2 · Privilege model integration — M/S/U/VS/VU per instruction ✓ RESOLVED

**Affects:** `docs/chapters/ch14-privilege-model.md` (new chapter).

Per-instruction privilege table for all 24 CE Suite instructions across M/HS/S/VS/U/VU.
Two new CSRs: `cme_priv_ctl` (0x7CF, M-mode RW, `S_EN` bit) enabling S/HS-mode CE
access, and `hcme_ctrl` (0x6C0, HS-mode RW, `VS_EN` bit) enabling VS-mode CE access.
Delegation level derivation: M-mode creates L=0 ECIDs; S/HS creates L=1; VS creates
L=2; nested VS creates L=3 (the leaf level for D ≤ 3). H-extension VM entry/exit
protocol specified in §14.8. Boot sequence showing firmware enablement in §14.9.

**Depends on:** P1 ✓.

---

### P3 · Complete trap/exception table ✓ RESOLVED

**Affects:** `docs/chapters/ch15-trap-table.md` (new chapter).

Unified trap-vs-`rd` outcome model for all 24 instructions. Universal trap conditions
(privilege check, reserved encoding, CE not implemented). Memory-access faults from
pointer operands use standard RISC-V causes 5/7/13/15. All other error conditions
return codes in `rd`. New exception cause: `CE_EXC_BANK_FAULT` (cause 16, in the
custom range) for `ec.ib`/`ec.ob` bank SRAM errors. Normative CME error code table
(CME_OK through CME_ERR_NOT_SEALED, values 0–7) defined here for the first time.
`medeleg`/`hedeleg` delegation guidance in §15.6.

---

### P4 · Discovery mechanism ✓ RESOLVED

**Affects:** `docs/chapters/ch16-discovery.md` (new chapter).

New CSR: `ce_present` (0xFD0, M-mode RO), bits 0–3 = CME/CPE/MSE/QoS present, bit 4
= H-extension CE integration present (`hcme_ctrl` exists). Reads 0 when CE is disabled
(per ch13 §2 rule); traps as illegal instruction when CE hardware is entirely absent.
ISA string extension names: `Xce` (umbrella), `Xcecme`, `Xcecpe`, `Xcemse`, `Xceqos`
(provisional `X`-prefix names; subject to RISC-V International registration).
M-mode boot probe sequence with trap-handler pattern. S-mode reads the firmware-
published value from the capability table (ch14 §14.9 mechanism). Device-tree
`riscv,isa` advertisement requirements. Relationship to per-extension capability CSRs
in ch13.

**Depends on:** P1 ✓.

---

### P5 · Memory ordering guarantees ✓ RESOLVED

**Affects:** `docs/chapters/ch17-memory-ordering.md` (new chapter); cross-reference
notes added to ch03 §3.1/3.2 and ch09/ch11 instruction sections.

**Decision:**
- `ec.ib` and `ec.ob` carry **no implicit fence**. Banks are on-chip SRAM; they are
  invisible to RVWMO. Same-hart switches need no fence (PPO covers ordering). For
  cross-hart migration, `FENCE W,W` is issued after `ec.im`, not around `ec.ib`/`ec.ob`.
- `ec.im` is a synchronous DMA write to ECS in RAM; it participates in RVWMO as a store.
  After `ec.im`, software must issue `FENCE W,W` before signaling another hart.
- `ec.om` is a synchronous DMA read from ECS in RAM; it participates in RVWMO as a load.
  Before `ec.om` (cross-hart), software must issue `FENCE R,R` after the acquire signal.
- Contract assignment instructions (`ms.ir`, `cp.ir`, `qs.ir`, etc.) operate on
  per-hart SRAM and hardware registers only. They carry no implicit fence. Cross-hart
  bandwidth accounting at the memory controller is handled by hardware atomic admission
  (charter §4.3.3). No software fence is needed around Contract assignment itself.
- A normative cross-hart migration fence sequence (steps 1–13 with `FENCE W,W` and
  `FENCE R,R`; AMO `.rl`/`.aq` alternative provided) is specified in ch17 §17.5.

---

### P6 · Opcode and extension-name allocation (process item)

**Affects:** ch03 §10, ch07 §11, ch09 §11, ch11 §12; charter.

Custom-0 (`0001011`) is used as a placeholder. Real submission requires:
- Formal extension names registered with RISC-V International.
- Allocated opcode space (or confirmation that custom-0 is appropriate for the
  proposal stage).
- Formal CSR address allocation (31 CSRs currently in provisional custom ranges).

This is a process item, not an authoring item — it requires engagement with RISC-V
International and cannot be resolved by editing the spec alone.

**Submission materials prepared** (`docs/submission/`):
- `submission-brief.md` — technical brief covering the three allocation requests
  (ISA names, opcode, CSRs), full 24-instruction inventory with encoding tables,
  implementer cost summary, and a next-steps table. Ready to accompany a TG
  formation request.
- `motivation.md` — use-case and value-proposition document. Covers eight
  compute classes (microcontrollers → wearables → mobile → laptops →
  desktops/gaming → workstation servers → cloud → telco/NFV → safety
  certification) plus a cross-cutting argument for foundation-level
  standardization and RISC-V market alignment.

---

### P7 · AsciiDoc conversion (mechanical)

**Affects:** All chapters.

RISC-V International specs use AsciiDoc with a specific toolchain. The Markdown
source needs conversion before a formal submission can be prepared. This is largely
mechanical but non-trivial given the volume of tables, code blocks, and cross-references.

---

### P8 · Sail formal model (large, separate project)

**Affects:** Separate deliverable alongside the spec.

RISC-V ratification increasingly requires a Sail formal model of instruction
semantics. This is a significant engineering effort independent of the spec text
and is noted here for completeness. Not a near-term authoring task.

---

## Proposal-readiness priority order

1. ~~**P1** — CSR chapter (blocks P2 and P4).~~ — **DONE** (ch13).
2. ~~**P2** — Privilege model (depends on P1 ✓).~~ — **DONE** (ch14).
3. ~~**P3** — Trap/exception table (can start in parallel with P2).~~ — **DONE** (ch15).
4. ~~**P4** — Discovery mechanism (depends on P1 ✓).~~ — **DONE** (ch16).
5. ~~**P5** — Memory ordering (independent; can be done any time).~~ — **DONE** (ch17).
6. **P6** — Opcode/name allocation (process item; engage RISC-V International).
7. **P7** — AsciiDoc conversion (mechanical; do last).
8. **P8** — Sail formal model (large separate project; deferred).

---

## Category E — Enhancements

These items extend the v1 spec with genuinely valuable additions that require
relatively little work and no fundamental model changes. Each was reviewed
against the current spec and classified as "category 3" (valuable, low effort,
pity to omit). Items are independent of each other unless noted.

Source: `docs/future-directions.md` items §1, §2, §5, §6, §8, §13, §16, §18.

---

### E1 · Capability Profiles ✓ RESOLVED

**Affects:** New appendix (Appendix B); ch16 §3.1 + §7 (cross-reference added).

**Decision:** Four standard profiles defined in a new Appendix B, as a naming
convention over existing discoverable parameters (`ce_present`, `cme_del_cap`,
`cme_bank_count`). No new hardware, no new CSR, no ISA string profile names.

- **`CE-Embedded`** — CME only, D=0, NV≥1, VMT=0. Target: microcontrollers.
- **`CE-MinimalRT`** — CME+CPE, D≥1, NV≥2. Target: embedded RTOS, industrial RT.
- **`CE-RT`** — CME+CPE+MSE, D≥2, NV≥4. Target: mixed-criticality, embedded Linux+RT.
- **`CE-Full`** — CME+CPE+MSE+QoS, D=3, NV≥8, VMT≥1. Target: cloud, server, ASIL-D.

CE-Full ⊇ CE-RT ⊇ CE-MinimalRT (nested); CE-Embedded is an independent branch
(D=0 and CPE=0 conflict with all others).

**Open questions resolved:**
- *Governance:* Profiles defined by the spec; vendor profiles use `V-<Vendor>-<Name>` prefix.
- *Composition:* Deferred to a future version; not supported in v1.
- *Profile-ID CSR:* Not introduced; profiles are purely naming over existing CSRs.
- *ISA string names:* Not introduced; profiles advertised via `ce,profile` DT property.

**Propagated to:** Appendix B (new file); ch16 §3.1 (capability profiles note added);
ch16 §7 (Appendix B listed in "Where to go next"); adoc/chapters/appendix-b-profiles.adoc
(new file); adoc/index.adoc (Appendix B include added).

**Note:** E7 (Minimal Embedded Profile from future-directions §7) is subsumed
by this item — it appears as the `CE-Embedded` profile in Appendix B §B.3.1.

---

### E2 · CLIC Integration ✓ RESOLVED

**Affects:** New ch18 (Chapter 18 — CLIC Interrupt Integration).

**Decision:** Standalone ch18 (not a section in ch05), because the content is
cross-OS (bare-metal, RTOS, Linux, KVM) and not Linux-specific, and the scope
— boot allocation, prologue/epilogue sequences, CPE isolation, MSE reservation,
nested interrupts, bank provisioning, timing — is too broad for a single section.

**Content added:**

- §18.1 — Problem statement: shared CE resources under preemption (register
  corruption, CPE isolation failure).
- §18.2 — Interrupt-EC pattern: dedicated ECID + Bank + CPE partition per ISR
  vector; permanent lifetime (not per-invocation).
- §18.3 — Boot-time allocation: `ec.ir` (leaf ECID), `cp.ir` (dedicated CPE
  partition), `ms.ir` (optional MSE Contract), `ec.om` (zero-initialize Bank).
- §18.4 — Interrupt entry and exit: M-mode prologue/epilogue using `mscratch`
  to preserve the preempted ECID across the `ec.ib`/`ec.ob` bank swap.
  §18.4.2: dirty-save optimization (`ec.ib x0, x0`) for GPR-only ISRs.
- §18.5 — CPE cache-partition isolation: L1/L2 controller switches partition on
  `ec.ob`; task hot lines undisturbed; independent WCET analysis.
- §18.6 — MSE memory reservation (optional): ISR Contract for bounded DRAM
  latency; omit for cache-resident interrupt handlers.
- §18.7 — Nested interrupts: one ECID per priority level; prologue/epilogue
  handles nesting without modification; nesting depth bounded by CLIC priority
  levels, not CE delegation depth D.
- §18.8 — Bank provisioning: provisioning rule = runnable ECIDs + ISR ECIDs;
  CME_ERR_NO_BANK recovery per ch03/ch15.
- §18.9 — Timing: 2–18 cycles per direction (fast path); dirty-save reduces to
  2–12 cycles; comparison to software save/restore (128+ cycles).
- §18.10 — Other operating environments: M-mode/S-mode/VS-mode variations;
  `mscratch`/`sscratch`/`vsscratch`; Linux IRQ trampoline pattern.
- §18.11 — Relationship to other chapters (ch03, ch04, ch07, ch09, ch13, ch14, ch15).

**No new instructions, CSRs, or charter changes required.**

**Propagated to:** ch18 (new file); ch17 footer updated to point to ch18;
refamiliarize.md chapter table and E2 status updated; work-items.md priority
order updated.

---

### E3 · Dirty / Lazy Tracking for Banks ✓ RESOLVED

**Affects:** ch03 (`ec.ib` definition); ch00 §0.5 (EC[e] layout — one dirty
bit per register group); possibly charter §3.2 if the EC[e] struct changes.

Add a dirty-bit per register group to EC[e]. Semantics: if rs1 = 0 on `ec.ib`,
hardware uses the dirty bitmap in place of an explicit mask, saving only groups
written since the last `ec.ib` or `ec.ob`. Software may still pass an explicit
non-zero mask to override. The FPU dirty-bit pattern used by Linux FP context
switch is the direct analogue. Reduces interrupt handler switch cost
substantially for contexts that never touch FPRs or vectors.

**Decision:** Dirty-group bitmap added as implementation-defined state in
`EC[e]` (fits under charter §3.2 "implementation-defined: cached bank/contract
refs, flags, etc." — no charter version bump needed). ch00 §0.3 adds a
"Dirty-group tracking" normative paragraph describing the bitmap layout (one bit
per register group, same positions as the register mask in §0.10), when hardware
sets/clears bits, and the two allowed physical placements (EC[e] impl-defined
region or a per-hart hardware register flushed on save). ch03 §3.1 `ec.ib`
updated: rs1 bullet notes the `x0`-encoding special case; side effects note
bitmap clearing; guaranteed cycles changed to 1–3; new "#### Dirty-Save Mode
(`rs1 = x0`)" subsection added with FPU analogy, code examples, and the
register-field-encoding disambiguation. ch03 §3.1 `ec.ob` side effects note
bitmap clearing for restored groups (resumed context begins with clean bitmap).
Charter §3.2 unchanged (dirty bits fall under the existing impl-defined
catch-all).

**Depends on:** No blocking dependencies.

---

### E4 · Bank Exhaustion Protocol ✓ RESOLVED

**Affects:** ch03 (`ec.ig` and `ec.ob` — add a normative recovery subsection);
ch15 (CME_ERR_NO_BANK already defined — add cross-reference).

**Decision:** Normative `#### Bank Exhaustion Recovery` subsections added under
`ec.ob` (§3.1) and `ec.ig` (§3.3) in ch03. Protocol for `ec.ig`: select victim,
`ec.im` to spill to RAM, `ec.og` to release the bank back to the free pool, retry
`ec.ig`. Protocol for `ec.ob`: same spill+release, then `ec.om` to fill the
target's state into the freed bank, retry `ec.ob`. ch15 `ec.ob` error table
corrected: "no bank assigned" row changed from `CME_ERR_INVALID_ECID` (1) to
`CME_ERR_NO_BANK` (2) — the condition is recoverable and distinct from an invalid
ECID. Cross-reference paragraph added to ch15 §15.4.

**Depends on:** No blocking dependencies. CME_ERR_NO_BANK already exists in
ch15; this item adds the protocol description to ch03.

---

### E5 · Nested Virtualization CSRs ✓ RESOLVED

**Affects:** ch13 (two new RO CSRs: `current_ecid_level` and
`current_ecid_parent`); ch14 (privilege access rules for the new CSRs).

**Decision:** Two read-only per-hart CME CSRs added:

- **`current_ecid_level` — 0xFD1.** Bits 1:0 hold the delegation level `L` of
  the running ECID, mirroring `EC[current_ecid].delegation_L`. Updated atomically
  with `current_ecid` on every successful `ec.ob`. Together with `cme_del_cap`,
  lets a nested hypervisor check delegation headroom (`L < D`) without an
  `EC[e]` table lookup.

- **`current_ecid_parent` — 0xFD2.** Bits 15:0 hold the parent ECID number of
  the running context, mirroring `EC[current_ecid].parent_ecid`. Reads as 0 for
  root ECIDs (L = 0). Updated atomically with `current_ecid` on every successful
  `ec.ob`.

**Address note:** The 0xFC0–0xFCF range was already fully assigned when E5 was
implemented (the "4 slots remain unassigned" claim in this item was stale).
Addresses 0xFD1–0xFD2 are used instead — the next available slots in the same
M-mode RO encoding class. Address 0xFD0 is provisionally assigned to `ce_present`
by Chapter 16.

**Privilege access:** S-mode, HS-mode, and VS-mode may read both CSRs when
enabled (same rules as `current_ecid`, per ch14 §14.6).

**Propagated to:** ch13 §1 (address table + note), §3.10–§3.11 (new CSR
definitions), §7 (illegal-access table), §8.2 (address summary); ch14 §14.6.2–§14.6.3
(CSR accessibility), §14.7 (illegal-access table).

**Depends on:** No blocking dependencies.

---

### E6 · Power Gating Integration ✓ RESOLVED

**Affects:** ch04 (new §4.14).

**Decision:** Normative §4.14 "Power Gating Protocol" added to ch04. Two-phase
protocol:

- **Before cutting SRAM power:** issue `ec.im x0, e, FULL_MASK` for every ECID
  `e` with a resident Bank. Abort the gate if `ec.im` returns a non-zero error
  code; alternatively destroy the ECID via `ec.oe`. If another agent may read the
  ECS during the gating window, issue `FENCE W,W` after the last `ec.im`.
- **After SRAM power is restored:** issue `ec.om x0, e, FULL_MASK` for every
  Bank that was spilled. All fills must complete before the first `ec.ob`.
  Issue `FENCE R,R` before the first `ec.om` if another hart may have updated the
  ECS during the gating window.

Four normative invariants added: spill before gate, fill before schedule, no skip
on error, bank bookkeeping survives the gate (ECS is RAM-resident per §4.2.1;
SRAM bank tags are not). Memory ordering cross-references point to ch17 §17.3.1
and §17.3.2.

**Depends on:** No blocking dependencies.

---

### E7 · SCHED_DEADLINE / MSE Integration

**Affects:** ch05 (Linux Kernel Integration) — one new informative section.

Add a section describing how Linux SCHED_DEADLINE's runtime/period parameters
map onto MSE Contract bandwidth and latency classes: when a SCHED_DEADLINE task
is admitted, the kernel calls `ms.ir` to allocate a matching MSE Contract; if
Contract admission fails (hardware reports insufficient bandwidth), task
admission fails. Closes the loop between the POSIX RT scheduling API and
hardware-enforced memory bandwidth reservation. No new instructions or CSRs;
this is informative guidance for OS integrators.

**Depends on:** No blocking dependencies.

---

### E8 · Return values for `ec.ib` and `ec.oe` ✓ RESOLVED

**Affects:** Charter §6.5/§6.6, ch00, ch02, ch03, ch05, ch06, ch08, ch10,
ch12, ch14, ch15, ch17, appendix-a, instruction-card.md.

**Decision (v0.14):**

- `ec.ib rd, rs1` — `rd` returns the bank slot index (0-based within the owning
  Group) of the bank written. `x0` discards.
- `ec.oe rd, rs1` — `rd` returns the total count of ECIDs freed, including the
  target itself. `x0` discards.

**Propagated to:** Charter v0.14 (§6.2, §6.5, §6.6, changelog); ch03 (7
locations); full sweep of all remaining chapters and reference files removing
"no rd" / "carry no rd" claims and updating assembly syntax to two-operand form.

---

## Enhancement priority order

These are independent and can be done in any order, with one exception:

1. ~~**E8**~~ — fully resolved ✓.
2. ~~**E4**~~ — fully resolved ✓.
3. ~~**E5**~~ — fully resolved ✓ (two new CSRs: `current_ecid_level` at 0xFD1, `current_ecid_parent` at 0xFD2; privilege rules added to ch14).
4. ~~**E6**~~ — fully resolved ✓ (ch04 §4.14: normative power-gating protocol — spill all Banks via `ec.im` before gating, fill via `ec.om` on wake).
5. ~~**E3**~~ — fully resolved ✓ (dirty-group bitmap in ch00 §0.3; `ec.ib` dirty-save mode and `ec.ob` bitmap clearing in ch03 §3.1).
6. ~~**E1**~~ — fully resolved ✓ (Appendix B: four standard profiles CE-Embedded/MinimalRT/RT/Full; ch16 §3.1 + §7 updated).
7. ~~**E2**~~ — fully resolved ✓ (ch18: CLIC Interrupt Integration — interrupt-EC pattern, boot allocation, M-mode prologue/epilogue, CPE isolation, MSE reservation, nested interrupts, bank provisioning).
8. **E7** — informative only; can be done any time.

---

*End of Work Items.*
