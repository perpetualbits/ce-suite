// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — CPE instruction decode stubs
 * Spec reference: ch07 §7.10 (encoding table)
 *
 * CPE instructions: cp.ir, cp.or, cp.it, cp.ot
 * opcode = 0b0001011, funct3 = 0b001 (CPE)
 * funct7: CPIR=0b0000000 CPOR=0b0000001 CPIT=0b0000010 CPOT=0b0000011
 * Execute functions: TODO (Sail v2)
 */

union clause instruction = CE_CPIR : (regidx, regidx, regidx)    /* rd, rs1(ecid), rs2(descriptor) */
union clause instruction = CE_CPOR : (regidx, regidx)            /* rd, rs1(ecid) */
union clause instruction = CE_CPIT : (regidx, regidx, regidx)    /* rd, rs1(src_ecid), rs2(child_ecid) */
union clause instruction = CE_CPOT : (regidx, regidx)            /* rd, rs1(child_ecid) */

mapping clause encdec = CE_CPIR(rd, rs1, rs2) <->
  0b0000000 @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b001 @ encdec_reg(rd) @ 0b0001011

mapping clause encdec = CE_CPOR(rd, rs1) <->
  0b0000001 @ 0b00000 @ encdec_reg(rs1) @ 0b001 @ encdec_reg(rd) @ 0b0001011

mapping clause encdec = CE_CPIT(rd, rs1, rs2) <->
  0b0000010 @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b001 @ encdec_reg(rd) @ 0b0001011

mapping clause encdec = CE_CPOT(rd, rs1) <->
  0b0000011 @ 0b00000 @ encdec_reg(rs1) @ 0b001 @ encdec_reg(rd) @ 0b0001011

/* Execute stubs — TODO in Sail v2 */
function clause execute(CE_CPIR(rd, rs1, rs2)) = Illegal_Instruction()
function clause execute(CE_CPOR(rd, rs1))      = Illegal_Instruction()
function clause execute(CE_CPIT(rd, rs1, rs2)) = Illegal_Instruction()
function clause execute(CE_CPOT(rd, rs1))      = Illegal_Instruction()
