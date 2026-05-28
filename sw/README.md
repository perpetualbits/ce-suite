<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com> -->

# Software (kernel-side support)

**Status: not yet populated.**

This tree is the placeholder for kernel-side software supporting the
CE Suite. The primary target is Linux, but the design generalizes to
other OSes (see `docs/chapters/ch05-linux-integration.md`).

## Planned layout

```
sw/
├── linux-patches/    # Linux kernel patches for CE support
└── tests/            # userland and kernel tests for CE behavior
```

## Scope

Eventually this tree will hold:

- Kernel patches teaching Linux to use CME instructions
  (`ec.ib`/`ec.ob`/`ec.im`/`ec.om`/`ec.od`) in the context-switch path.
- The radix-tree ECID allocator (see Appendix A).
- CPE, MSE, and QoS hooks.
- Userland tooling (e.g., `setcontract`, analogous to `cgcreate`).
- Tests that validate CE behavior on real silicon (or FPGA prototypes
  built in `../hw/`).

## Before any kernel work begins

1. Spec chapters 5, 7 (and eventually 8, 9) must be coherent enough to
   implement against.
2. A working CME implementation in `../hw/` is the prerequisite for
   anything beyond stub patches.

Until then, this directory is reserved.
