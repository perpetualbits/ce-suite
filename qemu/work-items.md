<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite QEMU — Work Items

**Purpose:** Tracks every task in the CE Suite QEMU implementation from
environment setup through upstream submission. Items are ordered by dependency.

**Relationship to Sail:** The Sail model (`../sail/work-items.md`) is the
formal reference. Sail Phases 1–8 (CME core) should be complete or well
underway before QEMU CME execute work starts. When QEMU and Sail disagree,
Sail wins.

**Scope decisions:**
- CPE, MSE, and QoS are **functional stubs** in QEMU v1: instructions execute
  and maintain state, but no real resource partitioning occurs.
- The 1–9 cycle timing of `ec.ib`/`ec.ob` is irrelevant in QEMU; functional
  correctness is the only goal.
- `ec.iv`/`ec.ov` vault execute is **not implemented** in QEMU v1 (same scope
  boundary as Sail v1; encryption algorithm implementation-defined).

---

## ⚑ Current priority — Phase 1 (environment)

Build a working QEMU for RISC-V with RVA23 support before adding anything.
A broken baseline is the most expensive mistake.

---

## Phase 1 — Environment setup

### Q1 · Fork / clone QEMU and establish baseline

**What:** Clone upstream QEMU, create a `ce-suite` branch, verify it builds
and boots a known-good RISC-V Linux image with RVA23 support.

```bash
git clone https://gitlab.com/qemu-project/qemu.git qemu-upstream
cd qemu-upstream
git checkout -b ce-suite
./configure --target-list=riscv64-softmmu,riscv64-linux-user
make -j$(nproc)
```

**Verify:** `qemu-system-riscv64 -machine virt -bios default` boots to
OpenSBI prompt. An RVA23 Linux image boots successfully.

**Status:** ☐

---

### Q2 · Understand the RISC-V QEMU extension pattern

**What:** Read how an existing RISC-V extension is implemented. Recommended:
read the Zicond or Zba/Zbb implementation. Understand:
- How `.decode` entries work
- How `trans_*` functions are structured
- How CSR entries are added to `csr.c`
- How `CPURISCVState` is extended

**Deliverable:** A short note in `qemu/README.md` confirming the integration
points are identified and any surprises documented.

**Status:** ☐

---

### Q3 · Set up bare-metal test infrastructure

**What:** A minimal RISC-V bare-metal test harness that:
- Runs under `qemu-system-riscv64 -machine virt -bios none`
- Can print pass/fail via UART
- Will be used for all CE Suite instruction tests

A suitable starting point is the RISC-V test suite's `test_macros.h` pattern
or a minimal crt0 + UART driver.

**Deliverable:** `qemu/tests/bare_main.c` + `Makefile` target that builds and
runs a trivial "hello from bare metal" test.

**Depends on:** Q1

**Status:** ☐

---

## Phase 2 — CE Suite state infrastructure

### Q4 · Add CE Suite state to CPURISCVState

**What:** Extend `target/riscv/cpu.h` with per-hart CE state:

```c
/* CE Suite per-hart state */
struct {
    uint32_t ce_ctrl;           /* 0x7D0: CME/CPE/MSE/QOS enable bits */
    uint64_t cme_ec_table_base; /* 0x7C0 */
    uint16_t current_ecid;      /* 0xFC0 */
    uint64_t cme_seal_key;      /* 0x7C3 */
    uint16_t dirty_bitmap;      /* dirty-group tracking */
    /* EC array and bank pool: heap-allocated on first use */
    struct CE_EC_entry *ec_array;   /* CE_MAX_ECIDS entries */
    struct CE_Bank     *bank_pool;  /* cme_bank_count_NV entries */
    uint32_t           bank_count;
} ce;
```

**Spec ref:** ch00 §0.3, ch13 §1–§3

**Depends on:** Q2

**Status:** ☐

---

### Q5 · Define CE Suite C structs

**What:** In a new file `target/riscv/ce_types.h`, define:

```c
typedef struct CE_EC_entry {
    uint64_t ecs_ptr;       /* always at offset 0 */
    uint8_t  generation;
    uint8_t  delegation_L;
    uint16_t parent_ecid;
    bool     allocated;
} CE_EC_entry;

typedef struct CE_Bank {
    uint16_t owner_ecid;
    bool     valid;
    bool     sealed;
    uint64_t gprs[31];  /* x1..x31 */
    uint64_t fprs[32];  /* f0..f31 */
    uint64_t pc;
    uint64_t mask;      /* effective mask used on last ec.ib */
} CE_Bank;
```

**Spec ref:** ch00 §0.3 (EC_entry), ch00 §0.6 (Bank)

**Depends on:** Q4

**Status:** ☐

---

### Q6 · Allocate EC array and bank pool on CPU realise

**What:** In `cpu_init()` or the CPU realise hook, `g_new0()` the EC array
(65536 entries) and bank pool (configurable; default 8). Free on CPU reset/
destroy. Guard every CE instruction with a NULL check.

**Depends on:** Q5

**Status:** ☐

---

## Phase 3 — CSR infrastructure

### Q7 · Add ce_ctrl CSR (0x7D0)

**What:** Add a CSR entry in `target/riscv/csr.c`:
- Read: return `env->ce.ce_ctrl`
- Write: store bits 3:0; ignore the rest (WIRI); return new value
- Access: M-mode only; raise `RISCV_EXCP_ILLEGAL_INST` from lower privilege

**Spec ref:** ch13 §1.1

**Depends on:** Q4

**Status:** ☐

---

### Q8 · Add remaining CE Suite CSRs

**What:** Add all CE Suite CSR entries to `csr.c`. Group by extension:

*CME (RO unless noted):*
- 0xFC0 `current_ecid` (RO)
- 0x7C0 `cme_ec_table_base` (RW WARL)
- 0xFC1 `cme_del_cap` (RO, returns 3)
- 0xFC2 `cme_bank_count` (RO, returns bank_count)
- 0xFC3 `cme_status` (RO)
- 0xFC4 `cme_reg_mask` (RO)
- 0x7C3 `cme_seal_key` (RW, M-mode only)
- 0xFD1 `current_ecid_level` (RO)
- 0xFD2 `current_ecid_parent` (RO)

*CPE, MSE, QoS:* stub reads (return 0) and writes (ignore) for now.

**Rule:** Every CE CSR read returns 0 when the corresponding `ce_ctrl` bit is 0.

**Spec ref:** ch13 §2–§6

**Depends on:** Q7

**Status:** ☐

---

### Q9 · ce_ctrl privilege gating

**What:** Add a helper `ce_cme_check(CPURISCVState *env)` that raises
`RISCV_EXCP_ILLEGAL_INST` if `ce_ctrl.CME_EN = 0` or if the current privilege
level is below what `cme_priv_ctl` allows. Call this at the start of every
CME `trans_` function.

**Spec ref:** ch14 §14.2–§14.5, ch13 §1.1

**Depends on:** Q7

**Status:** ☐

---

## Phase 4 — CME instruction decode

### Q10 · Add CME decode entries to insn32.decode

**What:** Add all 12 CME instructions to `target/riscv/insn32.decode`:

```
# CE Suite CME (funct3=000, opcode=0x0B)
ec_ib    0000000 ..... ..... 000 ..... 0001011 @r
ec_ob    0000001 ..... ..... 000 ..... 0001011 @r
ec_im    0000010 ..... ..... 000 ..... 0001011 @r
# ... all 12
```

**Spec ref:** ch03 §3.10

**Depends on:** Q2

**Status:** ☐

---

### Q11 · Add CME trans_ stub functions

**What:** Add stub `trans_ec_*` functions in `target/riscv/insn_trans/trans_ce.c.inc`:

```c
static bool trans_ec_ib(DisasContext *ctx, arg_ec_ib *a) {
    REQUIRE_EXT(ctx, RVA);  /* placeholder — replace with CE check */
    /* TODO: implement */
    return false;  /* false = unimplemented → illegal instruction */
}
```

Include the new file from `translate.c`. Verify all 12 CME instructions
raise illegal instruction cleanly before writing any real execute logic.

**Depends on:** Q10

**Status:** ☐

---

## Phase 5 — CME core: ec.ib / ec.ob

### Q12 · ec.ib — save current context to bank

**What:** Implement `trans_ec_ib`. Called at TCG translation time; generates
a call to a helper `helper_ec_ib(CPURISCVState *env, uint32_t rd_idx,
uint32_t rs1_idx)`.

The helper:
1. Calls `ce_cme_check(env)`.
2. Determines effective mask: if `rs1_idx == 0`, use `env->ce.dirty_bitmap`;
   else use `env->gpr[rs1_idx]`.
3. Finds the bank owned by `env->ce.current_ecid`. Fails with
   `CME_ERR_NO_BANK` if none.
4. Refuses sealed banks (`CME_ERR_ALREADY_SEALED`).
5. Copies GPRs, FPRs, PC as indicated by mask bits into the bank struct.
6. Clears dirty bitmap bits for saved groups.
7. Updates `env->ce.cme_reg_mask` and `env->ce.cme_status`.
8. Writes bank slot index to `env->gpr[rd_idx]`.

**Spec ref:** ch03 §3.1 (`ec.ib`), ch00 §0.3 (dirty bitmap)

**Sail ref:** `ce_cme_execute.sail` `CE_ECIB` clause

**Depends on:** Q6, Q9, Q11

**Status:** ☐

---

### Q13 · ec.ob — restore context from bank for target ECID

**What:** Helper `helper_ec_ob(env, rd_idx, rs1_idx, rs2_idx)`:

1. `ce_cme_check(env)`.
2. Read target ECID from `env->gpr[rs1_idx]` (low 16 bits).
3. Look up `ec_array[target_ecid]`; return `CME_ERR_INVALID_ECID` if not
   allocated.
4. Find the bank owned by `target_ecid`; return `CME_ERR_NO_BANK` if not
   resident.
5. Return `CME_ERR_ALREADY_SEALED` if bank is sealed.
6. Copy GPRs, FPRs from bank into `env->gpr[]`, `env->fpr[]`.
7. If PC bit set in mask, set `env->pc = bank->pc` (requires an `exit_tb`
   in the TCG sequence).
8. Update `env->ce.current_ecid = target_ecid`.
9. Clear dirty bitmap for restored groups.
10. Write 0 to `env->gpr[rd_idx]`.

**Spec ref:** ch03 §3.1 (`ec.ob`)

**Sail ref:** `ce_cme_execute.sail` `CE_ECOB` clause

**Depends on:** Q12

**Status:** ☐

---

### Q14 · Dirty-save mode in ec.ib (rs1 = x0)

**What:** Verify that when `rs1_idx == 0` (the zero register), `ec.ib` uses
`env->ce.dirty_bitmap` as the effective mask rather than zero. Add a bare-metal
test: write to GPRs, call `ec.ib x0, x0`, verify only written groups are saved.

**Spec ref:** ch03 §3.1 "Dirty-Save Mode"

**Depends on:** Q12

**Status:** ☐

---

### Q15 · Fast-path context switch test

**What:** Bare-metal test: allocate ECIDs A and B, assign banks, write known
GPR values as A, `ec.ib`, switch to B, `ec.ob` back to A, verify GPR values
are preserved.

**Spec ref:** ch03 §3.1 "Typical switch sequence", ch03 §3.13.1

**Depends on:** Q13, Q14

**Status:** ☐

---

## Phase 6 — CME bank management

### Q16 · ec.ig — assign a free bank to an ECID's Group

**What:** Helper scans `bank_pool[]` for a slot with `valid = false`. Sets
`valid = true`, `owner_ecid = target_ecid`. Returns bank slot index in `rd`,
or `CME_ERR_NO_BANK` if pool is exhausted.

**Spec ref:** ch03 §3.3 (`ec.ig`)

**Depends on:** Q6, Q9

**Status:** ☐

---

### Q17 · ec.og — release a bank from an ECID's Group

**What:** Find the bank owned by `rs1`. Set `valid = false`, clear
`owner_ecid`. Return count of remaining banks in the Group.

**Spec ref:** ch03 §3.3 (`ec.og`)

**Depends on:** Q16

**Status:** ☐

---

### Q18 · Bank exhaustion recovery test

**What:** Bare-metal test that exercises the full Bank Exhaustion Recovery
protocol: exhaust the bank pool, trigger `CME_ERR_NO_BANK`, spill a victim
via `ec.im`, release via `ec.og`, retry the original operation.

**Spec ref:** ch03 §3.3 "Bank Exhaustion Recovery"

**Depends on:** Q16, Q17, Q21 (ec.im needed for spill step)

**Status:** ☐

---

## Phase 7 — CME DMA path

### Q19 · ec.im — spill bank to guest RAM

**What:** Helper reads `ec_array[target_ecid].ecs_ptr`, then writes bank
contents (GPRs, FPRs, PC) to that guest physical address using
`cpu_stq_data_ra()` (or equivalent QEMU memory access). The bank slot remains
valid after the spill; `ec.og` releases it.

**Spec ref:** ch03 §3.2 (`ec.im`), ch17 §17.3.1 (FENCE W,W after ec.im)

**Depends on:** Q6, Q9

**Status:** ☐

---

### Q20 · ec.om — fill bank from guest RAM

**What:** Read from `ec_array[target_ecid].ecs_ptr` into a bank slot. Claim
a free bank slot (if not already assigned). Uses `cpu_ldq_data_ra()`.

**Spec ref:** ch03 §3.2 (`ec.om`), ch17 §17.3.2

**Depends on:** Q16, Q19

**Status:** ☐

---

## Phase 8 — CME ECID lifecycle

### Q21 · ec.ir — allocate a child ECID

**What:** Scan `ec_array[]` for an unallocated slot. Set `allocated = true`,
`generation` unchanged (already zero), `delegation_L = parent_L + 1` (or `D`
for leaf mode), `parent_ecid = current_ecid`. Return new ECID in `rd` or 0
on failure (`CME_ERR_CAP_DEPTH` if delegation cap exceeded).

**Spec ref:** ch03 §3.5 (`ec.ir`), ch00 §0.8

**Depends on:** Q6, Q9

**Status:** ☐

---

### Q22 · ec.oe — forced destroy of ECID and subtree

**What:** Walk `ec_array[]` to find all ECIDs with `parent_ecid` in the
subtree rooted at `rs1`. For each: free any owned banks (set `valid = false`),
increment `generation`, set `allocated = false`. Return total freed count in
`rd`. Always succeeds.

**Spec ref:** ch03 §3.5 (`ec.oe`), ch03 §3.13.3 (subtree walk)

**Depends on:** Q21

**Status:** ☐

---

## Phase 9 — CME delegation

### Q23 · ec.it — delegate one bank to a child ECID

**What:** Find one bank owned by `rs1`'s ECID. Change `owner_ecid` to `rs2`.
Verify `rs1` is an authorized ancestor of `rs2` (walk up `parent_ecid` chain).

**Spec ref:** ch03 §3.4 (`ec.it`)

**Depends on:** Q21, Q16

**Status:** ☐

---

### Q24 · ec.ot — revoke all resources from a child ECID

**What:** Find all banks owned by `rs1`'s ECID. Return them to `rs1`'s
parent Group (change `owner_ecid` back). ECID `rs1` remains allocated.

**Spec ref:** ch03 §3.4 (`ec.ot`)

**Depends on:** Q23

**Status:** ☐

---

## Phase 10 — CME validation

### Q25 · Compare CME behaviour against Sail model

**What:** For each implemented CME instruction, run the same test case in both
QEMU and the Sail model. Verify identical outcomes: same `rd` value, same state
changes, same error codes.

**Depends on:** Sail S7 (fast-path test), Q15

**Status:** ☐

---

### Q26 · Delegation depth cap enforcement test

**What:** Bare-metal test: allocate ECIDs at L=0, L=1, L=2, L=3. Verify
`ec.ir rs1=1` from L=3 returns `CME_ERR_CAP_DEPTH`. Verify `ec.ir rs1=0`
(leaf) from L=3 succeeds.

**Spec ref:** ch03 §3.5, ch00 §0.8

**Depends on:** Q21

**Status:** ☐

---

### Q27 · Sealed bank: ec.ob refusal test

**What:** Mark a bank as sealed. Verify `ec.ob` returns `CME_ERR_ALREADY_SEALED`
without modifying register state.

**Spec ref:** ch03 §3.6

**Depends on:** Q13

**Status:** ☐

---

## Phase 11 — CPE functional stubs

### Q28 · CPE state in CPURISCVState

**What:** Add a simple Contract map to `env->ce`: an array of
`CE_CPE_Contract` structs (one per ECID, lazy-allocated). Each contract holds
`l1_way_mask`, `l2_way_mask`. No actual cache partitioning occurs.

**Spec ref:** ch07 §7.4

**Depends on:** Phase 10 complete

**Status:** ☐

---

### Q29 · cp.ir / cp.or / cp.it / cp.ot execute

**What:** Functional implementations: `cp.ir` stores the partition descriptor
for the target ECID; `cp.or` clears it; `cp.it`/`cp.ot` transfer the
descriptor between ECIDs. All return 0 on success. `cpe_caps` CSR returns a
reasonable non-zero value.

**Spec ref:** ch07 §7.5–§7.8

**Depends on:** Q28

**Status:** ☐

---

## Phase 12 — MSE functional stubs

### Q30 · MSE state in CPURISCVState

**What:** Add `CE_MSE_Contract` array: one entry per ECID, holding `bw_class`
and `lat_class`. Add a simple "admitted bandwidth sum" counter for admission
checking.

**Spec ref:** ch09 §9.4

**Depends on:** Phase 11 complete

**Status:** ☐

---

### Q31 · ms.ir / ms.or / ms.it / ms.ot execute

**What:** `ms.ir`: record `bw_class`/`lat_class` for the target ECID; check
the running sum does not exceed a configured budget (returns `MSE_ERR_SYSTEM_FULL`
if over). `ms.or`: clear the Contract and subtract from the sum.
`ms.it`/`ms.ot`: transfer Contract between ECIDs.

**Spec ref:** ch09 §9.5–§9.8

**Depends on:** Q30

**Status:** ☐

---

### Q32 · MSE CSR stubs

**What:** Implement `mse_slot_ns` (return a fixed value, e.g. 100 ns),
`mse_slot_ratio` (RW), `mse_bw_cap` (RW), `mse_bw_sum` (computed from
admitted Contracts). Other MSE CSRs return 0.

**Spec ref:** ch13 §5

**Depends on:** Q30

**Status:** ☐

---

## Phase 13 — QoS functional stubs

### Q33 · QoS state and domain model

**What:** Add per-domain Contract arrays to `env->ce`. Implement
`qos_domain_count` (configurable; default 2), `qos_domain_sel` (per-hart
selector register).

**Spec ref:** ch11 §11.5, ch13 §6

**Depends on:** Phase 12 complete

**Status:** ☐

---

### Q34 · qs.ir / qs.or / qs.it / qs.ot execute

**What:** Same pattern as MSE, per domain. `qs.or`/`qs.ot` take `rs2` as a
domain selector (0 = all domains). Functional: maintain state, return correct
error codes; no real I/O arbitration.

**Spec ref:** ch11 §11.6–§11.9

**Depends on:** Q33

**Status:** ☐

---

### Q35 · QoS CSR stubs

**What:** `qos_domain_base` (return a configured guest physical address),
`qos_slot_ratio` (RW per domain via `qos_domain_sel`), `qos_bw_sum` (computed
from admitted Contracts). Other QoS CSRs return 0.

**Spec ref:** ch13 §6

**Depends on:** Q33

**Status:** ☐

---

## Phase 14 — Linux integration

### Q36 · Boot CE-unaware Linux without regression

**What:** Verify that a stock Linux kernel (without CE Suite patches) boots
successfully on the CE-enabled QEMU build. CE Suite must be invisible to a
non-CE kernel — all CE CSRs must reset to 0, no unexpected traps.

**Spec ref:** ch13 §2 (CE disabled convention), ch14 §14.2

**Depends on:** Q8, Phase 11 complete

**Status:** ☐

---

### Q37 · Bare-metal CE Suite test suite

**What:** A comprehensive set of bare-metal tests covering all implemented
instructions and error conditions. Each test prints PASS/FAIL via UART.
Structured so individual tests can be run in isolation.

**Deliverable:** `qemu/tests/` directory with at least:
- `test_ecib_ecob.c` — fast-path context switch
- `test_ecir_ecoe.c` — ECID lifecycle
- `test_bank_mgmt.c` — ec.ig/ec.og/ec.im/ec.om
- `test_errors.c` — all documented error codes
- `test_privcheck.c` — ce_ctrl gating

**Depends on:** Phases 5–10 complete

**Status:** ☐

---

### Q38 · Boot CE-aware Linux (kernel patches)

**What:** Once CE Suite Linux kernel patches exist (`../sw/linux-patches/`),
boot them on the CE-enabled QEMU. The kernel should detect CE via `ce_present`
(0xFD0), enable CME via `ce_ctrl`, and use CE Suite for context switching.

**Depends on:** Q37, sw/ kernel patches (separate work stream)

**Status:** ☐

---

## Phase 15 — Upstream contribution

### Q39 · QEMU coding style compliance

**What:** Run `scripts/checkpatch.pl` on all CE Suite patches. Fix all
style warnings. Verify the CE Suite code follows QEMU's naming conventions
(`riscv_ce_`, `trans_ce_`, etc.).

**Depends on:** Phases 5–13 complete

**Status:** ☐

---

### Q40 · QEMU documentation

**What:** Add `docs/system/riscv/ce-suite.rst` describing: what CE Suite is,
how to enable it (`-cpu rv64,x-ce-suite=on` or similar), what each extension
does in QEMU, and the functional-stub limitations (no real cache partitioning,
etc.).

**Depends on:** Q39

**Status:** ☐

---

### Q41 · Submit patches to QEMU mailing list

**What:** Send the CE Suite patch series to `qemu-riscv@nongnu.org` (the RISC-V
QEMU maintainer list). Coordinate timing with P6 (opcode allocation) — upstream
QEMU will not accept a custom-0 placeholder indefinitely; real opcode allocation
should be in progress before submission.

**Depends on:** Q39, Q40, P6 (spec: opcode allocation)

**Status:** ☐

---

## Priority order

| # | Item | Phase | Depends on |
|---|------|-------|-----------|
| 1 | **Q1** — Clone QEMU, build, verify RVA23 | 1 | — |
| 2 | **Q2** — Understand QEMU extension pattern | 1 | Q1 |
| 3 | **Q3** — Bare-metal test harness | 1 | Q1 |
| 4 | **Q4** — Add CE state to CPURISCVState | 2 | Q2 |
| 5 | **Q5** — Define CE C structs | 2 | Q4 |
| 6 | **Q6** — Allocate EC array + bank pool | 2 | Q5 |
| 7 | **Q7** — ce_ctrl CSR | 3 | Q4 |
| 8 | **Q8** — All CE CSRs | 3 | Q7 |
| 9 | **Q9** — ce_ctrl privilege gating | 3 | Q7 |
| 10 | **Q10** — CME decode entries | 4 | Q2 |
| 11 | **Q11** — CME trans_ stubs | 4 | Q10 |
| 12 | **Q12** — ec.ib execute | 5 | Q6, Q9, Q11 |
| 13 | **Q13** — ec.ob execute | 5 | Q12 |
| 14 | **Q14** — Dirty-save mode test | 5 | Q12 |
| 15 | **Q15** — Fast-path context switch test | 5 | Q13 |
| 16 | **Q16** — ec.ig | 6 | Q6, Q9 |
| 17 | **Q17** — ec.og | 6 | Q16 |
| 18 | **Q19** — ec.im | 7 | Q6, Q9 |
| 19 | **Q20** — ec.om | 7 | Q16, Q19 |
| 20 | **Q21** — ec.ir | 8 | Q6, Q9 |
| 21 | **Q22** — ec.oe | 8 | Q21 |
| 22 | **Q23** — ec.it | 9 | Q21, Q16 |
| 23 | **Q24** — ec.ot | 9 | Q23 |
| 24 | **Q25** — Compare vs Sail | 10 | Q15, Sail S7 |
| 25 | **Q26–Q27** — CME validation tests | 10 | Q21, Q13 |
| 26 | **Q18** — Bank exhaustion recovery test | 6 | Q16, Q17, Q19 |
| 27 | **Q36** — Boot CE-unaware Linux | 14 | Q8, Phase 11 |
| 28 | **Q28–Q29** — CPE functional stubs | 11 | Phase 10 |
| 29 | **Q30–Q32** — MSE functional stubs | 12 | Phase 11 |
| 30 | **Q33–Q35** — QoS functional stubs | 13 | Phase 12 |
| 31 | **Q37** — Bare-metal test suite | 14 | Phases 5–10 |
| 32 | **Q38** — Boot CE-aware Linux | 14 | Q37, sw/ patches |
| 33 | **Q39–Q40** — Style + docs | 15 | Phases 5–13 |
| 34 | **Q41** — Upstream submission | 15 | Q39, Q40, P6 |

---

*End of QEMU Work Items.*
