#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>
"""
md2adoc.py — Convert CE Suite Markdown files to AsciiDoc via pandoc,
then clean up pandoc's defensive passthrough escapes for underscores and
brackets inside code spans.

Usage: python3 tools/md2adoc.py <input.md> <output.adoc>
"""

import re
import subprocess
import sys


SPDX_HEADER = (
    '// SPDX-License-Identifier: CC-BY-4.0\n'
    '// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>\n'
    '\n'
)

PASSTHROUGH_FIXES = [
    ('++_++', '_'),
    ('++[++', '['),
    ('++]++', ']'),
    ('++*++', '*'),
    ('++.++', '.'),
    ('++`++', '`'),
]


def run_pandoc(src: str) -> str:
    result = subprocess.run(
        ['pandoc', '-f', 'markdown', '-t', 'asciidoc', src],
        capture_output=True, text=True, check=True
    )
    return result.stdout


def fix_passthroughs(text: str) -> str:
    for escaped, raw in PASSTHROUGH_FIXES:
        text = text.replace(escaped, raw)
    return text


def fix_source_blocks(text: str) -> str:
    """
    pandoc emits unlabelled literal blocks (..../ ....) for fenced code blocks
    without a language tag, and [source,lang] blocks for tagged ones.
    Both are fine; no change needed.  This hook is here for future fixups.
    """
    return text


def fix_tables(text: str) -> str:
    """
    pandoc emits [cols=",,...",options="header",] with empty column specs.
    Replace with a more readable form that Asciidoctor handles well.
    The number of columns is inferred from the separator count.
    """
    def rewrite_cols(m):
        # Count commas in the cols value to get number of columns
        cols_val = m.group(1)
        n = cols_val.count(',') + 1
        options = m.group(2)
        if 'header' in options:
            return f'[cols="{",".join(["1"] * n)}",options="header"]'
        return f'[cols="{",".join(["1"] * n)}"]'

    return re.sub(
        r'\[cols="([^"]*)",options="([^"]*)"\]',
        rewrite_cols,
        text
    )


def convert(src: str, dst: str) -> None:
    raw = run_pandoc(src)
    text = fix_passthroughs(raw)
    text = fix_source_blocks(text)
    text = fix_tables(text)
    with open(dst, 'w') as f:
        f.write(SPDX_HEADER + text)
    print(f'  {src} -> {dst}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f'Usage: {sys.argv[0]} <input.md> <output.adoc>', file=sys.stderr)
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
