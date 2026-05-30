// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

/* CE Suite — MSE instruction decode
 * Spec reference: ch09 §9.11 (encoding table)
 *
 * MSE instructions: ms.ir, ms.or, ms.it, ms.ot
 * opcode = 0b0001011, funct3 = 0b010 (MSE)
 * funct7: MSIR=0b0000000 MSOR=0b0000001 MSIT=0b0000010 MSOT=0b0000011
 * Execute functions for ms.ir/ms.or: ce_mse_execute.sail (Sail-B)
 * Execute functions for ms.it/ms.ot: TODO (Sail-C)
 */

union clause instruction = CE_MSIR : (regidx, regidx, regidx)    /* rd, rs1(ecid), rs2(descriptor) */
union clause instruction = CE_MSOR : (regidx, regidx)            /* rd, rs1(ecid) */
union clause instruction = CE_MSIT : (regidx, regidx, regidx)    /* rd, rs1(src_ecid), rs2(child_ecid) */
union clause instruction = CE_MSOT : (regidx, regidx)            /* rd, rs1(child_ecid) */

mapping clause encdec = CE_MSIR(rd, rs1, rs2) <->
  0b0000000 @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b010 @ encdec_reg(rd) @ 0b0001011

mapping clause encdec = CE_MSOR(rd, rs1) <->
  0b0000001 @ 0b00000 @ encdec_reg(rs1) @ 0b010 @ encdec_reg(rd) @ 0b0001011

mapping clause encdec = CE_MSIT(rd, rs1, rs2) <->
  0b0000010 @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b010 @ encdec_reg(rd) @ 0b0001011

mapping clause encdec = CE_MSOT(rd, rs1) <->
  0b0000011 @ 0b00000 @ encdec_reg(rs1) @ 0b010 @ encdec_reg(rd) @ 0b0001011

/* ms.ir and ms.or execute clauses are in ce_mse_execute.sail (Sail-B) */
function clause execute(CE_MSIT(rd, rs1, rs2)) = Illegal_Instruction()
function clause execute(CE_MSOT(rd, rs1))      = Illegal_Instruction()
