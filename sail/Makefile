# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

SAIL      ?= sail
SAIL_RISCV ?= $(error Set SAIL_RISCV to your sail-riscv checkout path)

CE_SOURCES = \
  model/ce_types.sail \
  model/ce_state.sail \
  model/ce_ctrl.sail \
  model/ce_csr.sail \
  model/ce_cme_types.sail \
  model/ce_cme_decode.sail \
  model/ce_cme_execute.sail \
  model/ce_cpe_decode.sail \
  model/ce_mse_decode.sail \
  model/ce_qos_decode.sail

.PHONY: check check-riscv clean

# Type-check CE sources standalone (useful for iterating quickly)
check:
	$(SAIL) -just_check $(CE_SOURCES)

# Type-check integrated with sail-riscv base model
check-riscv:
	$(SAIL) -just_check \
	  $(SAIL_RISCV)/model/prelude.sail \
	  $(SAIL_RISCV)/model/riscv_types.sail \
	  $(SAIL_RISCV)/model/riscv_regs.sail \
	  $(CE_SOURCES)

clean:
	rm -rf _build/
