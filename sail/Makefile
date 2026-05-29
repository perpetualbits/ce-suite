# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

SAIL       ?= sail
SAIL_RISCV ?= $(HOME)/git/sail-riscv

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
  model/ce_qos_decode.sail \
  model/ce_cme_test_s7.sail \
  model/ce_cme_test_s8.sail \
  model/ce_cme_test_s11.sail \
  model/ce_cme_test_s14.sail \
  model/ce_cme_test_s17.sail \
  model/ce_cme_test_s18.sail \
  model/ce_cme_test_s19.sail \
  model/ce_cme_test_s20.sail \
  model/ce_cme_test_s21.sail \
  model/ce_cme_test_s22.sail

# Standalone check: prepend the prelude that stubs sail-riscv types
CE_STANDALONE_SOURCES = \
  model/ce_standalone_prelude.sail \
  $(CE_SOURCES)

.PHONY: check check-riscv clean

# Type-check CE sources standalone (fast iteration; no sail-riscv needed)
check:
	$(SAIL) -just_check $(CE_STANDALONE_SOURCES)

# Type-check integrated with sail-riscv base model.
# Uses scripts/inject_ce_files.py to generate the ordered file list from
# sail-riscv's riscv.sail_project, injecting CE Suite files before
# postlude/insts_end.sail where scattered unions/functions are closed.
check-riscv:
	$(SAIL) -just_check \
	  $(shell python3 scripts/inject_ce_files.py \
	    $(SAIL) $(SAIL_RISCV)/model $(CE_SOURCES))

clean:
	rm -rf _build/
