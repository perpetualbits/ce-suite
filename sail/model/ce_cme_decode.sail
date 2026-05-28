// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — CME instruction decode
 * Spec reference: ch03 §3.10
 *
 * All CE Suite instructions are R-type under opcode custom-0 (0x0B).
 * funct3 = 000 selects CME; funct7 selects the specific instruction.
 *
 * Encoding: funct7[6:0] | rs2[4:0] | rs1[4:0] | 000 | rd[4:0] | 0001011
 */

union ast = {
  /* CME fast-path bank operations (ch03 §3.1) */
  CE_ECIB : (regidx, regidx),          /* rd, rs1(mask)  */
  CE_ECOB : (regidx, regidx, regidx),  /* rd, rs1(ecid), rs2(mask) */

  /* CME DMA spill/fill (ch03 §3.2) */
  CE_ECIM : (regidx, regidx, regidx),  /* rd, rs1(ecid), rs2(mask) */
  CE_ECOM : (regidx, regidx, regidx),  /* rd, rs1(ecid), rs2(mask) */

  /* CME bank-group assignment (ch03 §3.3) */
  CE_ECIG : (regidx, regidx),          /* rd, rs1(ecid) */
  CE_ECOG : (regidx, regidx),          /* rd, rs1(ecid) */

  /* CME resource delegation (ch03 §3.4) */
  CE_ECIT : (regidx, regidx, regidx),  /* rd, rs1(src_ecid), rs2(child_ecid) */
  CE_ECOT : (regidx, regidx),          /* rd, rs1(child_ecid) */

  /* CME ECID lifecycle (ch03 §3.5) */
  CE_ECIR : (regidx, regidx),          /* rd(new_ecid), rs1(leaf_flag) */
  CE_ECOE : (regidx, regidx),          /* rd(freed_count), rs1(ecid) */

  /* CME vault operations (ch03 §3.6) */
  CE_ECIV : (regidx, regidx, regidx),  /* rd, rs1(ecid), rs2(mask) */
  CE_ECOV : (regidx, regidx, regidx),  /* rd, rs1(ecid), rs2(mask) */

  /* Illegal/unimplemented CE instruction */
  CE_ILLEGAL : unit
}

/* ------------------------------------------------------------------ */
/* Decode mappings (R-type, opcode=custom-0, funct3=000 for CME)      */
/* ------------------------------------------------------------------ */

mapping clause encdec = CE_ECIB(rd, rs1) <->
  CME_ECIB @ 0b00000 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECOB(rd, rs1, rs2) <->
  CME_ECOB @ rs2 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECIM(rd, rs1, rs2) <->
  CME_ECIM @ rs2 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECOM(rd, rs1, rs2) <->
  CME_ECOM @ rs2 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECIG(rd, rs1) <->
  CME_ECIG @ 0b00000 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECOG(rd, rs1) <->
  CME_ECOG @ 0b00000 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECIT(rd, rs1, rs2) <->
  CME_ECIT @ rs2 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECOT(rd, rs1) <->
  CME_ECOT @ 0b00000 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECIR(rd, rs1) <->
  CME_ECIR @ 0b00000 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECOE(rd, rs1) <->
  CME_ECOE @ 0b00000 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECIV(rd, rs1, rs2) <->
  CME_ECIV @ rs2 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE

mapping clause encdec = CE_ECOV(rd, rs1, rs2) <->
  CME_ECOV @ rs2 @ rs1 @ FUNCT3_CME @ rd @ CE_OPCODE
