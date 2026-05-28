# CE Suite — QEMU functional emulator

QEMU implementation of the CE Suite RISC-V extensions (CME, CPE, MSE, QoS),
enabling software development and kernel work before silicon is available.

## Purpose and scope

QEMU provides **functional correctness** — instructions execute with the right
semantics, CSRs behave as specified, and software can run against the emulated
hardware. It does not model timing or physical resource partitioning:

- **CME:** Full functional implementation. `ec.ib`/`ec.ob` copy real guest
  register state to/from host-allocated bank buffers. Context switches work.
- **CPE:** Functional stubs. Instructions execute and maintain Contract state;
  no actual cache partitioning occurs in QEMU's host cache.
- **MSE:** Functional stubs. Contract admission is tracked; no real DRAM
  arbitration.
- **QoS:** Functional stubs. Same pattern as MSE, per I/O domain.

This is the correct scope for a QEMU implementation. A kernel developer can
write, compile, and test CE Suite kernel patches without caring whether the
underlying emulator really partitions caches.

## Relationship to Sail

The CE Suite Sail model (`../sail/`) is the **oracle**. When QEMU disagrees
with Sail on instruction behaviour, QEMU is wrong. The recommended development
order is:

1. Sail CME Phases 1–8 (formally correct execute semantics)
2. QEMU CME (C implementation; use Sail as reference)
3. Kernel patches (develop against QEMU)
4. Sail + QEMU for CPE/MSE/QoS in parallel

## Approach: patch set against upstream QEMU

CE Suite is implemented as a patch set against upstream QEMU. Patches live in
`patches/` and are applied to a local QEMU clone. This keeps the CE Suite repo
as the single source of truth while remaining upstreamable.

Relevant QEMU files (all under `target/riscv/`):

| QEMU file | CE Suite content |
|-----------|-----------------|
| `cpu.h` / `cpu.c` | `CPURISCVState` additions: EC array, bank pool, `current_ecid`, `ce_ctrl` |
| `insn32.decode` | CE Suite instruction decode entries (custom-0) |
| `translate.c` | `trans_CE_*` translation functions |
| `csr.c` | CE Suite CSR read/write handlers |
| `pmp.c` / `cpu_helper.c` | Privilege model integration (`ce_ctrl` gating) |

## Prerequisites

```bash
# Install QEMU build dependencies (Debian/Ubuntu)
sudo apt-get install git build-essential ninja-build pkg-config \
  libglib2.0-dev libpixman-1-dev

# Clone QEMU
git clone https://gitlab.com/qemu-project/qemu.git qemu-upstream
cd qemu-upstream

# Apply CE Suite patches
git am /path/to/ce-suite/qemu/patches/*.patch
```

## Build

```bash
# From ce-suite/qemu/
make QEMU_SRC=/path/to/qemu-upstream configure
make QEMU_SRC=/path/to/qemu-upstream build
```

## Specification references

All instruction semantics, CSR definitions, and error codes are taken from
the CE Suite specification (`../docs/chapters/`). The spec is normative;
this QEMU implementation is derivative.

| QEMU area | Spec reference |
|-----------|---------------|
| CPURISCVState additions | ch00 §0.3 (EC_entry), ch00 §0.6 (Bank) |
| CME decode | ch03 §3.10 |
| CME execute | ch03 §3.1–§3.6 |
| CSR handlers | ch13 |
| Privilege gating | ch14 §14.2–§14.5 |
| Error codes | ch15 §15.4 |
