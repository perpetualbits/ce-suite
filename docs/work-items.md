<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite — Work Items

**Purpose:** Tracks every known inconsistency, underspecification, and gap in the CE
Suite spec. Items are organized by type and priority. Usage-example chapters must not
be started until all Design Decision (D) and Specification Fix (F) items are resolved.

**Relationship to charter §8:** The charter's §8 lists *architectural* open items —
things not yet decided at the model level. This document lists *specification* work
items — inconsistencies and gaps within the chapters as currently written, plus
detailed design work that follows from locked architectural decisions.

---

## ⚑ Current priority — Cluster F (QoS), then Self-Preservation Invariant, then PUB5

The salvage cluster review is underway. Cluster G is complete (yielded D6, ✓ resolved).
Cluster D MSE telescoping is ✓ resolved through v0.21 (substantive) and v0.22
(corrective local-view revision; see "Cluster D Salvage" entry in Category D below).

**Next priorities:**

1. **Cluster F (MSE↔QoS isomorphism)** — framing decisions complete (refamiliarize.md
   §"Cluster F"); charter session pending (no code-prompt drafted yet).
2. **Self-Preservation Invariant** — flagged in refamiliarize.md (commit 34a0012);
   deferred until cluster F lands; requires charter + ch02/ch03/ch07/ch09/ch11 work.
3. **PUB5 §2–§4** — pre-submission gap audit axes 2–4; open.
4. **Sail redo** — holistic redo after spec completes; deferred (see refamiliarize.md
   §"Sail redo plan").

P6 (opcode allocation) and P8 (Sail completion) both remain open.
The submission email to `help@riscv.org` is in flight.

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

### D5 · Contract object model ✓ RESOLVED (v0.15)

**Decision:** Charter §4.3.0 added as a new normative subsection establishing: (a) the
Contract identity tuple `(owning_ECID, resource_class)` — no separately allocated
Contract ID; (b) the two-location state model — creation parameters in the Bank CP
field (§0.6), admission-control state in implementation-defined per-controller SRAM;
(c) the lifecycle from `*.ir`/`*.it` to `*.or`/`*.ot`/`ec.oe`. The existing four
invariants (§4.3.1 single ownership, §4.3.2 hierarchical splitting, §4.3.3 atomic
admission, §4.3.4 dissolution) and remaining items (§4.3.5 delegation depth, §4.3.6
per-extension delegation instructions) are unchanged in substance; they are now
formal numbered subsections rather than an informal numbered list.

**Deliberately out of scope:** No Contract ID namespace (ECID + class suffices). No
unified `Contract_descriptor` struct (the three resource classes have different storage
needs). No encoding changes to any `*.ir`/`*.it` instruction. No modification of
instruction semantics.

**Propagated to:** charter §4.3 restructured; ch00 §0.7.0 added (model restated with
concrete example); ch07 §7.4 single-sentence cross-reference; ch09 §9.4.1
single-sentence cross-reference; ch11 §11.5.1 single-sentence cross-reference;
refamiliarize.md §A.3 updated.

---

### D6 · TLB behavior of `ec.ob` when bit 6 (SATP) is set in the mask ✓ RESOLVED (v0.19)

**Decision:** Charter §6.8 (v0.19) established: when `ec.ob` restores a context with
mask bit 6 (SATP) set and the restored SATP value differs from the SATP value in effect
immediately before the `ec.ob`, hardware performs a TLB invalidation atomically with the
SATP restore, using any scope that satisfies the standard `csrw satp` followed by
`sfence.vma x0, x0` pattern. Implementations are *permitted* to skip the invalidation
when the restored SATP equals the current SATP (the unchanged-SATP optimization) but are
not *required* to detect this case; a conformant implementation that always invalidates is
also correct. Three sub-decisions parked as charter §8 open items:
- **D6.1** — Exact scope of the auto-invalidation (full flush vs. ASID-targeted vs.
  implementation-defined minimum). Relevant empirical scratchpad:
  `scratchpads/general/2026-05-asid-vmid-empirical.md`.
- **D6.2** — H-extension analogues for `vsatp` (via `hfence.vvma`) and `hgatp`
  (via `hfence.gvma`); resolution depends on D6.1 and ch19 §19.2.1 language.
- **D6.3** — Charter §1 "1–2 cycle" claim qualification for cross-address-space
  switches; see parked RT-subset insight in
  `scratchpads/general/2026-05-rt-subset-determinism.md`.

**Propagated to:** charter §6.8 (v0.19) and §8 items D6.1–D6.3; ch03 §3.1
"TLB Invalidation on SATP Restore" subsection (commit e6de533); ch00 §0.10
forward-reference note on mask bit 6 (commit f4e53a5); ch17 §17.2.1 note
distinguishing TLB invalidation from RVWMO fence obligations (commit 3e8e1f7);
Sail `ce_cme_execute.sail` `ec.ob` SATP handling with conditional
`flush_TLB(None(), None())` and supporting prelude additions (commit 2b9e9da).

**Deferred:** ch19 `vsatp`/`hgatp` TLB invalidation analogue, pending D6.2 resolution.

---

### Cluster D Salvage — MSE Telescoping Resolution ✓ RESOLVED (v0.21 + v0.22)

**v0.21 substantive work (commit 6c46f5a):** Cluster D (MSE telescoping and
arbitration policy) was the largest architectural addition in the cluster review
cycle. The resolution introduced:

- **Telescoping with per-delegation precision.** MSE Contracts can be split
  hierarchically via `ms.it`; each delegation step may reduce the child's precision
  (1–8 bits). Round-down rounding preserves the "child receives at most parent's
  promise" invariant.
- **Pre-flattening.** Hardware computes the child's absolute bandwidth at delegation
  time and stores it pre-flattened in the leaf Contract for O(1) arbitration.
- **8-bit field widths.** `bw_class` and `lat_class` are 8-bit fields (max 255),
  discoverable via `mse_caps`.
- **Multi-tier slot arbitration.** Within CN slots: within-budget Contract holders
  by `lat_class` → over-budget holders by `lat_class` → BE fallthrough. Idle
  bandwidth is never wasted.
- **Dithered slot scheduling.** Slot pattern satisfies `CN_FRAC` over each window
  and bounds the maximum gap between consecutive CN slots to ⌈256/CN_FRAC⌉.
  Preserves the (K+1) × slot_size_ns worst-case CN latency under interrupt nesting.
- **Cap rule.** Group bandwidth cap enforced on pre-flattened absolute values;
  round-down creates small unused capacity that flows via overflow or BE.
- **D7.1 parked.** A formal priority-inversion / bandwidth-donation mechanism is
  deferred to ratification-stage refinement (charter §8 item 10).

**Propagated to (v0.21):** charter §4.5 (new section); ch09 §9.4–§9.5 (significant
additions); ch10 (new usage examples); ch13 (new `mse_absolute_bw` and `mse_caps`
CSRs).

---

**v0.22 corrective revision (2026-05-30):** The v0.21 work inadvertently described
MSE telescoping in *global-view* terms — software at each delegation level would see
CSR values representing fraction-of-total-system-bandwidth. This violated CE Suite's
foundational property that software runs unchanged at any delegation level (the same
property CME's Group-zero-from-anywhere already embodies). Without local-view
semantics, kernel images would need depth-aware variants — incompatible with CE
Suite's deployment goals.

**Principle established:** *Software runs unchanged at any delegation level.* Each
level sees its bandwidth on a 0–255 local scale representing fraction of *its own
slice*. Hardware translates between levels transparently (stored-global for
arbitration; local readback via Formula 2). Stated formally in charter §4.5.0 and
ch00 §0.11 (architectural principle).

**The math (ch09 §9.4.6):**
- Formula 1 — storage at delegation: `s(c) = floor(s(p) × b(c) / 256)`
- Formula 2 — local readback: `r(e) = floor(s(e) × 256 / s(p(e)))`
- Verification: substituting Formula 1 into Formula 2 gives `r(c) ≈ b(c)`
  with bounded round-down residual. Software at any depth sees the value its
  parent wrote.

**Hardware mechanics unchanged from v0.21:** multi-tier slot arbitration, dithered
slot scheduling, round-down rounding, pre-flattening, reconfiguration timing.

**Commit chain:**

| Step | Commit |
|---|---|
| Charter v0.22 §4.5.0 + §4.5.1/2/3 revision | d535088 |
| ch09 — new §9.4.6 mathematical foundation + section revisions | 62f2474 |
| ch13 — §5.9 local-view rewrite + §5.4/§5.5 stored-global annotations | abab423 |
| docs/meta/web-claude-project-instructions.md stub | 9c63ebb |
| ch10 — extensive recast of MSE usage examples | 668153f |
| docs/refamiliarize.md "Current Work in Progress" section | d50152c |
| ch05 §5.7 — Linux SCHED_DEADLINE local-view mapping (ceil × 255) | 539bbcc |
| refamiliarize Self-Preservation Invariant note | 34a0012 |
| ch00 — new §0.11 foundational architectural principle | b140e85 |
| Sail-A patch — `read_CSR(0xFD3)` returns local view (Formula 2) | 446bdb2 |
| Sail-A hash back-fill | 9bfbe11 |

**Audit history:** The global-view error was surfaced by the architect late in the
cluster D framing session. Key insight: "Every OS and distro .iso would have to be
aware of where it would land. L0, L1, L2, L3. A nightmare." The v0.22 chain
corrects this before any downstream Sail redo or third-party implementation could
encode the wrong semantics. The OS-developer-perspective check ("does code at level N
work identically to code at level 0?") is now a default framing question for all
future salvage cluster sessions — see refamiliarize.md §"Workflow improvement noted."

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

### ~~F11~~ · ch08 Markdown line-wrap produces spurious `0.` list item in adoc — DONE

**Affects:** `docs/chapters/ch08-cpe-usage-examples.md`, §8.1 "All examples assume" bullet.

**Found during:** P7 adoc verification (`make html`). asciidoctor warning:
`ch08-cpe-usage-examples.adoc: line 23: list item index: expected 1, got 0`.

**Root cause:** The sentence "bit `[XLEN-1]` =\n0. The pointer form…" wraps so that
`0.` falls at the start of a new line inside a bullet point. AsciiDoc interprets this
as an ordered list item starting at 0 (which it does not support).

**Fix applied:** Changed `= 0. The pointer form` to `= 0; the pointer form` in
`ch08-cpe-usage-examples.md` §8.1; `make adoc` regenerated the adoc cleanly.

---

### F12 · §4.3.N cross-reference numbering drift in ch11, ch13, ch02

**Affects:** `ch11-qos-io-quality-of-service.md`, `ch13-csr-reference.md`,
`ch02-bank-group-delegation.md`.

**Found during:** D5 v0.15 propagation check (charter §4.3 restructuring).

With the formal §4.3.0–§4.3.6 subsection numbering established in v0.15, the
following pre-existing references are inconsistent with the convention used in
ch09 and ch17 (and now canonical):

- ~~**ch11 §11.5.3:** "charter §4.3.3" for hierarchical splitting — should be §4.3.2.~~ ✓ fixed
- ~~**ch11 §11.5.4:** "charter §4.3.5" for dissolution — should be §4.3.4.~~ ✓ fixed
- ~~**ch13 §4.1, `cpe_caps` DELEG bit:** "charter §4.3.7" for per-extension delegation
  instructions — should be §4.3.6 (§4.3.7 does not exist).~~ ✓ fixed
- ~~**ch02 §3.4:** "charter §4.3 item 7" for Contract delegation — should be §4.3.6.~~ ✓ fixed

---

### F13 · `ec.ob` generation counter encoding unspecified

**Affects:** `ch03-cme-instruction-set.md` §3.1 (`ec.ob` description).

**Found during:** S11 (Sail formal model — generation counter validation).

The spec states that `ec.ob` returns `CME_ERR_INVALID_ECID` on "generation
mismatch" but never specifies how the expected generation reaches the
instruction. The rs1 description says only "Target ECID number." Without an
explicit encoding, neither software nor hardware can implement the check.

**Options:**

**Option A — Pack into rs1 (recommended):** `X(rs1)[23:16]` = expected
generation (8 bits); `X(rs1)[15:0]` = ECID slot index (16 bits); bits
[63:24] = must be zero (ILLEGAL_FIELD if non-zero). This is the natural
register-packing idiom for a `(ECID, generation)` pair. The Sail model
(S11) already uses this convention as a placeholder.

**Option B — Software convention only:** The generation check is a software
responsibility; hardware only checks `allocated == true`. Simpler, but does
not provide a hardware ABA guarantee — a reallocated slot (same ECID number,
new generation) would pass the hardware check with stale software state.

**Recommendation:** Option A. It matches the spec's claim that the hardware
returns `CME_ERR_INVALID_ECID` on mismatch (Option B cannot satisfy this),
and the packing is unambiguous.

**Resolution:** Update ch03 §3.1 `ec.ob` rs1 description to specify the
`(generation[23:16] | ecid[15:0])` encoding. Add a note to §3.10.3 encoding
table. Update the §3.13.1 context-switch diagram to show the packed value.

**Status:** ✓ ch03 fixed (§3.1 rs1 description, §3.10.3 table footnote, §3.13.1
diagram). ch06 minimal propagation fix applied (one line). Two follow-up
fixes deferred to dedicated sessions:
- **ch05 §5.4**: code example uses `lhu a1, ECID_OFFSET(...)` (16-bit load)
  and prose says "16-bit ECID number" — needs `lwu`/`ld` and prose update.
- **ch14 §14.8**: vm_ecid/hs_ecid code examples need prose clarification
  that registers hold the packed (generation, ecid) value.

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
5. ~~**D5** (Contract object model)~~ — **DONE** (v0.15).
6. ~~**D6** (TLB behavior on SATP restore)~~ — **DONE** (v0.19).
7. ~~**F5** (charter §6.1 CME subset)~~ — **DONE**.
8. ~~**F3** (`ec.ir` clarification)~~ — **DONE**.
9. ~~**F1** (CPE redesign)~~ — **DONE**.
10. ~~**F2** (`qs.or`/`qs.ot` fix)~~ — **DONE** (with D4).
11. ~~**F4** (`ms.it` encoding)~~ — **DONE**.
12. ~~**F6** (`ec.is`/`ec.os`)~~ — **DONE** (option 2: `s` removed).
13. ~~**F7** (`ec.iv`/`ec.ov` incompleteness flag)~~ — **DONE**.
14. ~~**F9** (CPE QUERY)~~ — **DONE** (resolved in F1).
15. ~~**F10** (working notes stale note)~~ — **DONE**.
16. ~~**G2** (reserved-bit policy)~~ — **DONE**.
17. ~~**G1** (diagrams)~~ — **DONE**.
18. ~~**F8** (binary encoding)~~ — **DONE**.
19. ~~**G3** (RV32 width audit)~~ — **DONE**.
20. ~~**F11** (ch08 `0.` line-wrap artifact from P7 adoc verification)~~ — **DONE**.
21. ~~**F12** (§4.3.N drift in ch11 §11.5.3/§11.5.4, ch13 §4.1, ch02 §3.4)~~ — **DONE**.

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

**Sail encoding freeze.** For the purposes of Sail v1 modelling, the encoding
defined in ch03 §3.10 (custom-0 opcode `0001011`, R-type, funct3/funct7 scheme)
is treated as frozen. Sail decode functions will be written against this encoding.
If RISC-V International assigns a different opcode, the Sail decode tables will
need to be updated, but the execute functions will be unaffected. This decision
does not require a charter change — it is a modelling scope decision.

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

### P7 · AsciiDoc conversion (mechanical) ✓ RESOLVED

**Affects:** All chapters.

All 25 `.adoc` files generated and verified. `Makefile` added with `adoc`, `html`,
`pdf`, `check`, and `clean` targets. `make html` produces `build/index.html` (805 KB,
549 headings, 144 tables) via asciidoctor. One minor Markdown formatting artifact
remains in ch08 — tracked as F11.

---

### P8 · Sail formal model (large, separate project)

**Affects:** Separate deliverable alongside the spec.

RISC-V ratification increasingly requires a Sail formal model of instruction
semantics. This is a significant engineering effort independent of the spec text
and is noted here for completeness. Not a near-term authoring task.

**Vault instructions out of scope for Sail v1.** `ec.iv` and `ec.ov` are
defined as instruction shells in the spec; their cryptographic execute semantics
(key derivation, attestation, sealing format) are deferred to a future revision.
Sail v1 will model the decode for these instructions but not their execute
semantics. They will be represented as `undefined` or `unimplemented` in the
Sail execute function. This is a deliberate scope boundary, not a gap.

**Chip-global admission control abstraction.** The spec requires that Contract
creation (`ms.ir`, `qs.ir`, `cp.ir`, `ms.it`, `qs.it`, `cp.it`) involves
chip-globally atomic admission control (ch00 §0.7.4). Sail models a single hart
and cannot represent chip-global state directly. For Sail v1, admission control
will be modelled as an abstract function `admit_contract(ecid, class, params)`
that is axiomatised to either succeed (returning the new Contract state) or fail
atomically — the internal global accounting is treated as a black box. This is
sufficient for modelling instruction behaviour on a single hart; multi-hart
admission interactions are out of scope for Sail v1.

---

## Proposal-readiness priority order

1. ~~**P1** — CSR chapter (blocks P2 and P4).~~ — **DONE** (ch13).
2. ~~**P2** — Privilege model (depends on P1 ✓).~~ — **DONE** (ch14).
3. ~~**P3** — Trap/exception table (can start in parallel with P2).~~ — **DONE** (ch15).
4. ~~**P4** — Discovery mechanism (depends on P1 ✓).~~ — **DONE** (ch16).
5. ~~**P5** — Memory ordering (independent; can be done any time).~~ — **DONE** (ch17).
6. **P6** — Opcode/name allocation (process item; engage RISC-V International).
7. ~~**P7** — AsciiDoc conversion (mechanical; do last).~~ — **DONE**.
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

### E7 · SCHED_DEADLINE / MSE Integration ✓ RESOLVED

**Affects:** ch05 (Linux Kernel Integration) — new §5.7 (informative).

**Decision:** §5.7 "SCHED_DEADLINE and MSE Integration (Informative)" added to
ch05 with six subsections:

- §5.7.1 — Background: CBS model and CPU feasibility; why CPU admission alone
  is insufficient for hard RT.
- §5.7.2 — Mapping `runtime`/`period` and peak DRAM bandwidth to `bw_class`
  and `lat_class`.
- §5.7.3 — Two-phase admission at `sched_setattr()`: CPU feasibility first,
  then `ms.ir`; `MSE_ERR_SYSTEM_FULL` (4) or `MSE_ERR_CAP_EXCEEDED` (3) maps
  to `EBUSY`.
- §5.7.4 — Task lifecycle: `ec.ob` self-manages bw_class/lat_class across
  context switches; no per-switch MSE instruction needed; `ms.or` on demotion,
  `ec.oe` on teardown.
- §5.7.5 — Cgroup bandwidth caps: parent ECID's `bw_cap` enforces per-cgroup
  memory bandwidth limits.
- §5.7.6 — CPE + MSE combination for end-to-end provable WCET.

No new instructions, CSRs, or charter changes. §5.4.1 updated with a forward
reference to §5.7.

**Propagated to:** ch05 §5.4.1 (forward reference added); ch05 §5.7 (new
section); adoc/chapters/ch05-linux-integration.adoc (mirrored).

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
8. ~~**E7**~~ — fully resolved ✓ (ch05 §5.7: SCHED_DEADLINE admission integrates `ms.ir`; two-phase check; cgroup caps; CPE+MSE WCET).

---

## Category I — Interop

Items that specify how CE Suite coexists with external RISC-V extensions and profiles.

---

### I1 · Ratified-extension interop chapter ✓ RESOLVED

**Affects:** `docs/chapters/ch19-interop-ratified-extensions.md` (new chapter);
`docs/adoc/chapters/ch19-interop-ratified-extensions.adoc` (generated); `docs/adoc/index.adoc`
(ch19 include added between ch18 and appendix-a); ch16 §7 (one-sentence cross-reference added);
`docs/submission/submission-brief.md` and adoc mirror (ch19 listed in §8).

**What was produced:** A normative chapter (12–16 printed pages) mapping the RVA23S64
mandatory extension set and RVA23.1 optional extensions to CE Suite save/restore
obligations. For each extension the chapter identifies which CSRs belong in the per-EC
bank CSR slot (ch00 §0.6), how the `Smstateen`/`Ssstateen` CE-Suite gate bit (proposed
at bit 58 of `*stateen0`, provisional) interacts with `S_EN`/`VS_EN` (ch14), and what
state is per-hart vs. per-ECID.

**Covered in full sections:**

- H extension and Sha: `hgatp`, `hstatus`, `vsatp`, `vsstatus`, `vstvec`, `vsepc`,
  `vscause`, `vstval`, `vsie`, `vsip`, `vsscratch`, `sstateen0–3`, `hstateen0–3`.
- Smstateen / Ssstateen: CE-Suite gate bit assignment (bit 58, provisional); complementary
  relationship with `S_EN`/`VS_EN`.
- Smaia / Ssaia: `siselect`, `sireg`, `stopei`, `stopi`, `sseteipnum`, `sclreipnum`,
  `sseteienum`, `sclreienum`, `sclaimei`, and VS equivalents; IMSIC per-hart note.
- Sstc: `stimecmp`, `vstimecmp`. Sscofpmf: `scountovf` per-hart. Svnapot, Svinval:
  orthogonal.
- Supm / Ssnpm: `senvcfg`, `henvcfg`, `hstatus` PMM fields.
- Zicfilp / Zicfiss: ELP state bits in `sstatus`/`vsstatus`, `ssp`.
- Smcdeleg / Ssccfg: `scountinhibit`; Sscsrind: already covered by §19.2.3.
- Smmpm / Smnpm: per-hart in standard deployment.
- Sv48 / Sv57: SATP slot covers full value; no mode constraints.
- Svadu, Sdtrig, Ssstrict, Svvptc, Sspm: orthogonal.
- Ssqosid (RVA23.1): `srmcfg` per-EC; CE Contracts as admission layer above RCID
  tagging; open option for future RCID integration in Contract descriptor parked in
  charter §8.
- Ssctr (RVA23.1): CTR table via `siselect`/`sireg`, `scountovf`.
- Sscfg, Ssdbltrap, Svrsw60t59b (RVA23.1): per-paragraph coverage.
- Deferred: Smclic/ACLIC (ch18), Smmtt/Smsdid (v0.49 draft), charter §8 open items.
- §19.6 summary table: complete mapping of all 29 extensions.

**What was deliberately deferred:**

- The Ssqosid RCID→Contract integration option: parked in charter §8.
- Smmtt / Smsdid interoperability rules: deferred pending ratification.
- Smclic / ACLIC: handled by ch18; cross-referenced only.
- Any extension in Development or early Draft state not on the March 2026 BoD track.

**No new instructions, CSRs, or charter-level decisions were made in this session.**
The provisional `*stateen0` bit 58 assignment follows the same status as opcode
addresses and CSR addresses throughout the spec.

---

---

## Category PUB — Publication readiness

PUB1–PUB4 are resolved. Internal editorial scaffolding has been removed
from all publishable spec files. The adoc mirrors were regenerated via
`md2adoc.py` (updated to auto-emit SPDX headers) and the PDF/HTML builds cleanly.

---

### PUB1 · Remove retired-instruction rename history ✓ RESOLVED

The rename chain `ec.or → ec.od → ec.oe` is internal revision history. Readers of
a published spec need only the current name `ec.oe`; they do not need to know it
was ever called anything else.

**Affects and what to remove:**

- **`ch03-cme-instruction-set.md`** — two passages:
  - Lines ~37–39: introductory note "ec.or does not exist as a current instruction…
    renamed first to ec.od (v0.7) and then to ec.oe (v0.8)…"
  - Lines ~313–328: entire subsection "**Why there is no `ec.or`.**" explaining
    the rename history.
- **`ch00-fundamental-structure.md`** — lines ~370–371: parenthetical
  "(the name was retired; forced destroy is `ec.oe`)" — simplify to just name `ec.oe`.
- **`glossary.md`** — entire "Retired terms (do not use)" section (heading + table
  rows for `ec.or` and `ec.od`).

---

### PUB2 · Remove work-item tracking tags from spec text ✓ RESOLVED

P-series, F-series, and E-series labels are the project's internal tracking system.
They are invisible to implementers and reviewers of the published spec.

**Affects and what to remove:**

- **`ch14-privilege-model.md`** — most extensive: opening "(P2 work item)" in the
  first paragraph; "**Resolved questions (from the P2 work item):**" subheading
  and its bullet list; multiple inline "(P2 S-mode relaxations)" parentheticals.
- **`ch15-trap-table.md`** — opening sentence "(P3 work item) resolves…" — strip
  the tag; keep the rest of the sentence.
- **`ch16-discovery.md`** — opening "(P4 work item)" — strip tag only.
- **`ch13-csr-reference.md`** — several instances: "added in E5"; "(P2 — privilege
  model integration)"; "work item F7"; "(subject to P2 S-mode relaxations)";
  "(M-mode-only restriction applies even after P2 relaxations)"; "§0.3, Chapter 1
  §1.4, and charter §5.1, which did not previously assign a CSR" (history clause).
- **`ch17-memory-ordering.md`** — one instance: "§P5 poses" → rephrase without
  the tag (e.g., "The following questions arise for each category…").
- **`ch18-clic-integration.md`** — one instance: "(E3)" parenthetical inline.

---

### PUB3 · Remove or convert "charter §X" citations ✓ RESOLVED

The charter (`docs/charter/project_instructions.md`) is an internal authoring
document. Published specs do not cite their own design notes. In nearly every case
the normative rule is already stated in the spec chapter itself; the "(charter §X)"
parenthetical is just the source attribution, which readers do not need.

**Default action:** delete the parenthetical. Where the cross-reference adds
genuine reader value (e.g., pointing to a defined section of the spec itself),
convert to an in-spec section number.

**Affected files (one session each):**

| File | Approximate instance count | Notes |
|------|---------------------------|-------|
| `ch03-cme-instruction-set.md` | ~8 | Mix with PUB1 session |
| `ch13-csr-reference.md` | ~10 | Mix with PUB2 session |
| `ch09-mse-memory-scheduling.md` | ~12 | Highest count; mostly §4.3.X and §6.X |
| `ch11-qos-io-quality-of-service.md` | ~12 | Similar pattern to ch09 |
| `ch00-fundamental-structure.md` | ~4 | Mix with PUB1/PUB4 session |
| `ch19-interop-ratified-extensions.md` | ~6 | Several "charter §8" open-item refs |
| `ch02-bank-group-delegation.md` | ~4 | All parenthetical |
| `ch07-cpe-instruction-set.md` | ~3 | All parenthetical |
| `appendix-a-ecid.md` | ~3 | All parenthetical |
| `ch05-linux-integration.md` | ~2 | |
| `ch17-memory-ordering.md` | ~2 | Mix with PUB2 session |
| `ch04-hardware-microarch.md` | ~1 | "charter open items (charter §8.7)" |
| `ch06-cme-usage-examples.md` | ~1 | |
| `ch14-privilege-model.md` | ~1 | Mix with PUB2 session |
| `ch15-trap-table.md` | ~1 | Mix with PUB2 session |
| `ch16-discovery.md` | ~1 | Mix with PUB2 session |
| `ch18-clic-integration.md` | ~1 | Mix with PUB2 session |
| `glossary.md` | ~3 | Mix with PUB1/PUB4 session |
| `instruction-card.md` | ~2 | |

---

### PUB4 · Remove meta-document references ✓ RESOLVED

References to internal file paths, the charter as an external document, and
"earlier drafts" design history do not belong in published spec text.

**Affects and what to remove:**

- **`ch00-fundamental-structure.md`** — lines ~12–14: "The CE Suite charter
  (`docs/charter/project_instructions.md`) is the normative spine… if a later
  chapter conflicts with this one, the chapter is wrong." Rewrite as a
  self-referential statement without the file path: "This chapter, together with
  the CE Suite Project Instructions, is normative. If a later chapter conflicts
  with this chapter, the later chapter is wrong."
- **`ch01-execution-context-model.md`** — one sentence (~line 231): "Earlier
  drafts placed a Pool layer between ECIDs and Contracts." Delete it; the Pool
  model is not defined anywhere in the published spec, so the reference to it
  is meaningless to readers.
- **`glossary.md`** — intro lines 3–5: "A standalone copy of the normative
  glossary from charter §2, plus the list of retired terms, for quick lookup.
  **If this file disagrees with the charter, the charter wins.**" Rewrite without
  the "copy of charter §2" framing.

---

### PUB5 · Pre-submission gap audit

**Problem:** The spec is complete at the chapter level (ch00–ch19,
appendices A/B) but has not been systematically audited against its own
load-bearing claims for gaps in mechanism specification. The discovery
of D6 — a gap that materially affects the charter §1 "1–2 cycle
context switches" claim — indicates that other claim-to-mechanism gaps
likely exist. A RISC-V International reviewer will perform this
walk-through during routing or TG-formation review; doing it first lets
the project address findings on its own timeline rather than under
review pressure, and prevents the proposal from being characterized as
"promising but incomplete" on first inspection.

**Method:** A dedicated session walks through four axes:

1. **Charter §1 claims against chapter mechanisms.** For each
   load-bearing claim in the introduction — 1–2 cycle context switches,
   opt-in at every privilege level, certifiability for ASIL D /
   DO-178C / FDA Class III, 5–15% transistor overhead — identify the
   chapter(s) where the mechanism is specified, and verify the
   mechanism is fully specified rather than merely named.

   **Status (2026-05-29):** The area-claim sub-item is substantially
   addressed. The "5–15% transistor overhead" claim is now backed by:
   - `tools/ce-sizing-calculator.py` (v2, commit 891361c) — replaced the
     v1 calculator with industry-current SRAM data and concrete baselines.
   - `docs/chapters/appendix-c-implementation-guidance.md` §C.4
     (commit e6ea612) — stratified analysis by deployment class with named
     public baselines (SiFive U84, Cortex-A55, P670-class).
   - Charter §1 (v0.20, commit 6581fc1) — headline "5–15%" range retained
     with inline cross-reference to Appendix C §C.4.
   - `docs/chapters/ch01-execution-context-model.md` §1 (commit 5f297e7)
     — same refinement propagated from charter.
   - `docs/submission/submission-brief.md` §7.1 (commit 824ac10) — full
     rework with stratified table and per-component breakdown.

   Remaining gap: empirical validation against an actual RISC-V
   implementation (synthesis numbers from the hw/ work plan, when
   undertaken). This is captured in `hw/work-items.md` and does NOT
   block PUB5 closure. The other three axes (items 2–4) remain open.

2. **Global-state-mutating instructions.** For every CE instruction
   that mutates hart-global state (SATP via mask bit 6, mstatus,
   interrupt enables, fence state, ASID, contexts visible to other
   harts), verify the spec says what happens to dependent hardware
   structures — TLB entries, cache state, in-flight memory operations,
   interrupt latches — on that mutation. D6 is one example of this
   class.

3. **Implementation-defined surfaces.** For every "implementation-
   defined" or "implementation may" phrase, verify it does not hide a
   portability hole — i.e., that two conformant implementations cannot
   legally diverge in a way that breaks user-visible behavior.

4. **Cross-chapter references.** For every "§X.Y" or "Chapter N"
   cross-reference, verify the reference still points to the section
   claimed, and that the target section still says what the reference
   claims.

**Output:** Each finding becomes its own entry in `docs/work-items.md`
under the appropriate category (D / F / Gap / PUB / E). The audit
itself produces no spec changes — only new work items.

**Affected files:** None directly. Findings will identify affected
files for each follow-up item.

**Depends on:** No blocking dependencies. Recommended sequence is to
run after the salvage cluster work concludes (so the audit doesn't
compete with cluster decisions for attention) but before significant
new Sail work on mechanisms the audit might find gaps in.

**Unblocks:** Reduces the volume and severity of changes that will be
requested by RISC-V International reviewers post-submission. Improves
the signal of the proposal's completeness on first contact.

**Priority:** Medium-high. The salvage cluster work is currently in
progress; PUB5 should follow its completion.

**Estimated effort:** One focused session for the audit itself
(single-digit hours). Variable follow-on effort depending on findings.

**Source:** Surfaced from the discussion that produced D6
(2026-05-29). The recognition that one gap was found suggests
systematic search for others is warranted.

---

## PUB execution order (file by file) ✓ ALL 20 SESSIONS COMPLETE

All 20 files processed. `md2adoc.py` updated to auto-emit SPDX headers;
`make adoc` regenerated all mirrors; PDF and HTML rebuild cleanly.

| # | File | PUB items | Notes |
|---|------|-----------|-------|
| 1 | `ch03-cme-instruction-set.md` | PUB1 + PUB3 | Retire history + charter refs |
| 2 | `ch14-privilege-model.md` | PUB2 + PUB3 | P-series tags most extensive here |
| 3 | `glossary.md` | PUB1 + PUB3 + PUB4 | Retire terms table + meta intro |
| 4 | `ch00-fundamental-structure.md` | PUB1 + PUB3 + PUB4 | File path ref + minor retire ref |
| 5 | `ch13-csr-reference.md` | PUB2 + PUB3 | Multiple E/P tags + charter refs |
| 6 | `ch15-trap-table.md` | PUB2 + PUB3 | P3 tag + one charter ref |
| 7 | `ch16-discovery.md` | PUB2 + PUB3 | P4 tag + one charter ref |
| 8 | `ch17-memory-ordering.md` | PUB2 + PUB3 | P5 ref + two charter refs |
| 9 | `ch18-clic-integration.md` | PUB2 + PUB3 | E3 tag + one charter ref |
| 10 | `ch01-execution-context-model.md` | PUB4 | One sentence only |
| 11 | `ch09-mse-memory-scheduling.md` | PUB3 | Most charter refs of any single file |
| 12 | `ch11-qos-io-quality-of-service.md` | PUB3 | Similar volume to ch09 |
| 13 | `ch19-interop-ratified-extensions.md` | PUB3 | Several charter §8 refs |
| 14 | `ch02-bank-group-delegation.md` | PUB3 | Four parentheticals |
| 15 | `ch07-cpe-instruction-set.md` | PUB3 | Three parentheticals |
| 16 | `appendix-a-ecid.md` | PUB3 | Three parentheticals |
| 17 | `ch04-hardware-microarch.md` | PUB3 | One instance |
| 18 | `ch05-linux-integration.md` | PUB3 | Two instances |
| 19 | `ch06-cme-usage-examples.md` | PUB3 | One instance |
| 20 | `instruction-card.md` | PUB3 | Two instances |

After all 20 sessions: regenerate adoc mirrors (`make adoc`), rebuild PDF
(`make pdf`), and tick PUB1–PUB4 as resolved.

---

*End of Work Items.*
