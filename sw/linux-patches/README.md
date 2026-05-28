# CE Suite Linux kernel patches

Numbered patch series for CE Suite Linux kernel support, in application order.

## Applying

```bash
cd /path/to/linux
git am /path/to/ce-suite/sw/linux-patches/*.patch
```

## Generating

```bash
cd /path/to/linux-fork
git format-patch upstream/master --output-directory \
  /path/to/ce-suite/sw/linux-patches/
```

## Status

No patches yet — implementation not started. See `../work-items.md`.
