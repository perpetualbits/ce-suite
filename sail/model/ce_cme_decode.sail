// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — CME instruction decode
 * Spec reference: ch03 §3.10
 *
 * All CE Suite instructions are R-type under opcode custom-0 (0b0001011).
 * funct3 = 0b000 selects CME; funct7 selects the specific instruction.
 * Encoding: funct7[6:0] | rs2[4:0] | rs1[4:0] | 000 | rd[4:0] | 0001011
 *
 * Sail mapping clauses require literal bit patterns; symbolic constants
 * are inlined here (sail does not pattern-match let-bound constants).
 */

/* CME fast-path bank operations (ch03 §3.1) */
union clause instruction = CE_ECIB : (regidx, regidx)            /* rd, rs1(mask)  */
union clause instruction = CE_ECOB : (regidx, regidx, regidx)    /* rd, rs1(ecid), rs2(mask) */

/* CME DMA spill/fill (ch03 §3.2) */
union clause instruction = CE_ECIM : (regidx, regidx, regidx)    /* rd, rs1(ecid), rs2(mask) */
union clause instruction = CE_ECOM : (regidx, regidx, regidx)    /* rd, rs1(ecid), rs2(mask) */

/* CME bank-group assignment (ch03 §3.3) */
union clause instruction = CE_ECIG : (regidx, regidx)            /* rd, rs1(ecid) */
union clause instruction = CE_ECOG : (regidx, regidx)            /* rd, rs1(ecid) */

/* CME resource delegation (ch03 §3.4) */
union clause instruction = CE_ECIT : (regidx, regidx, regidx)    /* rd, rs1(src_ecid), rs2(child_ecid) */
union clause instruction = CE_ECOT : (regidx, regidx)            /* rd, rs1(child_ecid) */

/* CME ECID lifecycle (ch03 §3.5) */
union clause instruction = CE_ECIR : (regidx, regidx)            /* rd(new_ecid), rs1(leaf_flag) */
union clause instruction = CE_ECOE : (regidx, regidx)            /* rd(freed_count), rs1(ecid) */

/* CME vault operations (ch03 §3.6) */
union clause instruction = CE_ECIV : (regidx, regidx, regidx)    /* rd, rs1(ecid), rs2(mask) */
union clause instruction = CE_ECOV : (regidx, regidx, regidx)    /* rd, rs1(ecid), rs2(mask) */

/* ------------------------------------------------------------------ */
/* Decode mappings — literals only; no symbolic constants             */
/* opcode = 0b0001011, funct3 = 0b000 (CME)                          */
/* funct7 values: ECIB=0b0000000 ECOB=0b0000001 ECIM=0b0000010       */
/*                ECOM=0b0000011 ECIG=0b0000100 ECOG=0b0000101       */
/*                ECIT=0b0000110 ECOT=0b0000111 ECIR=0b0001000       */
/*                ECOE=0b0001001 ECIV=0b0001010 ECOV=0b0001011       */
/* ------------------------------------------------------------------ */

mapping clause encdec = CE_ECIB(rd, rs1) <->
  0b0000000 @ 0b00000 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECOB(rd, rs1, rs2) <->
  0b0000001 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECIM(rd, rs1, rs2) <->
  0b0000010 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECOM(rd, rs1, rs2) <->
  0b0000011 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECIG(rd, rs1) <->
  0b0000100 @ 0b00000 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECOG(rd, rs1) <->
  0b0000101 @ 0b00000 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECIT(rd, rs1, rs2) <->
  0b0000110 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECOT(rd, rs1) <->
  0b0000111 @ 0b00000 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECIR(rd, rs1) <->
  0b0001000 @ 0b00000 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECOE(rd, rs1) <->
  0b0001001 @ 0b00000 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECIV(rd, rs1, rs2) <->
  0b0001010 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0001011

mapping clause encdec = CE_ECOV(rd, rs1, rs2) <->
  0b0001011 @ rs2 @ rs1 @ 0b000 @ rd @ 0b0001011
