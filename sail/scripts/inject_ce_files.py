#!/usr/bin/env python3
"""
inject_ce_files.py — Build ordered sail -just_check file list for CE Suite
integrated type-check.

Usage:
    python3 inject_ce_files.py <sail_bin> <sail_riscv_model_dir> <ce_file> ...

Generates the file list from sail-riscv's riscv.sail_project (all modules),
inserts CE Suite files immediately before postlude/insts_end.sail (the point
where 'end instruction', 'end execute', 'end encdec', 'end read_CSR', and
'end write_CSR' close all the scattered declarations CE Suite extends),
then prints the full space-separated list for consumption by sail -just_check.
"""
import subprocess, sys

def main():
    if len(sys.argv) < 4:
        print("Usage: inject_ce_files.py <sail_bin> <sail_riscv_model_dir> <ce_file> ...",
              file=sys.stderr)
        sys.exit(1)

    sail_bin         = sys.argv[1]
    sail_riscv_model = sys.argv[2]
    ce_sources       = sys.argv[3:]

    result = subprocess.run(
        [sail_bin, '--list-files-separated', '\n',
         '--project', f'{sail_riscv_model}/riscv.sail_project',
         '--all-modules'],
        capture_output=True, text=True, check=True
    )
    files = [f for f in result.stdout.strip().split('\n') if f]

    # insts_end.sail closes instruction/execute/encdec/read_CSR/write_CSR
    # with 'end X' statements.  CE Suite clauses must appear before this.
    try:
        idx = next(i for i, f in enumerate(files) if 'insts_end.sail' in f)
    except StopIteration:
        print("ERROR: could not find insts_end.sail in sail-riscv file list",
              file=sys.stderr)
        sys.exit(1)

    ordered = files[:idx] + ce_sources + files[idx:]
    print(' '.join(ordered))

if __name__ == '__main__':
    main()
