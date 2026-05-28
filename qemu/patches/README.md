# CE Suite QEMU patches

This directory holds CE Suite patches for QEMU, in numbered order.

Patches are generated from a local QEMU fork and stored here so that
the ce-suite repository tracks the implementation alongside the spec.

## Applying patches

```bash
cd /path/to/qemu-upstream
git am /path/to/ce-suite/qemu/patches/*.patch
```

## Generating patches

```bash
cd /path/to/qemu-fork
git format-patch upstream/master --output-directory /path/to/ce-suite/qemu/patches/
```

## Status

No patches yet — implementation not started. See `../work-items.md`.
