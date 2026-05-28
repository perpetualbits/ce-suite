# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

SAIL      ?= sail
SAIL_RISCV ?= $(error Set SAIL_RISCV to your sail-riscv checkout path)

# CE Suite sources (no sail-riscv dependencies)
# Order matters: types before state, cme_types before state (EC_entry/Bank)
CE_SOURCES = \
  model/ce_types.sail \
  model/ce_cme_types.sail \
  model/ce_state.sail \
  model/ce_ctrl.sail \
  model/ce_csr.sail \
  model/ce_cme_decode.sail \
  model/ce_cme_execute.sail \
  model/ce_cpe_decode.sail \
  model/ce_mse_decode.sail \
  model/ce_qos_decode.sail

# Standalone check: prepend the prelude that stubs sail-riscv types
CE_STANDALONE_SOURCES = \
  model/ce_standalone_prelude.sail \
  $(CE_SOURCES)

.PHONY: check check-riscv clean

# Type-check CE sources standalone (fast iteration; no sail-riscv needed)
check:
	$(SAIL) -just_check $(CE_STANDALONE_SOURCES)

# Type-check integrated with sail-riscv base model
# NOTE (S4): sail-riscv now uses a .sail_project module system.
# This target needs rewriting to use:
#   sail --project $(SAIL_RISCV)/model/riscv.sail_project ...
# See sail/README.md integration-points section.
check-riscv:
	$(SAIL) -just_check \
	  $(SAIL_RISCV)/model/prelude/prelude.sail \
	  $(SAIL_RISCV)/model/prelude/errors.sail \
	  $(CE_SOURCES)

clean:
	rm -rf _build/
