# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

# CE suite sizing & percentage calculator
#
# Adjust the parameters in the CONFIG section (near the top) to explore
# different bank counts/sizes, technology nodes (bitcell area), and baselines.
#
# Outputs:
# 1) A summary table for the current config
# 2) A node sweep table (28nm/16nm/7nm presets)
# 3) A baseline sweep table (three example core baselines)
# 4) CSV files saved under /mnt/data for your repo
#
# Notes:
# - SRAM bitcell uses 6T by default. Periphery is modeled as a scalar multiplier.
# - Logic area for copy engine / lanes is modeled as a small additive fudge factor.
#   Tweak 'logic_overhead_mm2' as you gain better estimates from synthesis.

from dataclasses import dataclass, asdict
from typing import Dict, List
import pandas as pd
import math
from caas_jupyter_tools import display_dataframe_to_user

# ---------------------------- CONFIG ----------------------------------

@dataclass
class CESizingConfig:
    # Banks
    nv_banks: int = 64
    nv_bank_size_bytes: int = 1024           # 1 KB
    vmt_banks: int = 4
    vmt_bank_size_bytes: int = 4096          # 4 KB (1024-bit x 32)
    # Staging (S/R for NV and VMT)
    staging_nv_banks: int = 2
    staging_nv_bank_size_bytes: int = 1024
    staging_vmt_banks: int = 2
    staging_vmt_bank_size_bytes: int = 4096

    # SRAM technology
    bitcell_area_um2_per_bit: float = 0.04   # default ~16/12nm
    sram_periphery_factor: float = 1.25      # array * periphery overhead

    # Logic overhead (copy engine, decoders, small tables, lane drivers, misc)
    logic_overhead_mm2: float = 0.01         # tweak as data arrives

    # Transistor model (bitcell only; 6T)
    transistors_per_bitcell: int = 6
    periphery_trans_factor: float = 1.15     # transistor overhead for periphery (approx)

@dataclass
class Baseline:
    name: str
    core_area_mm2: float
    core_transistors_m: float
    core_sram_kb: float

cfg = CESizingConfig()

# Example core baselines you can edit or add to
baselines = [
    Baseline("Small in-order (uC-class)", core_area_mm2=0.7, core_transistors_m=18.0, core_sram_kb=80.0),
    Baseline("Mid in-order (apps)",       core_area_mm2=1.5, core_transistors_m=30.0, core_sram_kb=128.0),
    Baseline("Small OoO",                  core_area_mm2=3.0, core_transistors_m=60.0, core_sram_kb=192.0),
]

# Node presets for sweeps (bitcell area only; you can tweak periphery if desired)
node_presets = {
    "28nm-ish": 0.08,
    "16/12nm": 0.04,
    "7/5nm-ish": 0.027,
}

# ------------------------- CALCULATIONS -------------------------------

def ce_sram_bytes(config: CESizingConfig) -> int:
    return (config.nv_banks * config.nv_bank_size_bytes +
            config.vmt_banks * config.vmt_bank_size_bytes +
            config.staging_nv_banks * config.staging_nv_bank_size_bytes +
            config.staging_vmt_banks * config.staging_vmt_bank_size_bytes)

def sram_area_mm2(bytes_count: int, bitcell_area_um2_per_bit: float, periphery_factor: float) -> float:
    bits = bytes_count * 8
    area_um2 = bits * bitcell_area_um2_per_bit * periphery_factor
    return area_um2 / 1e6  # µm² -> mm²

def sram_transistors_m(bits: int, trans_per_bit: int, periph_factor: float) -> float:
    # bitcell trans + rough periphery multiplier
    return (bits * trans_per_bit * periph_factor) / 1e6  # millions

def summarize_config(config: CESizingConfig):
    bytes_total = ce_sram_bytes(config)
    bits_total = bytes_total * 8
    area_mm2 = sram_area_mm2(bytes_total, config.bitcell_area_um2_per_bit, config.sram_periphery_factor)
    trans_m = sram_transistors_m(bits_total, config.transistors_per_bitcell, config.periphery_trans_factor)
    total_area_mm2 = area_mm2 + config.logic_overhead_mm2

    return {
        "NV banks": config.nv_banks,
        "NV bank size (KB)": config.nv_bank_size_bytes / 1024,
        "VMT banks": config.vmt_banks,
        "VMT bank size (KB)": config.vmt_bank_size_bytes / 1024,
        "Staging NV banks": config.staging_nv_banks,
        "Staging VMT banks": config.staging_vmt_banks,
        "Total CE SRAM (KB)": bytes_total / 1024,
        "Bitcell area (µm²/bit)": config.bitcell_area_um2_per_bit,
        "SRAM periphery factor": config.sram_periphery_factor,
        "SRAM area (mm²)": round(area_mm2, 4),
        "Logic overhead (mm²)": config.logic_overhead_mm2,
        "Total CE area (mm²)": round(total_area_mm2, 4),
        "Bitcell trans/bit": config.transistors_per_bitcell,
        "Periphery trans factor": config.periphery_trans_factor,
        "CE SRAM transistors (M)": round(trans_m, 3),
    }

def percentages_vs_baseline(config: CESizingConfig, base: Baseline):
    bytes_total = ce_sram_bytes(config)
    bits_total = bytes_total * 8
    area_mm2 = sram_area_mm2(bytes_total, config.bitcell_area_um2_per_bit, config.sram_periphery_factor)
    trans_m = sram_transistors_m(bits_total, config.transistors_per_bitcell, config.periphery_trans_factor)
    total_area_mm2 = area_mm2 + config.logic_overhead_mm2

    pct_area = 100.0 * total_area_mm2 / base.core_area_mm2
    pct_trans = 100.0 * trans_m / base.core_transistors_m
    pct_sram = 100.0 * (bytes_total / 1024) / base.core_sram_kb

    return {
        "Baseline": base.name,
        "Baseline area (mm²)": base.core_area_mm2,
        "Baseline transistors (M)": base.core_transistors_m,
        "Baseline SRAM (KB)": base.core_sram_kb,
        "CE total area (mm²)": round(total_area_mm2, 4),
        "CE SRAM transistors (M)": round(trans_m, 3),
        "CE SRAM (KB)": bytes_total / 1024,
        "Area %": round(pct_area, 2),
        "Transistors %": round(pct_trans, 2),
        "SRAM %": round(pct_sram, 2),
    }

def build_summary_tables(config: CESizingConfig, baselines: List[Baseline]):
    # Current config summary
    cur = summarize_config(config)
    df_cur = pd.DataFrame([cur])

    # Node sweep
    rows = []
    for node, a_cell in node_presets.items():
        tmp = CESizingConfig(**asdict(config))
        tmp.bitcell_area_um2_per_bit = a_cell
        s = summarize_config(tmp)
        s["Node"] = node
        rows.append(s)
    df_nodes = pd.DataFrame(rows)[["Node","Total CE SRAM (KB)","Bitcell area (µm²/bit)","SRAM periphery factor",
                                   "SRAM area (mm²)","Logic overhead (mm²)","Total CE area (mm²)",
                                   "CE SRAM transistors (M)"]]

    # Baseline sweep
    df_base = pd.DataFrame([percentages_vs_baseline(config, b) for b in baselines])

    return df_cur, df_nodes, df_base

df_cur, df_nodes, df_base = build_summary_tables(cfg, baselines)

# Display to user
display_dataframe_to_user("CE Sizing — Current Config", df_cur)
display_dataframe_to_user("CE Sizing — Node Sweep", df_nodes)
display_dataframe_to_user("CE Sizing — Baseline Percentages", df_base)

# Save CSVs for the repo
df_cur.to_csv("/mnt/data/ce_sizing_current_config.csv", index=False)
df_nodes.to_csv("/mnt/data/ce_sizing_node_sweep.csv", index=False)
df_base.to_csv("/mnt/data/ce_sizing_baseline_percentages.csv", index=False)

"Done. CSVs saved under /mnt/data."

