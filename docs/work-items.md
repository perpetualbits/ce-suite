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

### F8 · Ch02 §10 — binary encoding is a placeholder

**Affects:** ch02 §10 "Instruction Encoding Sketch."

**Problem:** §10 currently reads:

> Opcode: 8 bits. Function: 4 bits. Operands: rd, rs1, rs2. Mask/Imm: 8 bits.
> Full binary encoding is deferred to the formal opcode assignment stage.

This is not RISC-V encoding. RISC-V custom instructions use:
- One of the custom-opcode spaces (custom-0 through custom-3)
- Fixed-position 5-bit register fields for rd, rs1, rs2
- funct3 and funct7 fields for instruction discrimination within an opcode

**Scope:** A full binary encoding requires:
1. Selecting which custom opcode(s) to use (one block may not be enough for all four
   extensions).
2. Assigning funct3/funct7 values to each instruction.
3. Handling instructions with no rd or no rs2 (set those fields to 00000 in the encoding).
4. For instructions that need an immediate (e.g. a mask), deciding whether to use
   I-type or pass the mask in a register.

**Done when:** §10 contains an actual RISC-V binary encoding table for each CME
instruction, following the RISC-V ISA spec custom-opcode conventions. Equivalent
sections in ch07, ch08, ch09 likewise completed.

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

### G3 · RV32 width audit — "64-bit" assumptions throughout

**Affects:** All chapters; highest risk in ch02, ch07, ch08, ch09 (instruction
operand descriptions).

**Problem:** The mask width bug found in ch00 §0.10 / ch02 §7 (said "64-bit value";
should be "XLEN-wide") is a symptom of a broader pattern: the spec was written with
RV64 implicitly assumed. Similar silent assumptions may lurk elsewhere:

- Instruction operand widths stated as "64-bit" instead of XLEN.
- EC entry field sizes that only make sense on RV64.
- ECS pointer arithmetic that assumes 8-byte pointers.
- Timing or bandwidth figures that assume 64-bit bus transactions.

**Done when:** A full audit of all chapters replaces hard-coded "64-bit" claims with
XLEN-aware language where the value is passed in a register or affects hardware
behavior differently on RV32 vs RV64. Items that are genuinely 64-bit (e.g., a
64-bit counter that lives in memory, not in a register) should be annotated as such
with a rationale.

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
16. **F8** (binary encoding) — significant effort; own session(s) per extension.
17. **G3** (RV32 width audit) — systematic sweep; lowest urgency.

---

## Usage example chapters

- ~~Chapter 10 — CPE Usage Examples~~ — **DONE**
- Chapter 11 — MSE Usage Examples — not yet started
- Chapter 12 — QoS Usage Examples — not yet started

---

*End of Work Items.*
