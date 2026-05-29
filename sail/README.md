# CE Suite — Sail Formal Model

Sail formal model for the CE Suite RISC-V ISA extensions (CME, CPE, MSE, QoS).

## Current status (through S25 — Phase 8 complete)

### CME — Context Management Extension

All 10 functional CME instructions have full execute implementations. The vault
pair (`ec.iv`/`ec.ov`) is decode-only (encryption algorithm is
implementation-defined; key management deferred to a later version).

| Instruction | Purpose | Status |
|-------------|---------|--------|
| `ec.ib` | Save live registers to bank | ✓ Full |
| `ec.ob` | Restore bank to live registers (context switch) | ✓ Full |
| `ec.im` | Spill bank state to ECS in RAM | ✓ Full |
| `ec.om` | Fill bank state from ECS in RAM | ✓ Full |
| `ec.ig` | Assign a free bank to an ECID's Group | ✓ Full |
| `ec.og` | Release a bank from an ECID's Group | ✓ Full |
| `ec.it` | Delegate one bank to a child ECID | ✓ Full |
| `ec.ot` | Revoke all banks from a child ECID to parent | ✓ Full |
| `ec.ir` | Allocate a child ECID | ✓ Full |
| `ec.oe` | Forced destroy of ECID and subtree | ✓ Full |
| `ec.iv` | Seal bank under encryption | Decode only |
| `ec.ov` | Unseal bank | Decode only |

**Privilege model (S22):** `ce_ctrl` (0x7D0) enables/disables extensions.
`cme_priv_ctl` (0x7CF) controls S/HS-mode access. `hcme_ctrl` (0x6C0) controls
VS-mode access. Every execute clause checks `cme_authorized()` before any other
logic.

**cme_status (S21):** Every execute clause updates `cme_status[7:0]` in parallel
with the `rd` write via `cme_ret_err`/`cme_ret_ok` helpers.

### CPE / MSE / QoS

Decode stubs only. Execute functions come after the CME validation suite (Phase 8)
is complete.

### Test suite (11 tests)

| Test file | Covers |
|-----------|--------|
| `ce_cme_test_s7.sail` | Fast-path context switch (ec.ib → ec.ob) |
| `ce_cme_test_s8.sail` | Dirty-save mode (rs1=x0 vs. explicit mask=0) |
| `ce_cme_test_s11.sail` | Generation counter validation (stale reference detection) |
| `ce_cme_test_s14.sail` | Bank exhaustion recovery protocol |
| `ce_cme_test_s17.sail` | Memory ordering fence sequence (§17.5) |
| `ce_cme_test_s18.sail` | ec.it: bank delegation with ancestry check |
| `ce_cme_test_s19.sail` | ec.ot: bank revocation to parent |
| `ce_cme_test_s20.sail` | CSR 0xFD1/0xFD2 reflect current_ecid after ec.ob |
| `ce_cme_test_s21.sail` | cme_status updated by all CME instructions |
| `ce_cme_test_s22.sail` | Privilege gating: M/S/VS/U-mode × CME_EN/S_EN/VS_EN |
| `ce_cme_test_s23.sail` | Round-trip register preservation (ec.ir → ec.ig → ec.ib → ec.ob × 2) |
| `ce_cme_test_s24.sail` | Delegation depth cap: ec.ir rs1=1 from L=D → CME_ERR_CAP_DEPTH |
| `ce_cme_test_s25.sail` | Sealed bank: ec.ob refusal, state unchanged; unseal → success |

### What's next

- **S26–S28** — CPE execute functions (cp.ir, cp.or, cp.it, cp.ot)
- **S29–S31** — MSE execute functions
- **S32–S34** — QoS execute functions
- **S35–S38** — Integration, litmus tests, submission prep

---

## Prerequisites

```
opam install sail
git clone https://github.com/riscv/sail-riscv.git
```

Verify: `sail --version` ≥ 0.17. Set `SAIL_RISCV` to the sail-riscv checkout
path (default: `~/git/sail-riscv`).

## Build

```
make check          # type-check CE Suite standalone (fast, no sail-riscv needed)
make check-riscv    # type-check integrated with sail-riscv
make clean
```

Both targets exit 0 with warnings only (no errors).

## Project structure

```
sail/
├── model/
│   ├── ce_types.sail              # Base types, constants, error codes
│   ├── ce_cme_types.sail          # CME-specific types: EC_entry, Bank, sealed state
│   ├── ce_state.sail              # Architectural state (EC array, bank pool, dirty bitmap)
│   │                              #   + lookup_ec, find_bank, is_ancestor helpers
│   ├── ce_ctrl.sail               # ce_ctrl (0x7D0), cme_priv_ctl (0x7CF), hcme_ctrl (0x6C0)
│   │                              #   + cme_enabled, cme_priv_allowed, cme_authorized
│   ├── ce_csr.sail                # All other CE Suite CSRs (read/write clauses)
│   ├── ce_cme_decode.sail         # CME instruction decode (all 12 instructions)
│   ├── ce_cme_execute.sail        # CME execute functions + cme_ret_err/cme_ret_ok helpers
│   ├── ce_cpe_decode.sail         # CPE decode stubs
│   ├── ce_mse_decode.sail         # MSE decode stubs
│   ├── ce_qos_decode.sail         # QoS decode stubs
│   ├── ce_standalone_prelude.sail # Stubs for standalone type-check (no sail-riscv)
│   ├── ce_cme_test_s7.sail        # Test: fast-path context switch
│   ├── ce_cme_test_s8.sail        # Test: dirty-save mode
│   ├── ce_cme_test_s11.sail       # Test: generation counter validation
│   ├── ce_cme_test_s14.sail       # Test: bank exhaustion recovery
│   ├── ce_cme_test_s17.sail       # Test: memory ordering obligations
│   ├── ce_cme_test_s18.sail       # Test: ec.it bank delegation
│   ├── ce_cme_test_s19.sail       # Test: ec.ot resource revocation
│   ├── ce_cme_test_s20.sail       # Test: CSR 0xFD1/0xFD2 correctness
│   ├── ce_cme_test_s21.sail       # Test: cme_status audit
│   ├── ce_cme_test_s22.sail       # Test: privilege gating
│   ├── ce_cme_test_s23.sail       # Test: round-trip register preservation
│   ├── ce_cme_test_s24.sail       # Test: delegation depth cap enforcement
│   └── ce_cme_test_s25.sail       # Test: sealed bank ec.ob refusal
├── scripts/
│   └── inject_ce_files.py         # Injects CE files into sail-riscv file list
├── work-items.md                  # Detailed work item tracking (S1–S38)
├── Makefile
└── README.md
```

## sail-riscv integration

CE Suite adds clauses to four scattered declarations in sail-riscv:

| sail-riscv declaration | File | CE Suite adds |
|---|---|---|
| `scattered union instruction` | `sys/insts_begin.sail` | 12 CME + 4 CPE + 4 MSE + 4 QoS variants |
| `scattered function execute` | `sys/insts_begin.sail` | one `function clause execute` per CE instruction |
| `scattered mapping encdec` | `sys/insts_begin.sail` | one `mapping clause encdec` per CE instruction |
| `scattered function read_CSR` | `core/csr_begin.sail` | CE Suite CSR read clauses |
| `scattered function write_CSR` | `core/csr_begin.sail` | CE Suite CSR write clauses |

`scripts/inject_ce_files.py` reads sail-riscv's file list via `sail --list-files`
and inserts CE Suite files immediately before `postlude/insts_end.sail`.

## Specification references

All instruction semantics, CSR definitions, and error codes are taken from the
CE Suite specification (`docs/chapters/`). The spec is the normative reference;
this Sail model is derivative.

| Sail file | Spec reference |
|-----------|----------------|
| `ce_types.sail` | ch00 §0.2, ch15 §15.4 |
| `ce_cme_types.sail` | ch00 §0.3–§0.7 |
| `ce_state.sail` | ch00 §0.2–§0.3, ch13 |
| `ce_ctrl.sail` | ch13 §1.1, ch14 §14.4 |
| `ce_csr.sail` | ch13 §3–§6 |
| `ce_cme_decode.sail` | ch03 §3.10 |
| `ce_cme_execute.sail` | ch03 §3.1–§3.6, §3.12, ch14 §14.2–§14.5, ch15 §15.5.1 |
| `ce_cpe_decode.sail` | ch07 §7.10 |
| `ce_mse_decode.sail` | ch09 §9.11 |
| `ce_qos_decode.sail` | ch11 §11.11 |
