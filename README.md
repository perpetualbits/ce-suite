<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite

The **Context Extensions (CE) suite** is a set of five coordinated RISC-V
extensions for hardware-guaranteed determinism on shared SoCs: hard real-time
worst-case execution time, certifiability (ASIL D, DO-178C, FDA Class III),
1–2 cycle context switches, and bounded memory/I/O access latency, at an
estimated 5–15% transistor overhead per core.

The five extensions:

1. **CME** — Context Management Extension (per-hart hardware context banks)
2. **CPE** — Cache Partitioning Extension (per-hart L1/L2-private slicing)
3. **MSE** — Memory Scheduling Extension (deterministic DRAM arbitration)
4. **QoS** — I/O Quality-of-Service Extension (NoC, DMA, peripheral)
5. **ECID + Group/Contract substrate** — the shared identity layer

This repository holds the specification documents and (eventually) reference
hardware and software implementations.

---

## Navigation

| If you are… | Start here |
|---|---|
| **A RISC-V International reviewer** | [`docs/submission/submission-brief.md`](docs/submission/submission-brief.md) for the allocation request, then [`docs/submission/motivation.md`](docs/submission/motivation.md) for the use cases |
| **Coming back after any break** | [`docs/refamiliarize.md`](docs/refamiliarize.md) |
| **Reviewing the design** | [`docs/charter/project_instructions.md`](docs/charter/project_instructions.md) then [`docs/chapters/ch00-fundamental-structure.md`](docs/chapters/ch00-fundamental-structure.md) |
| **Editing the spec** | Read the charter first; then [`docs/working_notes_for_authors.md`](docs/working_notes_for_authors.md); then your target chapter |
| **Looking for the original drafts** | [`docs/archive/`](docs/archive/) |
| **Looking for working notes** | [`scratchpads/`](scratchpads/) |
| **Building or simulating** | [`sail/`](sail/) (formal model), [`qemu/`](qemu/) (emulator), [`sw/`](sw/) (Linux patches) |

---

## Repository layout

```
ce-suite/
├── README.md                         # this file
├── LICENSE
├── .gitignore
├── docs/
│   ├── charter/
│   │   ├── project_instructions.md   # NORMATIVE: the comb
│   │   └── CHANGELOG.md              # charter version history
│   ├── refamiliarize.md              # re-onboarding doc
│   ├── working_notes_for_authors.md  # workflow companion
│   ├── chapters/                     # the spec proper
│   │   ├── ch00-fundamental-structure.md
│   │   ├── ch01-execution-context-model.md
│   │   ├── ch02-bank-group-delegation.md
│   │   ├── ch03-cme-instruction-set.md
│   │   ├── ch04-hardware-microarch.md
│   │   ├── ch05-linux-integration.md
│   │   ├── ch06-cme-usage-examples.md
│   │   ├── ch07-cpe-instruction-set.md
│   │   ├── ch08-cpe-usage-examples.md
│   │   ├── ch09-mse-memory-scheduling.md
│   │   ├── ch10-mse-usage-examples.md
│   │   ├── ch11-qos-io-quality-of-service.md
│   │   ├── ch12-qos-usage-examples.md
│   │   ├── ch13-csr-reference.md
│   │   ├── ch14-privilege-model.md
│   │   ├── ch15-trap-table.md
│   │   ├── ch16-discovery.md
│   │   ├── ch17-memory-ordering.md
│   │   ├── ch18-clic-integration.md
│   │   ├── ch19-interop-ratified-extensions.md
│   │   ├── appendix-a-ecid.md
│   │   └── appendix-b-profiles.md
│   ├── work-items.md                 # tracked inconsistencies and open items
│   ├── submission/                   # RISC-V International submission materials
│   │   ├── submission-brief.md
│   │   └── motivation.md
│   └── future-directions.md         # non-normative: ideas, research notes, future extensions
│   ├── reference/                    # quick reference materials
│   │   └── instruction-card.md
│   ├── diagrams/                     # SVG / mermaid figures
│   └── archive/                      # superseded drafts, kept for provenance
├── scratchpads/                      # working notes; not normative
│   ├── mse/                          # MSE design material
│   └── general/
├── tools/                            # simulators, sizing calculators
├── hw/                               # FPGA / RTL work (future)
│   ├── rtl/
│   ├── tb/
│   ├── sim/
│   └── board/
└── sw/                               # kernel-side support (future)
    ├── linux-patches/
    └── tests/
```

---

## Document hierarchy

The documents in `docs/` are arranged by normative authority:

1. **`docs/charter/project_instructions.md`** — the **comb**. The normative
   spine. If anything in this repository contradicts the charter, the
   charter wins and the other thing is wrong.
2. **`docs/chapters/ch00-fundamental-structure.md`** — the formal data model.
   Versioned in lockstep with the charter.
3. **`docs/chapters/ch01..ch19`** and appendices — derivative spec chapters. Must be
   consistent with the charter and Chapter 0.
4. **`docs/refamiliarize.md`**, **`docs/working_notes_for_authors.md`** —
   onboarding and workflow companions. Not normative on the architecture,
   but normative on *how the project is run*.
5. **`docs/archive/`** — superseded material kept for provenance only.
   Never edit; never cite as current.
6. **`scratchpads/`** — explicitly not normative. The playground.

---

## Status

| Component | State |
|---|---|
| Charter (project instructions) | **v0.18 — current** |
| Chapter 0 (Fundamental Structure) | Done |
| Chapter 1 (Execution Context Model) | Done |
| Chapter 2 (Bank/Group/Delegation Semantics) | Done |
| Chapter 3 (CME Instruction Set Reference) | Done |
| Chapter 4 (Hardware Microarchitecture) | Done |
| Chapter 5 (Linux Kernel Integration) | Done |
| Chapter 6 (CME Usage Examples) | Done |
| Chapter 7 (CPE Instruction Set Reference) | Done |
| Chapter 8 (CPE Usage Examples) | Done |
| Chapter 9 (MSE Memory Scheduling) | Done |
| Chapter 10 (MSE Usage Examples) | Done |
| Chapter 11 (QoS I/O Quality of Service) | Done |
| Chapter 12 (QoS Usage Examples) | Done |
| Chapter 13 (CSR Reference) | Done — 32 CSRs |
| Chapter 14 (Privilege Model) | Done |
| Chapter 15 (Trap and Exception Table) | Done |
| Chapter 16 (Discovery) | Done |
| Chapter 17 (Memory Ordering) | Done |
| Chapter 18 (CLIC Interrupt Integration) | Done |
| Chapter 19 (Interoperability with Ratified Extensions) | Done |
| Appendix A (ECID) | Done |
| Appendix B (Capability Profiles) | Done |
| `sail/` | Work plan complete; implementation started (S1 done) |
| `qemu/` | Work plan complete; implementation not yet started |
| `sw/` | Work plan complete; implementation not yet started |
| `hw/` | Future work |

See `docs/refamiliarize.md` Part A.3 for the detailed chapter status table,
and `docs/work-items.md` for all tracked inconsistencies and open design
decisions.

---

## License

Specification text (all `.md` and `.adoc` files under `docs/`) is licensed under
[CC BY 4.0](LICENSE-CC-BY-4.0.txt). Code (everything under `sail/`, `qemu/`, `sw/`,
`tools/`, `hw/`) is licensed under [BSD 3-Clause](LICENSE-BSD-3-Clause.txt).
