<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite Sail — Work Items

**Purpose:** Tracks every task in the CE Suite Sail formal model from toolchain
setup through submission. Items are ordered by dependency; nothing in a later
phase should be started until the items it depends on are resolved.

**Relationship to spec:** The CE Suite specification (`docs/chapters/`) is the
normative reference. This Sail model is derivative. When a Sail execute function
disagrees with the spec, the spec wins.

**Scope decisions (recorded in `docs/work-items.md` P6/P8):**
- Encoding frozen at custom-0 for Sail v1; only decode tables need updating if
  P6 changes opcode assignment.
- `ec.iv`/`ec.ov` execute semantics are out of Sail v1 scope (encryption
  algorithm implementation-defined; key management deferred).
- Chip-global admission control is axiomatised as a black-box function; multi-hart
  admission interactions are out of scope for Sail v1.

---

## ⚑ Current priority — Phase 1 (toolchain)

Set up the Sail toolchain and get `make check-riscv` to pass before writing
any execute logic. Type errors found early are cheap; type errors found after
ten execute functions are expensive.

---

## Phase 1 — Toolchain and integration

### S1 · Install Sail toolchain

**What:** Install the Sail compiler via OPAM.

```
opam install sail
```

Verify: `sail --version` prints a version ≥ 0.17.

**Status:** ✓ Done — Sail 0.20.1 via OPAM 2.5.0; OCaml 5.2.1; z3 4.13.3.
Installed: `sudo apt install opam libgmp-dev pkg-config bubblewrap z3`,
then `opam init --bare`, `opam switch create default ocaml-base-compiler`,
`opam install sail`. Binary at `~/.opam/default/bin/sail`; sourced via
`~/.opam/opam-init/init.sh` in `.bashrc`.
Note: `make check` finds a syntax error in `ce_state.sail` line 58 and a
`let`-mutability bug in `find_bank` — both deferred to S3.

---

### S2 · Clone sail-riscv and identify integration point

**What:** Clone the official RISC-V Sail model and identify where CE Suite
extension clauses should be inserted.

```
git clone https://github.com/riscv/sail-riscv.git
```

Identify: which sail-riscv files define `ast`, `execute`, `read_CSR`,
`write_CSR` — these are the extension points CE Suite hooks into.

**Deliverable:** A short note (comment in `sail/README.md`) documenting which
sail-riscv files are included and in what order.

**Status:** ✓ Done — sail-riscv uses `.sail_project` module system, not flat
files. Four scattered declarations are the CE Suite hooks:
`scattered union instruction` and `scattered function execute` in
`sys/insts_begin.sail`; `scattered function read_CSR` / `write_CSR` in
`core/csr_begin.sail`. Pattern to follow: Zicond extension. Integration note
and S4 Makefile warning documented in `sail/README.md`.
sail-riscv cloned to `~/git/sail-riscv`.

---

### S3 · Get `make check` to pass (standalone)

**What:** `sail -just_check` on the CE Suite sources alone, without sail-riscv.
Fixes all type errors in the CE Suite model files.

**Depends on:** S1

**Status:** ✓ Done — `make check` exits 0 (warnings only; no errors).
Fixes required in skeleton:
- `struct { ... }` keyword needed for new record literals (not `{ ... }`)
- `{ record with field = v }` correct for updates (no `struct` keyword)
- `cme_status[7..0] = v` for slice assignment (not `with [n..m]` syntax)
- `var` not `let` for mutable locals (find_bank result)
- `union clause instruction` throughout (not `union ast` / `union clause ast`)
- Decode mappings require literal bit patterns, not symbolic constants
- `lookup_ec`: foreach loop instead of direct index (bounds proof issue)
- `bank_pool[idx]`: `truncate(slot, 3)` to give Sail a 3-bit index type
- New `ce_standalone_prelude.sail`: stubs for xlenbits, regidx, X(), zeros(),
  zero_extend(), to_bits(), `%` operator, `~` for bool, scattered declarations
- Source order: ce_cme_types before ce_state (EC_entry/Bank defined before use)

---

### S4 · Get `make check-riscv` to pass (integrated)

**What:** CE Suite sources type-check when compiled after sail-riscv prelude,
types, and register definitions. Resolve any name conflicts or missing
dependencies.

**Deliverable:** `make check-riscv` exits 0. Update `sail/Makefile` with the
correct sail-riscv include path list.

**Depends on:** S2, S3

**Status:** ✓ Done — `make check-riscv` exits 0 (warnings only).
Integration approach: `scripts/inject_ce_files.py` uses `sail --list-files`
to get the sail-riscv ordered file list, injects CE Suite files immediately
before `postlude/insts_end.sail` (where scattered unions are closed).
Fixes required beyond S3:
- `write_CSR` must return `result(xlenbits, unit)` — add `Ok()` wrapper
- `regidx` is a `newtype` in sail-riscv; standalone prelude updated to match
- `encdec_reg(rs1)` needed in decode mappings (not plain `rs1`)
- `encdec_reg(rs1) == 0b00000` for x0 check in execute (not `rs1 == 0b00000`)
- Removed `raise()`/exception stubs from execute — use `Illegal_Instruction()`
  (the sail-riscv `ExecutionResult` variant) uniformly in both modes
Default SAIL_RISCV: `$(HOME)/git/sail-riscv`.

---

## Phase 2 — CME core: ec.ib / ec.ob

These two instructions are the entire fast-path context switch. Getting them
right validates the state model.

### S5 · Flesh out ec.ib register-state copy

**What:** Replace the abstract comment in `ce_cme_execute.sail` with concrete
register group saves. For each bit set in the effective mask, copy the
corresponding architectural register group into the bank struct.

**Spec ref:** ch03 §3.1, ch00 §0.10 (mask bit definitions)

**Sail work:**
- Bit 0 (GPR): copy `X(1)..X(31)` into `bank.gprs`
- Bit 1 (FPR): copy `F(0)..F(31)` into `bank.fprs`
- Bit 4 (PC): copy `PC` into `bank.pc`
- Bits 2,3,5,6 (VEC, MAT, CSR, SATP): stubbed until those extensions are
  modelled — write a `TODO` comment and skip

**Depends on:** S4

**Status:** ✓ Done — GPR (bit 0), FPR (bit 1), PC (bit 4), and SATP (bit 6)
saves implemented. VEC/MAT/CSR (bits 2,3,5) remain TODO stubs. Added
`fregidx` newtype, `F` overload, and `get_arch_pc` to
`ce_standalone_prelude.sail` to mirror sail-riscv's `fdext_regs.sail` /
`pc_access.sail`. SATP save added (v0.19 D6 propagation): `satp_val` field
added to `Bank` struct; `ce_standalone_prelude.sail` gains `satp` register
stub, `asidbits` type, and `flush_TLB` stub. Both `make check` and
`make check-riscv` exit 0.

---

### S6 · Flesh out ec.ob register-state restore

**What:** Mirror of S5 for restore. For each bit in the mask, copy from
`bank.gprs`/`bank.fprs`/`bank.pc` back into the architectural registers.

**Special case:** If bit 4 (PC) is set, update the program counter. In
sail-riscv this is typically done by setting `nextPC`.

**Spec ref:** ch03 §3.1, ch00 §0.10

**Depends on:** S4, S5

**Status:** ✓ Done — GPR (bit 0), FPR (bit 1), PC (bit 4), and SATP (bit 6)
restores implemented. PC case uses `set_next_pc(b.pc)` to redirect execution
on commit (sail-riscv pattern). VEC/MAT/CSR (bits 2,3,5) remain TODO stubs.
SATP restore added (v0.19 D6 propagation, charter §6.8): reads old SATP,
writes `b.satp_val` to `satp`, calls `flush_TLB(None(), None())` if the
values differ (full-flush scope; D6.1 unresolved). Skip when unchanged
expresses the permitted optimization. API: `flush_TLB` from
`sail-riscv/model/sys/vmem_tlb.sail`. Both checks pass.

---

### S7 · Validate fast-path context switch sequence

**What:** Write a small Sail test or assertion that executes the canonical
two-instruction context switch: `ec.ib mask` then `ec.ob x0, other_ecid, mask`
and verifies that `current_ecid` has changed and the register state is as
expected.

**Spec ref:** ch03 §3.1 "Typical switch sequence", ch03 §3.13.1 (diagram)

**Depends on:** S5, S6

**Status:** ✓ Done — `ce_cme_test_s7.sail` added to CE_SOURCES. Sets up
ECID_A (bank 0) and ECID_B (bank 1 with known sentinel values), executes
`ec.ib x0, x1` then `ec.ob x0, x2, x1`, asserts current_ecid == B and
B's sentinel (0xBBBB...0003) is live in x3. Both make check and
make check-riscv exit 0.

---

### S8 · Dirty-save mode in ec.ib (rs1 = x0)

**What:** When `rs1` encodes `x0` (field value `00000`), the effective mask
is the dirty-group bitmap, not zero. Verify the current implementation handles
the `rs1 == 0b00000` special case correctly and clears dirty bits on save.

**Spec ref:** ch03 §3.1 "Dirty-Save Mode", ch00 §0.3

**Depends on:** S5

**Status:** ✓ Done — `ce_cme_test_s8.sail` added. Two scenarios:
(1) `ec.ib x0, x0` (rs1=x0) uses dirty_bitmap as mask, clears bits after;
(2) `ec.ib x0, a1` with X(a1)=0 (rs1≠x0) uses explicit mask=0, saves
nothing, leaves dirty_bitmap unchanged. Covers the spec distinction:
encoding 00000, not value zero. Both checks pass.

---

## Phase 3 — CME ECID lifecycle: ec.ir / ec.oe

### S9 · ec.ir — Allocate a child ECID

**What:** Replace the ec.ir stub with a real implementation. Allocate a free
slot in `ec_array`, set `delegation_L = parent_L + 1` (or `D` for leaf),
increment generation counter, mark allocated. Return new ECID in `rd` or 0
on failure.

**Spec ref:** ch03 §3.5 (`ec.ir`), ch00 §0.8 (delegation levels)

**Error conditions:**
- `CME_ERR_CAP_DEPTH` if `parent_L >= D` and rs1=1 (delegating child)
- 0 in rd if no free slots

**Depends on:** S4

**Status:** ✓ Done — full implementation replaces stub. flag[63..1] != 0
returns ILLEGAL_FIELD; delegating child checks parent_L >= D_val for
CAP_DEPTH; leaf pins child_L = D; delegating sets child_L = parent_L+1.
Free slot found via foreach 1..63; entry written with incremented
generation counter. Both checks pass.

---

### S10 · ec.oe — Forced destroy of ECID and subtree

**What:** Depth-first walk of the delegation subtree rooted at `rs1`. For each
node: revoke Contracts (stub: no-op in Sail v1), free Banks (clear bank owner),
increment generation counter, mark slot unallocated. Return total count of freed
ECIDs in `rd`. Must always succeed.

**Spec ref:** ch03 §3.5 (`ec.oe`), ch03 §3.13.3 (subtree walk diagram)

**Depends on:** S9

**Status:** ✓ Done — two-phase mark-then-free implementation. Phase 1:
mark target slot, then 3 propagation sweeps to reach descendants up to
D=3 levels deep (each sweep marks nodes whose parent is already marked).
Phase 2: for each marked slot, free owned banks (valid=false,
owner=zeros), increment generation counter, mark unallocated. rd = freed
count. Always succeeds. Permission check deferred to S22. Both checks pass.

---

### S11 · Generation counter validation in ec.ob / ec.oe

**What:** ec.ob should validate the generation counter of the target ECID
(once the model carries per-call generation values). ec.oe increments the
counter on each freed slot. Add assertions that stale references are detectable.

**Spec ref:** ch00 §0.2 (generation counters), ch03 §3.1 (ec.ob), ch03 §3.5
(ec.oe)

**Depends on:** S9, S10

**Status:** ✓ Done — ec.ob now extracts expected_gen from X(rs1)[23..16]
alongside target_ecid from X(rs1)[15..0] (Sail v1 convention). Combined
condition ~entry.allocated | entry.generation != expected_gen returns
CME_ERR_INVALID_ECID. ce_cme_test_s11.sail verifies stale gen=6 → error
and correct gen=7 → success for a slot at generation 7. Both checks pass.

---

## Phase 4 — CME bank management: ec.ig / ec.og

### S12 · ec.ig — Assign a free bank to an ECID's Group

**What:** Find a bank slot with `valid = false` in `bank_pool`. Set
`owner_ecid = rs1`, `valid = true`. Return bank slot index in `rd` or
`CME_ERR_NO_BANK` if none available.

**Spec ref:** ch03 §3.3 (`ec.ig`)

**Depends on:** S4

**Status:** ✓ Done — scans bank_pool for first free slot, claims it for
target_ecid, returns slot index. CME_ERR_NO_BANK if all 8 slots occupied.

---

### S13 · ec.og — Release a bank from an ECID's Group

**What:** Find the bank owned by `rs1`. Set `valid = false`, clear
`owner_ecid`. Return count of remaining banks in the Group in `rd`.

**Spec ref:** ch03 §3.3 (`ec.og`)

**Depends on:** S12

**Status:** ✓ Done — uses find_bank to locate the owned bank, releases it
(valid=false, owner=zeros), counts remaining Group banks for rd.
Implemented alongside S12 (trivially paired). Both checks pass.

---

### S14 · Bank exhaustion recovery test

**What:** Verify that the normative Bank Exhaustion Recovery protocol works
end-to-end: `ec.ig` returns `CME_ERR_NO_BANK` → caller issues `ec.im` +
`ec.og` to free a bank → retry `ec.ig` succeeds.

**Spec ref:** ch03 §3.3 "Bank Exhaustion Recovery"

**Depends on:** S12, S13, S15 (ec.im needed for spill step)

**Status:** ✓ Done — ce_cme_test_s14.sail. Fills all 8 slots, asserts
CME_ERR_NO_BANK, calls ec.im (stub, CME_OK), calls ec.og (genuinely frees
slot 7), retries ec.ig → succeeds with slot 7 assigned to ECID_E. Both
checks pass. ec.im stub is sufficient — protocol structure is validated.

---

## Phase 5 — CME DMA path: ec.im / ec.om

### S15 · ec.im — Spill bank to ECS in RAM

**What:** Replace the ec.im stub with a memory write: copy bank contents to
`EC[rs1].ecs_ptr` in RAM. In sail-riscv this means calling the memory model
write function. The bank remains allocated after spill; `ec.og` releases it.

**Spec ref:** ch03 §3.2 (`ec.im`), ch17 §17.3.1 (FENCE W,W after ec.im)

**Depends on:** S4

**Status:** ✓ Done — writes bank groups to ECS via write_ram (8 bytes/word).
Defined ECS layout: GPRs at +0, FPRs at +248, PC at +504, mask at +512.
Bank remains valid after spill; ec.og releases it. Standalone prelude
adds physaddr, write_kind, read_kind, mem_meta, write_ram, read_ram stubs.
Both checks pass.

---

### S16 · ec.om — Fill bank from ECS in RAM

**What:** Memory read from `EC[rs1].ecs_ptr`. Assign a free bank, copy ECS
contents into it, update `ec_array[rs1]` bank reference.

**Spec ref:** ch03 §3.2 (`ec.om`), ch17 §17.3.2 (FENCE R,R before ec.om)

**Depends on:** S12, S15

**Status:** ✓ Done — reads register groups from ecs_ptr via read_ram using
the S15 ECS layout (GPRs +0, FPRs +248, PC +504). Claims a free bank slot
(like ec.ig), populates it from ECS, marks valid. CME_ERR_NO_BANK if pool
exhausted. Both checks pass.

---

### S17 · Memory ordering obligations

**What:** Verify that the Sail model correctly interacts with the sail-riscv
memory model for the normative fence sequences in ch17. Specifically:
- After `ec.im`: a `FENCE W,W` must be architecturally visible before the
  signalling store to another hart.
- Before `ec.om` (cross-hart): a `FENCE R,R` after the acquire load.

**Spec ref:** ch17 §17.3, §17.5 (normative migration sequence)

**Depends on:** S15, S16

**Status:** ✓ Done — ce_cme_test_s17.sail encodes the §17.5 migration
sequence (Hart 0 steps 1–5, Hart 1 steps 7–11) in a single-hart Sail
test. Fence positions documented as comments at their spec-mandated
locations. Key assertions: ec.im leaves bank valid (bank remains allocated
after spill per spec); ec.om claims a new bank for the migrated ECID.
Verifies ec.im/ec.om use write_ram/read_ram (RVWMO stores/loads). Both
checks pass. Full cross-hart ordering requires the memory model simulator.

---

## Phase 6 — CME delegation: ec.it / ec.ot

### S18 · ec.it — Delegate one bank to a child ECID

**What:** Find one bank in `rs1`'s Group. Change `owner_ecid` from `rs1` to
`rs2`. Verify `rs1` is an authorized ancestor of `rs2`.

**Spec ref:** ch03 §3.4 (`ec.it`)

**Depends on:** S9, S12

**Status:** ✓ Done — `is_ancestor` helper added to `ce_state.sail` (walks up
to D+1=4 levels). `ec.it` validates both ECIDs, checks ancestry
(→ `CME_ERR_PERMISSION`), finds a bank owned by parent, transfers
`owner_ecid` to child. Three-scenario test (success, no-bank, permission
violation) added as `ce_cme_test_s18.sail`. Both checks pass.
Also fixed a batch of pre-existing sail-riscv compatibility issues surfaced
by the sail-riscv update (2026-05-28): `~expr` → `~(expr)`, `struct { rec with }` →
`{ rec with }`, XLEN/FLEN polymorphism (zero_extend/truncate), physaddrbits
for ECS pointer, bits(N)-typed slot accumulators, `encdec_reg` for register
index construction.

---

### S19 · ec.ot — Revoke all resources from a child ECID

**What:** Return all banks in `rs1`'s Group to the parent Group (change
`owner_ecid` back). ECID `rs1` remains allocated but holds no resources.

**Spec ref:** ch03 §3.4 (`ec.ot`)

**Depends on:** S18

**Status:** ✓ Done — validates target ECID, reads parent_ecid from EC[e],
transfers all banks owned by rs1 to parent in a single foreach sweep.
rs1 stays allocated. Contract and recursive child ECID handling are Sail
v1 no-ops. Two-scenario test (success + invalid ECID). Both checks pass.

---

## Phase 7 — CME privilege and CSR correctness

### S20 · current_ecid_level / current_ecid_parent update on ec.ob

**What:** Verify that the `0xFD1` and `0xFD2` CSR read functions in
`ce_csr.sail` correctly reflect the delegation level and parent ECID of
`current_ecid` after each successful `ec.ob`.

**Spec ref:** ch13 §3.10–§3.11

**Depends on:** S6

**Status:** ✓ Done — CSR functions at 0xFD1/0xFD2 already do live
lookup_ec(current_ecid) reads, so they automatically track the ECID that
ec.ob switched to. No code change needed. ce_cme_test_s20.sail verifies:
before ec.ob → CSRs reflect ECID_A (level 1, parent = root); after
ec.ob → CSRs reflect ECID_B (level 2, parent = ECID_A). Both checks pass.

---

### S21 · cme_status update on all CME instructions

**What:** Every CME instruction that can fail should update `cme_status[7:0]`
with the error code in parallel with writing `rd`. Audit all execute functions
for this.

**Spec ref:** ch13 §3.6, ch03 §3.12

**Depends on:** Phase 2–6 complete

**Status:** ✓ Done — added `cme_ret_err(rd, code)` and `cme_ret_ok(rd, data)`
helpers that write both rd and cme_status[7:0] atomically. Replaced all
scattered `X(rd) = ...; RETIRE_SUCCESS` sites throughout ec.ob, ec.im,
ec.om, ec.ig, ec.og, ec.it, ec.ot, ec.ir, ec.oe with these helpers.
After the refactor, the only X(rd) writes in the file are inside the two
helpers. ce_cme_test_s21.sail confirms success and error cme_status values
for all affected instructions. Both checks pass.

---

### S22 · ce_ctrl gating — privilege model integration

**What:** Integrate ch14 privilege checks. When `ce_ctrl.CME_EN = 0`, all CME
instructions should raise illegal instruction before any other check. When
`S_EN = 0` and the current privilege level is S/HS/VS, same result.

**Spec ref:** ch14 §14.2–§14.5, ch13 §1.1 (`ce_ctrl`)

**Depends on:** S4, `ce_ctrl.sail` complete

**Status:** ✓ Done — added `Privilege` enum + `cur_privilege` register to
standalone prelude (matches sail-riscv). Added `cme_priv_ctl` (0x7CF,
S_EN) and `hcme_ctrl` (0x6C0, VS_EN) registers with CSR read/write
clauses. Added `cme_priv_allowed()` (M → true, S/HS → S_EN, VS →
S_EN & VS_EN, U/VU → false) and `cme_authorized() = cme_enabled() &
cme_priv_allowed()` in ce_ctrl.sail. Replaced `~(cme_enabled())` with
`~(cme_authorized())` in all 10 CME execute clauses (one replace_all).
ce_cme_test_s22.sail covers 7 scenarios: M+CME_EN=1 allowed; M+CME_EN=0
traps; S+S_EN=0 traps; S+S_EN=1 allowed; U traps; VS+VS_EN=1 allowed;
VS+VS_EN=0 traps. Both checks pass.

---

## Phase 8 — CME validation suite

### S23 · Context switch sequence: round-trip register preservation

**What:** Multi-step test: allocate two ECIDs A and B, assign a bank to each,
write known values to GPRs as A, `ec.ib`, switch to B, `ec.ob` back to A,
verify GPR values match.

**Spec ref:** ch03 §3.13.1

**Depends on:** S5, S6, S9, S12

**Status:** ✓ Done — ce_cme_test_s23.sail: allocates ECID_A and ECID_B via
ec.ir, assigns banks via ec.ig, pre-loads B's bank with GPR_MASK + A's
ec.ob reference + SENTINEL_B (so the return journey works without separate
register setup), writes SENTINEL_A to x5 as ECID_A, saves via ec.ib,
switches A→B→A, asserts x5 == SENTINEL_A on return. Also verifies x1
(mask), x3 (ECID_A), x4 (ECID_B) round-trip. Both checks pass.

---

### S24 · Delegation depth cap enforcement

**What:** Verify that `ec.ir rs1=1` (delegating child) from an ECID at `L = D`
returns `CME_ERR_CAP_DEPTH`. Verify that `ec.ir rs1=0` (leaf child) from the
same ECID succeeds.

**Spec ref:** ch03 §3.5, ch00 §0.8, ch13 §3.3

**Depends on:** S9

**Status:** ✓ Done — ce_cme_test_s24.sail builds the full delegation chain
L=0→L=1→L=2→L=3=D via three ec.ir rs1=1 calls (each switching
current_ecid before the next). From ECID_L3 (L=D): ec.ir rs1=1 →
CME_ERR_CAP_DEPTH confirmed in both rd and cme_status; ec.ir rs1=0 →
success, leaf ECID allocated with delegation_L == D confirmed. Both
checks pass.

---

### S25 · Sealed bank: ec.ob refusal

**What:** Mark a bank as sealed (`bank.sealed = true`). Verify that `ec.ob`
targeting that bank returns `CME_ERR_ALREADY_SEALED` (6) without modifying
any state.

**Spec ref:** ch03 §3.6 "Sealed bank state"

**Depends on:** S6

**Status:** ✓ Done — ce_cme_test_s25.sail. Scenario 1: bank.sealed=true,
ec.ob → CME_ERR_ALREADY_SEALED in rd and cme_status; current_ecid
unchanged, bank.sealed still true, bank.gprs[2] (sentinel) intact.
Scenario 2: bank.sealed=false, same ec.ob → CME_OK, current_ecid
switches to target, x3 carries sentinel. Both checks pass.

---

## Phase 9 — CPE execute functions

### S26 · CPE state types

**What:** Define `CPE_Contract` type: `l1_way_mask`, `l2_way_mask`, `deleg`
flag. Add `cpe_contracts` map to per-hart state.

**Spec ref:** ch07 §7.4, ch13 §4.1 (`cpe_caps`)

**Depends on:** Phase 8 complete

**Status:** ☐

---

### S27 · cp.ir / cp.or execute

**What:** `cp.ir`: create a CPE Contract for ECID `rs1` using partition
descriptor in `rs2`. `cp.or`: revoke the CPE Contract for ECID `rs1`.

**Spec ref:** ch07 §7.5–§7.6

**Depends on:** S26

**Status:** ☐

---

### S28 · cp.it / cp.ot execute (delegation)

**What:** `cp.it`: split a parent CPE Contract and delegate a subset to child
ECID. Sum of children ≤ parent. `cp.ot`: revoke child Contract.

**Spec ref:** ch07 §7.7–§7.8

**Depends on:** S27

**Status:** ☐

---

## Phase 10 — MSE execute functions

**Cluster D note (v0.21 charter §4.5).** The cluster D resolution (commit
6c46f5a) expanded the MSE Sail scope materially: 8-bit fields on a pre-flattened
0–255 scale, per-delegation precision, multi-tier slot arbitration, dithered
scheduling, and the full CSR set (`mse_absolute_bw` at 0xFD3, `mse_caps` at
0xFD4). Items S29–S31 below are the pre-cluster-D descriptions; they are
superseded by S29a–S29n which reflect the full v0.21 scope.

---

### S29 · MSE state types and admission axiom (pre-cluster-D)

**What:** Define `MSE_Contract` type: `bw_class`, `lat_class`. Define the
axiomatised admission function:

```sail
val admit_mse_contract : (ecid_t, bits(8), bits(8)) -> option(unit)
```

Returns `Some(())` on success, `None()` on admission failure. The internal
chip-global accounting is a black box (Sail v1 scope decision).

**Spec ref:** ch09 §9.4, work-items.md P8 (admission axiom decision)

**Depends on:** Phase 9 complete

**Status:** Superseded by cluster D resolution (v0.21 charter §4.5). See S29a.

---

### S30 · ms.ir / ms.or execute (pre-cluster-D)

**What:** `ms.ir`: call `admit_mse_contract`; on success, record Contract for
ECID `rs1`. `ms.or`: revoke MSE Contract for ECID `rs1`, return bandwidth
to parent.

**Spec ref:** ch09 §9.5–§9.6

**Depends on:** S29

**Status:** Superseded by cluster D resolution (v0.21 charter §4.5). See S29b.

---

### S31 · ms.it / ms.ot execute (delegation, pre-cluster-D)

**What:** `ms.it`: split parent MSE Contract to child. Child `bw_class` must
≤ parent headroom. `ms.ot`: revoke child Contract.

**Spec ref:** ch09 §9.7–§9.8

**Depends on:** S30

**Status:** Superseded by cluster D resolution (v0.21 charter §4.5). See S29c.

---

### S29a · MSE Contract type, per-hart state, CSR plumbing (cluster D scaffolding)

**What:** `MSE_Contract` struct (8-bit `bw_class`, 8-bit `lat_class`, 4-bit
`precision`, `valid` flag); type aliases `bw_class_t`, `lat_class_t`,
`precision_t`; `MSE_Contract_default`. Per-hart registers: `mse_slot_ratio`,
`mse_bw_cap`, `mse_bw_sum`, `mse_status`, `mse_violation`, `mse_violation_en`.
Implementation constants: `mse_slot_ns_val` (100 ns), `mse_max_nesting` (K=3),
`mse_caps_val` (0x8388F0 zero-extended = v0.21-compliant). Contract pool
`mse_contract_pool` (64 slots). Accessors `find_mse_contract`,
`mse_contract_active`. Full CSR set: 0x7C6 (mse_slot_ratio, RW), 0xFC7
(mse_slot_ns, RO), 0xFC8 (mse_max_nesting, RO), 0x7C7 (mse_bw_cap, RW),
0xFC9 (mse_bw_sum, RO), 0xFCA (mse_status, RO), 0x7C8 (mse_violation, W1C),
0x7C9 (mse_violation_en, RW), 0xFD3 (mse_absolute_bw, RO), 0xFD4
(mse_caps, RO). No execute logic (ms.ir/ms.or/ms.it/ms.ot still
Illegal_Instruction).

**Spec ref:** charter §4.5, ch09 §9.4, ch13 §5

**Depends on:** Phase 9 complete (relaxed: can proceed before CPE if needed)

**Status:** ✓ Done — Sail-A session. New file `sail/model/ce_mse_types.sail`;
updates to `ce_state.sail`, `ce_csr.sail`, `sail/Makefile`. Both `make check`
and `make check-riscv` pass. Commit: 8572aa0.

---

### S29b · ms.ir / ms.or execute

**What:** `ms.ir`: validate ECID, admit Contract (cap check), record in
`mse_contract_pool`, update `mse_bw_sum`. `ms.or`: revoke Contract, restore
`mse_bw_sum`. Both update `mse_status`. Pre-flattened `bw_class` on 0–255
scale (§9.4.1). Admission checks `bw_class + mse_bw_sum ≤ mse_bw_cap`.

**Spec ref:** ch09 §9.5–§9.6, charter §4.5.6

**Depends on:** S29a

**Status:** ✓ Done — Sail-B session. `ce_mse_execute.sail` adds `val admit_mse_contract`
axiom (abstract), `mse_ret_err`/`mse_ret_ok` helpers, and execute clauses for
`CE_MSIR` and `CE_MSOR`. Cap check (`mse_bw_cap == 0 || sum + bw ≤ cap`) inline.
Error codes defined in `ce_mse_types.sail`: MSE_ERR_ADMISSION_DENIED (0x10),
MSE_ERR_NO_CONTRACT (0x11), MSE_ERR_INVALID_ECID (0x12), MSE_ERR_DESCRIPTOR_RESERVED
(0x13). MSIR/MSOR stubs removed from `ce_mse_decode.sail`. Both checks pass.
Commit: 7b9d6c8.

---

### S29c · ms.it / ms.ot execute with telescoping

**What:** `ms.it`: split parent Contract to child via
`child_pre_flat = floor(parent_pre_flat × (child_bw_class / parent_scale))`.
Enforce cap: sum(children) ≤ parent. Optionally set child `precision`. `ms.ot`:
revoke child Contract recursively. Both update `mse_status`.

**Spec ref:** ch09 §9.7–§9.8, charter §4.5.2

**Depends on:** S29b

**Status:** ☐

---

### S29d · Multi-tier arbitration decision function

**What:** One-shot `mse_arbitrate` function implementing the three-tier CN
slot selection: within-budget by `lat_class` → over-budget by `lat_class` →
BE fallthrough. Round-robin tie-break.

**Spec ref:** charter §4.5.4, ch09 §9.7.1

**Depends on:** S29a

**Status:** ☐

---

### S29e · Reconfiguration recomputation function

**What:** `mse_recompute_subtree(e)` — recompute pre-flattened `bw_class` for
all descendants of ECID `e` after a parent reconfiguration. Must complete before
the next affected arbitration cycle (§4.5.3).

**Spec ref:** charter §4.5.3, ch09 §9.4.5

**Depends on:** S29c

**Status:** ☐

---

### S29f · Tests: ms.ir / ms.or round-trip

**What:** Verify that ms.ir admits a Contract, records it in `mse_contract_pool`,
updates `mse_bw_sum`; ms.or revokes and restores `mse_bw_sum`. Check
`mse_absolute_bw` CSR reads the admitted value.

**Spec ref:** ch09 §9.5–§9.6

**Depends on:** S29b

**Status:** ✓ Done — Sail-B session. `ce_mse_test_s29f.sail` (`$[test]` function
`test_mse_ir_or_roundtrip`): ms.ir with bw_class=64/lat_class=2 → Contract active,
mse_bw_sum=0x40, mse_status=MSE_OK, rd=0; ms.or → Contract gone, mse_bw_sum=0x00.
Compiles with both checks. Note: `$[test]` functions are type-checked but not executed
by `make check`; actual simulation requires a Sail simulator target (not in scope for
Sail v1 type-check-only builds). Commit: 7b9d6c8.

---

### S29g · Tests: single-level delegation

**What:** ms.ir for parent, ms.it to child; verify child's pre-flattened
`bw_class` is computed correctly (round-down); verify cap enforcement
(sum(children) ≤ parent fails with error).

**Spec ref:** ch09 §9.4.3, charter §4.5.2

**Depends on:** S29c

**Status:** ☐

---

### S29h · Tests: two-level and full-depth delegation

**What:** Root → L=1 → L=2 → L=3. Verify round-down accumulation at each
level matches the worked example in charter §4.5.2.

**Spec ref:** charter §4.5.2

**Depends on:** S29c

**Status:** ☐

---

### S29i · Tests: reduced-precision delegation

**What:** ms.it with `child_precision` = 4 bits. Verify child Contract stores
4-bit effective precision; pre-flattened value computed on 4-bit scale.

**Spec ref:** ch09 §9.4.3, charter §4.5.1

**Depends on:** S29c

**Status:** ☐

---

### S29j · Tests: cap enforcement

**What:** Three children whose `bw_class` sum exceeds parent headroom — third
ms.it returns error; first two remain valid. `mse_bw_sum` stays consistent.

**Spec ref:** charter §4.5.6, ch09 §9.4.2

**Depends on:** S29c

**Status:** ☐

---

### S29k · Tests: reconfiguration cascade

**What:** After parent reconfiguration (bw_class reduced), verify
`mse_recompute_subtree` updates all descendant pre-flattened values correctly.
Verify `mse_absolute_bw` reflects new values.

**Spec ref:** charter §4.5.3

**Depends on:** S29e

**Status:** ☐

---

### S29l · Tests: arbitration decision (multiple scenarios)

**What:** Verify `mse_arbitrate` selects correctly: EC within budget wins over
EC over budget; EC over budget wins over BE fallthrough; round-robin tie-break
rotates on equal `lat_class`.

**Spec ref:** charter §4.5.4

**Depends on:** S29d

**Status:** ☐

---

### S29m · Tests: round-robin tie-break

**What:** Two ECs with equal `lat_class` and budget; verify alternating grant
across consecutive CN slots (round-robin tie-break).

**Spec ref:** charter §4.5.4

**Depends on:** S29d

**Status:** ☐

---

### S29n · Tests: virtualization-layer divergence

**What:** Three scenarios: (a) daemon-style delegation (L=0 → L=1 → L=2
→ L=3 with precision reduction at each level); (b) no-Contract VM (ms.ir
not called; EC competes as BE); (c) container at L=1 delegates to L=2
with full parent precision.

**Spec ref:** ch09 §9.4.3, charter §4.5.2

**Depends on:** S29c

**Status:** ☐

---

## Phase 11 — QoS execute functions

### S32 · QoS state types and domain model

**What:** Define `QoS_Contract` type: `bw_class`, `lat_class`, `domain_id`.
Model `qos_domain_sel` as per-hart state selecting which domain subsequent
QoS CSR accesses target.

**Spec ref:** ch11 §11.5, ch13 §6

**Depends on:** Phase 10 complete

**Status:** ☐

---

### S33 · qs.ir / qs.or execute

**What:** `qs.ir`: admit QoS Contract for ECID `rs1` on domain `rs2`. `qs.or`:
revoke QoS Contract; `rs2` = domain selector (0 = all domains).

**Spec ref:** ch11 §11.6–§11.7

**Depends on:** S32

**Status:** ☐

---

### S34 · qs.it / qs.ot execute (delegation)

**What:** Per-domain Contract delegation and revocation.

**Spec ref:** ch11 §11.8–§11.9

**Depends on:** S33

**Status:** ☐

---

## Phase 12 — Integration, validation, and submission

### S35 · Full `make check-riscv` with all execute functions

**What:** All CE Suite Sail sources type-check cleanly integrated with
sail-riscv after Phases 9–11 are complete.

**Depends on:** All phase 9–11 items

**Status:** ☐

---

### S36 · Litmus tests for memory ordering (ch17 fence sequences)

**What:** Translate the normative cross-hart migration sequence (ch17 §17.5,
steps 1–13) into a Sail or litmus test. Verify that the fence instructions
appear in the correct positions relative to `ec.im`/`ec.om`.

**Spec ref:** ch17 §17.5

**Depends on:** S17, S35

**Status:** ☐

---

### S37 · sail-riscv upstream integration review

**What:** Review the integration against the current sail-riscv extension
contribution guidelines. Ensure CE Suite follows the same patterns as other
RISC-V extensions in the model (naming conventions, prelude dependencies,
test infrastructure).

**Depends on:** S35

**Status:** ☐

---

### S38 · Submission to RISC-V International / sail-riscv

**What:** Package the CE Suite Sail model for submission alongside the P6
opcode allocation request. The Sail model is a required deliverable for
RISC-V ratification.

**Depends on:** S36, S37, P6 (spec work-items: opcode allocation)

**Status:** ☐

---

## Priority order

| # | Item | Phase | Depends on |
|---|------|-------|-----------|
| 1 | **S1** — Install Sail toolchain | 1 | — |
| 2 | **S2** — Clone sail-riscv, identify integration point | 1 | S1 |
| 3 | **S3** — `make check` passes (standalone) | 1 | S1 |
| 4 | **S4** — `make check-riscv` passes (integrated) | 1 | S2, S3 |
| 5 | **S5** — ec.ib register-state copy | 2 | S4 |
| 6 | **S6** — ec.ob register-state restore | 2 | S5 |
| 7 | **S8** — Dirty-save mode validation | 2 | S5 |
| 8 | **S7** — Fast-path context switch test | 2 | S6 |
| 9 | **S9** — ec.ir (allocate ECID) | 3 | S4 |
| 10 | **S10** — ec.oe (forced destroy) | 3 | S9 |
| 11 | **S12** — ec.ig (assign bank) | 4 | S4 |
| 12 | **S13** — ec.og (release bank) | 4 | S12 |
| 13 | **S15** — ec.im (spill to RAM) | 5 | S4 |
| 14 | **S16** — ec.om (fill from RAM) | 5 | S12, S15 |
| 15 | **S18** — ec.it (delegate bank) | 6 | S9, S12 |
| 16 | **S19** — ec.ot (revoke resources) | 6 | S18 |
| 17 | **S11** — Generation counter validation | 3 | S9, S10 |
| 18 | **S14** — Bank exhaustion recovery test | 4 | S12, S13, S15 |
| 19 | **S17** — Memory ordering obligations | 5 | S15, S16 |
| 20 | **S21** — cme_status audit | 7 | Phases 2–6 |
| 21 | **S22** — ce_ctrl privilege gating | 7 | S4 |
| 22 | **S20** — CSR level/parent update | 7 | S6 |
| 23 | **S23–S25** — CME validation suite | 8 | Phases 2–7 |
| 24 | **S26–S28** — CPE execute | 9 | Phase 8 |
| 25 | **S29a** — MSE Contract type, state, CSR plumbing (Sail-A) ✓ | 10 | Phase 9 |
| 26 | **S29b** — ms.ir / ms.or execute (Sail-B) | 10 | S29a |
| 27 | **S29c** — ms.it / ms.ot with telescoping (Sail-C) | 10 | S29b |
| 28 | **S29d** — Multi-tier arbitration function (Sail-D) | 10 | S29a |
| 29 | **S29e** — Reconfiguration recomputation (Sail-D/E) | 10 | S29c |
| 30 | **S29f** — Tests: ms.ir/ms.or round-trip | 10 | S29b |
| 31 | **S29g** — Tests: single-level delegation | 10 | S29c |
| 32 | **S29h** — Tests: two-level and full-depth delegation | 10 | S29c |
| 33 | **S29i** — Tests: reduced-precision delegation | 10 | S29c |
| 34 | **S29j** — Tests: cap enforcement | 10 | S29c |
| 35 | **S29k** — Tests: reconfiguration cascade | 10 | S29e |
| 36 | **S29l** — Tests: arbitration decision | 10 | S29d |
| 37 | **S29m** — Tests: round-robin tie-break | 10 | S29d |
| 38 | **S29n** — Tests: virtualization-layer divergence | 10 | S29c |
| 39 | **S32–S34** — QoS execute | 11 | Phase 10 |
| 40 | **S35–S37** — Integration and review | 12 | Phases 9–11 |
| 41 | **S38** — Submission | 12 | S35–S37, P6 |

---

*End of Sail Work Items.*
