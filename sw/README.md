<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# CE Suite — Linux kernel patches

This tree holds CE Suite patches for the Linux kernel and associated
userland tooling. The primary target is the RISC-V `arch/riscv/` subtree,
but CE Suite touches the scheduler, cgroup subsystem, KVM, interrupt
framework, and power management as well.

## Layout

```
sw/
├── README.md             # this file
├── work-items.md         # full Linux patch work plan
└── linux-patches/        # numbered patch files (git format-patch output)
    └── README.md
```

## Scope

| Area | What changes |
|------|-------------|
| `arch/riscv/` | ISA detection, boot init, context switch, trap handler, SMP migration, KVM |
| `kernel/sched/` | SCHED_DEADLINE + MSE integration |
| `include/linux/` | CE-aware `task_struct` extensions, cgroup CE types |
| `drivers/` | QoS domain drivers (future) |
| `tools/testing/selftests/riscv/` | CE Suite kernel selftests |
| `Documentation/arch/riscv/` | CE Suite Linux documentation |

## Development target

Linux kernel patches are developed and tested against the CE Suite QEMU
implementation (`../qemu/`). A QEMU CE Suite build is the prerequisite for
any kernel work; real silicon or FPGA is the eventual target.

See `../qemu/work-items.md` for the QEMU work plan. CE Suite QEMU Phase 10
(CME validation complete) is the recommended starting point for kernel work.

## Key design decision: SBI interface for ce_ctrl

`ce_ctrl` (0x7D0) is M-mode only. Linux (S-mode) cannot write it directly.
The boot sequence requires either:
- Firmware (OpenSBI) pre-enables CE Suite before booting Linux, OR
- A new SBI extension (`SBI_EXT_CE`) exposes a `ce_enable(hart, mask)` call.

This decision is tracked as **L1** in `work-items.md` and must be resolved
before any boot or context-switch patches can be written.
