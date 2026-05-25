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

### D2 · `ec.it` resource selection mechanism

**Affects:** ch02 (`ec.it`), ch03 (delegation semantics), ch06 (CME usage examples).

**Problem:** `ec.it rs1, rs2` (parent ECID, child ECID) specifies *who* receives
resources but not *which* resources. A parent with three banks and two Contracts cannot
use `ec.it` to delegate a specific subset.

**Decision needed:** Choose one of:

1. **`ec.it` delegates all resources** — semantics become "move everything from parent
   to child." Simple, but inflexible; parent cannot retain any resources after calling
   `ec.it`. Subsequent delegation requires separate `ec.ig`/`ms.ir` calls to the parent.
2. **Resource mask in rs2** — rs2 encodes a bitmask of resource types to delegate.
   Keeps ECID in rs1; rs2 specifies e.g. which bank slot, which Contract type.
3. **Delegate by type per instruction** — separate instructions for bank delegation
   and Contract delegation (e.g. `ec.it` for banks only; Contract delegation goes
   through `ms.it`/`qs.it`/`cp.it`). This is partially already the case for MSE/QoS.

**Note:** MSE's `ms.it` and QoS's `qs.it` already handle Contract delegation for
their respective resources. The question is whether `ec.it` should delegate banks only
(leaving Contracts to the per-extension instructions), or serve as a general delegation
dispatcher.

**Done when:** Semantics of `ec.it` are precisely defined; ch02, ch03, and the charter
updated accordingly.

---

### D3 · CPE Contract delegation

**Affects:** ch07 (CPE instruction set).

**Problem:** MSE and QoS both define delegation instructions (`ms.it`/`ms.ot`,
`qs.it`/`qs.ot`) because their Contracts are hierarchically splittable (charter §4.3).
CPE declares subset `{r}` only — no `cp.it`/`cp.ot`.

Charter §4.3 says all Contracts are splittable. Either:

- CPE cache-partition Contracts are an exception to this rule, or
- `cp.it`/`cp.ot` are missing from ch07.

**Decision needed:** Choose one of:

1. **CPE Contracts are not delegatable** — state this explicitly in ch07 and in
   charter §4.3 as an exception. Rationale: cache ways are a per-hart resource with
   fixed total capacity; splitting them hierarchically adds complexity with little gain
   since the OS already controls assignment directly.
2. **Add `cp.it` and `cp.ot`** — CPE subset becomes `{r, t}`; ch07 gains two new
   instructions with semantics parallel to MSE's.

**Done when:** Decision recorded in charter §4.3 (as exception or as acknowledgment
that cp.it/cp.ot are required); ch07 updated.

---

### D4 · `qs.or` / `qs.ot` domain selector operand

**Affects:** ch09 (`qs.or`, `qs.ot`).

**Problem:** An ECID can hold Contracts on multiple QoS domains simultaneously. `qs.or`
needs to know which domain's Contract to revoke. The current text encodes the `domain_id`
in "the low bits of `rd` on input" — but `rd` is a destination register in RISC-V; it
cannot be read by hardware. This is architecturally illegal.

**Decision needed:** How to pass the domain selector:

1. **`rs2` for domain** — `qs.or rd, rs1, rs2` where rs2 = domain_id (or 0 = all
   domains). Consistent with `qs.ir` which already uses rs2 for parameters.
2. **Implicit from Contract state** — `qs.or rd, rs1` revokes the sole Contract held
   by `rs1` on whichever domain; if rs1 holds multiple, the hardware picks one
   (requires software to call `qs.or` once per domain). Less convenient but simpler encoding.
3. **Separate instruction per domain** — explicit domain in the instruction encoding
   via an immediate. Complex; probably not worth it.

**Done when:** Syntax of `qs.or` and `qs.ot` is corrected; ch09 updated; RISC-V
architectural validity confirmed (rd is write-only).

---

## Category F — Specification fixes

These items can be resolved once the relevant D items are decided, or independently
where no design decision is needed.

---

### F1 · CPE ch07 complete redesign

**Affects:** ch07.
**Depends on:** D3 (delegation decision), D1 (error reporting policy).

**Problems:**

1. `cp.ir rs1, rs2` packs the ECID into bits 63:48 of `rs1` along with a dozen flag
   fields. This violates the ECID-first convention (charter §6.2): `rs1` should be the
   plain ECID number; parameters go in `rs2`.
2. `rs1` contains an `OPC` field (ASSIGN / MODIFY / REVOKE / QUERY) that overlaps with
   the instruction mnemonics. `cp.ir` with OPC=REVOKE and `cp.or` are redundant. The
   mnemonic should determine the operation.
3. The QUERY operation (OPC=QUERY) is mentioned but not defined: what does it return,
   in which register, in what format?

**Done when:** ch07 rewritten with `rs1` = ECID, `rs2` = partition descriptor;
OPC field removed; QUERY either defined properly or removed; delegation settled per D3;
error reporting settled per D1.

---

### F2 · `qs.or` and `qs.ot` syntax correction

**Affects:** ch09.
**Depends on:** D4.

**Done when:** Syntax corrected to not use `rd` as input; ch09 updated consistently.

---

### F3 · `ec.ir` rs1 semantics clarification

**Affects:** ch02 (`ec.ir`).

**Problem:** The description says rs1 is "maximum delegation depth permitted for the
child (must satisfy `child_L = parent_L + 1 ≤ D`; pass 0 to prevent further
delegation)." These two clauses contradict each other: if the value *must* equal
`parent_L + 1`, it cannot also be 0 for a different semantic.

**Fix:** Choose one clear meaning:

- rs1 is a **flag**: 0 = allocate leaf ECID (L = D, no further delegation); non-zero =
  allocate delegating ECID (L = parent_L + 1 < D). The constraint L = parent_L + 1
  is always satisfied by hardware; software only chooses leaf vs. non-leaf.
- rs1 is the **desired delegation level** for the child: hardware validates that it
  equals parent_L + 1 and rejects 0.

**Done when:** ch02 `ec.ir` description states one unambiguous meaning.

---

### F4 · `ms.it` rs2 dual-purpose encoding

**Affects:** ch08 (`ms.it`).

**Problem:** `ms.it rd, rs1, rs2` describes rs2 as the child ECID, but then says "the
portion [bw_class] is encoded in the low bits of `rs2` if bit 62 is set." This makes
rs2 simultaneously a 16-bit ECID (bits 15:0) *and* a bw_class selector (low bits when
bit 62 is set). The field layout is never shown explicitly.

**Fix:** Provide a formal bit-field table for rs2 in the context of `ms.it`:

| Bits | Field | Meaning |
|---|---|---|
| 15:0 | child_ecid | Child ECID to receive the split Contract |
| 19:16 | child_bw_class | Bandwidth class to delegate (0 = delegate all) |
| 23:20 | child_lat_class | Latency class to delegate (0 = delegate all) |
| 62:24 | — | Reserved, must be zero |
| 63 | ptr_flag | If set, rs2 is a pointer to an `MSE_Delegation_Params` struct |

(Exact layout TBD; the table above is illustrative.)

**Done when:** A formal bit-field table for `ms.it` rs2 appears in ch08; the
description no longer relies on "bit 62" as a magic flag without context.

---

### F5 · Charter §6.1 — CME subset list incomplete

**Affects:** Charter `project_instructions.md` §6.1.

**Problem:** Charter §6.1 lists CME's target-letter subset as `{b, m, s, v, e}`. But
ch02 defines instructions using `g` (ec.ig, ec.og), `t` (ec.it, ec.ot), and `r`
(ec.ir). These letters are in the global table and the instructions are correct, but
the charter's declared subset is wrong.

**Fix:** Update the CME subset to `{b, m, s, v, e, g, t, r}` (or whatever the settled
list is after D2 is resolved).

**Done when:** Charter §6.1 lists the correct CME subset; version bumped; changelog
entry added.

---

### F6 · `ec.is` / `ec.os` — staging bank instructions absent

**Affects:** ch02, charter §6.1.

**Problem:** Charter §6.1 lists `s` (stream / staging bank) as part of CME's subset,
implying instructions `ec.is` and `ec.os` exist or are planned. They do not appear in
ch02. The fast-path `ec.ib`/`ec.ob` operate through staging banks in hardware, but
there are no explicit staging-bank instructions.

**Decision needed:** Either:

1. **Define `ec.is` / `ec.os`** — specify what software control over staging banks is
   needed and add the instructions to ch02.
2. **Remove `s` from the CME subset** — staging banks are entirely hardware-managed;
   no software instruction is needed. Update charter §6.1.

**Done when:** One of the two options is implemented; ch02 and charter §6.1 consistent.

---

### F7 · `ec.iv` / `ec.ov` — vault instructions partially defined

**Affects:** ch02 (`ec.iv`, `ec.ov`).

**Problem:** `ec.iv` and `ec.ov` have syntax and basic side-effect descriptions, but
the semantics of "hardware-managed encryption" are underspecified: which key is used,
how it is derived, what the sealed representation looks like, how the unsealing ECID
is authenticated. Charter §8.6 defers key derivation, attestation, and rotation.

**Current state:** The instructions exist but cannot be used by an implementer or OS
author without the missing pieces.

**Options:**

1. **Flag as incomplete in ch02** — add an explicit note to `ec.iv`/`ec.ov` definitions
   stating that full semantics await resolution of charter §8.6. Prevents false
   confidence.
2. **Move to a future appendix** — remove from ch02's main instruction table; list as
   a planned extension pending §8.6 resolution.

**Done when:** ch02 clearly communicates the boundary between what is defined and what
is deferred, so a reader knows exactly what is and is not specified.

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

### F9 · CPE QUERY operation undefined

**Affects:** ch07.
**Depends on:** F1 (CPE redesign).

**Problem:** The current ch07 rs1 field includes `OPC=3=QUERY` but never defines what
a QUERY returns, in what register, in what format. If QUERY is kept after F1, it needs
a full definition.

**Done when:** Either QUERY is defined (return register, format), or it is removed from
the spec.

---

### F10 · `working_notes_for_authors.md` §5.5 stale

**Affects:** `docs/working_notes_for_authors.md`.

**Problem:** §5.5 says "MSE has been substantially designed in `scratchpads/mse/` but
does not yet have a chapter." MSE now has ch08. The scratchpads are in `docs/archive/`.

**Done when:** §5.5 updated to reflect that ch08 exists and is complete.

---

## Category G — Gaps requiring new content

Items where the spec is silent and content needs to be created.

---

### G1 · Context switch sequence diagram (ch02 §13 placeholder)

**Affects:** ch02 §13 "Placeholder: Diagrams."

Three diagrams are called out but not drawn:
1. `ec.ib` → `ec.ob` context switch sequence showing `current_ecid` transition.
2. ECID operand lookup: how `ec.ob rs1` locates the bank via `EC[rs1]`.
3. `ec.oe` subtree walk with generation-counter increments.

**Done when:** All three diagrams (ASCII or otherwise) appear in ch02 §13 and the
"Placeholder" heading is removed.

---

### G2 · Reserved-bit policy for instruction masks

**Affects:** ch02 §7 (register mask encoding).

**Problem:** The mask table lists many reserved bits (7, 8–31, 32–47, 48–51, 52–59,
60–63). There is no stated policy: are reserved bits silently ignored, or do they
cause a trap? A writer implementing this extension needs to know.

**Done when:** A one-line policy statement appears in ch02 §7.

---

## Priority order for execution

1. ~~**D1** (error/status policy)~~ — **DONE** (v0.9).
2. **D2** (`ec.it` selection) — affects CME examples directly.
3. **D3** (CPE delegation) — prerequisite for F1.
4. **D4** (`qs.or` domain selector) — prerequisite for F2.
5. **F5** (charter §6.1 CME subset) — small; do alongside D decisions.
6. **F3** (`ec.ir` clarification) — small; do in same session as ch02.
7. **F1** (CPE redesign) — large; own session after D3 settled.
8. **F2** (`qs.or`/`qs.ot` fix) — own session after D4 settled.
9. **F4** (`ms.it` encoding) — own session.
10. **F6** (`ec.is`/`ec.os`) — decision + charter update.
11. **F7** (`ec.iv`/`ec.ov` incompleteness flag) — editorial; own session.
12. **F8** (binary encoding) — significant effort; own session(s) per extension.
13. **F9** (CPE QUERY) — resolved as part of F1.
14. **F10** (working notes stale note) — trivial.
15. **G1** (diagrams) — own session after ch02 is stable.
16. **G2** (reserved-bit policy) — small; fold into ch02 session.

---

## Not started yet (after all above)

- Chapter 10 — CPE Usage Examples
- Chapter 11 — MSE Usage Examples
- Chapter 12 — QoS Usage Examples

These chapters must not be started until all D and F items above are resolved.

---

*End of Work Items.*
