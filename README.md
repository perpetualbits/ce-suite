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
| **Coming back after any break** | [`docs/refamiliarize.md`](docs/refamiliarize.md) |
| **Reviewing the design** | [`docs/charter/project_instructions.md`](docs/charter/project_instructions.md) then [`docs/chapters/ch00-fundamental-structure.md`](docs/chapters/ch00-fundamental-structure.md) |
| **Editing the spec** | Read the charter first; then [`docs/working_notes_for_authors.md`](docs/working_notes_for_authors.md); then your target chapter |
| **Looking for the original drafts** | [`docs/archive/`](docs/archive/) |
| **Looking for working notes** | [`scratchpads/`](scratchpads/) |
| **Building or simulating** | `hw/` and `sw/` (placeholders for now) |

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
│   │   ├── ch02-cme-instruction-set.md
│   │   ├── ch03-bank-group-delegation.md
│   │   ├── ch04-hardware-microarch.md
│   │   ├── ch05-linux-integration.md
│   │   ├── ch06-cme-usage-examples.md
│   │   ├── ch07-cpe-instruction-set.md
│   │   ├── ch08-mse-memory-scheduling.md
│   │   ├── ch09-qos-io-quality-of-service.md
│   │   └── appendix-a-ecid.md
│   ├── work-items.md                 # tracked inconsistencies and open items
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
3. **`docs/chapters/ch01..ch09`** — derivative spec chapters. Must be
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
| Charter (project instructions) | **v0.11 — current** |
| Chapter 0 (Fundamental Structure) | Done — aligned to charter v0.11 |
| Chapters 1–6 | Done — ECID-first; known issues tracked in `docs/work-items.md` |
| Chapter 7 (CPE) | **Being redesigned** — see work item F1 in `docs/work-items.md` |
| Chapter 8 (MSE) | Done — ms.{ir,or,it,ot}, BE/contract slot model |
| Chapter 9 (QoS) | Done — qs.{ir,or,it,ot}, per-domain contracts |
| Appendix A (ECID) | Done — radix-tree algorithms and diagrams |
| `hw/` | empty; future work |
| `sw/` | empty; future work |

See `docs/refamiliarize.md` Part A.3 for the detailed chapter status table,
and `docs/work-items.md` for all tracked inconsistencies and open design
decisions.

---

## License

[TBD — your choice. See `LICENSE`.]
