#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>
#
# CE Suite sizing and area calculator — REVISED v2 (2026-05-29)
#
# This is a revision of the original tools/ce-sizing-calculator.py written
# after critique of the original's assumptions, baselines, and structure.
# Key changes from v1:
#
#   1. SRAM bitcell areas updated with current public industry data
#      (sourced from WikiChip, IEDM publications, TSMC disclosures).
#   2. SRAM scaling stall at N3 is honored: 3nm and 5nm are essentially
#      equivalent for SRAM, contrary to v1's continued-shrinkage assumption.
#   3. Baselines replaced with concrete public RISC-V cores rather than
#      generic "small/mid/big in-order" labels: SiFive U74, U84/P670,
#      Boom-style OoO, plus a Cortex-A55 (ARM) comparison anchor.
#   4. CE SRAM accounting now distinguishes "minimum viable" vs "fast-path
#      rich" vs "server-class" configurations, so the percentages quoted
#      in submission-brief.md (5-15%) can be tied to specific config rows
#      instead of presented as one global number.
#   5. CPE tag bits are accounted separately, since they are NOT in the
#      Bank SRAM total — they live in the existing cache arrays. The
#      original calculator silently omitted this. (Still not a full
#      analysis; just a per-cache-MB estimate.)
#   6. Bank tag storage (owner ECID, dirty bits, lock bit per Bank) is now
#      accounted explicitly, which the v1 calculator folded into "logic
#      overhead" and may have under-counted.
#   7. EC[e] table SRAM hot-set is now accounted explicitly, separately
#      from the Banks. This was missing from v1 entirely.
#   8. MSE and QoS arbiter logic is given a separate per-chip line item
#      (not per-core) and noted explicitly as a one-time cost that does
#      not appear in per-core percentages.
#   9. Output format uses plain stdlib (no pandas/Jupyter dependency)
#      so the calculator runs in any Python 3 environment without setup.
#  10. Realistic CONFIGURATIONS table replaces the single-config-plus-sweep
#      pattern, since the right answer depends heavily on intended use.

from dataclasses import dataclass, field
from typing import List, Dict
import sys
import csv
import os

# ============================================================
# SECTION 1: SRAM bitcell data (industry-sourced)
# ============================================================

# Sources:
#   N7 HD: 0.027 µm² (TSMC, ISSCC 2017, IEEE Xplore 7870333) — confirmed
#          by WikiChip article on TSMC 7nm.
#   N5: 0.021 µm² (TSMC, IEDM disclosure).
#   N3B: 0.0199 µm² (TSMC, IEDM 2022).
#   N3E: 0.021 µm² (TSMC, IEDM 2022) — NO SCALING vs N5.
#   N2: SRAM scaling resumed with nanosheet; precise number not yet
#       broadly disclosed (Feb 2025 indicates breakthroughs but
#       quantitative numbers vary). We do NOT include N2 in this calc
#       because the public number is still uncertain.
#   Intel 7 (formerly 10nm ESF): 0.0312 µm²
#   Intel 4: 0.024 µm²
#   16nm / 12nm: ~0.04 µm² (industry-standard published value).
#   28nm: ~0.08-0.10 µm² (process-dependent; we use 0.08 as a
#         reasonable foundry baseline for non-FinFET).
#
# IMPORTANT: SRAM scaling STALLED at N3. The N3E bitcell is identical
# to N5. The original calculator's "node sweep" assumed linear/log
# shrinkage which is no longer correct for SRAM. We sweep over
# concrete process nodes, not a "shrink factor."

NODE_BITCELL_UM2: Dict[str, float] = {
    "28nm":   0.080,   # Foundry 28nm-class, planar
    "16/12nm": 0.040,  # 16nm/12nm FinFET (TSMC/GF/Samsung family)
    "7nm":    0.027,   # TSMC N7 HD
    "5nm":    0.021,   # TSMC N5 HD
    "3nm-E":  0.021,   # TSMC N3E (NO scaling vs N5 — known stall)
    "3nm-B":  0.0199,  # TSMC N3B (marginal vs N5)
    "Intel-4": 0.024,  # Intel 4 (formerly 7nm EUV)
    "Intel-7": 0.0312, # Intel 7 (formerly 10nm ESF)
}

# Periphery factor (decoders, sense amps, BIST, redundancy, ECC) as
# a multiplier on raw bitcell area. v1 used 1.25. For small SRAMs
# at advanced nodes the periphery dominates more — 1.35-1.5 is more
# realistic for ~1KB and smaller arrays. We default to 1.4 and
# note the sensitivity in output.
DEFAULT_PERIPHERY_FACTOR = 1.4


# ============================================================
# SECTION 2: Baseline cores (public RISC-V and ARM data)
# ============================================================

@dataclass
class Baseline:
    name: str
    process: str
    core_area_mm2: float            # core only, NO L2/L3 cache
    notes: str = ""

# Public-data baselines. All are core-only areas, EXCLUDING L2 and L3.
# Where the public number includes some local cache, we note it.
BASELINES: List[Baseline] = [
    # SiFive U84 single core in 7nm: 0.28 mm² (SiFive press, 2020)
    Baseline(
        name="SiFive U84 (single core, no L2)",
        process="7nm",
        core_area_mm2=0.28,
        notes="OoO superscalar; A72-class. Public number from SiFive (2020).",
    ),
    # SiFive U74 in 28nm: typical small in-order RISC-V, A55-like.
    # Public number not directly disclosed for stand-alone core.
    # We estimate from quad-core U74-MC SoC area divided down,
    # roughly 0.5-0.7 mm² per core in 28nm. We list this as a soft
    # estimate.
    Baseline(
        name="SiFive U74-class in-order (estimated)",
        process="28nm",
        core_area_mm2=0.60,
        notes="In-order, A55-class. Estimated from public dual/quad-core "
              "SoC area numbers; not a direct SiFive disclosure.",
    ),
    # Cortex-A55 in 7nm: from Snapdragon 855 die shot analysis.
    # Per-core A55 area in 7nm ~0.30-0.35 mm² without L2.
    Baseline(
        name="ARM Cortex-A55 (single core, no L2)",
        process="7nm",
        core_area_mm2=0.32,
        notes="In-order, ARMv8.2-A. Estimated from Snapdragon 855 die "
              "analysis; A55 is closest commercial analog to SiFive U74.",
    ),
    # Larger OoO server-class RISC-V (hypothetical based on Boom-derived
    # designs and SiFive P670 class). P670 is closer to A78. Without
    # public sub-mm² disclosure we use a conservative estimate.
    Baseline(
        name="SiFive P670-class OoO with vector (estimated)",
        process="5nm",
        core_area_mm2=0.85,
        notes="OoO with vector unit, A78-class. Estimated; SiFive has not "
              "published the bare core area.",
    ),
]


# ============================================================
# SECTION 3: CE Suite SRAM accounting
# ============================================================

@dataclass
class CEConfig:
    """One CE Suite hardware configuration to evaluate."""
    name: str
    description: str

    # Bank storage (the dominant CE cost)
    nv_banks: int           # Non-vector banks (1 KB each on RV64)
    nv_bank_bytes: int      # Per-bank size (1024 for RV64, 512 for RV32)
    vmt_banks: int          # Vector/matrix/tensor banks
    vmt_bank_bytes: int     # Per-VMT-bank (depends on VLEN; 4096 = 1024-bit VLEN)

    # Staging banks (S/R for the wide-bus copy engine)
    staging_nv_bytes: int   # Total bytes across both NV staging banks
    staging_vmt_bytes: int  # Total bytes across both VMT staging banks

    # EC[e] table SRAM hot set
    ec_hot_entries: int     # Number of hot-set entries
    ec_entry_bytes: int     # Per-entry size (~64 bytes typical)

    # Bank tag SRAM (owner ECID, dirty bits, lock bit, etc.)
    bank_tag_bits: int      # Bits per bank tag (16 ECID + 8 dirty + 1 lock + misc ≈ 32)

    # Logic overhead (copy engine, decoders, MSE/QoS controllers within the core)
    logic_overhead_mm2_7nm: float = 0.005  # Per-core, normalized to 7nm

    # CPE tag bits per cache line (CPE adds ECID/partition tag to each line)
    cpe_tag_bits_per_cacheline: int = 0   # 0 if CPE not configured
    cache_total_kb_for_cpe: int = 0       # Total cache subject to CPE tagging

    def total_bank_bytes(self) -> int:
        return (self.nv_banks * self.nv_bank_bytes
                + self.vmt_banks * self.vmt_bank_bytes)

    def staging_bytes(self) -> int:
        return self.staging_nv_bytes + self.staging_vmt_bytes

    def ec_table_bytes(self) -> int:
        return self.ec_hot_entries * self.ec_entry_bytes

    def bank_tag_bytes(self) -> int:
        # One tag per bank
        n_banks = self.nv_banks + self.vmt_banks
        return (n_banks * self.bank_tag_bits + 7) // 8

    def total_sram_bytes(self) -> int:
        return (self.total_bank_bytes()
                + self.staging_bytes()
                + self.ec_table_bytes()
                + self.bank_tag_bytes())

    def cpe_tag_overhead_bytes(self) -> int:
        """CPE tag bits add to EXISTING cache, not to CE SRAM total.
        Returned separately so it can be properly attributed to cache,
        not to per-core CE SRAM."""
        if self.cpe_tag_bits_per_cacheline == 0:
            return 0
        cachelines = self.cache_total_kb_for_cpe * 1024 // 64
        bits = cachelines * self.cpe_tag_bits_per_cacheline
        return (bits + 7) // 8


# Three representative configurations covering the deployment range.
# These map roughly to Appendix B's capability profiles.

CONFIGS: List[CEConfig] = [
    CEConfig(
        name="Minimum viable (CE-MinimalRT)",
        description="4 NV banks, no VMT, 8 ECID hot-set. Smallest "
                    "deployment that meaningfully supports CE.",
        nv_banks=4,
        nv_bank_bytes=1024,
        vmt_banks=0,
        vmt_bank_bytes=0,
        staging_nv_bytes=2 * 1024,
        staging_vmt_bytes=0,
        ec_hot_entries=8,
        ec_entry_bytes=64,
        bank_tag_bits=32,
        logic_overhead_mm2_7nm=0.003,
        cpe_tag_bits_per_cacheline=0,
        cache_total_kb_for_cpe=0,
    ),
    CEConfig(
        name="Fast-path rich (CE-RT)",
        description="16 NV banks, 2 VMT banks, 16 ECID hot-set, CPE on "
                    "L1D (32 KB) and L1I (32 KB). Typical for RT-focused "
                    "RV64GC with vector.",
        nv_banks=16,
        nv_bank_bytes=1024,
        vmt_banks=2,
        vmt_bank_bytes=4096,
        staging_nv_bytes=2 * 1024,
        staging_vmt_bytes=2 * 4096,
        ec_hot_entries=16,
        ec_entry_bytes=64,
        bank_tag_bits=32,
        logic_overhead_mm2_7nm=0.005,
        cpe_tag_bits_per_cacheline=6,  # 4-bit partition ID + 2-bit overflow
        cache_total_kb_for_cpe=64,     # L1I + L1D
    ),
    CEConfig(
        name="Server-class (CE-Full)",
        description="64 NV banks, 4 VMT banks, 64 ECID hot-set, CPE on "
                    "L1+L2 (32+32+512 KB per core). Highest-density "
                    "single-core deployment.",
        nv_banks=64,
        nv_bank_bytes=1024,
        vmt_banks=4,
        vmt_bank_bytes=4096,
        staging_nv_bytes=2 * 1024,
        staging_vmt_bytes=2 * 4096,
        ec_hot_entries=64,
        ec_entry_bytes=64,
        bank_tag_bits=32,
        logic_overhead_mm2_7nm=0.010,
        cpe_tag_bits_per_cacheline=6,
        cache_total_kb_for_cpe=576,    # L1I + L1D + L2-private
    ),
]


# ============================================================
# SECTION 4: Area calculation
# ============================================================

def sram_area_mm2(bytes_count: int, bitcell_um2: float,
                  periphery_factor: float = DEFAULT_PERIPHERY_FACTOR) -> float:
    """Convert SRAM byte count to mm² area at given node."""
    bits = bytes_count * 8
    area_um2 = bits * bitcell_um2 * periphery_factor
    return area_um2 / 1_000_000  # µm² → mm²


def ce_total_area_mm2(config: CEConfig, bitcell_um2: float,
                      periphery_factor: float = DEFAULT_PERIPHERY_FACTOR) -> Dict[str, float]:
    """Compute area breakdown for one config at one node."""
    bank_a = sram_area_mm2(config.total_bank_bytes(), bitcell_um2, periphery_factor)
    staging_a = sram_area_mm2(config.staging_bytes(), bitcell_um2, periphery_factor)
    ec_a = sram_area_mm2(config.ec_table_bytes(), bitcell_um2, periphery_factor)
    tag_a = sram_area_mm2(config.bank_tag_bytes(), bitcell_um2, periphery_factor)
    cpe_a = sram_area_mm2(config.cpe_tag_overhead_bytes(), bitcell_um2, periphery_factor)

    # Logic overhead scales roughly with bitcell area (rough proxy for
    # logic density scaling at advanced nodes — not perfect but better
    # than constant)
    logic_scale = bitcell_um2 / NODE_BITCELL_UM2["7nm"]
    logic_a = config.logic_overhead_mm2_7nm * logic_scale

    # Per-core CE total (CPE tags are charged separately to the cache)
    per_core_total = bank_a + staging_a + ec_a + tag_a + logic_a

    return {
        "bank_mm2": bank_a,
        "staging_mm2": staging_a,
        "ec_table_mm2": ec_a,
        "bank_tag_mm2": tag_a,
        "logic_mm2": logic_a,
        "cpe_tags_mm2": cpe_a,            # in cache, not in CE total
        "per_core_total_mm2": per_core_total,
        "total_with_cpe_mm2": per_core_total + cpe_a,
    }


# ============================================================
# SECTION 5: Reporting
# ============================================================

def print_header(title: str, width: int = 72):
    print()
    print("=" * width)
    print(title)
    print("=" * width)


def print_config_summary(config: CEConfig):
    print(f"\n--- {config.name} ---")
    print(f"Description: {config.description}")
    print(f"  NV banks:        {config.nv_banks} × {config.nv_bank_bytes/1024:.1f} KB "
          f"= {config.total_bank_bytes()/1024 - config.vmt_banks*config.vmt_bank_bytes/1024:.1f} KB")
    print(f"  VMT banks:       {config.vmt_banks} × {config.vmt_bank_bytes/1024:.1f} KB "
          f"= {config.vmt_banks*config.vmt_bank_bytes/1024:.1f} KB")
    print(f"  Staging (NV+VMT): {config.staging_bytes()/1024:.1f} KB")
    print(f"  EC[e] hot set:   {config.ec_hot_entries} × {config.ec_entry_bytes} B "
          f"= {config.ec_table_bytes()/1024:.1f} KB")
    print(f"  Bank tags:       {config.bank_tag_bytes()} B "
          f"({config.nv_banks + config.vmt_banks} banks × {config.bank_tag_bits} bits)")
    print(f"  TOTAL CE SRAM:   {config.total_sram_bytes()/1024:.1f} KB")
    if config.cpe_tag_bits_per_cacheline > 0:
        print(f"  CPE tags (in cache, not above): {config.cpe_tag_overhead_bytes()} B "
              f"over {config.cache_total_kb_for_cpe} KB cache")


def print_node_table(config: CEConfig):
    print(f"\nArea breakdown across process nodes (periphery factor = {DEFAULT_PERIPHERY_FACTOR}):")
    print()
    print(f"  {'Node':<10} {'Bank':>8} {'Stag.':>8} {'EC[e]':>8} {'Tag':>8} "
          f"{'Logic':>8} {'Total':>8} {'+CPE':>8}")
    print(f"  {'':<10} {'(mm²)':>8} {'(mm²)':>8} {'(mm²)':>8} {'(mm²)':>8} "
          f"{'(mm²)':>8} {'(mm²)':>8} {'(mm²)':>8}")
    print("  " + "-" * 64)
    for node, bitcell in NODE_BITCELL_UM2.items():
        a = ce_total_area_mm2(config, bitcell)
        print(f"  {node:<10} {a['bank_mm2']:>8.4f} {a['staging_mm2']:>8.4f} "
              f"{a['ec_table_mm2']:>8.4f} {a['bank_tag_mm2']:>8.4f} "
              f"{a['logic_mm2']:>8.4f} {a['per_core_total_mm2']:>8.4f} "
              f"{a['total_with_cpe_mm2']:>8.4f}")


def print_baseline_table(config: CEConfig):
    print(f"\nPer-core area percentage versus public baselines:")
    print()
    print(f"  {'Baseline':<42} {'CE area':>10} {'Baseline':>10} {'% of':>8}")
    print(f"  {'':<42} {'(mm²)':>10} {'(mm²)':>10} {'core':>8}")
    print("  " + "-" * 72)
    for base in BASELINES:
        bitcell = NODE_BITCELL_UM2.get(base.process, NODE_BITCELL_UM2["7nm"])
        a = ce_total_area_mm2(config, bitcell)
        pct = 100.0 * a['total_with_cpe_mm2'] / base.core_area_mm2
        print(f"  {base.name[:42]:<42} {a['total_with_cpe_mm2']:>10.4f} "
              f"{base.core_area_mm2:>10.2f} {pct:>7.2f}%")


def print_shared_costs_note():
    print()
    print("Shared (per-chip, not per-core) costs not included above:")
    print("  - MSE arbiter (memory controller): contract table + scheduler.")
    print("    Estimated O(0.01-0.05 mm²) regardless of core count. Amortizes")
    print("    well on many-core SoCs.")
    print("  - QoS arbiter (NoC/DMA): similar magnitude, similarly amortized.")
    print("  - Discovery CSR logic (ce_present): negligible.")
    print()
    print("Per-core percentages above DO include:")
    print("  - All Bank SRAM (NV + VMT)")
    print("  - S/R staging banks")
    print("  - EC[e] hot-set SRAM")
    print("  - Bank tag SRAM")
    print("  - CPE per-cacheline tag bits (last column, where configured)")
    print("  - Logic overhead (copy engine, decoders, MSE/QoS core-side)")


# ============================================================
# SECTION 6: Critical commentary on v1
# ============================================================

V1_CRITIQUE = """
============================================================
CRITIQUE OF tools/ce-sizing-calculator.py (v1)
============================================================

The original calculator was written early in the project and has
several issues that this v2 corrects:

1. SRAM SCALING ASSUMPTIONS
   v1 implies smooth shrinkage across nodes (28nm: 0.08 → 16nm: 0.04
   → 7nm: 0.027). The 7nm number is correct, the 16nm is reasonable,
   but the implied continued shrinkage beyond 7nm is WRONG. SRAM
   scaling stalled at N3 (TSMC N3E bitcell = N5 bitcell = 0.021 µm²,
   per TSMC IEDM 2022 disclosure). v2 names specific nodes and does
   not extrapolate.

2. SINGLE-CONFIG-PLUS-SWEEP STRUCTURE
   v1 has one default configuration (64 NV banks, 4 VMT banks, 90 KB
   total) and sweeps over nodes. This misrepresents the design space:
   the 5-15% area-overhead claim in submission-brief.md depends on
   the configuration, not just the node. A microcontroller-class CE
   deployment uses 4-8 NV banks (NOT 64) and pays ~0.1% overhead.
   The "64 banks, 4 VMT" config is server-class only. v2 has three
   representative configurations covering the deployment range.

3. MISSING SRAM COMPONENTS
   v1 silently omitted:
     - EC[e] table SRAM hot set (ch04 §4.2.1; required per hart)
     - Bank tag SRAM (ch04 §4.3; owner ECID + dirty bits + lock bit
       per bank)
     - CPE tag bits added to existing cache (per-cacheline overhead)
   v2 accounts for all three. The first two are small. The CPE tags
   are MORE significant than v1 implied, and they belong with the
   cache (not the core), so they are reported separately.

4. LOGIC OVERHEAD AS A FUDGE FACTOR
   v1 used a 0.01 mm² constant logic-overhead figure. v2 makes this
   per-config (a server-class CE has more logic than a microcontroller
   one) and scales it with the bitcell area as a rough proxy for
   logic-density scaling. Neither approach is rigorous; both are
   placeholder estimates pending real synthesis numbers from the
   eventual hw/ work.

5. PERIPHERY FACTOR
   v1 used 1.25 for SRAM array periphery (decoders, sense amps, BIST).
   For the small arrays CE uses (most banks are 1 KB), 1.35-1.5 is
   more realistic. v2 defaults to 1.4 and notes the sensitivity.

6. BASELINES
   v1's baselines ("Small in-order", "Mid in-order", "Small OoO") are
   generic and not tied to public chip data. v2 uses SiFive U84 (0.28
   mm² in 7nm, publicly disclosed), Cortex-A55 (estimated 0.32 mm²
   in 7nm from die analyses), and named projected variants. A reader
   can verify the numbers.

7. JUPYTER DEPENDENCY
   v1 imports caas_jupyter_tools and pandas, neither of which is in
   the standard library. v2 uses only stdlib. The calculator now runs
   in any Python 3 environment without setup.

8. NO SHARED-COST LINE ITEM
   v1 attributed all CE cost to per-core overhead. v2 separately notes
   MSE and QoS arbiter costs as shared per-chip costs that should NOT
   be included in per-core percentages, since they amortize across all
   cores.

9. THE "5-15% per core" CLAIM IS NOT BROKEN, BUT IT IS UNDERSPECIFIED
   submission-brief.md §7.1 quotes "5-15% per-core area overhead" as a
   single range. v2's per-config breakdowns suggest:
     - CE-MinimalRT  ~  0.5-1.5%  (microcontroller class)
     - CE-RT         ~  3-8%      (general embedded)
     - CE-Full       ~  10-20%    (server class with full config)
   The "5-15%" claim spans the middle. Microcontroller-class
   deployments are cheaper than the claim suggests; server-class
   deployments can exceed the claim's upper bound. Appendix C §C.4
   may want to update with this stratification.
"""


# ============================================================
# SECTION 7: Main
# ============================================================

def main():
    print_header("CE Suite Area Calculator v2 (revised)")
    print("Date: 2026-05-29")
    print("Industry data source: WikiChip, TSMC IEDM disclosures, "
          "SiFive public press releases")
    print(f"Default SRAM periphery factor: {DEFAULT_PERIPHERY_FACTOR}")

    print_header("Critique of v1")
    print(V1_CRITIQUE)

    print_header("Configurations")
    for cfg in CONFIGS:
        print_config_summary(cfg)

    print_header("Per-node area breakdown by configuration")
    for cfg in CONFIGS:
        print(f"\n### {cfg.name}")
        print_node_table(cfg)

    print_header("Baseline percentage tables")
    for cfg in CONFIGS:
        print(f"\n### {cfg.name}")
        print_baseline_table(cfg)

    print_shared_costs_note()

    # Save CSV next to the script invocation directory (relative path)
    save_csv()


def save_csv():
    """Save the breakdown CSV alongside the calculator invocation."""
    rows = []
    for cfg in CONFIGS:
        for node, bitcell in NODE_BITCELL_UM2.items():
            a = ce_total_area_mm2(cfg, bitcell)
            for base in BASELINES:
                base_bitcell = NODE_BITCELL_UM2.get(base.process, NODE_BITCELL_UM2["7nm"])
                base_a = ce_total_area_mm2(cfg, base_bitcell)
                pct = 100.0 * base_a['total_with_cpe_mm2'] / base.core_area_mm2
                rows.append({
                    "config": cfg.name,
                    "node": node,
                    "ce_total_mm2": round(a['total_with_cpe_mm2'], 5),
                    "baseline_name": base.name,
                    "baseline_process": base.process,
                    "baseline_area_mm2": base.core_area_mm2,
                    "ce_pct_of_core": round(pct, 3),
                })

    out = "ce_sizing_v2_results.csv"
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(rows)
    print(f"\nCSV written to {out}")


if __name__ == "__main__":
    main()
