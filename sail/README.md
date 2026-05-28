# CE Suite — Sail Formal Model

Sail formal model for the CE Suite RISC-V ISA extensions (CME, CPE, MSE, QoS).

## Scope — v1

- **CME (Context Management Extension):** full instruction decode; execute functions
  for `ec.ib` and `ec.ob` (the fast-path core); stubs for the remainder.
- **CPE / MSE / QoS:** decode stubs only. Execute functions come after CME is validated.
- **`ce_ctrl` CSR** (0x7D0): modelled with four independent enable bits.
- **Vault (`ec.iv`/`ec.ov`):** decode modelled; execute semantics are out of scope
  for v1 (encryption algorithm is implementation-defined; key management deferred).
- **Chip-global admission control:** axiomatised as a black-box
  `admit_contract(ecid, class, params)` that either succeeds atomically or fails.
  Multi-hart admission interactions are out of scope for v1.

## Prerequisites

```
opam install sail
```

The CE Suite Sail model is intended to extend the official `sail-riscv` model:

```
git clone https://github.com/riscv/sail-riscv.git
```

Set `SAIL_RISCV` to the path of your sail-riscv checkout before building.

## Project structure

```
sail/
├── model/
│   ├── ce_types.sail       # Base types, constants, error codes
│   ├── ce_state.sail       # Architectural state (registers, EC array, banks)
│   ├── ce_ctrl.sail        # ce_ctrl CSR (0x7D0) — per-extension enable bits
│   ├── ce_csr.sail         # All other CE Suite CSRs (read/write clauses)
│   ├── ce_cme_types.sail   # CME-specific types: EC_entry, Bank, sealed state
│   ├── ce_cme_decode.sail  # CME instruction decode (all 12 instructions)
│   ├── ce_cme_execute.sail # CME execute functions
│   ├── ce_cpe_decode.sail  # CPE decode stubs (cp.ir/cp.or/cp.it/cp.ot)
│   ├── ce_mse_decode.sail  # MSE decode stubs (ms.ir/ms.or/ms.it/ms.ot)
│   └── ce_qos_decode.sail  # QoS decode stubs (qs.ir/qs.or/qs.it/qs.ot)
└── Makefile
```

## Build

```
make check          # type-check CE Suite Sail sources standalone
make check-riscv    # type-check integrated with sail-riscv (requires SAIL_RISCV)
make clean
```

## Specification references

All instruction semantics, CSR definitions, and error codes are taken from the
CE Suite specification (`docs/chapters/` and `docs/adoc/chapters/`). The spec
is the normative reference; this Sail model is derivative.

| Sail file | Spec reference |
|-----------|---------------|
| `ce_types.sail` | ch00 §0.2, ch15 §15.4 |
| `ce_state.sail` | ch00 §0.3, ch13 |
| `ce_ctrl.sail` | ch13 §1.1 |
| `ce_csr.sail` | ch13 §3–§6 |
| `ce_cme_types.sail` | ch00 §0.3–§0.7 |
| `ce_cme_decode.sail` | ch03 §3.10 |
| `ce_cme_execute.sail` | ch03 §3.1–§3.6, ch15 §15.5.1 |
| `ce_cpe_decode.sail` | ch07 §7.10 |
| `ce_mse_decode.sail` | ch09 §9.11 |
| `ce_qos_decode.sail` | ch11 §11.11 |
